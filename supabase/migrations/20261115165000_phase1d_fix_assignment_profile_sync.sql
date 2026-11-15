-- ============================================================================
-- Round 4 (verification fix) — sync_client_profile_assignment must not
-- move profile rows across gyms.
--
-- The 006 trigger syncs client_profiles.coach_id from the latest active
-- assignment, but its UPDATE also did `SET gym_id = src.gym_id` on EVERY
-- profile row of the user (WHERE cp.user_id = src.client_id, no gym
-- filter). Every new auth user gets a bare gym-less client_profiles row
-- from the signup trigger, so the first time any assignment becomes
-- active the trigger tries to move that bare row onto the gym — and
-- collides with the member's real gym profile row:
--   duplicate key value violates unique constraint
--   "uq_client_profiles_user_gym".
-- That made confirm_coach_client_assignment() (DB-45) fail outright.
-- This is a pre-existing defect in 006, found by the round-4 behavioral
-- suite; the fix is scoped to the assignment's gym and never reassigns
-- gym_id. (006 itself is untouched, as required.)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sync_client_profile_assignment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_client_id uuid;
  v_gym_id uuid;
BEGIN
  v_client_id := COALESCE(NEW.client_id, OLD.client_id);
  v_gym_id := COALESCE(NEW.gym_id, OLD.gym_id);

  IF v_client_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Only the profile row FOR THIS GYM is synced, and its gym_id is never
  -- reassigned: a profile row's gym is its identity. If the member has no
  -- profile row for this gym yet, there is nothing to sync.
  UPDATE public.client_profiles cp
  SET coach_id = src.coach_profile_id,
      updated_at = now()
  FROM (
    SELECT DISTINCT ON (cca.client_id)
      cca.client_id,
      cca.gym_id,
      cprof.id AS coach_profile_id
    FROM public.coach_client_assignments cca
    LEFT JOIN public.coach_profiles cprof
      ON cprof.user_id = cca.coach_id
    WHERE cca.client_id = v_client_id
      AND cca.gym_id = v_gym_id
      AND cca.is_active = true
    ORDER BY cca.client_id, cca.assigned_at DESC, cca.id DESC
  ) AS src
  WHERE cp.user_id = src.client_id
    AND cp.gym_id = src.gym_id;

  IF NOT FOUND THEN
    UPDATE public.client_profiles
    SET coach_id = NULL,
        updated_at = now()
    WHERE user_id = v_client_id
      AND gym_id = v_gym_id;
  END IF;

  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.sync_client_profile_assignment() IS
  'Round 4 fix: syncs client_profiles.coach_id from the latest active assignment, scoped to the assignment gym. Never reassigns a profile row to another gym (the 006 version did SET gym_id, which collided with the bare gym-less profile row every signup creates).';
