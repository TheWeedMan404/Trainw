-- Phase 1d (round 4): DB-27 + DB-28 — close the direct booking/session
-- write paths. Bookings and sessions may only change through the
-- sanctioned flows (session RPCs + the sessions->bookings sync trigger);
-- direct table writes are manager-only and consistency-checked.
--
-- DB-27: bookings_manage_v17 was FOR ALL for any row where
-- client_id/coach_id = auth.uid(), with no check that the linked session
-- belongs to that user, that gym_id matches, or that the transition is
-- legal. A client/coach could UPDATE/DELETE their own booking (e.g. mark
-- it completed), move a booking to another gym by changing gym_id, or
-- INSERT a booking for a session belonging to another client.
--   * Direct booking writes are now manager-only (manage_bookings).
--     Clients/coaches change bookings only via the session RPCs
--     (book/respond/complete/cancel — all SECURITY DEFINER, so the
--     policy change does not break them) and the sync trigger
--     (sync_booking_from_session, also SECURITY DEFINER). The frontend
--     writes no bookings directly (verified by grep, 2026-11-15).
--   * New trigger validate_booking_consistency enforces that the linked
--     session exists and that gym_id/client_id/coach_id match it, so a
--     booking can never desynchronise from its session in either
--     direction.
-- DB-28: sessions_update let the coaching branch (coach_id = auth.uid())
-- UPDATE any column on a session they coach, with no assignment check
-- and no column restriction — a coach could reassign a session to a
-- different client, change gym_id/payment_id/capacity/status, bypassing
-- the RPC state machine.
--   * New trigger validate_session_coach_update: when the caller is the
--     session's own coach acting directly, the identity/payment columns
--     (gym_id, client_id, coach_id, payment_id) are frozen, and status
--     may only move along the transitions the RPCs allow:
--     pending->confirmed, pending->cancelled, confirmed->completed,
--     confirmed->cancelled, confirmed->no_show. Managers keep full edit
--     rights. A caller who is neither a manager nor the session's coach
--     never reaches the trigger directly (the policy blocks them first),
--     so such updates can only be SECURITY DEFINER RPCs working on
--     someone else's behalf (book_coach_session sets payment_id as the
--     member) — the trigger lets those through, since the RPCs validate
--     their own transitions.
--   * The assignment-check alternative from the audit (require an active
--     coach_client_assignments row) was NOT implemented: legacy and
--     manager-created sessions can exist with no assignment row, and
--     blocking the coach's direct UPDATE there would break legitimate
--     sessions while the RPC path (which does not check assignment)
--     stays open anyway. The policy already restricts the coach branch
--     to sessions they coach (coach_id = auth.uid()).

-- ---------------------------------------------------------------------------
-- DB-27: bookings writes are manager-only
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS bookings_manage_v17 ON public.bookings;

CREATE POLICY bookings_insert_v18 ON public.bookings
  FOR INSERT
  WITH CHECK (
    public.has_permission('manage_bookings', gym_id)
  );

CREATE POLICY bookings_update_v18 ON public.bookings
  FOR UPDATE
  USING (
    public.has_permission('manage_bookings', gym_id)
  )
  WITH CHECK (
    public.has_permission('manage_bookings', gym_id)
  );

CREATE POLICY bookings_delete_v18 ON public.bookings
  FOR DELETE
  USING (
    public.has_permission('manage_bookings', gym_id)
  );

-- The read policy is unchanged: participants can still read their own
-- bookings, managers can read the gym's.

-- ---------------------------------------------------------------------------
-- DB-27: booking/session consistency trigger
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_booking_consistency()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_session
  FROM public.sessions s
  WHERE s.id = NEW.session_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking_session_missing: the linked session does not exist';
  END IF;

  IF v_session.gym_id IS DISTINCT FROM NEW.gym_id THEN
    RAISE EXCEPTION 'booking_gym_mismatch: booking gym_id does not match its session';
  END IF;

  IF v_session.client_id IS DISTINCT FROM NEW.client_id THEN
    RAISE EXCEPTION 'booking_client_mismatch: booking client_id does not match its session';
  END IF;

  IF v_session.coach_id IS DISTINCT FROM NEW.coach_id THEN
    RAISE EXCEPTION 'booking_coach_mismatch: booking coach_id does not match its session';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_booking_consistency() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_booking_consistency() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_validate_booking_consistency ON public.bookings;
CREATE TRIGGER trg_validate_booking_consistency
  BEFORE INSERT OR UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_booking_consistency();

-- ---------------------------------------------------------------------------
-- DB-28: coach-branch session update guard
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_session_coach_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transition_allowed boolean;
BEGIN
  -- Managers (and the SECURITY DEFINER RPCs acting for them) keep full
  -- edit rights. can_manage_sessions reads the caller's membership, so
  -- the RPCs' own writes — which only ever make legal transitions —
  -- pass through untouched.
  IF public.can_manage_sessions(OLD.gym_id) THEN
    RETURN NEW;
  END IF;

  -- The caller is not the session's coach and not a manager. A DIRECT
  -- write by such a caller never reaches this trigger: the
  -- sessions_update policy only lets a manager or the session's own
  -- coach through (anything else affects 0 rows). So an update that
  -- arrives here from a third party can only be a SECURITY DEFINER RPC
  -- working on someone else's behalf — e.g. book_coach_session setting
  -- payment_id while the member books. The RPCs validate their own
  -- transitions; let it through. (Raising here would break booking.)
  IF OLD.coach_id IS DISTINCT FROM auth.uid() THEN
    RETURN NEW;
  END IF;

  -- From here the caller IS the session's coach, acting directly: the
  -- policy already restricted the row to their own sessions, and the
  -- trigger now restricts what they may change on them.
  IF NEW.gym_id IS DISTINCT FROM OLD.gym_id
    OR NEW.client_id IS DISTINCT FROM OLD.client_id
    OR NEW.coach_id IS DISTINCT FROM OLD.coach_id
    OR NEW.payment_id IS DISTINCT FROM OLD.payment_id THEN
    RAISE EXCEPTION 'session_update_forbidden: gym_id, client_id, coach_id and payment_id cannot be changed by a coach';
  END IF;

  -- Status may only move along the transitions the session RPCs allow.
  v_transition_allowed := (NEW.status IS NOT DISTINCT FROM OLD.status)
    OR (OLD.status = 'pending' AND NEW.status IN ('confirmed', 'cancelled'))
    OR (OLD.status = 'confirmed' AND NEW.status IN ('completed', 'cancelled', 'no_show'));

  IF NOT v_transition_allowed THEN
    RAISE EXCEPTION 'session_update_forbidden: illegal status transition % -> % for a coach', OLD.status, NEW.status;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_session_coach_update() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_session_coach_update() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_validate_session_coach_update ON public.sessions;
CREATE TRIGGER trg_validate_session_coach_update
  BEFORE UPDATE ON public.sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_session_coach_update();
