-- ============================================================================
-- Round 5 (FE-18 follow-up) — server-side write idempotency.
--
-- The client-side double-submit guards (round 4, FE-18) stop double
-- clicks, but a retry after a lost response could still double-fire on
-- the server. The rule applied here: a retry of a request whose effect
-- already landed returns success (the existing id) instead of raising.
-- Every function below already locks its session row FOR UPDATE, so the
-- check-then-act is race-safe.
--
--   * leave_session_review: an existing review for the session is
--     returned instead of raising 'conflict'.
--   * book_coach_session: the same client re-booking the same coach,
--     date and start time gets the existing pending/confirmed session
--     back (no duplicate session, no duplicate pending payment). A
--     different client for the same slot raises 'conflict' — an
--     individual session has capacity 1 and the chain had no overlap
--     guard at all.
--   * respond/cancel/complete/no_show: already in the requested end
--     state returns success; a mismatched end state still raises
--     invalid_state (e.g. confirming a cancelled session).
--
-- Payments already carry idempotency keys (round 3, DB-17); direct
-- table writes that can only fail (not duplicate) on retry — manual
-- check-in (unique daily), message insert (no key; the client guard is
-- the control, see notes) — are unchanged.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.leave_session_review(
  p_session_id uuid,
  p_rating integer,
  p_comment text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
  v_review_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication_required: you must be logged in';
  END IF;

  IF public.get_my_role() <> 'client' THEN
    RAISE EXCEPTION 'forbidden: only clients can leave reviews';
  END IF;

  IF p_rating IS NULL OR p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'validation_error: rating must be between 1 and 5';
  END IF;

  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: session does not exist';
  END IF;

  IF v_session.client_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'forbidden: you can only review your own sessions';
  END IF;

  IF COALESCE(v_session.status, 'pending') <> 'completed' THEN
    RAISE EXCEPTION 'invalid_state: only completed sessions can be reviewed';
  END IF;

  -- Idempotent retry: a review already exists for this session (e.g.
  -- the first call succeeded but the response was lost) — return its id
  -- instead of raising. The session row is locked FOR UPDATE above, so
  -- two concurrent calls serialize here.
  SELECT id INTO v_review_id
  FROM public.reviews r
  WHERE r.session_id = p_session_id;
  IF v_review_id IS NOT NULL THEN
    RETURN v_review_id;
  END IF;

  INSERT INTO public.reviews (
    session_id,
    coach_id,
    client_id,
    gym_id,
    rating,
    comment
  )
  VALUES (
    p_session_id,
    v_session.coach_id,
    v_session.client_id,
    v_session.gym_id,
    p_rating,
    NULLIF(BTRIM(COALESCE(p_comment, '')), '')
  )
  RETURNING id INTO v_review_id;

  RETURN v_review_id;
END;
$$;

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

  -- Idempotent retry: the same client re-booking the same coach, date
  -- and start time returns the existing pending/confirmed session
  -- instead of creating a duplicate session (and a duplicate pending
  -- payment). The advisory locks above serialize concurrent calls, so
  -- the check-then-insert is race-safe. A different client for the same
  -- slot is a real conflict: an individual session has capacity 1.
  SELECT id INTO v_session_id
  FROM public.sessions s
  WHERE s.coach_id = p_coach_id
    AND s.client_id = v_client_id
    AND s.gym_id = v_client_gym_id
    AND s.session_date = p_session_date
    AND s.start_time = p_start_time
    AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
  ORDER BY s.created_at DESC
  LIMIT 1;
  IF v_session_id IS NOT NULL THEN
    RETURN v_session_id;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.sessions s
    WHERE s.coach_id = p_coach_id
      AND s.gym_id = v_client_gym_id
      AND s.session_date = p_session_date
      AND s.start_time = p_start_time
      AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
  ) THEN
    RAISE EXCEPTION 'conflict: this slot is already booked';
  END IF;

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

CREATE OR REPLACE FUNCTION public.respond_to_session_booking(
  p_session_id uuid,
  p_decision text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
  v_decision text := lower(BTRIM(COALESCE(p_decision, '')));
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
    RAISE EXCEPTION 'forbidden: you cannot update this booking';
  END IF;

  IF v_decision NOT IN ('confirmed', 'cancelled') THEN
    RAISE EXCEPTION 'validation_error: decision must be confirmed or cancelled';
  END IF;

  -- Idempotent retry: already in the requested end state returns success.
  IF COALESCE(v_session.status, 'pending') = v_decision THEN
    RETURN p_session_id;
  END IF;

  IF COALESCE(v_session.status, 'pending') <> 'pending' THEN
    RAISE EXCEPTION 'invalid_state: only pending sessions can be confirmed or rejected';
  END IF;

  UPDATE public.sessions
  SET status = v_decision,
      confirmed_at = CASE WHEN v_decision = 'confirmed' THEN COALESCE(confirmed_at, now()) ELSE confirmed_at END,
      cancelled_at = CASE WHEN v_decision = 'cancelled' THEN COALESCE(cancelled_at, now()) ELSE cancelled_at END,
      cancellation_reason = CASE
        WHEN v_decision = 'cancelled' THEN COALESCE(cancellation_reason, 'rejected_by_coach')
        ELSE cancellation_reason
      END,
      updated_by = auth.uid()
  WHERE id = p_session_id;

  IF v_decision = 'cancelled' AND v_session.payment_id IS NOT NULL THEN
    UPDATE public.payments
    SET status = CASE
          WHEN status IN ('pending', 'authorized') THEN 'cancelled'
          ELSE status
        END,
        cancelled_at = CASE
          WHEN status IN ('pending', 'authorized') THEN COALESCE(cancelled_at, now())
          ELSE cancelled_at
        END
    WHERE id = v_session.payment_id;
  END IF;

  RETURN p_session_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_session_booking(
  p_session_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
  v_reason text;
BEGIN
  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: session does not exist';
  END IF;

  IF NOT (
    public.manages_gym(v_session.gym_id)
    OR v_session.client_id = auth.uid()
    OR v_session.coach_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'forbidden: you cannot cancel this session';
  END IF;

  -- Idempotent retry: already cancelled returns success (the original
  -- cancelled_at / cancellation_reason are kept by the COALESCEs below).
  IF COALESCE(v_session.status, 'pending') = 'cancelled' THEN
    RETURN p_session_id;
  END IF;

  IF COALESCE(v_session.status, 'pending') NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'invalid_state: only pending or confirmed sessions can be cancelled';
  END IF;

  v_reason := NULLIF(BTRIM(COALESCE(p_reason, '')), '');
  IF v_reason IS NULL THEN
    v_reason := CASE
      WHEN v_session.client_id = auth.uid() THEN 'cancelled_by_client'
      WHEN v_session.coach_id = auth.uid() THEN 'cancelled_by_coach'
      ELSE 'cancelled_by_manager'
    END;
  END IF;

  UPDATE public.sessions
  SET status = 'cancelled',
      cancelled_at = COALESCE(cancelled_at, now()),
      cancellation_reason = v_reason,
      updated_by = auth.uid()
  WHERE id = p_session_id;

  IF v_session.payment_id IS NOT NULL THEN
    UPDATE public.payments
    SET status = CASE
          WHEN status IN ('pending', 'authorized') THEN 'cancelled'
          ELSE status
        END,
        cancelled_at = CASE
          WHEN status IN ('pending', 'authorized') THEN COALESCE(cancelled_at, now())
          ELSE cancelled_at
        END
    WHERE id = v_session.payment_id;
  END IF;

  RETURN p_session_id;
END;
$$;

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

  -- Idempotent retry: already completed returns success.
  IF COALESCE(v_session.status, 'pending') = 'completed' THEN
    RETURN p_session_id;
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

CREATE OR REPLACE FUNCTION public.mark_session_no_show(p_session_id uuid)
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
    RAISE EXCEPTION 'forbidden: you cannot update this session';
  END IF;

  -- Idempotent retry: already no_show returns success.
  IF COALESCE(v_session.status, 'pending') = 'no_show' THEN
    RETURN p_session_id;
  END IF;

  IF COALESCE(v_session.status, 'pending') <> 'confirmed' THEN
    RAISE EXCEPTION 'invalid_state: only confirmed sessions can be marked no-show';
  END IF;

  UPDATE public.sessions
  SET status = 'no_show',
      no_show_at = COALESCE(no_show_at, now()),
      updated_by = auth.uid()
  WHERE id = p_session_id;

  RETURN p_session_id;
END;
$$;

