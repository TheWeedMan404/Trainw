-- DB-59 — let a session's own client/coach read its history after the
-- session is deleted.
--
-- 003 deliberately drops every FK on session_status_history.session_id
-- so history survives session deletion, but the SELECT policy (004)
-- only showed a row to a manager or to a participant of the
-- still-existing session (an EXISTS against the live sessions row).
-- After a session is deleted, its own client/coach could no longer read
-- its history — the retained audit trail was visible only to managers.
--
-- Fix: keep the no-FK design and the manager branch, and base the
-- participant branch on the stored session_snapshot as well as the live
-- row. log_session_status_event stores to_jsonb(NEW)/to_jsonb(OLD), so
-- the snapshot always carries the session's client_id and coach_id as
-- text (or null for sessions without a client). The snapshot branch
-- reveals a row only to the exact client/coach named in it — no
-- cross-gym leak: the row's gym_id is the session's gym and the named
-- participant belongs to it. Rows whose snapshot is null (pre-snapshot
-- rows) fall back to the live-session branch, as before.
--
-- Not decided here: a retention rule for orphaned history (rows whose
-- session is long deleted accumulate forever). That needs a retention
-- period decision from the gym owner side; see the notes file.

DROP POLICY IF EXISTS session_status_history_select ON public.session_status_history;
CREATE POLICY session_status_history_select_v18 ON public.session_status_history
  FOR SELECT
  USING (
    public.manages_gym(gym_id)
    OR EXISTS (
      SELECT 1
      FROM public.sessions s
      WHERE s.id = session_id
        AND (s.client_id = auth.uid() OR s.coach_id = auth.uid())
    )
    OR (session_snapshot->>'client_id')::uuid = auth.uid()
    OR (session_snapshot->>'coach_id')::uuid = auth.uid()
  );
