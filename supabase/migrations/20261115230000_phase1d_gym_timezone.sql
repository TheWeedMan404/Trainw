-- DB-37 — compute "today" in the gym's timezone.
--
-- The database runs on UTC, but every membership / gate / check-in
-- cut-off was computed with CURRENT_DATE / LOCALTIME, i.e. the server's
-- date. For a Tunisian gym (Africa/Tunis, UTC+1) that is wrong for one
-- hour a day: between 23:00 and 23:59 UTC the server already thinks it
-- is tomorrow while the gym is still on today — a membership ending
-- today would read as expired at the gate, and a check-in at 00:30
-- Tunis time would be stamped on the wrong day. Any gym in another
-- timezone (MENA expansion) would be wrong for hours a day.
--
-- Fix: two helpers, gym_timezone(p_gym_id) and gym_today(p_gym_id),
-- read the gym's timezone (gyms.timezone, default Africa/Tunis) and
-- every access-path "today" goes through them:
--   * membership_is_active_for_access / client_membership_is_active:
--     the reference date now defaults to NULL meaning "the gym's
--     today" (an explicit date is still honoured — book_coach_session
--     passes the session date, and the ledger passes period dates).
--   * validate_member_credential: the same-day duplicate / tailgating
--     day is the gym's day.
--   * validate_session_write / book_coach_session /
--     complete_session_booking / get_bookable_slots: the past/future
--     checks use the gym's today (and, for booking, the gym's clock).
--   * shift_membership_for_freeze: freeze windows are judged on the
--     gym's day.
--   * enforce_check_in_membership: drops the explicit CURRENT_DATE and
--     uses the new default.
--   * check_ins.checked_in_date: was a GENERATED column in UTC
--     ((checked_in_at AT TIME ZONE 'UTC')::date) — a generated column
--     cannot read another table, so it becomes a plain column set by a
--     BEFORE INSERT/UPDATE trigger in the row's gym timezone, with a
--     backfill and a re-dedup for live data (two rows that were
--     different UTC days can land on the same gym day).
--
-- NOT changed on purpose (different concepts, not access cut-offs):
--   * ai_proxy_usage.day (per-user UTC quota day),
--   * the payments ledger's invoice_date / period fallbacks (business
--     dates, and the settlement trigger passes explicit dates),
--   * client_profiles.membership_start_date DEFAULT CURRENT_DATE (a
--     column default cannot see the row's gym),
--   * get_bookable_slots' slot timestamps, which are generated as
--     naive timestamps and compared to now() — the date filter is fixed
--     here, but generating slots in the gym timezone is a follow-up
--     (see the notes file).
--
-- Phase 1h (2026-11-15): the 1g commit changed
-- membership_is_active_for_access's freeze clause (raw p_reference_date
-- -> COALESCE with gym_today) without updating this file's frozen hash
-- for it, so a fresh chain apply failed here. Hash recomputed from the
-- current body: 45fdc7f004152f175c06411c6c660a29.
--
-- FREEZE NOTE (DB-61): membership_is_active_for_access and
-- client_membership_is_active are frozen helpers. Their definitions
-- change here, so the frozen hashes are updated at the end of this
-- migration (the assert is re-created with the new hashes, then run).
-- The freeze hash does NOT cover a function's DEFAULT expressions
-- (proargdefaults is not in the hash formula) — a default-only change
-- would slip past the tripwire. This migration changes the bodies too,
-- so the hashes do change; hardening the hash to include defaults is
-- recorded as a follow-up in the notes file.

-- ----------------------------------------------------------------------------
-- Helpers: the gym's timezone and "today" in it.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.gym_timezone(p_gym_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    NULLIF(BTRIM((SELECT g.timezone FROM public.gyms g WHERE g.id = p_gym_id)), ''),
    'Africa/Tunis'
  );
$$;

CREATE OR REPLACE FUNCTION public.gym_today(p_gym_id uuid)
RETURNS date
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT (now() AT TIME ZONE public.gym_timezone(p_gym_id))::date;
$$;

-- ----------------------------------------------------------------------------
-- membership_is_active_for_access / client_membership_is_active
-- (DB-61 frozen helpers — hashes updated at the end of this file).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.membership_is_active_for_access(p_client_id uuid, p_gym_id uuid, p_reference_date date DEFAULT NULL)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        OR cp.membership_start_date <= COALESCE(p_reference_date, public.gym_today(p_gym_id))
      )
      AND (
        cp.membership_end_date IS NULL
        OR cp.membership_end_date >= COALESCE(p_reference_date, public.gym_today(p_gym_id))
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.membership_freezes f
        WHERE f.user_id = p_client_id
          AND f.gym_id = p_gym_id
          AND f.status = 'active'
          AND COALESCE(p_reference_date, public.gym_today(p_gym_id)) BETWEEN f.start_date AND f.end_date
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.client_membership_is_active(p_client_id uuid, p_reference_date date DEFAULT NULL)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.client_profiles cp
    WHERE cp.user_id = p_client_id
      AND public.membership_is_active_for_access(p_client_id, cp.gym_id, COALESCE(p_reference_date, public.gym_today(cp.gym_id)))
  );
$function$;
-- ----------------------------------------------------------------------------
-- validate_member_credential: the gate's 'today' is the gym's day.
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
  v_today date := public.gym_today(p_gym_id);
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
-- ----------------------------------------------------------------------------
-- validate_session_write: the future-session check uses the gym's day.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_session_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_coach_gym_id uuid;
  v_client_gym_id uuid;
  v_class_gym_id uuid;
  v_payment_gym_id uuid;
  v_payment_client_id uuid;
  v_active_enrollment_count integer;
  v_range tsrange;
BEGIN
  IF NEW.gym_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: session gym is required';
  END IF;

  IF NEW.status IN ('pending', 'confirmed', 'completed', 'no_show')
     AND NEW.start_time IS NULL THEN
    RAISE EXCEPTION 'validation_error: active sessions require a start time';
  END IF;

  IF NEW.coach_id IS NOT NULL THEN
    SELECT u.gym_id
    INTO v_coach_gym_id
    FROM public.users u
    WHERE u.id = NEW.coach_id
      AND u.role = 'coach';

    IF v_coach_gym_id IS NULL THEN
      RAISE EXCEPTION 'validation_error: session coach must be a coach user';
    END IF;

    IF v_coach_gym_id IS DISTINCT FROM NEW.gym_id THEN
      RAISE EXCEPTION 'validation_error: coach must belong to the session gym';
    END IF;
  END IF;

  IF NEW.client_id IS NOT NULL THEN
    SELECT u.gym_id
    INTO v_client_gym_id
    FROM public.users u
    WHERE u.id = NEW.client_id
      AND u.role = 'client';

    IF v_client_gym_id IS NULL THEN
      RAISE EXCEPTION 'validation_error: session client must be a client user';
    END IF;

    IF v_client_gym_id IS DISTINCT FROM NEW.gym_id THEN
      RAISE EXCEPTION 'validation_error: client must belong to the session gym';
    END IF;
  END IF;

  IF NEW.class_id IS NOT NULL THEN
    SELECT gc.gym_id
    INTO v_class_gym_id
    FROM public.gym_classes gc
    WHERE gc.id = NEW.class_id;

    IF v_class_gym_id IS NULL THEN
      RAISE EXCEPTION 'validation_error: linked class does not exist';
    END IF;

    IF v_class_gym_id IS DISTINCT FROM NEW.gym_id THEN
      RAISE EXCEPTION 'validation_error: linked class must belong to the session gym';
    END IF;
  END IF;

  IF NEW.payment_id IS NOT NULL THEN
    SELECT p.gym_id, p.client_id
    INTO v_payment_gym_id, v_payment_client_id
    FROM public.payments p
    WHERE p.id = NEW.payment_id;

    IF v_payment_gym_id IS NULL THEN
      RAISE EXCEPTION 'validation_error: linked payment does not exist';
    END IF;

    IF v_payment_gym_id IS DISTINCT FROM NEW.gym_id THEN
      RAISE EXCEPTION 'validation_error: linked payment must belong to the session gym';
    END IF;

    IF NEW.client_id IS NOT NULL
       AND v_payment_client_id IS NOT NULL
       AND v_payment_client_id IS DISTINCT FROM NEW.client_id THEN
      RAISE EXCEPTION 'validation_error: linked payment must belong to the session client';
    END IF;
  END IF;

  IF NEW.type IN ('individual_training', 'assessment')
     AND NEW.status IN ('confirmed', 'completed', 'no_show')
     AND NEW.client_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: individual sessions must have a client';
  END IF;

  IF NEW.status IN ('completed', 'no_show')
     AND NEW.session_date > public.gym_today(NEW.gym_id) THEN
    RAISE EXCEPTION 'invalid_state: future sessions cannot be completed or marked no-show';
  END IF;

  SELECT COUNT(*)
  INTO v_active_enrollment_count
  FROM public.session_enrollments se
  WHERE se.session_id = COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

  IF NEW.type NOT IN ('individual_training', 'assessment')
     AND v_active_enrollment_count > NEW.capacity THEN
    RAISE EXCEPTION 'validation_error: session capacity is below existing enrollments';
  END IF;

  IF NEW.status IN ('pending', 'confirmed')
     AND NEW.start_time IS NOT NULL
     AND NEW.end_time IS NOT NULL THEN
    v_range := public.session_time_range(
      NEW.session_date,
      NEW.start_time,
      NEW.end_time,
      NEW.duration_minutes
    );

    IF NEW.coach_id IS NOT NULL THEN
      PERFORM public.lock_booking_key(
        format('session:coach:%s:%s', NEW.coach_id, NEW.session_date)
      );

      IF EXISTS (
        SELECT 1
        FROM public.sessions s
        WHERE s.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
          AND s.coach_id = NEW.coach_id
          AND s.session_date = NEW.session_date
          AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
          AND public.session_time_range(
                s.session_date,
                s.start_time,
                s.end_time,
                s.duration_minutes
              ) && v_range
      ) THEN
        RAISE EXCEPTION 'conflict: coach already has a session in that slot';
      END IF;
    END IF;

    IF NEW.client_id IS NOT NULL THEN
      PERFORM public.lock_booking_key(
        format('session:client:%s:%s', NEW.client_id, NEW.session_date)
      );

      IF EXISTS (
        SELECT 1
        FROM public.sessions s
        WHERE s.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
          AND s.client_id = NEW.client_id
          AND s.session_date = NEW.session_date
          AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
          AND public.session_time_range(
                s.session_date,
                s.start_time,
                s.end_time,
                s.duration_minutes
              ) && v_range
      ) THEN
        RAISE EXCEPTION 'conflict: client already has a session in that slot';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
-- ----------------------------------------------------------------------------
-- book_coach_session: the past-booking check uses the gym's day and clock.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.book_coach_session(
  p_coach_id uuid,
  p_session_date date,
  p_start_time time,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_client_id uuid := auth.uid();
  v_client_gym_id uuid := public.get_my_gym_id();
  v_coach_gym_id uuid;
  v_slot_minutes integer;
  v_price numeric(10,2);
  v_session_id uuid;
  v_payment_id uuid;
  v_assignment_id uuid;
  v_today date;
  v_now_time time;
  v_assignment_status text;
BEGIN
  IF v_client_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required: you must be logged in';
  END IF;

  IF public.get_my_role() <> 'client' THEN
    RAISE EXCEPTION 'forbidden: only clients can book coach sessions';
  END IF;

  IF v_client_gym_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: client must belong to a gym';
  END IF;

  IF NOT public.client_membership_is_active(v_client_id, p_session_date) THEN
    RAISE EXCEPTION 'forbidden: membership must be active before booking';
  END IF;

  IF p_session_date IS NULL OR p_start_time IS NULL THEN
    RAISE EXCEPTION 'validation_error: date and start time are required';
  END IF;

  v_today := public.gym_today(v_client_gym_id);
  v_now_time := (now() AT TIME ZONE public.gym_timezone(v_client_gym_id))::time;

  IF p_session_date < v_today
     OR (p_session_date = v_today AND p_start_time <= v_now_time) THEN
    RAISE EXCEPTION 'validation_error: booking time must be in the future';
  END IF;

  SELECT
    COALESCE(cp.gym_id, u.gym_id),
    ca.slot_minutes,
    COALESCE(cp.price_per_session, cp.hourly_rate, 0)
  INTO
    v_coach_gym_id,
    v_slot_minutes,
    v_price
  FROM public.users u
  JOIN public.coach_profiles cp
    ON cp.user_id = u.id
  JOIN public.coach_availability ca
    ON ca.coach_id = u.id
  WHERE u.id = p_coach_id
    AND u.role = 'coach'
    AND cp.approval_status = 'approved'
    AND cp.is_active = true
    AND ca.is_active = true
    AND ca.day_of_week = EXTRACT(DOW FROM p_session_date)::integer
    AND p_start_time >= ca.start_time
    AND public.session_effective_end_time(p_start_time, NULL, ca.slot_minutes) <= ca.end_time
    AND MOD(
          EXTRACT(EPOCH FROM (p_start_time - ca.start_time))::integer / 60,
          ca.slot_minutes
        ) = 0
    AND (ca.valid_from IS NULL OR p_session_date >= ca.valid_from)
    AND (ca.valid_until IS NULL OR p_session_date <= ca.valid_until)
  ORDER BY ca.start_time
  LIMIT 1;

  IF v_coach_gym_id IS NULL OR v_coach_gym_id IS DISTINCT FROM v_client_gym_id THEN
    RAISE EXCEPTION 'forbidden: coach is not available for your gym';
  END IF;

  IF v_slot_minutes IS NULL THEN
    RAISE EXCEPTION 'not_bookable: selected slot does not match coach availability';
  END IF;

  PERFORM public.lock_booking_key(format('session:coach:%s:%s', p_coach_id, p_session_date));
  PERFORM public.lock_booking_key(format('session:client:%s:%s', v_client_id, p_session_date));

  INSERT INTO public.sessions (
    gym_id,
    coach_id,
    client_id,
    session_date,
    start_time,
    duration_minutes,
    type,
    status,
    notes,
    capacity,
    session_name,
    booking_source,
    created_by,
    updated_by
  )
  VALUES (
    v_client_gym_id,
    p_coach_id,
    v_client_id,
    p_session_date,
    p_start_time,
    v_slot_minutes,
    'individual_training',
    'pending',
    NULLIF(BTRIM(COALESCE(p_notes, '')), ''),
    1,
    'Coach Session',
    'client',
    v_client_id,
    v_client_id
  )
  RETURNING id INTO v_session_id;

  IF COALESCE(v_price, 0) > 0 THEN
    INSERT INTO public.payments (
      gym_id,
      client_id,
      session_id,
      created_by,
      payment_type,
      status,
      provider,
      amount_total,
      amount_paid,
      currency_code,
      metadata
    )
    VALUES (
      v_client_gym_id,
      v_client_id,
      v_session_id,
      v_client_id,
      'session',
      'pending',
      'manual',
      v_price,
      0,
      'TND',
      jsonb_build_object('source', 'book_coach_session')
    )
    RETURNING id INTO v_payment_id;

    UPDATE public.sessions
    SET payment_id = v_payment_id,
        updated_by = v_client_id
    WHERE id = v_session_id;
  END IF;

  -- DB-45: booking no longer grants the coach ongoing data access. It
  -- creates a PENDING assignment only; the coach (or a gym manager) must
  -- confirm it via confirm_coach_client_assignment() before
  -- can_manage_client_data() grants anything. An ended assignment is
  -- never reactivated by a booking — a fresh pending row is created.
  SELECT cca.id, cca.status
  INTO v_assignment_id, v_assignment_status
  FROM public.coach_client_assignments cca
  WHERE cca.coach_id = p_coach_id
    AND cca.client_id = v_client_id
    AND cca.gym_id = v_client_gym_id
  ORDER BY
    CASE cca.status WHEN 'active' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END,
    cca.assigned_at DESC, cca.created_at DESC, cca.id DESC
  LIMIT 1;

  IF v_assignment_id IS NULL OR v_assignment_status = 'ended' THEN
    INSERT INTO public.coach_client_assignments (
      coach_id,
      client_id,
      gym_id,
      assigned_by,
      assigned_at,
      status,
      is_active
    )
    VALUES (
      p_coach_id,
      v_client_id,
      v_client_gym_id,
      v_client_id,
      now(),
      'pending',
      false
    );
  END IF;
  -- A pending/active row already exists: leave it exactly as it is.

  RETURN v_session_id;
END;
$$;
-- ----------------------------------------------------------------------------
-- complete_session_booking: the future check uses the session gym's day.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.complete_session_booking(p_session_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
BEGIN
  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: session does not exist';
  END IF;

  IF NOT (public.manages_gym(v_session.gym_id) OR v_session.coach_id = auth.uid()) THEN
    RAISE EXCEPTION 'forbidden: you cannot complete this session';
  END IF;

  IF COALESCE(v_session.status, 'pending') <> 'confirmed' THEN
    RAISE EXCEPTION 'invalid_state: only confirmed sessions can be completed';
  END IF;

  IF v_session.session_date > public.gym_today(v_session.gym_id) THEN
    RAISE EXCEPTION 'invalid_state: future sessions cannot be completed';
  END IF;

  UPDATE public.sessions
  SET status = 'completed',
      completed_at = COALESCE(completed_at, now()),
      updated_by = auth.uid()
  WHERE id = p_session_id;

  RETURN p_session_id;
END;
$$;
-- ----------------------------------------------------------------------------
-- get_bookable_slots: the date filter uses the caller's gym day.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_bookable_slots(
  p_coach_id uuid,
  p_session_date date
)
RETURNS TABLE (
  slot_time text,
  slot_end_time text,
  slot_minutes integer,
  price_per_session numeric
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH coach_data AS (
    SELECT
      u.id AS coach_id,
      COALESCE(cp.gym_id, u.gym_id) AS gym_id,
      cp.approval_status,
      cp.is_active,
      COALESCE(cp.price_per_session, cp.hourly_rate, 0) AS price_per_session
    FROM public.users u
    JOIN public.coach_profiles cp
      ON cp.user_id = u.id
    WHERE u.id = p_coach_id
      AND u.role = 'coach'
  ),
  windows AS (
    SELECT
      ca.start_time,
      ca.end_time,
      ca.slot_minutes,
      cd.price_per_session
    FROM public.coach_availability ca
    JOIN coach_data cd
      ON TRUE
    WHERE p_session_date IS NOT NULL
      AND p_session_date >= public.gym_today(public.get_my_gym_id())
      AND ca.coach_id = p_coach_id
      AND ca.is_active = true
      AND cd.approval_status = 'approved'
      AND cd.is_active = true
      AND COALESCE(ca.gym_id, cd.gym_id) = public.get_my_gym_id()
      AND ca.day_of_week = EXTRACT(DOW FROM p_session_date)::integer
      AND (ca.valid_from IS NULL OR p_session_date >= ca.valid_from)
      AND (ca.valid_until IS NULL OR p_session_date <= ca.valid_until)
  ),
  raw_slots AS (
    SELECT
      gs.slot_start_ts,
      (gs.slot_start_ts + make_interval(mins => w.slot_minutes)) AS slot_end_ts,
      w.slot_minutes,
      w.price_per_session
    FROM windows w
    CROSS JOIN LATERAL generate_series(
      p_session_date + w.start_time,
      p_session_date + w.end_time - make_interval(mins => w.slot_minutes),
      make_interval(mins => w.slot_minutes)
    ) AS gs(slot_start_ts)
  )
  SELECT
    to_char(rs.slot_start_ts, 'HH24:MI') AS slot_time,
    to_char(rs.slot_end_ts, 'HH24:MI') AS slot_end_time,
    rs.slot_minutes,
    rs.price_per_session
  FROM raw_slots rs
  WHERE rs.slot_start_ts > now()
    AND NOT EXISTS (
      SELECT 1
      FROM public.sessions s
      WHERE s.coach_id = p_coach_id
        AND s.session_date = p_session_date
        AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
        AND public.session_time_range(
              s.session_date,
              s.start_time,
              s.end_time,
              s.duration_minutes
            ) && tsrange(rs.slot_start_ts, rs.slot_end_ts, '[)')
    )
  ORDER BY rs.slot_start_ts;
$$;
-- ----------------------------------------------------------------------------
-- shift_membership_for_freeze: freeze windows judged on the gym's day.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.shift_membership_for_freeze()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days integer;
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'active' AND NEW.end_date >= public.gym_today(NEW.gym_id) THEN
    v_days := NEW.end_date - NEW.start_date;
    IF v_days > 0 THEN
      UPDATE public.client_profiles
      SET membership_end_date = (
            CASE WHEN membership_end_date IS NULL THEN NULL
                 ELSE (membership_end_date + v_days)::date END),
          updated_at = now()
      WHERE user_id = NEW.user_id AND gym_id = NEW.gym_id;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
    AND OLD.status = 'active'
    AND NEW.status = 'cancelled'
    AND OLD.end_date >= public.gym_today(OLD.gym_id) THEN
    v_days := OLD.end_date - OLD.start_date;
    IF v_days > 0 THEN
      UPDATE public.client_profiles
      SET membership_end_date = (
            CASE WHEN membership_end_date IS NULL THEN NULL
                 ELSE GREATEST(
                   COALESCE(membership_start_date, public.gym_today(NEW.gym_id)),
                   (membership_end_date - v_days)::date
                 ) END),
          updated_at = now()
      WHERE user_id = NEW.user_id AND gym_id = NEW.gym_id;
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;
-- ----------------------------------------------------------------------------
-- enforce_check_in_membership: use the new default (the gym's today).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_check_in_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Service-role callers (the gate functions) enforce membership
  -- themselves before inserting, so they bypass. Everyone else — a
  -- manager, coach or client inserting manually — must hold an active
  -- membership for this gym.
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    IF NOT public.membership_is_active_for_access(NEW.client_id, NEW.gym_id) THEN
      RAISE EXCEPTION 'Membership is not active for check-in.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
-- ----------------------------------------------------------------------------
-- check_ins.checked_in_date: generated in UTC -> set by trigger in the
-- row's gym timezone.
-- ----------------------------------------------------------------------------

ALTER TABLE public.check_ins DROP COLUMN IF EXISTS checked_in_date;
ALTER TABLE public.check_ins ADD COLUMN checked_in_date date;

-- Backfill for live data: recompute from checked_in_at in each row's
-- gym timezone (Africa/Tunis when the gym is missing).
UPDATE public.check_ins ci
SET checked_in_date = (ci.checked_in_at AT TIME ZONE COALESCE(g.timezone, 'Africa/Tunis'))::date
FROM public.gyms g
WHERE g.id = ci.gym_id AND ci.checked_in_at IS NOT NULL;

UPDATE public.check_ins ci
SET checked_in_date = (ci.checked_in_at AT TIME ZONE 'Africa/Tunis')::date
WHERE ci.checked_in_at IS NOT NULL
  AND ci.checked_in_date IS NULL;

-- Re-run the 009 dedup: two rows that were different UTC days can land
-- on the same gym day.
WITH ranked_check_ins AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY gym_id, client_id, checked_in_date
           ORDER BY checked_in_at ASC, id ASC
         ) AS row_num
  FROM public.check_ins
  WHERE checked_in_date IS NOT NULL
)
DELETE FROM public.check_ins ci
USING ranked_check_ins ranked
WHERE ci.id = ranked.id
  AND ranked.row_num > 1;

CREATE OR REPLACE FUNCTION public.set_check_in_date()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.checked_in_at IS NOT NULL THEN
    NEW.checked_in_date := (NEW.checked_in_at AT TIME ZONE public.gym_timezone(NEW.gym_id))::date;
  ELSE
    NEW.checked_in_date := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_check_in_date ON public.check_ins;
CREATE TRIGGER trg_set_check_in_date
  BEFORE INSERT OR UPDATE OF checked_in_at ON public.check_ins
  FOR EACH ROW EXECUTE FUNCTION public.set_check_in_date();

CREATE UNIQUE INDEX IF NOT EXISTS uq_check_ins_gym_client_day
ON public.check_ins (gym_id, client_id, checked_in_date);

-- ----------------------------------------------------------------------------
-- DB-61 freeze update for the two changed helpers.
-- The new hashes are filled in after the first apply (computed from the
-- live definitions with the assert's own formula) and the assert is
-- re-created with them, then run. Placeholder until then — see below.
-- ----------------------------------------------------------------------------

-- DB-37 (20261115230000): hashes updated for
-- membership_is_active_for_access and client_membership_is_active,
-- whose reference date now defaults to NULL (the gym's today).
CREATE OR REPLACE FUNCTION public.assert_rls_helpers_frozen()
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $freeze$
DECLARE
  v_bad text;
BEGIN
  WITH expected(signature, definition_hash) AS (
    VALUES
      ('auth_user_email(p_user_id uuid)', '68813f886337e6bd2e0f1e3e71d27bfd'),
      ('caller_holds_permission_in_gym(p_permission_code text, p_gym_id uuid)', '2afec0f282864f769b6a5c725091d784'),
      ('caller_manages_gym_direct(p_gym_id uuid)', '2d2cc8caa77b341122a605a24c7dab66'),
      ('can_manage_client_data(p_client_id uuid, p_gym_id uuid)', '162814305a7fdc34b557e8e10a41cb7d'),
      ('can_manage_sessions(p_gym_id uuid)', '4ce5d3db59e75df7c9f5dbb53fede941'),
      ('can_message_user(p_other_user_id uuid, p_gym_id uuid)', 'ccc71d2ad5793763bf324fa22ff8fb97'),
      ('can_read_workout_log(p_log_id uuid)', 'a41a103e3be5d780c4c7abd7979ae803'),
      ('can_read_workout_plan(p_plan_id uuid)', '4bea08bfea5b51eb06b292831ba682bc'),
      ('can_view_user(p_user_id uuid)', 'f8dbcbcbb26cf6744e57c4d6bc1659ec'),
      ('can_write_workout_log(p_log_id uuid)', '41c54b06c04a5990abbff3c410784136'),
      ('can_write_workout_plan(p_plan_id uuid)', '1adf43d4b6c044aad740d0bec63db642'),
      ('client_membership_is_active(p_client_id uuid, p_reference_date date)', '6a710ac86dc5e56468b247dea2f8cab9'),
      ('current_membership(p_requested_gym_id uuid)', '83be8d645898a6780d7beff3b90d97db'),
      ('get_my_gym_id()', '0a82c7547a021a4c51c7c4bae88a0ac4'),
      ('get_my_permissions(p_gym_id uuid)', '0f33fbd61e2477469c6ca8969ec64462'),
      ('get_my_portal()', '2673176cfa8fdf097b01b6a8cee329a7'),
      ('get_my_role()', '19ab56717fe1ff10600c1b97502b7dc6'),
      ('get_signup_role()', '38dd3bd6f7d2204c1b0c33e438a49622'),
      ('has_permission(p_permission_code text, p_gym_id uuid)', 'efad206bf5b2c86873e2348f06cd8dae'),
      ('is_gym_manager()', '88054510fd5cfad7222b4eb9b46ddd6f'),
      ('is_same_gym_user(p_user_id uuid)', '61dbb3359536ba80c501284444e42385'),
      ('lock_booking_key(p_key text)', 'a0ec8b10f159f279d43aa05163710ccd'),
      ('manages_gym(p_gym_id uuid)', '3d67f24e1a9ad1d2a21852e2dece2911'),
      ('membership_is_active_for_access(p_client_id uuid, p_gym_id uuid, p_reference_date date)', '45fdc7f004152f175c06411c6c660a29'),
      ('permission_codes_for_membership(p_membership_id uuid)', 'b4307205e32ac9d478656510daf95349'),
      ('safe_uuid(p_value text)', 'ad93f96932948e740ac01cf02c010ea2'),
      ('storage_object_is_public(p_bucket text, p_path text)', 'b92dad2a3ee8cce1ad4ac22e05566231'),
      ('user_gym_id(p_user_id uuid)', '7f1fdc9a845a1a86adb86ac3d315ac2e'),
      ('user_has_membership(p_gym_id uuid, p_user_id uuid)', '94ac0afc764b1820e42da1ed2cdaab1d'),
      ('user_role(p_user_id uuid)', 'c1e6720d1dffad16835c292af0d723d9')
  ), actual AS (
    SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS signature,
           md5(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
             || '|' || pg_get_function_result(p.oid)
             || '|' || l.lanname
             || '|' || p.provolatile::text
             || '|' || p.prosecdef::text
             || '|' || COALESCE(array_to_string(p.proconfig, ','), '')
             || '|' || p.prosrc) AS definition_hash
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname = 'public'
  )
  SELECT string_agg(e.signature, ', ' ORDER BY e.signature)
  INTO v_bad
  FROM expected e
  LEFT JOIN actual a ON a.signature = e.signature
  WHERE a.signature IS NULL OR a.definition_hash <> e.definition_hash;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'RLS helper definitions drifted from the DB-61 freeze: %', v_bad;
  END IF;
END;
$freeze$;

SELECT public.assert_rls_helpers_frozen();
