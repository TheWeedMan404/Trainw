-- ============================================================================
-- U5 (2026-11-15) — rescheduling a session to a PM time failed with
-- "range lower bound must be less than or equal to range upper bound"
-- ============================================================================
-- Root cause (reproduced locally on the full chain, and the error text
-- matches the tester's exactly): prepare_session_write() set
-- NEW.end_time := session_effective_end_time(start, end, duration),
-- which returns a non-null stored end_time UNCHANGED. saveEditSession
-- sends start_time only (the UI has no end-time input — duration only),
-- so the row kept the end_time computed at creation. A session created
-- 11:00 + 60 min stores end_time 12:00; moving it to 14:00 left
-- end_time 12:00, and validate_session_write() then built
-- tsrange('2026-11-19 14:00', '2026-11-19 12:00') -> the range error.
-- AM moves worked only because 11:00 stayed below the stale 12:00 end.
-- The UI is not at fault: the edit input is type="time", whose .value
-- is always 24-hour ("14:00"), and saveEditSession sends "14:00:00".
--
-- Fix: in prepare_session_write() only (the one place that decides what
-- end_time gets stored). end_time is now always derived from
-- start_time + duration_minutes. session_effective_end_time() itself is
-- untouched: every other caller passes NULL for end_time, and fresh
-- inserts (end_time NULL) already computed correctly. The create-session
-- path (submitNewSession) never sent end_time, so it never hit this; no
-- UI change is needed for U5.
-- No RLS change. No data migration: existing rows self-heal on their
-- next write (their stored end_time is recomputed then); rows never
-- re-saved keep a consistent start/end pair from creation.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.prepare_session_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.duration_minutes := GREATEST(COALESCE(NEW.duration_minutes, 60), 15);
  NEW.type := COALESCE(NULLIF(lower(BTRIM(NEW.type)), ''), 'group_class');
  NEW.status := COALESCE(NULLIF(lower(BTRIM(NEW.status)), ''), 'pending');
  NEW.booking_source := COALESCE(NULLIF(lower(BTRIM(NEW.booking_source)), ''), 'gym_manager');
  NEW.notes := NULLIF(BTRIM(NEW.notes), '');
  NEW.cancellation_reason := NULLIF(BTRIM(NEW.cancellation_reason), '');
  NEW.session_name := COALESCE(
    NULLIF(BTRIM(NEW.session_name), ''),
    CASE
      WHEN NEW.type IN ('individual_training', 'assessment') THEN 'Coach Session'
      WHEN NEW.type = 'open_gym' THEN 'Open Gym'
      ELSE 'Session'
    END
  );
  NEW.booked_at := COALESCE(NEW.booked_at, NEW.created_at, now());
  NEW.gym_id := COALESCE(
    NEW.gym_id,
    (SELECT u.gym_id FROM public.users u WHERE u.id = NEW.client_id),
    (SELECT u.gym_id FROM public.users u WHERE u.id = NEW.coach_id),
    (SELECT gc.gym_id FROM public.gym_classes gc WHERE gc.id = NEW.class_id)
  );

  IF NEW.type IN ('individual', 'personal', 'personal_training') THEN
    NEW.type := 'individual_training';
  END IF;

  IF NEW.status = 'canceled' THEN
    NEW.status := 'cancelled';
  END IF;

  -- U5 (2026-11-15): end_time is recomputed from start + duration on
  -- every write. session_effective_end_time() kept a non-null stored
  -- end_time verbatim, so rescheduling a session past its old end
  -- (11:00 + 60 min -> end 12:00, then moved to 14:00) left end_time at
  -- 12:00 and validate_session_write() built tsrange(14:00, 12:00),
  -- raising "range lower bound must be less than or equal to range upper
  -- bound" for every PM move (AM moves stayed below the stale end and
  -- passed). Merely keeping a stored end that is still after the new
  -- start is NOT enough: 11:00 -> 14:00 (end 15:00) -> 11:00 would leave
  -- a 4-hour session (end 15:00) behind, a phantom block in every
  -- overlap check that reads end_time. end_time is purely derived — no
  -- UI, RPC or migration ever writes an explicit sessions.end_time
  -- (verified by grep; this trigger is its only writer) — so always
  -- deriving it is correct and also self-heals rows carrying a stale end
  -- from the old bug on their next write. Clamped to 23:59 when
  -- start+duration wraps past midnight (same pattern as the 003 data
  -- cleanup), so the end_time > start_time CHECK stays satisfied.
  NEW.end_time := CASE
    WHEN NEW.start_time IS NULL THEN NULL
    WHEN (NEW.start_time + make_interval(mins => GREATEST(COALESCE(NEW.duration_minutes, 60), 15)))::time > NEW.start_time
      THEN (NEW.start_time + make_interval(mins => GREATEST(COALESCE(NEW.duration_minutes, 60), 15)))::time
    WHEN NEW.start_time < time '23:59:00' THEN time '23:59:00'
    ELSE NULL
  END;
  NEW.capacity := GREATEST(
    COALESCE(
      NEW.capacity,
      CASE
        WHEN NEW.type IN ('individual_training', 'assessment') THEN 1
        ELSE 10
      END
    ),
    1
  );

  IF NEW.type IN ('individual_training', 'assessment') THEN
    NEW.capacity := 1;
    NEW.attendee_count := CASE WHEN NEW.client_id IS NOT NULL THEN 1 ELSE 0 END;
  ELSE
    NEW.attendee_count := LEAST(
      GREATEST(COALESCE(NEW.attendee_count, 0), 0),
      NEW.capacity
    );
  END IF;

  IF NEW.status = 'confirmed' THEN
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, now());
  ELSIF NEW.status = 'cancelled' THEN
    NEW.cancelled_at := COALESCE(NEW.cancelled_at, now());
  ELSIF NEW.status = 'completed' THEN
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NEW.booked_at, now());
    NEW.completed_at := COALESCE(NEW.completed_at, now());
  ELSIF NEW.status = 'no_show' THEN
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NEW.booked_at, now());
    NEW.no_show_at := COALESCE(NEW.no_show_at, now());
  END IF;

  NEW.created_by := COALESCE(NEW.created_by, auth.uid(), NEW.client_id);
  NEW.updated_by := COALESCE(auth.uid(), NEW.updated_by, NEW.created_by);

  RETURN NEW;
END;
$$;
