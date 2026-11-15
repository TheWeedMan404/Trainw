-- ============================================================================
-- Round 4 (DB-45) — coach/client assignments are pending until confirmed.
--
-- book_coach_session used to auto-create (or reactivate) a
-- coach_client_assignments row with is_active = true and
-- assigned_by = the client themselves. Booking a session silently granted
-- that coach data access to the client under can_manage_client_data
-- (weight logs, workout logs, goals) with no manager approval and no
-- expiry — even if a previous assignment had been ended.
--
-- New model:
--   * coach_client_assignments gains a status column
--     ('pending' | 'active' | 'ended'); status is the source of truth.
--   * is_active is a derived mirror kept in sync by a trigger
--     (is_active = (status = 'active')), so every existing reader
--     (can_manage_client_data, can_message_user, the frontend) enforces
--     the new model with no edits to those functions.
--   * book_coach_session creates a PENDING row only and never reactivates
--     an ended one (a fresh pending row is created instead).
--   * confirm_coach_client_assignment() (assigned coach or gym manager)
--     moves pending -> active; end_coach_client_assignment() (coach,
--     client, or manager) moves pending/active -> ended.
--   * The manager UI (tw-gym-acc-v17.js) writes status directly, so a
--     manager assigning a coach is the confirmation and stays active.
--   * Legacy is_active writes are honoured by the trigger (an explicit
--     is_active change with an unchanged status derives status from it),
--     so cached frontend JS keeps working.
--   * Existing rows are grandfathered: is_active = true becomes
--     status = 'active' (they were granted under the old model).
-- ============================================================================

-- 1. Status column + backfill. The is_active default flips to false so a
--    row that omits both columns is pending, not silently active.
ALTER TABLE public.coach_client_assignments
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending';

ALTER TABLE public.coach_client_assignments
  ADD CONSTRAINT coach_client_assignments_status_check
  CHECK (status IN ('pending', 'active', 'ended'));

UPDATE public.coach_client_assignments
SET status = CASE WHEN is_active THEN 'active' ELSE 'ended' END
WHERE status = 'pending';

ALTER TABLE public.coach_client_assignments
  ALTER COLUMN is_active SET DEFAULT false;

-- 2. Sync trigger: status is the source of truth, is_active the mirror.
CREATE OR REPLACE FUNCTION public.sync_coach_assignment_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $func$
BEGIN
  -- Legacy direct is_active writes (cached manager UI): an explicit
  -- is_active change with an unchanged status derives status from it.
  IF TG_OP = 'UPDATE'
     AND NEW.is_active IS DISTINCT FROM OLD.is_active
     AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    NEW.status := CASE WHEN NEW.is_active THEN 'active' ELSE 'ended' END;
  ELSIF TG_OP = 'INSERT'
     AND NEW.is_active
     AND NEW.status = 'pending' THEN
    -- Legacy manager upsert passes is_active = true with no status.
    NEW.status := 'active';
  END IF;

  NEW.is_active := (NEW.status = 'active');
  IF NEW.status = 'ended' AND NEW.ended_at IS NULL THEN
    NEW.ended_at := now();
  ELSIF NEW.status <> 'ended' THEN
    NEW.ended_at := NULL;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_coach_assignment_sync_status ON public.coach_client_assignments;
CREATE TRIGGER trg_coach_assignment_sync_status
  BEFORE INSERT OR UPDATE ON public.coach_client_assignments
  FOR EACH ROW EXECUTE FUNCTION public.sync_coach_assignment_status();

COMMENT ON FUNCTION public.sync_coach_assignment_status() IS
  'DB-45: status is the source of truth for coach_client_assignments; is_active is a derived mirror (is_active = (status = ''active'')). can_manage_client_data/can_message_user read is_active, so they enforce the pending model through this trigger.';

-- 3. book_coach_session: pending-only assignment (verbatim rewrite of the
--    003 definition with only the assignment block changed).
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

  IF p_session_date < CURRENT_DATE
     OR (p_session_date = CURRENT_DATE AND p_start_time <= LOCALTIME) THEN
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

-- 4. Confirm / end RPCs.
CREATE OR REPLACE FUNCTION public.confirm_coach_client_assignment(p_assignment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
  v_row public.coach_client_assignments%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public.coach_client_assignments WHERE id = p_assignment_id;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'not_found: assignment does not exist';
  END IF;
  IF NOT (auth.uid() = v_row.coach_id OR public.manages_gym(v_row.gym_id)) THEN
    RAISE EXCEPTION 'forbidden: only the assigned coach or a gym manager can confirm';
  END IF;
  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'invalid_state: only a pending assignment can be confirmed (current: %)', v_row.status;
  END IF;
  UPDATE public.coach_client_assignments
  SET status = 'active', updated_at = now()
  WHERE id = p_assignment_id;
END;
$func$;

REVOKE ALL ON FUNCTION public.confirm_coach_client_assignment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_coach_client_assignment(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.end_coach_client_assignment(p_assignment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
  v_row public.coach_client_assignments%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public.coach_client_assignments WHERE id = p_assignment_id;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'not_found: assignment does not exist';
  END IF;
  IF NOT (auth.uid() = v_row.coach_id OR auth.uid() = v_row.client_id OR public.manages_gym(v_row.gym_id)) THEN
    RAISE EXCEPTION 'forbidden: only the coach, the client, or a gym manager can end an assignment';
  END IF;
  IF v_row.status = 'ended' THEN
    RAISE EXCEPTION 'invalid_state: assignment is already ended';
  END IF;
  UPDATE public.coach_client_assignments
  SET status = 'ended', updated_at = now()
  WHERE id = p_assignment_id;
END;
$func$;

REVOKE ALL ON FUNCTION public.end_coach_client_assignment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.end_coach_client_assignment(uuid) TO authenticated;

COMMENT ON FUNCTION public.confirm_coach_client_assignment(uuid) IS
  'DB-45: pending -> active. Only the assigned coach or a gym manager. Booking alone no longer grants data access.';
COMMENT ON FUNCTION public.end_coach_client_assignment(uuid) IS
  'DB-45: pending/active -> ended. Coach, client, or gym manager.';
