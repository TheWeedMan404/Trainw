import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.119.0';

// FE-04 / DB-25 (Phase 1b): the gate terminal PIN used to travel in the URL
// and was compared in the browser (a blank PIN passed: '' === ''). The PIN
// now never leaves the server:
//   * set_pin — the gym manager (signed-in JWT, verified in code) sets a
//     4–8 digit PIN. The function stores HMAC-SHA256(PIN,
//     GATE_TERMINAL_PEPPER) in gyms.gate_terminal_pin_hash. Setting a new
//     PIN invalidates all existing terminal sessions for the gym.
//   * auth — the terminal proves the PIN and receives a 256-bit random
//     session token (8h). Only the SHA-256 hash is stored in
//     gate_terminal_sessions (migration 20261115060000). The terminal sends
//     the token as the x-terminal-token header to gate-checkin, which
//     verifies it. No PIN is ever returned, logged, or put in a URL.
//
// Deploy-time secrets (Supabase dashboard > Edge Functions > Secrets):
//   GATE_TERMINAL_PEPPER — random 32+ byte hex string, e.g. from
//     `openssl rand -hex 32`. Never commit it. Without it, set_pin and
//     auth fail closed (server_not_configured).
//   TURNSTILES_ENABLED — must be exactly 'true' for any of this to work.
//     Default (unset / anything else) = turnstiles disabled, fail closed.
//   SUPABASE_URL / SUPABASE_ANON_KEY / SERVICE_ROLE_KEY are injected by
//     Supabase into every edge function automatically.
// config.toml sets verify_jwt = false for this function: the auth action is
// unauthenticated by design (the PIN is the credential), and set_pin
// verifies the JWT in code below.

const TERMINAL_SESSION_TTL_MS = 8 * 60 * 60 * 1000;
const PIN_RE = /^\d{4,8}$/;
const AUTH_RATE_LIMITS = {
  perIpPerMinute: 10,
  perGymPerMinute: 20,
};

function safeString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function corsHeaders(req: Request): Record<string, string> {
  const allowedOrigin = safeString(Deno.env.get('ALLOWED_ORIGIN')) || 'null';
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

function jsonResponse(
  req: Request,
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
  });
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function hmacSha256Hex(keyHex: string, value: string): Promise<string> {
  const keyBytes = new Uint8Array(
    keyHex.match(/.{1,2}/g)?.map((h) => parseInt(h, 16)) ?? [],
  );
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// Constant-time comparison so a wrong PIN cannot be probed byte by byte.
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function randomTokenHex(bytes = 32): string {
  return [...crypto.getRandomValues(new Uint8Array(bytes))]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function createAdminClient() {
  const url = safeString(Deno.env.get('SUPABASE_URL'));
  const key = safeString(Deno.env.get('SERVICE_ROLE_KEY'));
  if (!url || !key) return null;
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// Verifies the caller's JWT against the project's auth and returns the user,
// or null. Used by set_pin (verify_jwt is false for this function, so the
// JWT must be checked in code).
async function getUserFromJwt(req: Request) {
  const authHeader = safeString(req.headers.get('Authorization'));
  const jwt = authHeader.toLowerCase().startsWith('bearer ')
    ? authHeader.slice(7).trim()
    : '';
  if (!jwt) return null;
  const url = safeString(Deno.env.get('SUPABASE_URL'));
  const anonKey = safeString(Deno.env.get('SUPABASE_ANON_KEY'));
  if (!url || !anonKey) return null;
  const client = createClient(url, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await client.auth.getUser(jwt);
  if (error || !data?.user) return null;
  return data.user;
}

// PIN-guessing protection. Unlike gate-checkin (fail OPEN), this fails
// CLOSED: when the limiter itself is down, auth must not proceed.
async function checkAuthRateLimits(
  admin: ReturnType<typeof createClient>,
  clientIp: string,
  gymId: string,
): Promise<{ allowed: boolean; limitedBy?: string; unavailable?: boolean }> {
  const consume = async (bucketKey: string, limit: number) => {
    const { data, error } = await admin.rpc('trainw_gate_rate_limit_consume', {
      p_bucket_key: bucketKey,
      p_limit: limit,
    });
    if (error) throw error;
    return data === true;
  };
  try {
    const ipAllowed = await consume(`terminal-auth-ip:${clientIp}`, AUTH_RATE_LIMITS.perIpPerMinute);
    if (!ipAllowed) return { allowed: false, limitedBy: 'ip' };
    const gymAllowed = await consume(`terminal-auth-gym:${gymId}`, AUTH_RATE_LIMITS.perGymPerMinute);
    if (!gymAllowed) return { allowed: false, limitedBy: 'gym' };
    return { allowed: true };
  } catch (error) {
    console.warn('[gate-terminal-auth] rate limit check failed, failing closed', error);
    return { allowed: false, unavailable: true };
  }
}

function getClientIp(req: Request): string {
  const forwardedFor = safeString(req.headers.get('x-forwarded-for'));
  if (forwardedFor) return forwardedFor.split(',')[0].trim().slice(0, 45);
  return safeString(req.headers.get('x-real-ip')).slice(0, 45) || 'unknown';
}

serve(async (req: Request) => {
  const headers = corsHeaders(req);
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers });
  }
  if (req.method !== 'POST') {
    return jsonResponse(req, 405, { ok: false, error: 'method_not_allowed' });
  }

  try {
    // Turnstile flag FIRST: while it is off, neither action runs.
    if (safeString(Deno.env.get('TURNSTILES_ENABLED')) !== 'true') {
      return jsonResponse(req, 503, { ok: false, error: 'turnstiles_disabled' });
    }

    const body = await req.json().catch(() => null);
    const action = safeString(body?.action);
    const gymId = safeString(body?.gym_id);
    const pin = safeString(body?.pin);

    if (!gymId) {
      return jsonResponse(req, 400, { ok: false, error: 'missing_gym_id' });
    }
    if (action !== 'set_pin' && action !== 'auth') {
      return jsonResponse(req, 400, { ok: false, error: 'invalid_action' });
    }
    if (!PIN_RE.test(pin)) {
      return jsonResponse(req, 400, { ok: false, error: 'invalid_pin' });
    }

    const admin = createAdminClient();
    if (!admin) {
      return jsonResponse(req, 500, { ok: false, error: 'server_not_configured' });
    }

    if (action === 'set_pin') {
      const user = await getUserFromJwt(req);
      if (!user) {
        return jsonResponse(req, 401, { ok: false, error: 'unauthorized' });
      }
      const { data: gym, error: gymError } = await admin
        .from('gyms')
        .select('manager_id')
        .eq('id', gymId)
        .maybeSingle();
      if (gymError) throw gymError;
      if (!gym || gym.manager_id !== user.id) {
        return jsonResponse(req, 403, { ok: false, error: 'forbidden' });
      }

      const pepper = safeString(Deno.env.get('GATE_TERMINAL_PEPPER'));
      if (!pepper) {
        return jsonResponse(req, 500, { ok: false, error: 'server_not_configured' });
      }
      const pinHash = await hmacSha256Hex(pepper, pin);
      const { error: updateError } = await admin
        .from('gyms')
        .update({ gate_terminal_pin_hash: pinHash })
        .eq('id', gymId);
      if (updateError) throw updateError;
      // A new PIN invalidates every terminal session for the gym.
      await admin.from('gate_terminal_sessions').delete().eq('gym_id', gymId);
      return jsonResponse(req, 200, { ok: true });
    }

    // action === 'auth'
    const rateLimit = await checkAuthRateLimits(admin, getClientIp(req), gymId);
    if (!rateLimit.allowed) {
      if (rateLimit.unavailable) {
        return jsonResponse(req, 503, { ok: false, error: 'rate_limit_unavailable' });
      }
      return jsonResponse(
        req,
        429,
        { ok: false, error: 'rate_limited', limited_by: rateLimit.limitedBy },
      );
    }

    const pepper = safeString(Deno.env.get('GATE_TERMINAL_PEPPER'));
    if (!pepper) {
      return jsonResponse(req, 500, { ok: false, error: 'server_not_configured' });
    }
    const { data: gym, error: gymError } = await admin
      .from('gyms')
      .select('gate_terminal_pin_hash')
      .eq('id', gymId)
      .maybeSingle();
    if (gymError) throw gymError;
    if (!gym || !gym.gate_terminal_pin_hash) {
      return jsonResponse(req, 403, { ok: false, error: 'pin_not_set' });
    }
    const presentedHash = await hmacSha256Hex(pepper, pin);
    if (!constantTimeEqual(presentedHash, gym.gate_terminal_pin_hash)) {
      return jsonResponse(req, 401, { ok: false, error: 'invalid_pin' });
    }

    const token = randomTokenHex(32);
    const expiresAt = new Date(Date.now() + TERMINAL_SESSION_TTL_MS).toISOString();
    const { error: insertError } = await admin.from('gate_terminal_sessions').insert({
      gym_id: gymId,
      device_id: safeString(body?.device_id) || null,
      token_hash: await sha256Hex(token),
      expires_at: expiresAt,
    });
    if (insertError) throw insertError;

    return jsonResponse(req, 200, { ok: true, token, expires_at: expiresAt });
  } catch (error) {
    console.error('[gate-terminal-auth] unexpected error', error);
    return jsonResponse(req, 500, { ok: false, error: 'server_error' });
  }
});
