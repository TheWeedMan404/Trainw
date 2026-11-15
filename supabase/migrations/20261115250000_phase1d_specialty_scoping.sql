-- DB-57 + DB-64 — specialty_tags / coach_specialties: decide the writer
-- and scope coach specialties to the coach's gym.
--
-- DB-57 writer decision: these tables are SEED-ONLY. The audit offered
-- "add a policy plus a validated RPC, or document them as seed-only
-- tables" — seed-only is the right call, because nothing in the app
-- reads or writes them: the frontend's specialty mechanism is the
-- free-text coach_profiles.specialty column (tw-gym-acc.js, tw-coach-acc.js),
-- and the only writer anywhere is supabase/seeds/trainw_demo_seed.sql
-- (tags 'Strength & Conditioning', 'Mobility'). Building an app-facing
-- writer for a feature nothing reads would be inventing scope.
-- Concretely: no INSERT/UPDATE/DELETE policy is added for either table
-- (SELECT-only policies stay), and under the DB-41 grant model the
-- authenticated role holds no write grant on them either — so an app
-- user cannot write them even if a future client tries. If a
-- gym-specific tag list is ever wanted, the work is: add gym_id to
-- specialty_tags, add policies + a validated RPC, and wire the frontend
-- to read coach_specialties instead of coach_profiles.specialty.
-- specialty_tags stays a GLOBAL curated list (name citext UNIQUE, no
-- gym_id): tag names are generic ('Strength & Conditioning'), and
-- per-gym tags are the future item above, not this migration.
--
-- DB-64 gym scoping: a BEFORE INSERT OR UPDATE trigger on
-- coach_specialties enforces gym_id = the coach's gym. The coach's gym
-- is resolved from users.gym_id first, then coach_profiles.gym_id. A
-- NULL gym_id is filled in from the coach's gym; a set gym_id that does
-- not match raises 'specialty_gym_mismatch'. A coach with no gym
-- anywhere keeps NULL (nothing to scope to). The demo seed is safe: its
-- coach (Youssef Trabelsi) belongs to the gym the seed's rows use.

CREATE OR REPLACE FUNCTION public.validate_coach_specialty_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_gym_id uuid;
BEGIN
  SELECT u.gym_id INTO v_coach_gym_id
  FROM public.users u
  WHERE u.id = NEW.coach_user_id;

  IF v_coach_gym_id IS NULL THEN
    SELECT cp.gym_id INTO v_coach_gym_id
    FROM public.coach_profiles cp
    WHERE cp.user_id = NEW.coach_user_id
    ORDER BY cp.created_at ASC
    LIMIT 1;
  END IF;

  IF v_coach_gym_id IS NULL THEN
    -- Gym-less coach: nothing to scope to; leave gym_id as given.
    RETURN NEW;
  END IF;

  IF NEW.gym_id IS NULL THEN
    NEW.gym_id := v_coach_gym_id;
    RETURN NEW;
  END IF;

  IF NEW.gym_id IS DISTINCT FROM v_coach_gym_id THEN
    RAISE EXCEPTION 'specialty_gym_mismatch: coach specialty gym_id % does not match the coach''s gym %',
      NEW.gym_id, v_coach_gym_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_coach_specialty_write ON public.coach_specialties;
CREATE TRIGGER trg_validate_coach_specialty_write
  BEFORE INSERT OR UPDATE ON public.coach_specialties
  FOR EACH ROW EXECUTE FUNCTION public.validate_coach_specialty_write();

COMMENT ON TABLE public.specialty_tags IS
  'DB-57: global curated tag list, seed/service-role only. No app-facing write policy exists on purpose — the live specialty mechanism is the free-text coach_profiles.specialty column. Per-gym tags would need a gym_id column plus policies + RPC + frontend wiring.';
COMMENT ON TABLE public.coach_specialties IS
  'DB-57: join table, seed/service-role only (no app-facing write policy). DB-64: gym_id is enforced by trg_validate_coach_specialty_write to equal the coach''s gym.';
