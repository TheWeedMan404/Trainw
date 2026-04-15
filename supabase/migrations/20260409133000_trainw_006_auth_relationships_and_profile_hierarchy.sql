-- ============================================================================
-- TRAINW V16 PRODUCTION - AUTH RELATIONSHIP CANONICALIZATION AND PROFILE HIERARCHY
-- Purpose:
--   - Remove ambiguous PostgREST relationships between profile tables and users
--   - Add the missing gym/client hierarchy columns required by the SaaS data model
--   - Keep coach/client profile links synchronized with assignments
--   - Stay idempotent and safe on partially migrated production databases
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PROFILE COLUMN PATCHES
-- ----------------------------------------------------------------------------

ALTER TABLE public.coach_profiles
  ADD COLUMN IF NOT EXISTS sessions_completed integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS certifications text[];

ALTER TABLE public.client_profiles
  ADD COLUMN IF NOT EXISTS gym_id uuid,
  ADD COLUMN IF NOT EXISTS coach_id uuid,
  ADD COLUMN IF NOT EXISTS sessions_completed integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS active_plan text,
  ADD COLUMN IF NOT EXISTS progress_notes text;

CREATE TABLE IF NOT EXISTS public.gym_profiles (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL,
  gym_id     uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.gym_profiles
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS gym_id uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();


-- ----------------------------------------------------------------------------
-- DATA NORMALIZATION
-- ----------------------------------------------------------------------------

UPDATE public.coach_profiles
SET sessions_completed = GREATEST(COALESCE(sessions_completed, 0), 0);

UPDATE public.client_profiles
SET sessions_completed = GREATEST(COALESCE(sessions_completed, 0), 0);

UPDATE public.client_profiles cp
SET gym_id = COALESCE(cp.gym_id, u.gym_id)
FROM public.users u
WHERE cp.user_id = u.id
  AND cp.gym_id IS NULL
  AND u.gym_id IS NOT NULL;

UPDATE public.client_profiles cp
SET gym_id = src.gym_id
FROM (
  SELECT DISTINCT ON (cca.client_id)
    cca.client_id,
    cca.gym_id
  FROM public.coach_client_assignments cca
  WHERE cca.gym_id IS NOT NULL
  ORDER BY cca.client_id, cca.is_active DESC, cca.assigned_at DESC, cca.id DESC
) AS src
WHERE cp.user_id = src.client_id
  AND cp.gym_id IS NULL;

UPDATE public.client_profiles cp
SET coach_id = src.coach_profile_id
FROM (
  SELECT DISTINCT ON (cca.client_id)
    cca.client_id,
    cprof.id AS coach_profile_id
  FROM public.coach_client_assignments cca
  JOIN public.coach_profiles cprof
    ON cprof.user_id = cca.coach_id
  WHERE cca.is_active = true
  ORDER BY cca.client_id, cca.assigned_at DESC, cca.id DESC
) AS src
WHERE cp.user_id = src.client_id
  AND (cp.coach_id IS NULL OR cp.coach_id IS DISTINCT FROM src.coach_profile_id);

UPDATE public.client_profiles cp
SET gym_id = NULL
WHERE cp.gym_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.gyms g
    WHERE g.id = cp.gym_id
  );

UPDATE public.client_profiles cp
SET coach_id = NULL
WHERE cp.coach_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.coach_profiles cprof
    WHERE cprof.id = cp.coach_id
  );

WITH manager_source AS (
  SELECT DISTINCT ON (src.user_id)
    src.user_id,
    src.gym_id
  FROM (
    SELECT g.manager_id AS user_id, g.id AS gym_id, g.created_at
    FROM public.gyms g
    WHERE g.manager_id IS NOT NULL

    UNION ALL

    SELECT u.id AS user_id, u.gym_id, u.created_at
    FROM public.users u
    WHERE u.gym_id IS NOT NULL
      AND u.role IN ('gym_owner', 'gym', 'admin')
  ) AS src
  ORDER BY src.user_id, src.created_at ASC, src.gym_id
)
UPDATE public.gym_profiles gp
SET gym_id = ms.gym_id,
    updated_at = now()
FROM manager_source ms
WHERE gp.user_id = ms.user_id
  AND gp.gym_id IS DISTINCT FROM ms.gym_id;

WITH manager_source AS (
  SELECT DISTINCT ON (src.gym_id)
    src.user_id,
    src.gym_id
  FROM (
    SELECT g.manager_id AS user_id, g.id AS gym_id, g.created_at
    FROM public.gyms g
    WHERE g.manager_id IS NOT NULL

    UNION ALL

    SELECT u.id AS user_id, u.gym_id, u.created_at
    FROM public.users u
    WHERE u.gym_id IS NOT NULL
      AND u.role IN ('gym_owner', 'gym', 'admin')
  ) AS src
  ORDER BY src.gym_id, src.created_at ASC, src.user_id
)
UPDATE public.gym_profiles gp
SET user_id = ms.user_id,
    updated_at = now()
FROM manager_source ms
WHERE gp.gym_id = ms.gym_id
  AND gp.user_id IS DISTINCT FROM ms.user_id;

INSERT INTO public.gym_profiles (user_id, gym_id)
SELECT ms.user_id, ms.gym_id
FROM (
  SELECT DISTINCT ON (src.user_id)
    src.user_id,
    src.gym_id
  FROM (
    SELECT g.manager_id AS user_id, g.id AS gym_id, g.created_at
    FROM public.gyms g
    WHERE g.manager_id IS NOT NULL

    UNION ALL

    SELECT u.id AS user_id, u.gym_id, u.created_at
    FROM public.users u
    WHERE u.gym_id IS NOT NULL
      AND u.role IN ('gym_owner', 'gym', 'admin')
  ) AS src
  ORDER BY src.user_id, src.created_at ASC, src.gym_id
) AS ms
WHERE ms.user_id IS NOT NULL
  AND ms.gym_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.gym_profiles gp
    WHERE gp.user_id = ms.user_id
       OR gp.gym_id = ms.gym_id
  );


-- ----------------------------------------------------------------------------
-- FOREIGN KEYS
-- ----------------------------------------------------------------------------

ALTER TABLE public.coach_profiles
  DROP CONSTRAINT IF EXISTS coaches_user_id_fkey;

ALTER TABLE public.client_profiles
  DROP CONSTRAINT IF EXISTS clients_user_id_fkey;

DO $$
DECLARE
  v_constraint_name text;
BEGIN
  FOR v_constraint_name IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_attribute att
      ON att.attrelid = con.conrelid
     AND att.attnum = ANY(con.conkey)
    WHERE con.contype = 'f'
      AND con.conrelid = 'public.coach_profiles'::regclass
      AND att.attname = 'approved_by'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.coach_profiles DROP CONSTRAINT IF EXISTS %I',
      v_constraint_name
    );
  END LOOP;
END $$;

ALTER TABLE public.client_profiles
  DROP CONSTRAINT IF EXISTS client_profiles_coach_id_fkey;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.coach_profiles'::regclass
      AND conname = 'coach_profiles_user_id_fkey'
  ) THEN
    ALTER TABLE public.coach_profiles
      ADD CONSTRAINT coach_profiles_user_id_fkey
      FOREIGN KEY (user_id)
      REFERENCES public.users(id)
      ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.coach_profiles'::regclass
      AND conname = 'coach_profiles_gym_id_fkey'
  ) THEN
    ALTER TABLE public.coach_profiles
      ADD CONSTRAINT coach_profiles_gym_id_fkey
      FOREIGN KEY (gym_id)
      REFERENCES public.gyms(id)
      ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.client_profiles'::regclass
      AND conname = 'client_profiles_user_id_fkey'
  ) THEN
    ALTER TABLE public.client_profiles
      ADD CONSTRAINT client_profiles_user_id_fkey
      FOREIGN KEY (user_id)
      REFERENCES public.users(id)
      ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.client_profiles'::regclass
      AND conname = 'client_profiles_gym_id_fkey'
  ) THEN
    ALTER TABLE public.client_profiles
      ADD CONSTRAINT client_profiles_gym_id_fkey
      FOREIGN KEY (gym_id)
      REFERENCES public.gyms(id)
      ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.client_profiles'::regclass
      AND conname = 'client_profiles_coach_id_fkey'
  ) THEN
    ALTER TABLE public.client_profiles
      ADD CONSTRAINT client_profiles_coach_id_fkey
      FOREIGN KEY (coach_id)
      REFERENCES public.coach_profiles(id)
      ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.gym_profiles'::regclass
      AND conname = 'gym_profiles_user_id_fkey'
  ) THEN
    ALTER TABLE public.gym_profiles
      ADD CONSTRAINT gym_profiles_user_id_fkey
      FOREIGN KEY (user_id)
      REFERENCES public.users(id)
      ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.gym_profiles'::regclass
      AND conname = 'gym_profiles_gym_id_fkey'
  ) THEN
    ALTER TABLE public.gym_profiles
      ADD CONSTRAINT gym_profiles_gym_id_fkey
      FOREIGN KEY (gym_id)
      REFERENCES public.gyms(id)
      ON DELETE CASCADE;
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- INDEXES AND CHECKS
-- ----------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_gym_profiles_user_id
  ON public.gym_profiles(user_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_gym_profiles_gym_id
  ON public.gym_profiles(gym_id);

CREATE INDEX IF NOT EXISTS idx_users_gym_role_active
  ON public.users(gym_id, role, is_active);

CREATE INDEX IF NOT EXISTS idx_coach_profiles_gym_active_rating
  ON public.coach_profiles(gym_id, approval_status, is_active, rating DESC, user_id);

CREATE INDEX IF NOT EXISTS idx_client_profiles_gym_coach
  ON public.client_profiles(gym_id, coach_id, user_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.coach_profiles'::regclass
      AND conname = 'coach_profiles_sessions_completed_check'
  ) THEN
    ALTER TABLE public.coach_profiles
      ADD CONSTRAINT coach_profiles_sessions_completed_check
      CHECK (sessions_completed >= 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.client_profiles'::regclass
      AND conname = 'client_profiles_sessions_completed_check'
  ) THEN
    ALTER TABLE public.client_profiles
      ADD CONSTRAINT client_profiles_sessions_completed_check
      CHECK (sessions_completed >= 0);
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- TRIGGERS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sync_client_profile_assignment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_client_id uuid;
BEGIN
  v_client_id := COALESCE(NEW.client_id, OLD.client_id);

  IF v_client_id IS NULL THEN
    RETURN NULL;
  END IF;

  UPDATE public.client_profiles cp
  SET gym_id = src.gym_id,
      coach_id = src.coach_profile_id,
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
      AND cca.is_active = true
    ORDER BY cca.client_id, cca.assigned_at DESC, cca.id DESC
  ) AS src
  WHERE cp.user_id = src.client_id;

  IF NOT FOUND THEN
    UPDATE public.client_profiles
    SET coach_id = NULL,
        updated_at = now()
    WHERE user_id = v_client_id;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_client_profile_assignment ON public.coach_client_assignments;
CREATE TRIGGER trg_sync_client_profile_assignment
  AFTER INSERT OR UPDATE OR DELETE ON public.coach_client_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_client_profile_assignment();

DROP TRIGGER IF EXISTS trg_gym_profiles_upd ON public.gym_profiles;
CREATE TRIGGER trg_gym_profiles_upd
  BEFORE UPDATE ON public.gym_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ----------------------------------------------------------------------------
-- RLS AND GRANTS
-- ----------------------------------------------------------------------------

ALTER TABLE public.gym_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS gym_profiles_select ON public.gym_profiles;
DROP POLICY IF EXISTS gym_profiles_insert ON public.gym_profiles;
DROP POLICY IF EXISTS gym_profiles_update ON public.gym_profiles;
DROP POLICY IF EXISTS gym_profiles_delete ON public.gym_profiles;

CREATE POLICY gym_profiles_select ON public.gym_profiles
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR public.manages_gym(gym_id)
  );

CREATE POLICY gym_profiles_insert ON public.gym_profiles
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    OR public.manages_gym(gym_id)
  );

CREATE POLICY gym_profiles_update ON public.gym_profiles
  FOR UPDATE
  USING (
    user_id = auth.uid()
    OR public.manages_gym(gym_id)
  )
  WITH CHECK (
    user_id = auth.uid()
    OR public.manages_gym(gym_id)
  );

CREATE POLICY gym_profiles_delete ON public.gym_profiles
  FOR DELETE
  USING (
    user_id = auth.uid()
    OR public.manages_gym(gym_id)
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.gym_profiles TO authenticated;
