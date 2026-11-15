-- ============================================================================
-- TRAINW ROUND 7 — MEMBER-CREDENTIAL PEPPER MOVES OFF THE GUC (DB-07 follow-up)
-- User decisions 2026-11-15: DB-66 = CREDIT, P2-10 = DELETE src/.
-- Branch: phase1-security-fixes. Local only until applied live.
--
-- WHY: the pepper used to live in the database GUC
--   trainw.member_credential_pepper (migration 20261115010000). That GUC
--   CANNOT be set via the Supabase Management API (ALTER DATABASE / ALTER
--   ROLE SET are denied 42501, the config endpoint rejects custom GUC
--   keys, ALTER SYSTEM is impossible inside a transaction) — so on the
--   live project credential enrolment and gate validation failed closed
--   with "pepper is not configured" (P1-13). The pepper now lives in a
--   locked-down table instead.
--
-- DESIGN:
--   * public.app_secrets (key, value) holds operator-managed secrets
--     that cannot live in env vars or GUCs. RLS is ON with NO policies,
--     so every app role (anon, authenticated) is denied; only the table
--     owner (postgres) and SECURITY DEFINER functions can read it.
--     service_role bypasses RLS by design — that is the operator path
--     for setting/rotating values, not an app path.
--   * public.hash_member_credential is now SECURITY DEFINER and reads
--     the pepper from app_secrets (key 'member_credential_pepper'). It
--     still FAILS CLOSED (raises) when the row is missing or empty, and
--     it still returns only the HMAC of its input — the pepper never
--     leaves the function. EXECUTE is granted to the app roles because
--     the enrolment trigger (invoker) and the SECURITY DEFINER
--     validators both call it.
--   * public.member_credential_pepper() (the GUC reader) is DROPPED:
--     it was called only by hash_member_credential.
--   * The pepper VALUE is NEVER in this file. Set it once per project
--     via SQL (see docs/DEPLOY_RUNBOOK.md §3) and back it up with the
--     database dumps — the value lives ONLY in this table. Rotating the
--     pepper invalidates all stored hashes: every member must re-enrol.
--
-- VERIFICATION (local throwaway cluster, then live):
--   * With no app_secrets row, enrolling a credential raises
--     'pepper is not configured' (fail closed).
--   * After INSERTing a throwaway pepper, enrolment stores a hash
--     (credential_data NULL, credential_ref 'XXXX...') and
--     validate_member_credential grants access for the same data.
--   * As role authenticated, SELECT on app_secrets returns nothing
--     (RLS denies it).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_secrets (
  key text PRIMARY KEY,
  value text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_secrets IS 'Operator-managed secrets that cannot live in env vars or GUCs (e.g. the member-credential pepper). Values are NEVER committed; set them via SQL on the live project. The pepper value lives ONLY in this table — back it up with the database dumps (docs/DEPLOY_RUNBOOK.md §3/§5). Rotating the pepper invalidates all stored hashes: every member must re-enrol.';

ALTER TABLE public.app_secrets ENABLE ROW LEVEL SECURITY;

-- No policies: RLS denies every app role. Only the owner (postgres) and
-- SECURITY DEFINER functions can read the table.
REVOKE ALL ON TABLE public.app_secrets FROM PUBLIC;
REVOKE ALL ON TABLE public.app_secrets FROM anon, authenticated;

-- The GUC reader is gone: the pepper no longer comes from a GUC.
DROP FUNCTION IF EXISTS public.member_credential_pepper();

CREATE OR REPLACE FUNCTION public.hash_member_credential(p_credential_data text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_pepper text;
BEGIN
  SELECT value INTO v_pepper
  FROM public.app_secrets
  WHERE key = 'member_credential_pepper';

  IF v_pepper IS NULL OR BTRIM(v_pepper) = '' THEN
    RAISE EXCEPTION 'member credential pepper is not configured (app_secrets.member_credential_pepper)';
  END IF;
  IF p_credential_data IS NULL OR BTRIM(p_credential_data) = '' THEN
    RAISE EXCEPTION 'credential data is required';
  END IF;
  -- pgcrypto hmac(): keyed hash; the raw credential never leaves this call.
  RETURN encode(extensions.hmac(BTRIM(p_credential_data), v_pepper, 'sha256'), 'hex');
END;
$$;

-- Safe to call from app roles: the function returns only the HMAC of its
-- input, never the pepper. The enrolment trigger (invoker) and the
-- SECURITY DEFINER validators both need EXECUTE.
REVOKE ALL ON FUNCTION public.hash_member_credential(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hash_member_credential(text) TO anon, authenticated, service_role;
