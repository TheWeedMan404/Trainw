const VALID_TYPES = new Set(['qr', 'rfid_card', 'fingerprint', 'face']);

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

// Phase 1b (turnstile flag, user requirement 2026-11-15): turnstiles are
// deactivated by default. The gate-checkin function fails closed while the
// flag is off — no check-in is processed, no token is consumed, nothing is
// logged as an access attempt. Re-enable by setting the TURNSTILES_ENABLED
// edge secret to exactly 'true' (Supabase dashboard > Edge Functions >
// gate-checkin > Secrets, or `supabase secrets set TURNSTILES_ENABLED=true`).
// Unset, or any value other than 'true', means OFF.
function turnstilesEnabled(options) {
  return safeString(options?.getEnv?.('TURNSTILES_ENABLED')) === 'true';
}

async function sha256Hex(value) {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// P1-12 (GT-03): per-IP + per-device rate limiting, enforced before any
// token/credential lookup so a flood cannot hammer the database or probe
// token validity. Limits are per fixed calendar minute; the counters live in
// public.gate_rate_limits and are consumed atomically by the
// trainw_gate_rate_limit_consume() RPC (see migration
// 20261114040000_phase1_gate_rate_limits.sql).
// A busy gym terminal does a few scans a minute, so 60/min per IP and
// 30/min per device leave ample headroom while stopping a brute-force flood.
const RATE_LIMITS = {
  perIpPerMinute: 60,
  perDevicePerMinute: 30,
};

function getClientIp(req) {
  const forwardedFor = safeString(req?.headers?.get?.('x-forwarded-for'));
  if (forwardedFor) {
    const first = forwardedFor.split(',')[0].trim();
    if (first) return first.slice(0, 45);
  }
  const connectingIp = safeString(req?.headers?.get?.('cf-connecting-ip'));
  if (connectingIp) return connectingIp.slice(0, 45);
  const realIp = safeString(req?.headers?.get?.('x-real-ip'));
  if (realIp) return realIp.slice(0, 45);
  return 'unknown';
}

// Returns { allowed: true } or { allowed: false, limitedBy: 'ip' | 'device' }.
// Fail OPEN on limiter infrastructure errors (console.warn): the gate must
// keep letting members in when the limiter itself is down — the token is
// 96-bit, single-use and short-lived, so the limiter is defence-in-depth,
// not the sole brute-force control.
async function checkRateLimits(admin, { clientIp, deviceId }) {
  const consume = async (bucketKey, limit) => {
    const { data, error } = await admin.rpc('trainw_gate_rate_limit_consume', {
      p_bucket_key: bucketKey,
      p_limit: limit,
    });
    if (error) throw error;
    return data === true;
  };

  try {
    const ipAllowed = await consume(`ip:${clientIp}`, RATE_LIMITS.perIpPerMinute);
    if (!ipAllowed) return { allowed: false, limitedBy: 'ip' };

    if (deviceId) {
      const deviceAllowed = await consume(`device:${deviceId}`, RATE_LIMITS.perDevicePerMinute);
      if (!deviceAllowed) return { allowed: false, limitedBy: 'device' };
    }

    return { allowed: true };
  } catch (error) {
    console.warn('[gate-checkin] rate limit check failed, failing open', error);
    return { allowed: true };
  }
}

// FE-04 (Phase 1b): the terminal proves it was unlocked with the gym's PIN
// by sending the session token issued by gate-terminal-auth as the
// x-terminal-token header. Only the SHA-256 hash of the token is stored
// (gate_terminal_sessions.token_hash), so a leaked database row cannot be
// replayed. Returns { ok: true, session } or { ok: false }.
// When expectedGymId is given, the session must belong to that gym.
async function verifyTerminalSession(admin, req, expectedGymId) {
  const token = safeString(req?.headers?.get?.('x-terminal-token'));
  if (!token) return { ok: false };
  const tokenHash = await sha256Hex(token);
  const { data, error } = await admin
    .from('gate_terminal_sessions')
    .select('id, gym_id, expires_at')
    .eq('token_hash', tokenHash)
    .maybeSingle();
  if (error || !data) return { ok: false };
  if (new Date(data.expires_at).getTime() <= Date.now()) return { ok: false };
  if (expectedGymId && data.gym_id !== expectedGymId) return { ok: false };
  // Best-effort last-seen refresh; never fail the check-in over it.
  try {
    await admin
      .from('gate_terminal_sessions')
      .update({ last_seen_at: new Date().toISOString() })
      .eq('id', data.id);
  } catch (error) {
    console.warn('[gate-checkin] last_seen_at refresh failed', error);
  }
  return { ok: true, session: data };
}

function parseMembershipEnd(dateValue) {
  if (!dateValue) return null;
  const parsed = new Date(`${dateValue}T23:59:59.999Z`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

// DB-47 (Phase 1b): the credential reference is first 4 characters + '...'
// ('****' for 4 characters or fewer) — the same rule as the SQL
// truncate_credential_ref() in migration 20261115010000.
function truncateCredentialRef(value) {
  const trimmed = safeString(value);
  if (!trimmed) return null;
  if (trimmed.length <= 4) return '****';
  return `${trimmed.slice(0, 4)}...`;
}

function normalizeAccessBody(body) {
  if (body && typeof body === 'object' && !Array.isArray(body)) {
    return body;
  }

  return {
    access: false,
    reason: 'invalid_access_response',
  };
}

async function emitAccessEvent(admin, payload) {
  if (!admin?.channel || !payload?.gym_id) return;

  const channel = admin.channel(`gate-terminal:${payload.gym_id}`, {
    config: {
      broadcast: {
        ack: false,
        self: false,
      },
    },
  });
  try {
    await channel.send({
      type: 'broadcast',
      event: 'access_result',
      payload,
    });
  } catch (error) {
    console.warn('[gate-checkin] broadcast failed', error);
  } finally {
    try {
      admin.removeChannel(channel);
    } catch (error) {
      console.warn('[gate-checkin] failed to remove realtime channel', error);
    }
  }
}

async function recordAccessLog(admin, entry) {
  if (!admin || !entry?.gym_id) return;

  const insertPayload = {
    gym_id: entry.gym_id,
    client_id: entry.client_id || null,
    credential_type: entry.credential_type,
    credential_ref: truncateCredentialRef(entry.credential_ref),
    access_granted: Boolean(entry.access_granted),
    denial_reason: entry.access_granted ? null : safeString(entry.denial_reason) || 'unknown_denial',
    device_id: safeString(entry.device_id) || null,
    attempted_at: entry.attempted_at || new Date().toISOString(),
  };

  const { error } = await admin.from('gate_access_log').insert(insertPayload);
  if (error) {
    console.warn('[gate-checkin] access log insert failed', error);
  }
}

function createAdminClientOrNull(options, corsHeaders) {
  const supabaseUrl = safeString(options?.getEnv?.('SUPABASE_URL'));
  const serviceRoleKey = safeString(options?.getEnv?.('SERVICE_ROLE_KEY'));

  if (!supabaseUrl || !serviceRoleKey) {
    return {
      client: null,
      errorResponse: json({ access: false, reason: 'server_not_configured' }, 500, corsHeaders),
    };
  }

  return {
    client: options.createAdminClient(supabaseUrl, serviceRoleKey),
    errorResponse: null,
  };
}

export function createGateCheckinHandler(options) {
  const corsHeaders = buildCorsHeaders(options);
  return async function handleGateCheckinRequest(req) {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders });
    }

    try {
      if (req.method !== 'POST') {
        return json({ access: false, reason: 'method_not_allowed' }, 405, corsHeaders);
      }

      // Turnstile flag FIRST: while it is off, nothing below runs — no
      // rate-limit consumption, no token lookup, no check-in.
      if (!turnstilesEnabled(options)) {
        return json({ access: false, reason: 'turnstiles_disabled' }, 503, corsHeaders);
      }

      const payload = await req.json();
      const type = safeString(payload?.type || 'qr').toLowerCase() || 'qr';
      const requestedGymId = safeString(payload?.gym_id);
      const deviceId = safeString(payload?.device_id);

      if (!VALID_TYPES.has(type)) {
        return json({ access: false, reason: 'invalid_type' }, 400, corsHeaders);
      }

      const adminState = createAdminClientOrNull(options, corsHeaders);
      if (adminState.errorResponse) {
        return adminState.errorResponse;
      }
      const admin = adminState.client;

      // P1-12: rate-limit before any credential/token lookup. A 429 reveals
      // nothing about token validity, and limited attempts are NOT written to
      // gate_access_log (that would let an attacker flood the log table).
      const rateLimit = await checkRateLimits(admin, {
        clientIp: getClientIp(req),
        deviceId: deviceId || null,
      });
      if (!rateLimit.allowed) {
        return json(
          { access: false, reason: 'rate_limited', limited_by: rateLimit.limitedBy },
          429,
          { ...corsHeaders, 'Retry-After': '60' },
        );
      }

      // FE-04: the terminal must prove it was unlocked with the gym PIN
      // (gate-terminal-auth session token). The gym binding is checked
      // again once the effective gym is known, in each branch below.
      const terminalSession = await verifyTerminalSession(admin, req, null);
      if (!terminalSession.ok) {
        return json({ access: false, reason: 'invalid_terminal_session' }, 401, corsHeaders);
      }

      if (type !== 'qr') {
        const credentialData = safeString(payload?.credential_data || payload?.credential_value);
        if (!requestedGymId) {
          return json({ access: false, reason: 'missing_gym_id' }, 400, corsHeaders);
        }
        if (!credentialData) {
          return json({ access: false, reason: 'missing_credential_data' }, 400, corsHeaders);
        }
        if (terminalSession.session.gym_id !== requestedGymId) {
          return json({ access: false, reason: 'invalid_terminal_session' }, 401, corsHeaders);
        }

        const { data: rpcResult, error: rpcError } = await admin.rpc('validate_member_credential', {
          p_gym_id: requestedGymId,
          p_credential_type: type,
          p_credential_data: credentialData,
          p_device_id: deviceId || null,
        });

        if (rpcError) throw rpcError;

        const responseBody = normalizeAccessBody(rpcResult);
        await emitAccessEvent(admin, {
          gym_id: requestedGymId,
          device_id: deviceId || null,
          access: Boolean(responseBody.access),
          reason: responseBody.reason || null,
          credential_type: type,
          client_id: responseBody.client_id || null,
          client_name: responseBody.client_name || null,
          days_left: responseBody.days_left ?? null,
          attempted_at: new Date().toISOString(),
        });

        return json(responseBody, responseBody.access ? 200 : 403, corsHeaders);
      }

      const token = safeString(payload?.token);

      if (!token) {
        return json({ access: false, reason: 'missing_token' }, 400, corsHeaders);
      }

      const denyQr = async (status, reason, details = {}) => {
        const attemptedAt = details.attempted_at || new Date().toISOString();
        await recordAccessLog(admin, {
          gym_id: details.gym_id || requestedGymId || null,
          client_id: details.client_id || null,
          credential_type: 'qr',
          // FE-09: log only a prefix of the opaque token — the full token
          // is a live bearer for 60s and must not sit in the access log.
          credential_ref: `qr:${token.slice(0, 8)}`,
          access_granted: false,
          denial_reason: reason,
          device_id: deviceId || null,
          attempted_at: attemptedAt,
        });
        await emitAccessEvent(admin, {
          gym_id: details.gym_id || requestedGymId || null,
          device_id: deviceId || null,
          access: false,
          reason,
          credential_type: 'qr',
          client_id: details.client_id || null,
          client_name: details.client_name || null,
          days_left: details.days_left ?? null,
          attempted_at: attemptedAt,
        });
        return json({ access: false, reason }, status, corsHeaders);
      };

      // FE-09/GT-05: tokens are single opaque 128-bit crypto-random
      // strings. The legacy dotted format (userId.gymId.timestamp.random)
      // is rejected outright — the member and gym come from the
      // gate_sessions row, never from the token itself.
      if (token.includes('.')) {
        return denyQr(400, 'invalid_token');
      }

      const { data: gateSession, error: gateSessionError } = await admin
        .from('gate_sessions')
        .select('id, client_id, gym_id, token, expires_at, used')
        .eq('token', token)
        .maybeSingle();

      if (gateSessionError) throw gateSessionError;
      if (!gateSession) {
        return denyQr(404, 'invalid_token');
      }

      if (requestedGymId && requestedGymId !== gateSession.gym_id) {
        return denyQr(403, 'gym_mismatch', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }
      if (terminalSession.session.gym_id !== gateSession.gym_id) {
        return denyQr(401, 'invalid_terminal_session', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }
      if (gateSession.used) {
        return denyQr(409, 'token_used', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }

      const expiresAt = new Date(gateSession.expires_at);
      if (Number.isNaN(expiresAt.getTime()) || expiresAt.getTime() <= Date.now()) {
        return denyQr(410, 'token_expired', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }

      // DB-23: membership is decided by the single shared rule
      // (membership_is_active_for_access) — paid/trial/waived, or
      // price_paid > 0 and not cancelled/refunded/overdue, with end_date
      // >= today. The old payment_status = 'paid' + end-date check is
      // retired (trial/waived members were wrongly refused, and the
      // profile lookup had no gym filter). The profile is still read,
      // gym-filtered, for the member's name and days_left only.
      const { data: membershipActive, error: membershipError } = await admin.rpc(
        'membership_is_active_for_access',
        {
          p_client_id: gateSession.client_id,
          p_gym_id: gateSession.gym_id,
          // DB-37: no p_reference_date — the RPC default is the gym's
          // today. Passing the server's UTC date here would reintroduce
          // the off-by-one the DB-37 migration fixed.
        },
      );
      if (membershipError) throw membershipError;

      const [
        { data: clientProfile, error: clientProfileError },
        { data: clientUser, error: clientUserError },
      ] = await Promise.all([
        admin
          .from('client_profiles')
          .select('membership_end_date')
          .eq('user_id', gateSession.client_id)
          .eq('gym_id', gateSession.gym_id)
          .maybeSingle(),
        admin
          .from('users')
          .select('name')
          .eq('id', gateSession.client_id)
          .maybeSingle(),
      ]);

      if (clientProfileError) throw clientProfileError;
      if (clientUserError) throw clientUserError;

      if (membershipActive !== true) {
        return denyQr(403, 'membership_inactive', {
          gym_id: gateSession.gym_id,
          client_id: gateSession.client_id,
          client_name: clientUser?.name || null,
        });
      }

      const membershipEnd = parseMembershipEnd(clientProfile?.membership_end_date ?? null);
      const daysLeft = membershipEnd
        ? Math.max(0, Math.ceil((membershipEnd.getTime() - Date.now()) / 86400000))
        : null;

      // DB-24 / GT-08: graceful duplicate handling instead of a raw
      // unique-index error. Within 15 minutes of the last check-in the
      // member is already inside; a second check-in later the same day
      // is a duplicate for the day. Both are logged denials, not errors.
      const { data: lastCheckIns, error: lastCheckInError } = await admin
        .from('check_ins')
        .select('checked_in_at')
        .eq('gym_id', gateSession.gym_id)
        .eq('client_id', gateSession.client_id)
        .order('checked_in_at', { ascending: false })
        .limit(1);

      if (lastCheckInError) throw lastCheckInError;
      if (Array.isArray(lastCheckIns) && lastCheckIns.length > 0) {
        const lastAt = new Date(lastCheckIns[0].checked_in_at).getTime();
        if (!Number.isNaN(lastAt) && Date.now() - lastAt < 15 * 60 * 1000) {
          return denyQr(409, 'already_inside', {
            gym_id: gateSession.gym_id,
            client_id: gateSession.client_id,
            client_name: clientUser?.name || null,
            days_left: daysLeft,
          });
        }
        const todayUtc = new Date().toISOString().slice(0, 10);
        if (!Number.isNaN(lastAt) && new Date(lastAt).toISOString().slice(0, 10) === todayUtc) {
          return denyQr(409, 'duplicate_checkin_today', {
            gym_id: gateSession.gym_id,
            client_id: gateSession.client_id,
            client_name: clientUser?.name || null,
            days_left: daysLeft,
          });
        }
      }

      const { data: consumedSession, error: consumeError } = await admin
        .from('gate_sessions')
        .update({
          used: true,
          used_at: new Date().toISOString(),
          device_id: deviceId || null,
        })
        .eq('id', gateSession.id)
        .eq('used', false)
        .select('id')
        .maybeSingle();

      if (consumeError) throw consumeError;
      if (!consumedSession) {
        return denyQr(409, 'token_used', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }

      const { error: insertCheckInError } = await admin
        .from('check_ins')
        .insert({
          gym_id: gateSession.gym_id,
          client_id: gateSession.client_id,
          method: 'qr_gate',
          notes: JSON.stringify({
            source: 'turnstile_qr',
            device_id: deviceId || null,
            client_name: clientUser?.name || 'Client',
            days_left: daysLeft,
          }),
        });

      if (insertCheckInError) {
        if (insertCheckInError.code === '23505') {
          return denyQr(409, 'duplicate_checkin_today', {
            gym_id: gateSession.gym_id,
            client_id: gateSession.client_id,
            client_name: clientUser?.name || null,
            days_left: daysLeft,
          });
        }
        // GT-07: the token was consumed but the check-in did not land.
        // Un-consume it so the member can retry with the same QR instead
        // of being locked out with a spent token.
        try {
          await admin
            .from('gate_sessions')
            .update({ used: false, used_at: null })
            .eq('id', gateSession.id);
        } catch (resetError) {
          console.warn('[gate-checkin] failed to un-consume gate session after insert failure', resetError);
        }
        throw insertCheckInError;
      }

      const attemptedAt = new Date().toISOString();
      await recordAccessLog(admin, {
        gym_id: gateSession.gym_id,
        client_id: gateSession.client_id,
        credential_type: 'qr',
        credential_ref: token,
        access_granted: true,
        device_id: deviceId || null,
        attempted_at: attemptedAt,
      });
      await emitAccessEvent(admin, {
        gym_id: gateSession.gym_id,
        device_id: deviceId || null,
        access: true,
        reason: null,
        credential_type: 'qr',
        client_id: gateSession.client_id,
        client_name: clientUser?.name || 'Client',
        days_left: daysLeft,
        attempted_at: attemptedAt,
      });

      return json({
        access: true,
        client_name: clientUser?.name || 'Client',
        days_left: daysLeft,
      }, 200, corsHeaders);
    } catch (error) {
      // GT-06: never leak internals (stack traces, SQL, Supabase error
      // text) to the caller. The raw error goes to the server log only.
      console.error('[gate-checkin] unexpected error', error);
      return json({ access: false, reason: 'server_error' }, 500, corsHeaders);
    }
  };
}
