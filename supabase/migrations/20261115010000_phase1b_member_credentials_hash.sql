-- ============================================================================
-- TRAINW PHASE 1B — MEMBER CREDENTIAL HASHING + GATE VALIDATION HARDENING
-- Audit 2026-11-14: DB-07 (CRITICAL), DB-22, DB-23, DB-24, DB-25, DB-47.
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- DB-07 — member credentials (RFID / fingerprint / face templates) were stored
--   as PLAINTEXT in public.member_credentials.credential_data, with a UNIQUE
--   index on the raw value. From here on only a salted hash is stored:
--     credential_hash = hex(HMAC-SHA256(credential_data, pepper))
--   The pepper is a deploy-time secret, NEVER committed:
--     * Supabase SQL editor / psql (once, per project):
--         ALTER DATABASE postgres
--           SET trainw.member_credential_pepper = '<random 32+ byte hex>';
--       (then restart pooled connections / wait for the setting to apply;
--        or per session: SELECT set_config('trainw.member_credential_pepper',
--        '<value>', false);)
--     * The hash function FAILS CLOSED (raises) when the pepper is unset, so
--       enrolment and gate validation refuse to run with plaintext rather
--       than silently storing/comparing it.
--   A BEFORE INSERT/UPDATE trigger hashes any plaintext present in
--   credential_data and then clears the column, so no plaintext ever lands
--   in the table through the app. credential_data is kept as a nullable
--   write-only intake column (the trigger clears it); credential_hash is
--   the stored value, and credential_ref (first 4 chars + '...') is the
--   non-sensitive display identifier shown in the dashboard list.
--   Existing rows are NOT hashed by this migration (hashing them needs the
--   pepper, which the migration cannot know): after setting the pepper, the
--   operator runs exactly once, as the project owner:
--     SELECT public.trainw_backfill_member_credential_hashes();
--   Until then, pre-existing credentials fail closed at the gate (hash
--   lookup misses) — that is intentional. Pepper rotation invalidates all
--   stored hashes: every member must re-enrol (documented, no silent
--   downgrade to plaintext comparison).
-- DB-22 — validate_member_credential now joins client_profiles with
--   cp.gym_id = p_gym_id; a profile from another gym no longer satisfies
--   the membership check, and a missing profile for this gym fails closed.
-- DB-23 — one shared membership definition:
--   public.membership_is_active_for_access(p_client_id, p_gym_id,
--   p_reference_date). client_membership_is_active() now delegates to it
--   (true when active in ANY gym — signature unchanged). Rule: paid / trial /
--   waived, or price_paid > 0 and not cancelled/refunded/overdue; NULL
--   membership_start_date means "no lower bound" (previously the gate
--   treated a NULL start as inactive — see notes); end_date >= reference.
--   client_profiles.membership_start_date now defaults to CURRENT_DATE.
-- DB-24 — same-day duplicate check-ins are a graceful denial
--   ('duplicate_checkin_today', logged) instead of a raw unique-index
--   error; the 2-hour anti-tailgating window is now 15 minutes and returns
--   'already_inside' (checked first, so a scan minutes after entry reports
--   "already inside" rather than "duplicate today").
-- DB-25 — new service-role-only RPC public.validate_gate_session(p_token):
--   atomic check-and-consume of a gate_sessions row, returning the session
--   as jsonb. The gate-checkin edge function keeps its inline QR flow for
--   now (it must check membership BEFORE consuming the token); the RPC is
--   the primitive for future callers.
-- DB-47 — turnstile_truncate_credential_ref no longer returns the full
--   value for short inputs (RFID UIDs are 8-14 chars, so the old version
--   stored the whole UID in gate_access_log). It now returns '****' for
--   values of 4 chars or fewer, else the first 4 chars + '...'.
--
-- VERIFICATION (no live DB was available when this was written):
--   * Apply to staging, set the pepper, run the backfill function, then
--     enrol a test RFID + validate it via the gate-checkin edge function:
--     access must be granted, gate_access_log.credential_ref must be
--     'XXXX...' (never the full UID), and member_credentials.credential_data
--     must be NULL for the new row.
--   * With the pepper unset, enrolment/validation must raise (fail closed).
--   * A profile valid in gym A must NOT open the gate in gym B.
--   * A second scan the same day must return 'duplicate_checkin_today';
--     a scan within 15 minutes must return 'already_inside'.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DB-07 — pepper + hashing helpers.
-- ----------------------------------------------------------------------------

-- Returns the deploy-time pepper, or raises when it is not configured.
-- The pepper lives in a database GUC (see header) — never in this file.
CREATE OR REPLACE FUNCTION public.member_credential_pepper()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT NULLIF(BTRIM(current_setting('trainw.member_credential_pepper', true)), '')
$$;

CREATE OR REPLACE FUNCTION public.hash_member_credential(p_credential_data text)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_pepper text := public.member_credential_pepper();
BEGIN
  IF v_pepper IS NULL THEN
    RAISE EXCEPTION 'member credential pepper is not configured (trainw.member_credential_pepper)';
  END IF;
  IF p_credential_data IS NULL OR BTRIM(p_credential_data) = '' THEN
    RAISE EXCEPTION 'credential data is required';
  END IF;
  -- pgcrypto hmac(): keyed hash; the raw credential never leaves this call.
  RETURN encode(hmac(BTRIM(p_credential_data), v_pepper, 'sha256'), 'hex');
END;
$$;

-- ----------------------------------------------------------------------------
-- DB-07 — table changes: hash + display ref columns, plaintext intake.
-- ----------------------------------------------------------------------------

ALTER TABLE public.member_credentials
  ADD COLUMN IF NOT EXISTS credential_hash text,
  ADD COLUMN IF NOT EXISTS credential_ref text;

-- credential_data becomes a write-only intake column: the trigger below
-- hashes it and clears it before the row is stored, so it must be nullable.
ALTER TABLE public.member_credentials
  ALTER COLUMN credential_data DROP NOT NULL;

-- Drop the UNIQUE constraint/index on the RAW credential value and replace
-- it with one on the hash. (Dropping the constraint drops its index too;
-- the DROP INDEX is defensive for any surviving copy.)
ALTER TABLE public.member_credentials
  DROP CONSTRAINT IF EXISTS member_credentials_gym_type_credential_data_key;
DROP INDEX IF EXISTS public.uq_member_credentials_gym_type_data_idx;
DROP INDEX IF EXISTS public.idx_member_credentials_active_lookup;

CREATE UNIQUE INDEX IF NOT EXISTS uq_member_credentials_gym_type_hash_idx
  ON public.member_credentials(gym_id, type, credential_hash)
  WHERE credential_hash IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_member_credentials_hash_lookup
  ON public.member_credentials(gym_id, type, credential_hash)
  WHERE is_active = true;

-- BEFORE INSERT/UPDATE: hash any plaintext present, store the display ref,
-- then clear the plaintext. Runs for every write, including the backfill
-- (which touches rows by re-setting credential_data to itself).
CREATE OR REPLACE FUNCTION public.trainw_hash_member_credential()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.credential_data IS NOT NULL AND BTRIM(NEW.credential_data) <> '' THEN
    NEW.credential_hash := public.hash_member_credential(NEW.credential_data);
    NEW.credential_ref := public.turnstile_truncate_credential_ref(NEW.credential_data);
    NEW.credential_data := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_credentials_hash ON public.member_credentials;
CREATE TRIGGER trg_member_credentials_hash
  BEFORE INSERT OR UPDATE ON public.member_credentials
  FOR EACH ROW EXECUTE FUNCTION public.trainw_hash_member_credential();

-- One-shot operator backfill (run AFTER setting the pepper, as the project
-- owner — NOT granted to authenticated/anon). Returns the number of rows
-- hashed. Re-running it is a no-op (already-hashed rows have NULL data).
CREATE OR REPLACE FUNCTION public.trainw_backfill_member_credential_hashes()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer := 0;
BEGIN
  UPDATE public.member_credentials
  SET credential_data = credential_data
  WHERE credential_hash IS NULL
    AND credential_data IS NOT NULL
    AND BTRIM(credential_data) <> '';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.trainw_backfill_member_credential_hashes() FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- DB-47 — truncation must never return the full credential.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.turnstile_truncate_credential_ref(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_value IS NULL OR NULLIF(BTRIM(p_value), '') IS NULL THEN NULL
    WHEN char_length(BTRIM(p_value)) <= 4 THEN '****'
    ELSE left(BTRIM(p_value), 4) || '...'
  END;
$$;

-- ----------------------------------------------------------------------------
-- DB-23 — single shared membership-is-active definition.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.membership_is_active_for_access(
  p_client_id uuid,
  p_gym_id uuid,
  p_reference_date date DEFAULT CURRENT_DATE
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.client_profiles cp
    JOIN public.users u
      ON u.id = cp.user_id
    WHERE cp.user_id = p_client_id
      AND cp.gym_id = p_gym_id
      AND u.role = 'client'
      AND COALESCE(u.is_active, true)
      AND (
        cp.payment_status IN ('paid', 'trial', 'waived')
        OR (
          cp.price_paid > 0
          AND cp.payment_status NOT IN ('cancelled', 'refunded', 'overdue')
        )
      )
      AND (
        cp.membership_start_date IS NULL
        OR cp.membership_start_date <= p_reference_date
      )
      AND (
        cp.membership_end_date IS NULL
        OR cp.membership_end_date >= p_reference_date
      )
  );
$$;

-- client_membership_is_active keeps its signature (no gym argument) and now
-- delegates: true when the client is active in ANY gym.
CREATE OR REPLACE FUNCTION public.client_membership_is_active(
  p_client_id uuid,
  p_reference_date date DEFAULT CURRENT_DATE
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.client_profiles cp
    WHERE cp.user_id = p_client_id
      AND public.membership_is_active_for_access(p_client_id, cp.gym_id, p_reference_date)
  );
$$;

-- New profiles start "today" unless an explicit start date is given, so a
-- freshly created membership is not accidentally inactive for a NULL start.
ALTER TABLE public.client_profiles
  ALTER COLUMN membership_start_date SET DEFAULT CURRENT_DATE;

-- ----------------------------------------------------------------------------
-- DB-22 / DB-24 / DB-07 — validate_member_credential rewrite.
-- Same return shape and logging as before; changes:
--   * lookup compares credential_hash (never the raw value);
--   * the profile join is filtered to p_gym_id (DB-22);
--   * membership is decided by membership_is_active_for_access (DB-23);
--   * same-day duplicates are a graceful 'duplicate_checkin_today' and the
--     anti-tailgating window is 15 minutes returning 'already_inside'
--     (DB-24);
--   * the advisory-lock key and the last_used_at update use the hash;
--   * the logged credential_ref is the truncated form (DB-47).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_member_credential(
  p_gym_id uuid,
  p_credential_type text,
  p_credential_data text,
  p_device_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_today date := CURRENT_DATE;
  v_type_text text := lower(BTRIM(COALESCE(p_credential_type, '')));
  v_type public.member_credential_type;
  v_log_type public.gate_access_credential_type;
  v_credential_data text := BTRIM(COALESCE(p_credential_data, ''));
  v_credential_hash text;
  v_device_id text := NULLIF(BTRIM(COALESCE(p_device_id, '')), '');
  v_credential_ref text := public.turnstile_truncate_credential_ref(p_credential_data);
  v_client_id uuid;
  v_client_name text;
  v_has_profile boolean := false;
  v_membership_start_date date;
  v_membership_end_date date;
  v_is_user_active boolean;
  v_days_left integer;
BEGIN
  IF p_gym_id IS NULL OR v_type_text = '' OR v_credential_data = '' THEN
    RETURN jsonb_build_object(
      'access', false,
      'reason', 'invalid_credential'
    );
  END IF;

  IF v_type_text NOT IN ('rfid_card', 'fingerprint', 'face') THEN
    RETURN jsonb_build_object(
      'access', false,
      'reason', 'invalid_credential'
    );
  END IF;

  v_type := v_type_text::public.member_credential_type;
  v_log_type := v_type_text::public.gate_access_credential_type;

  -- DB-07: hash the presented credential for the lookup. Raises (fail
  -- closed) when the pepper is not configured — no plaintext fallback.
  v_credential_hash := public.hash_member_credential(v_credential_data);

  -- DB-07: the advisory-lock key uses the hash, never the raw credential.
  PERFORM public.lock_booking_key(
    format('turnstile:credential:%s:%s:%s', p_gym_id, v_type_text, v_credential_hash)
  );

  SELECT
    mc.client_id,
    u.name,
    cp.user_id IS NOT NULL,
    cp.membership_start_date,
    cp.membership_end_date,
    COALESCE(u.is_active, true)
  INTO
    v_client_id,
    v_client_name,
    v_has_profile,
    v_membership_start_date,
    v_membership_end_date,
    v_is_user_active
  FROM public.member_credentials mc
  JOIN public.users u
    ON u.id = mc.client_id
  LEFT JOIN public.client_profiles cp
    ON cp.user_id = mc.client_id
   AND cp.gym_id = p_gym_id
  WHERE mc.gym_id = p_gym_id
    AND mc.type = v_type
    AND mc.credential_hash = v_credential_hash
    AND mc.is_active = true
    AND u.role = 'client'
  FOR UPDATE OF mc;

  IF v_client_id IS NULL THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      NULL,
      v_log_type,
      v_credential_ref,
      false,
      'invalid_credential',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'invalid_credential'
    );
  END IF;

  -- DB-22/DB-23: no profile for THIS gym, or a deactivated user, is inactive.
  IF NOT v_has_profile OR COALESCE(v_is_user_active, true) = false THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      v_client_id,
      v_log_type,
      v_credential_ref,
      false,
      'membership_inactive',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'membership_inactive'
    );
  END IF;

  IF v_membership_end_date IS NOT NULL
     AND v_membership_end_date < v_today THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      v_client_id,
      v_log_type,
      v_credential_ref,
      false,
      'membership_expired',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'membership_expired'
    );
  END IF;

  -- DB-23: the shared definition is the final authority (payment status,
  -- start/end dates). The old 'payment_unpaid' reason is retired: trial /
  -- waived members are active under the shared rule.
  IF NOT public.membership_is_active_for_access(v_client_id, p_gym_id, v_today) THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      v_client_id,
      v_log_type,
      v_credential_ref,
      false,
      'membership_inactive',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'membership_inactive'
    );
  END IF;

  PERFORM public.lock_booking_key(
    format('turnstile:client:%s:%s', v_client_id, p_gym_id)
  );

  -- DB-24: anti-tailgating first — a scan within 15 minutes of a check-in
  -- reports 'already_inside'.
  IF EXISTS (
    SELECT 1
    FROM public.check_ins ci
    WHERE ci.gym_id = p_gym_id
      AND ci.client_id = v_client_id
      AND ci.checked_in_at >= (v_now - interval '15 minutes')
  ) THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      v_client_id,
      v_log_type,
      v_credential_ref,
      false,
      'already_inside',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'already_inside'
    );
  END IF;

  -- DB-24: one check-in per member per gym per calendar day — a graceful,
  -- logged denial instead of a raw unique-index error.
  IF EXISTS (
    SELECT 1
    FROM public.check_ins ci
    WHERE ci.gym_id = p_gym_id
      AND ci.client_id = v_client_id
      AND ci.checked_in_date = v_today
  ) THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      v_client_id,
      v_log_type,
      v_credential_ref,
      false,
      'duplicate_checkin_today',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'duplicate_checkin_today'
    );
  END IF;

  v_days_left := CASE
    WHEN v_membership_end_date IS NULL THEN NULL
    ELSE GREATEST(v_membership_end_date - v_today, 0)
  END;

  INSERT INTO public.check_ins (
    gym_id,
    client_id,
    checked_in_at,
    method,
    notes
  )
  VALUES (
    p_gym_id,
    v_client_id,
    v_now,
    v_type_text,
    jsonb_build_object(
      'source', 'turnstile',
      'device_id', v_device_id,
      'client_name', COALESCE(v_client_name, 'Client'),
      'days_left', v_days_left
    )::text
  );

  UPDATE public.member_credentials
  SET last_used_at = v_now
  WHERE gym_id = p_gym_id
    AND client_id = v_client_id
    AND type = v_type
    AND credential_hash = v_credential_hash;

  INSERT INTO public.gate_access_log (
    gym_id,
    client_id,
    credential_type,
    credential_ref,
    access_granted,
    denial_reason,
    device_id,
    attempted_at
  )
  VALUES (
    p_gym_id,
    v_client_id,
    v_log_type,
    v_credential_ref,
    true,
    NULL,
    v_device_id,
    v_now
  );

  RETURN jsonb_build_object(
    'access', true,
    'client_id', v_client_id,
    'client_name', COALESCE(v_client_name, 'Client'),
    'days_left', v_days_left
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- DB-25 — service-role-only gate-session validation RPC.
-- Atomic check-and-consume: a token is usable exactly once. The gate-checkin
-- edge function keeps its inline QR flow (membership must be checked BEFORE
-- the token is consumed); this RPC is the primitive for future callers.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_gate_session(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.gate_sessions%ROWTYPE;
BEGIN
  IF p_token IS NULL OR BTRIM(p_token) = '' THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'invalid_token');
  END IF;

  SELECT gs.*
  INTO v_session
  FROM public.gate_sessions gs
  WHERE gs.token = BTRIM(p_token)
    AND gs.used = false
    AND gs.expires_at > now()
  FOR UPDATE OF gs;

  IF v_session.id IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'invalid_token');
  END IF;

  UPDATE public.gate_sessions
  SET used = true,
      used_at = now()
  WHERE id = v_session.id;

  RETURN jsonb_build_object(
    'valid', true,
    'session_id', v_session.id,
    'client_id', v_session.client_id,
    'gym_id', v_session.gym_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.validate_gate_session(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_gate_session(text) TO service_role;
