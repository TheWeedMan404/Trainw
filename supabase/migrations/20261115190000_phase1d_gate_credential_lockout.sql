-- ============================================================================
-- Round 4 (DB-48) — gate credential lockout: 5 consecutive failures lock a
-- credential for 15 minutes.
--
-- validate_member_credential had no rate limiting of its own (the edge
-- function rate-limits the HTTP endpoint, but the RPC itself could be
-- called directly — and the turnstiles are currently disabled, so the
-- HTTP path is not the only one that matters). A stolen or guessed RFID
-- UID could be brute-forced without limit.
--
-- New table public.gate_credential_lockouts, scoped by (gym_id,
-- credential_hash, device_id) — device_id is '' when the terminal sends
-- none, so unknown-device attempts share one counter. RLS is enabled
-- with no policies: only the service role (via the SECURITY DEFINER
-- functions below) touches it, so it gets no authenticated grant under
-- the DB-41 model.
--
-- New helper public.record_gate_credential_failure(gym, hash, device)
-- returns the locked_until timestamp when the failure just triggered a
-- lock, else NULL. It upserts the counter; an expired lock restarts the
-- window at attempt 1; reaching 5 sets locked_until = now() + 15 min
-- and resets the counter to 0 (5 attempts per 15-minute window).
--
-- validate_member_credential (verbatim round-2 body + 4 insertions):
--   * after the credential advisory lock, a live lockout returns
--     {access:false, reason:'credential_locked', locked_until} and is
--     logged to gate_access_log (denial_reason is free text — no
--     constraint change needed);
--   * only the invalid-credential branch records a failure — a valid
--     credential denied for membership reasons must never lock a
--     legitimate member out;
--   * a successful validation clears the counter for that credential +
--     device.
-- The gate-checkin edge function passes the reason through unchanged,
-- and gate-terminal.js gains the French label for the new reason.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Lockout table.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.gate_credential_lockouts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id          uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  credential_hash text NOT NULL,
  device_id       text NOT NULL DEFAULT '',
  failed_attempts int NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  locked_until    timestamptz,
  first_failed_at timestamptz NOT NULL DEFAULT now(),
  last_failed_at  timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (gym_id, credential_hash, device_id)
);

ALTER TABLE public.gate_credential_lockouts ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_gate_credential_lockouts_locked
  ON public.gate_credential_lockouts(gym_id, locked_until)
  WHERE locked_until IS NOT NULL;

COMMENT ON TABLE public.gate_credential_lockouts IS
  'DB-48: per-credential+device failure counters for the gate. 5 consecutive failures lock the credential for 15 minutes. device_id is empty string when the terminal sends none. Service-role only (no policies, no authenticated grant).';

-- ----------------------------------------------------------------------------
-- Failure recorder.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_gate_credential_failure(
  p_gym_id uuid,
  p_credential_hash text,
  p_device_id text DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_device text := COALESCE(NULLIF(BTRIM(COALESCE(p_device_id, '')), ''), '');
  v_attempts int;
  v_locked_until timestamptz;
  v_now timestamptz := now();
BEGIN
  IF p_gym_id IS NULL OR COALESCE(p_credential_hash, '') = '' THEN
    RETURN NULL;
  END IF;

  SELECT failed_attempts, locked_until
  INTO v_attempts, v_locked_until
  FROM public.gate_credential_lockouts
  WHERE gym_id = p_gym_id
    AND credential_hash = p_credential_hash
    AND device_id = v_device
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.gate_credential_lockouts
      (gym_id, credential_hash, device_id, failed_attempts, first_failed_at, last_failed_at)
    VALUES (p_gym_id, p_credential_hash, v_device, 1, v_now, v_now);
    RETURN NULL;
  END IF;

  IF v_locked_until IS NOT NULL AND v_locked_until <= v_now THEN
    -- Lock expired: a fresh window, this failure is attempt 1.
    UPDATE public.gate_credential_lockouts
    SET failed_attempts = 1,
        locked_until = NULL,
        first_failed_at = v_now,
        last_failed_at = v_now,
        updated_at = v_now
    WHERE gym_id = p_gym_id
      AND credential_hash = p_credential_hash
      AND device_id = v_device;
    RETURN NULL;
  END IF;

  v_attempts := COALESCE(v_attempts, 0) + 1;

  IF v_attempts >= 5 THEN
    v_locked_until := v_now + interval '15 minutes';
    UPDATE public.gate_credential_lockouts
    SET failed_attempts = 0,
        locked_until = v_locked_until,
        last_failed_at = v_now,
        updated_at = v_now
    WHERE gym_id = p_gym_id
      AND credential_hash = p_credential_hash
      AND device_id = v_device;
    RETURN v_locked_until;
  END IF;

  UPDATE public.gate_credential_lockouts
  SET failed_attempts = v_attempts,
      last_failed_at = v_now,
      updated_at = v_now
  WHERE gym_id = p_gym_id
    AND credential_hash = p_credential_hash
    AND device_id = v_device;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.record_gate_credential_failure(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_gate_credential_failure(uuid, text, text) TO service_role;

COMMENT ON FUNCTION public.record_gate_credential_failure(uuid, text, text) IS
  'DB-48: records one failed gate credential attempt; returns the lock expiry when the failure just locked the credential (5 consecutive failures = 15-minute lock), else NULL.';

-- ----------------------------------------------------------------------------
-- validate_member_credential rewrite (round-2 body + DB-48 insertions).
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
  v_locked_until timestamptz;
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

  -- DB-48: credential lockout — 5 consecutive failures for the same
  -- credential + device lock the credential for 15 minutes. Checked here,
  -- after the advisory lock serialises concurrent scans of one credential.
  SELECT locked_until INTO v_locked_until
  FROM public.gate_credential_lockouts
  WHERE gym_id = p_gym_id
    AND credential_hash = v_credential_hash
    AND device_id = COALESCE(v_device_id, '')
  FOR UPDATE;

  IF v_locked_until IS NOT NULL AND v_locked_until > v_now THEN
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
      'credential_locked',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'credential_locked',
      'locked_until', v_locked_until
    );
  END IF;

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

    -- DB-48: only a failed CREDENTIAL counts toward the lockout — a
    -- valid credential denied for membership reasons must never lock a
    -- legitimate member out. The 5th consecutive failure locks the
    -- credential and returns that reason instead.
    v_locked_until := public.record_gate_credential_failure(
      p_gym_id, v_credential_hash, v_device_id
    );

    IF v_locked_until IS NOT NULL THEN
      RETURN jsonb_build_object(
        'access', false,
        'reason', 'credential_locked',
        'locked_until', v_locked_until
      );
    END IF;

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

  -- DB-48: a successful validation clears the failure counter for this
  -- credential + device.
  DELETE FROM public.gate_credential_lockouts
  WHERE gym_id = p_gym_id
    AND credential_hash = v_credential_hash
    AND device_id = COALESCE(v_device_id, '');

  RETURN jsonb_build_object(
    'access', true,
    'client_id', v_client_id,
    'client_name', COALESCE(v_client_name, 'Client'),
    'days_left', v_days_left
  );
END;
$$;
