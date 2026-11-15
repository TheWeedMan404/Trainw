-- ============================================================================
-- TRAINW PHASE 1B — TRIGGER FUNCTIONS THAT WRITE RLS-PROTECTED TABLES
-- Audit 2026-11-14: DB-31 (SUSPECTED).
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- The audit/refresh trigger functions below write to RLS-protected tables
-- (payment_events, session_status_history, sessions, coach_profiles) but
-- were SECURITY INVOKER: fired by an ordinary authenticated user, their
-- writes were evaluated against that user's RLS policies and silently
-- failed (or raised) — the audit trail and the attendee/review counters
-- quietly stopped updating. They are recreated here as SECURITY DEFINER
-- with SET search_path = public, the same pattern as
-- sync_booking_from_session (007), which already is. Bodies are verbatim
-- from 003 apart from the added SECURITY DEFINER.
-- NOTE: auth.uid() inside these functions still returns the CALLER's id
-- (it comes from the JWT, not the role), so the created_by / changed_by
-- attribution in the audit rows is unchanged.
-- prepare_payment_write / prepare_session_write / validate_* only mutate
-- NEW and need no change.
--
-- VERIFICATION (no live DB was available when this was written):
--   * As a plain client, insert/update a payment and a session: the
--     payment_events / session_status_history rows must appear, and the
--     session attendee_count must refresh. Before this fix they did not.
--   * Confirm on staging that no trigger now fails with an RLS error.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sync_session_enrollment_counts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.refresh_session_attendee_count(COALESCE(NEW.session_id, OLD.session_id));
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_session_after_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.refresh_session_attendee_count(NEW.id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_reviews_after_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM public.refresh_coach_review_stats(OLD.coach_id);
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM public.refresh_coach_review_stats(NEW.coach_id);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.log_payment_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_type text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.payment_events (
      payment_id,
      gym_id,
      event_type,
      previous_status,
      next_status,
      amount_delta,
      payload,
      created_by
    )
    VALUES (
      NEW.id,
      NEW.gym_id,
      'created',
      NULL,
      NEW.status,
      NEW.amount_paid,
      to_jsonb(NEW),
      COALESCE(NEW.created_by, auth.uid())
    );

    RETURN NEW;
  END IF;

  IF ROW(
    OLD.status,
    OLD.amount_total,
    OLD.amount_paid,
    OLD.amount_refunded,
    OLD.provider_reference,
    OLD.cancelled_at,
    OLD.paid_at
  ) IS NOT DISTINCT FROM ROW(
    NEW.status,
    NEW.amount_total,
    NEW.amount_paid,
    NEW.amount_refunded,
    NEW.provider_reference,
    NEW.cancelled_at,
    NEW.paid_at
  ) THEN
    RETURN NEW;
  END IF;

  v_event_type := CASE
    WHEN OLD.status IS DISTINCT FROM NEW.status THEN 'status_changed'
    ELSE 'updated'
  END;

  INSERT INTO public.payment_events (
    payment_id,
    gym_id,
    event_type,
    previous_status,
    next_status,
    amount_delta,
    payload,
    created_by
  )
  VALUES (
    NEW.id,
    NEW.gym_id,
    v_event_type,
    OLD.status,
    NEW.status,
    COALESCE(NEW.amount_paid, 0) - COALESCE(OLD.amount_paid, 0),
    jsonb_build_object(
      'old', to_jsonb(OLD),
      'new', to_jsonb(NEW)
    ),
    COALESCE(NEW.created_by, auth.uid())
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_session_status_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_type text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.session_status_history (
      session_id,
      gym_id,
      event_type,
      previous_status,
      new_status,
      reason,
      metadata,
      session_snapshot,
      changed_by
    )
    VALUES (
      NEW.id,
      NEW.gym_id,
      'created',
      NULL,
      NEW.status,
      NEW.cancellation_reason,
      jsonb_build_object(
        'booking_source', NEW.booking_source,
        'type', NEW.type
      ),
      to_jsonb(NEW),
      COALESCE(NEW.created_by, auth.uid())
    );

    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.session_status_history (
      session_id,
      gym_id,
      event_type,
      previous_status,
      new_status,
      reason,
      metadata,
      session_snapshot,
      changed_by
    )
    VALUES (
      OLD.id,
      OLD.gym_id,
      'deleted',
      OLD.status,
      COALESCE(OLD.status, 'cancelled'),
      OLD.cancellation_reason,
      jsonb_build_object('deleted', true),
      to_jsonb(OLD),
      auth.uid()
    );

    RETURN OLD;
  END IF;

  IF ROW(
    OLD.status,
    OLD.session_date,
    OLD.start_time,
    OLD.end_time,
    OLD.duration_minutes,
    OLD.type,
    OLD.coach_id,
    OLD.client_id,
    OLD.capacity,
    OLD.notes,
    OLD.cancellation_reason,
    OLD.payment_id,
    OLD.class_id,
    OLD.booking_source
  ) IS NOT DISTINCT FROM ROW(
    NEW.status,
    NEW.session_date,
    NEW.start_time,
    NEW.end_time,
    NEW.duration_minutes,
    NEW.type,
    NEW.coach_id,
    NEW.client_id,
    NEW.capacity,
    NEW.notes,
    NEW.cancellation_reason,
    NEW.payment_id,
    NEW.class_id,
    NEW.booking_source
  ) THEN
    RETURN NEW;
  END IF;

  v_event_type := CASE
    WHEN OLD.status IS DISTINCT FROM NEW.status THEN 'status_changed'
    ELSE 'updated'
  END;

  INSERT INTO public.session_status_history (
    session_id,
    gym_id,
    event_type,
    previous_status,
    new_status,
    reason,
    metadata,
    session_snapshot,
    changed_by
  )
  VALUES (
    NEW.id,
    NEW.gym_id,
    v_event_type,
    OLD.status,
    NEW.status,
    COALESCE(NEW.cancellation_reason, OLD.cancellation_reason),
    jsonb_build_object(
      'old', to_jsonb(OLD),
      'new', to_jsonb(NEW)
    ),
    to_jsonb(NEW),
    COALESCE(NEW.updated_by, auth.uid(), NEW.created_by)
  );

  RETURN NEW;
END;
$$;
