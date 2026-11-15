-- ============================================================================
-- TRAINW PHASE 2 — P2-5: STOP THE ENUMERATION AND SPAM PATHS (JOIN FLOW)
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- The Next.js parts of this step (NX-01/02/05/06/14) are SUPERSEDED (P2-10:
-- src/ deleted). What remains for the vanilla app:
--
--   * Public gym directory: the vanilla directory has NO search input —
--     tw-role.js calls list_public_gyms(), which lists every active gym
--     with safe columns only (no email/phone/owner/prices). There is no
--     query to give a minimum length or wildcard-escape, so those two
--     controls are moot here. What was missing was a rate limit: any
--     signed-in user could hammer the listing. Added: per-user 30/min.
--   * Join requests: request_gym_membership() is idempotent, but a flood
--     of requests is still a spam path. Added: per-user 10/min.
--   * Coach search (FE-08, vanilla): min query length 2 + LIKE-wildcard
--     escaping, in tw-gym-acc.js (no migration — client-side).
--
-- The limiter mirrors the proven gate limiter (20261114040000, GT-03):
-- one row per bucket key per fixed calendar minute, the counter only
-- increments while under the limit, stale windows for the key are
-- deleted on consume. Deliberate differences from the gate limiter:
--   - separate table (rpc_rate_limits) so join-flow buckets can never
--     collide with gate buckets;
--   - the consume function is owner-only (REVOKE ALL FROM PUBLIC, no
--     GRANT): it is called only from inside these SECURITY DEFINER RPCs,
--     which run as the function owner. Granting it to authenticated
--     would let any user burn another user's bucket by naming it.
--   - fail OPEN on limiter error (logged): a broken limiter must never
--     block the join flow. The gate handler fails open the same way.
--
-- VERIFICATION (local throwaway cluster): p25-tests.sql — consume
-- semantics (limit 3: T,T,T,F; separate keys independent; stale window
-- purged), list_public_gyms 30 OK / 31st rejected, request_gym_membership
-- 10 OK / 11th rejected, anon cannot call the consume function.
-- Live verification of the pre-existing controls is in the P2-5 appendix
-- of PHASE1_IMPLEMENTATION_NOTES.md (Auth config, unconfirmed-user test,
-- signup 429, password-reset 429, gate limiter consume probe).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Rate-limit table + consume function (gate-limiter pattern, separate table).
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.rpc_rate_limits (
  bucket_key text NOT NULL,
  window_start timestamptz NOT NULL,
  hits integer NOT NULL DEFAULT 0 CHECK (hits >= 0),
  PRIMARY KEY (bucket_key, window_start)
);

ALTER TABLE public.rpc_rate_limits ENABLE ROW LEVEL SECURITY;

-- No policies on purpose: the table is only reachable through the
-- SECURITY DEFINER function below. Direct access is denied by default when
-- RLS is enabled with no policy.

CREATE OR REPLACE FUNCTION public.trainw_rpc_rate_limit_consume(
  p_bucket_key text,
  p_limit integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window_start timestamptz := date_trunc('minute', now());
  v_hits integer;
BEGIN
  IF p_bucket_key IS NULL OR p_bucket_key = '' OR p_limit IS NULL OR p_limit < 1 THEN
    RETURN false;
  END IF;

  -- Keep at most one row per bucket key: drop this key's previous windows.
  DELETE FROM public.rpc_rate_limits
  WHERE bucket_key = p_bucket_key
    AND window_start < v_window_start;

  -- First hit of the window inserts the row (hits = 1). Later hits bump the
  -- counter only while still under the limit; when already at the limit the
  -- UPDATE matches no row and RETURNING yields NULL, so the request is
  -- refused without inflating the counter.
  INSERT INTO public.rpc_rate_limits (bucket_key, window_start, hits)
  VALUES (p_bucket_key, v_window_start, 1)
  ON CONFLICT (bucket_key, window_start)
  DO UPDATE SET hits = rpc_rate_limits.hits + 1
    WHERE rpc_rate_limits.hits < p_limit
  RETURNING hits INTO v_hits;

  RETURN v_hits IS NOT NULL AND v_hits <= p_limit;
END;
$$;

-- Owner-only on purpose (see header): the join-flow RPCs call it from
-- inside SECURITY DEFINER, running as the function owner. No GRANT.
REVOKE ALL ON FUNCTION public.trainw_rpc_rate_limit_consume(text, integer) FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- list_public_gyms: same columns, same ordering, same grants — now
-- plpgsql so the per-user rate limit (30/min) can run before the SELECT.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.list_public_gyms()
RETURNS TABLE (
  gym_id uuid,
  name text,
  address text,
  location text,
  logo_storage_bucket text,
  logo_storage_path text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_limited boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to list gyms.';
  END IF;

  -- P2-5: per-user rate limit (30/min). Fail open on limiter error (see
  -- the request_gym_membership note below for why the flag is needed).
  BEGIN
    v_limited := NOT public.trainw_rpc_rate_limit_consume('dir:' || auth.uid()::text, 30);
  EXCEPTION
    WHEN OTHERS THEN
      RAISE LOG 'trainw_rpc_rate_limit_consume failed for dir:% (fail open): % - %', auth.uid(), SQLSTATE, SQLERRM;
      v_limited := false;
  END;
  IF v_limited THEN
    RAISE EXCEPTION 'Too many requests. Please wait a minute and try again.';
  END IF;

  RETURN QUERY
  SELECT g.id, g.name, g.address, g.location,
         g.logo_storage_bucket, g.logo_storage_path
  FROM public.gyms g
  WHERE g.is_active = true
  ORDER BY g.name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.list_public_gyms() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_public_gyms() TO authenticated;

-- ----------------------------------------------------------------------------
-- request_gym_membership: unchanged behaviour + P2-5 per-user rate limit
-- (10/min). Body carried verbatim from 20261116100000 except the limiter
-- block and the v_limited declaration.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.request_gym_membership(
  p_gym_id uuid,
  p_role_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_role_code text;
  v_limited boolean := false;
  v_role_id uuid;
  v_gym_name text;
  v_existing record;
  v_membership_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to request a membership.';
  END IF;

  -- P2-5: per-user rate limit on join requests (10/min) — the spam path
  -- for the public directory is join-request flooding (the call is
  -- idempotent, but a flood still burns DB + mailbox-free work). A
  -- rejection raises; a limiter fault fails OPEN (logged) so a broken
  -- limiter can never block legitimate joins. The flag dance matters:
  -- raising inside the BEGIN block would be swallowed by its own
  -- EXCEPTION handler.
  BEGIN
    v_limited := NOT public.trainw_rpc_rate_limit_consume('join:' || auth.uid()::text, 10);
  EXCEPTION
    WHEN OTHERS THEN
      RAISE LOG 'trainw_rpc_rate_limit_consume failed for join:% (fail open): % - %', auth.uid(), SQLSTATE, SQLERRM;
      v_limited := false;
  END;
  IF v_limited THEN
    RAISE EXCEPTION 'Too many join requests. Please wait a minute and try again.';
  END IF;

  v_role_code := lower(BTRIM(COALESCE(p_role_code, '')));
  IF v_role_code NOT IN ('client', 'coach') THEN
    RAISE EXCEPTION 'Join requests are only open for client and coach roles.';
  END IF;

  SELECT g.name INTO v_gym_name
  FROM public.gyms g
  WHERE g.id = p_gym_id AND g.is_active = true;
  IF v_gym_name IS NULL THEN
    RAISE EXCEPTION 'Gym not found.';
  END IF;

  SELECT r.id INTO v_role_id
  FROM public.roles r
  WHERE r.gym_id = p_gym_id AND r.code = v_role_code
  LIMIT 1;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'This gym is not accepting % registrations yet.', v_role_code;
  END IF;

  SELECT gm.id, gm.status INTO v_existing
  FROM public.gym_memberships gm
  WHERE gm.gym_id = p_gym_id
    AND gm.user_id = auth.uid()
    AND gm.role_id = v_role_id
    AND gm.status IN ('pending', 'accepted', 'active')
  ORDER BY gm.created_at DESC
  LIMIT 1;

  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'membership_id', v_existing.id,
      'gym_id', p_gym_id,
      'role_code', v_role_code,
      'status', v_existing.status,
      'already_requested', true
    );
  END IF;

  INSERT INTO public.gym_memberships (
    gym_id, user_id, role_id, status, invitation_status,
    invite_email, invited_name, invited_by, invite_token,
    is_default
  )
  VALUES (
    p_gym_id, auth.uid(), v_role_id, 'pending', 'pending',
    public.auth_user_email(auth.uid()),
    (SELECT name FROM public.users WHERE id = auth.uid()),
    NULL, NULL,
    false
  )
  RETURNING id INTO v_membership_id;

  RETURN jsonb_build_object(
    'membership_id', v_membership_id,
    'gym_id', p_gym_id,
    'role_code', v_role_code,
    'status', 'pending',
    'already_requested', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_gym_membership(uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_gym_membership(uuid, text) TO authenticated;
