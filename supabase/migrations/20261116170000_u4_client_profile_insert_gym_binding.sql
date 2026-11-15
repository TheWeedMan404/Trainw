-- ============================================================================
-- U4 (2026-11-15) — client_profiles_insert must bind gym_id to the caller's gym
-- ============================================================================
-- Found while fixing the direct "Ajouter un Client" RLS failure (U4):
-- the client_profiles_insert WITH CHECK never constrained NEW.gym_id. A
-- manager could insert a profile row for a user in their own gym with
-- gym_id pointing at ANY other gym and it passed RLS. Proven live
-- 2026-11-15: the TEST Gym owner inserted a client_profiles row for Test
-- Client (same-gym user) with gym_id = TEST Gym B (a gym they do not
-- manage) and got 201; the probe row was deleted immediately after.
-- (The stray row was not even visible to Gym B's manager — the SELECT
-- policy needs is_same_gym_user(user_id) — so the practical impact was
-- cross-gym data pollution, not cross-gym disclosure. Still a hole.)
--
-- Fix: the manager branch now also requires manages_gym(gym_id) — the
-- caller must hold a membership in the gym the row claims, with the admin
-- portal or the manage_staff permission. The self-insert branch
-- (user_id = auth.uid(), used by signup bootstrap for the client's own
-- row, gym_id NULL at that point) is untouched.
--
-- This is defence-in-depth, NOT the U4 add-client fix itself: the
-- add-client fix is the UI reorder in submitNewClient (membership row
-- before the profile row, so is_same_gym_user holds). The reorder works
-- under the old policy too (verified live, Phase B of the U4 repro).
-- No other direct browser insert of client_profiles exists (only
-- submitNewClient); every SQL-side insert runs in a migration or a
-- SECURITY DEFINER function and bypasses RLS, so nothing else is
-- affected. The UPDATE/DELETE policies on this table share the unbound
-- shape (they key off the row's user, not its gym_id); they can only
-- touch rows whose user is in the manager's gym, and stray rows can no
-- longer be created via INSERT — tightening them is a follow-up, not
-- part of U4.
-- ============================================================================

DROP POLICY IF EXISTS client_profiles_insert ON public.client_profiles;

CREATE POLICY client_profiles_insert ON public.client_profiles
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    OR (
      public.is_gym_manager()
      AND public.is_same_gym_user(user_id)
      AND public.manages_gym(gym_id)
    )
  );
