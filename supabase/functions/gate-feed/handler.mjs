// FE-10 (Phase 1e): the authenticated gate feed.
//
// The gate-checkin broadcast used to carry member names, days_left and
// denial reasons on the public Realtime channel `gate-terminal:<gymId>`.
// It now carries only an opaque `access_refresh` signal. This function
// is what the terminal calls after a refresh signal (and once at startup)
// to fetch the recent entries for its gym — authenticated by the same
// terminal session token gate-checkin verifies (x-terminal-token header,
// device-bound per GT-02).
//
// Response: { entries: [{ access, reason, credential_type, client_id,
// client_name, days_left, device_id, attempted_at }] } — newest first,
// at most 8. `reason` is null for grants and the denial_reason otherwise.
// `days_left` is the member's remaining membership days, computed the
// same way gate-checkin does (membership_end_date, ceil of days left,
// 0 floor, null when there is no end date).
//
// Deploy-time secrets: TURNSTILES_ENABLED must be exactly 'true'
// (default = disabled, fail closed). SUPABASE_URL / SERVICE_ROLE_KEY are
// injected by Supabase. config.toml sets verify_jwt = false: the
// terminal authenticates with the session token, verified in code below.
//
// NOTE: verifyTerminalSession is duplicated from gate-checkin/handler.mjs
// (same device-bound check). The functions are separate Deno deployments
// and this repo has no supabase/functions/_shared module; keep the two
// copies in sync when the session rules change.

const FEED_LIMIT = 8;

function buildCorsHeaders(options) {
  return {
    'Access-Control-Allow-Origin': safeString(options?.getEnv?.('ALLOWED_ORIGIN')) || 'null',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-terminal-token',
  };
}

function json(body, status = 200, corsHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

function safeString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function turnstilesEnabled(options) {
  return safeString(options?.getEnv?.('TURNSTILES_ENABLED')) === 'true';
}

async function sha256Hex(value) {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Same contract as gate-checkin/handler.mjs: { ok: true, session } or
// { ok: false }. Token hash + expiry + gym binding + GT-02 device binding.
async function verifyTerminalSession(admin, req, expectedGymId, expectedDeviceId) {
  const token = safeString(req?.headers?.get?.('x-terminal-token'));
  if (!token) return { ok: false };
  const tokenHash = await sha256Hex(token);
  const { data, error } = await admin
    .from('gate_terminal_sessions')
    .select('id, gym_id, device_id, expires_at')
    .eq('token_hash', tokenHash)
    .maybeSingle();
  if (error || !data) return { ok: false };
  if (new Date(data.expires_at).getTime() <= Date.now()) return { ok: false };
  if (expectedGymId && data.gym_id !== expectedGymId) return { ok: false };
  if (safeString(data.device_id) && safeString(expectedDeviceId) !== safeString(data.device_id)) return { ok: false };
  try {
    await admin
      .from('gate_terminal_sessions')
      .update({ last_seen_at: new Date().toISOString() })
      .eq('id', data.id);
  } catch (error) {
    console.warn('[gate-feed] last_seen_at refresh failed', error);
  }
  return { ok: true, session: data };
}

function parseMembershipEnd(dateValue) {
  if (!dateValue) return null;
  const parsed = new Date(`${dateValue}T23:59:59.999Z`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function daysLeftFromEnd(membershipEnd) {
  if (!membershipEnd) return null;
  return Math.max(0, Math.ceil((membershipEnd.getTime() - Date.now()) / 86400000));
}

export function createGateFeedHandler(options) {
  const corsHeaders = buildCorsHeaders(options);
  return async function handleGateFeedRequest(req) {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders });
    }

    try {
      if (req.method !== 'POST') {
        return json({ entries: [], error: 'method_not_allowed' }, 405, corsHeaders);
      }

      if (!turnstilesEnabled(options)) {
        return json({ entries: [], error: 'turnstiles_disabled' }, 503, corsHeaders);
      }

      const payload = await req.json().catch(() => ({}));
      const requestedGymId = safeString(payload?.gym_id);
      const deviceId = safeString(payload?.device_id);

      const supabaseUrl = safeString(options?.getEnv?.('SUPABASE_URL'));
      const serviceRoleKey = safeString(options?.getEnv?.('SERVICE_ROLE_KEY'));
      if (!supabaseUrl || !serviceRoleKey) {
        return json({ entries: [], error: 'server_not_configured' }, 500, corsHeaders);
      }
      const admin = options.createAdminClient(supabaseUrl, serviceRoleKey);

      // The session must belong to this gym AND this device. A token from
      // another gym or another terminal gets the same 401 either way —
      // the caller learns nothing about which part failed.
      const terminalSession = await verifyTerminalSession(admin, req, requestedGymId || null, deviceId);
      if (!terminalSession.ok) {
        return json({ entries: [], error: 'invalid_terminal_session' }, 401, corsHeaders);
      }
      const gymId = terminalSession.session.gym_id;

      const { data: logRows, error: logError } = await admin
        .from('gate_access_log')
        .select('client_id, credential_type, access_granted, denial_reason, device_id, attempted_at')
        .eq('gym_id', gymId)
        .order('attempted_at', { ascending: false })
        .limit(FEED_LIMIT);
      if (logError) throw logError;

      const clientIds = [...new Set((logRows || []).map((row) => row.client_id).filter(Boolean))];
      let namesById = new Map();
      let endsById = new Map();
      if (clientIds.length > 0) {
        const [{ data: users, error: usersError }, { data: profiles, error: profilesError }] = await Promise.all([
          admin.from('users').select('id, name').in('id', clientIds),
          admin.from('client_profiles').select('user_id, membership_end_date').eq('gym_id', gymId).in('user_id', clientIds),
        ]);
        if (usersError) throw usersError;
        if (profilesError) throw profilesError;
        namesById = new Map((users || []).map((u) => [u.id, u.name || null]));
        endsById = new Map((profiles || []).map((p) => [p.user_id, parseMembershipEnd(p.membership_end_date)]));
      }

      const entries = (logRows || []).map((row) => ({
        access: Boolean(row.access_granted),
        reason: row.access_granted ? null : (safeString(row.denial_reason) || 'unknown_denial'),
        credential_type: row.credential_type,
        client_id: row.client_id || null,
        client_name: row.client_id ? (namesById.get(row.client_id) || null) : null,
        days_left: row.client_id ? daysLeftFromEnd(endsById.get(row.client_id) || null) : null,
        device_id: safeString(row.device_id) || null,
        attempted_at: row.attempted_at,
      }));

      return json({ entries }, 200, corsHeaders);
    } catch (error) {
      // GT-06 discipline: never leak internals to the caller.
      console.error('[gate-feed] unexpected error', error);
      return json({ entries: [], error: 'server_error' }, 500, corsHeaders);
    }
  };
}
