-- ============================================================================
-- TRAINW PHASE 1B — GATE TERMINAL SESSIONS (FE-04 database side)
-- Audit 2026-11-14: FE-04 (gate terminal PIN must never be in a URL).
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- The terminal PIN is never stored and never travels in a URL anymore:
--   * gyms.gate_terminal_pin_hash — HMAC-SHA256 of the PIN under the
--     GATE_TERMINAL_PEPPER edge secret (computed by the gate-terminal-auth
--     edge function, never by the browser). NULL = no PIN set = the
--     terminal is disabled until a manager sets one.
--   * public.gate_terminal_sessions — short-lived terminal sessions issued
--     by gate-terminal-auth after a correct PIN: one row per terminal
--     device, token stored as a SHA-256 hash (the raw token is shown to
--     the terminal once and never stored), 8-hour expiry. RLS is enabled
--     with NO policies: only service_role (the edge functions) can read
--     or write it. The gate-checkin edge function verifies the
--     x-terminal-token header against token_hash before processing any
--     scan while turnstiles are enabled.
--   * The PIN itself is set/checked only through the gate-terminal-auth
--     edge function (supabase/functions/gate-terminal-auth). See the
--     function source for the PIN format (4-8 digits) and rate limits.
--
-- VERIFICATION (no live DB was available when this was written):
--   * After a manager sets a PIN, gyms.gate_terminal_pin_hash must be a
--     64-char hex string (never the PIN itself).
--   * gate_terminal_sessions must reject direct SELECT/INSERT from an
--     authenticated client (no policy = deny by default).
--   * gate-checkin with no/invalid x-terminal-token must return 401
--     invalid_terminal_session; with a valid session token it proceeds.
-- ============================================================================

ALTER TABLE public.gyms
  ADD COLUMN IF NOT EXISTS gate_terminal_pin_hash text;

CREATE TABLE IF NOT EXISTS public.gate_terminal_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  token_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.gate_terminal_sessions ENABLE ROW LEVEL SECURITY;

-- NOTE: deliberately NO policies on gate_terminal_sessions. RLS enabled
-- with no policy denies every authenticated/anon caller; only service_role
-- (the gate-terminal-auth and gate-checkin edge functions) can touch it.

CREATE INDEX IF NOT EXISTS idx_gate_terminal_sessions_gym_device
  ON public.gate_terminal_sessions(gym_id, device_id);

CREATE INDEX IF NOT EXISTS idx_gate_terminal_sessions_token_hash
  ON public.gate_terminal_sessions(token_hash);

REVOKE ALL ON TABLE public.gate_terminal_sessions FROM PUBLIC;
