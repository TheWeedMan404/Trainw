-- ============================================================================
-- Round 5 (DB-57 follow-up) — specialty tags are per-gym now.
--
-- Before: specialty_tags was a GLOBAL curated list (name citext UNIQUE,
-- no gym_id), seed/service-role only; a gym could not have its own
-- tags, and the frontend's specialty mechanism is the free-text
-- coach_profiles.specialty column.
--
-- After:
--   * specialty_tags.gym_id (nullable; NULL = global, seeded tags stay
--     global). The global UNIQUE on name is replaced by two partial
--     uniques: one name per global list, one name per gym (citext, so
--     the match is case-insensitive in both cases).
--   * SELECT: any signed-in user sees global tags + the tags of their
--     current gym + the tags of any gym they manage.
--   * INSERT/UPDATE/DELETE: gym managers only, gym tags only
--     (gym_id IS NOT NULL and manages_gym(gym_id)) — global tags stay
--     seed/service-role only, and a tag cannot be moved into or out
--     of the global list by a gym manager (the UPDATE WITH CHECK
--     requires a non-null gym they manage).
--   * create_gym_specialty_tag(p_gym_id, p_name): validated create
--     RPC (SECURITY DEFINER; trims, 1-60 chars, manages_gym check).
--     Idempotent: an existing tag with the same name in the same gym
--     is returned instead of raising, so the coach-edit UI can offer
--     "save this specialty as a tag" without a duplicate-key error.
--   * coach_specialties is untouched: its trigger already enforces
--     gym_id = the coach's gym (DB-64). The free-text
--     coach_profiles.specialty column stays the live specialty
--     mechanism; the tags are suggestions for it (gym dashboard
--     coach-edit modal), not a replacement.
-- ============================================================================

ALTER TABLE public.specialty_tags
  ADD COLUMN IF NOT EXISTS gym_id uuid REFERENCES public.gyms(id) ON DELETE CASCADE;

-- Replace the global UNIQUE with the two partial uniques.
ALTER TABLE public.specialty_tags DROP CONSTRAINT IF EXISTS specialty_tags_name_key;
CREATE UNIQUE INDEX IF NOT EXISTS specialty_tags_global_name_key
  ON public.specialty_tags (name) WHERE gym_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS specialty_tags_gym_name_key
  ON public.specialty_tags (gym_id, name) WHERE gym_id IS NOT NULL;

-- SELECT: globals for everyone signed in; gym tags for that gym's
-- members and its managers.
DROP POLICY IF EXISTS specialty_tags_select ON public.specialty_tags;
CREATE POLICY specialty_tags_select ON public.specialty_tags
  FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND (
      gym_id IS NULL
      OR gym_id = public.get_my_gym_id()
      OR public.manages_gym(gym_id)
    )
  );

-- INSERT/UPDATE/DELETE: gym managers, gym tags only.
DROP POLICY IF EXISTS specialty_tags_insert ON public.specialty_tags;
CREATE POLICY specialty_tags_insert ON public.specialty_tags
  FOR INSERT
  WITH CHECK (gym_id IS NOT NULL AND public.manages_gym(gym_id));

DROP POLICY IF EXISTS specialty_tags_update ON public.specialty_tags;
CREATE POLICY specialty_tags_update ON public.specialty_tags
  FOR UPDATE
  USING (gym_id IS NOT NULL AND public.manages_gym(gym_id))
  WITH CHECK (gym_id IS NOT NULL AND public.manages_gym(gym_id));

DROP POLICY IF EXISTS specialty_tags_delete ON public.specialty_tags;
CREATE POLICY specialty_tags_delete ON public.specialty_tags
  FOR DELETE
  USING (gym_id IS NOT NULL AND public.manages_gym(gym_id));

-- Table grants: the chain only ever granted SELECT on specialty_tags
-- (seed/service-role only). Manager writes need the privileges; the
-- RLS policies above constrain what they can actually do.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.specialty_tags TO authenticated;

-- Validated create RPC: trim + length cap + manager check; returns the
-- existing tag id when the name already exists in the gym.
CREATE OR REPLACE FUNCTION public.create_gym_specialty_tag(
  p_gym_id uuid,
  p_name text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_name text;
  v_tag_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication_required: you must be logged in';
  END IF;

  IF p_gym_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: a gym is required for a gym tag';
  END IF;

  IF NOT public.manages_gym(p_gym_id) THEN
    RAISE EXCEPTION 'forbidden: only a manager of this gym can create its tags';
  END IF;

  v_name := BTRIM(COALESCE(p_name, ''));
  IF v_name = '' THEN
    RAISE EXCEPTION 'validation_error: tag name is required';
  END IF;
  IF char_length(v_name) > 60 THEN
    RAISE EXCEPTION 'validation_error: tag name must be 60 characters or fewer';
  END IF;

  INSERT INTO public.specialty_tags (gym_id, name)
  VALUES (p_gym_id, v_name)
  ON CONFLICT (gym_id, name) WHERE gym_id IS NOT NULL
  DO NOTHING
  RETURNING id INTO v_tag_id;

  IF v_tag_id IS NULL THEN
    -- citext = text resolves case-SENSITIVELY (citext is cast to text),
    -- so the lookup must cast the input to citext to match 'CrossFit'
    -- when the caller typed 'crossfit'.
    SELECT id INTO v_tag_id
    FROM public.specialty_tags
    WHERE gym_id = p_gym_id AND name = v_name::citext;
  END IF;

  RETURN v_tag_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_gym_specialty_tag(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_gym_specialty_tag(uuid, text) TO authenticated;

COMMENT ON COLUMN public.specialty_tags.gym_id IS
  'DB-57 (round 5): NULL = global curated tag; otherwise the owning gym. Gym managers create their own tags via create_gym_specialty_tag(); global tags stay seed/service-role only.';
