-- ============================================================================
-- TRAINW V17 HOTFIX - AUTH RECOVERY, REVIEW COMPATIBILITY, AND RLS SAFETY
-- Purpose:
--   - Repair legacy profile rows so existing auth accounts can log in again
--   - Add missing review compatibility columns used by the V17 frontend
--   - Replace recursive/fragile helper functions and policies
--   - Keep migrations idempotent and safe on partially-upgraded databases
-- ============================================================================

-- ----------------------------------------------------------------------------
-- REVIEW COMPATIBILITY
-- ----------------------------------------------------------------------------

ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS session_id uuid,
  ADD COLUMN IF NOT EXISTS coach_id uuid,
  ADD COLUMN IF NOT EXISTS client_id uuid,
  ADD COLUMN IF NOT EXISTS gym_id uuid,
  ADD COLUMN IF NOT EXISTS comment text,
  ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

UPDATE public.reviews r
SET gym_id = s.gym_id,
    coach_id = COALESCE(r.coach_id, s.coach_id),
    client_id = COALESCE(r.client_id, s.client_id)
FROM public.sessions s
WHERE r.session_id IS NOT NULL
  AND s.id = r.session_id
  AND (
    r.gym_id IS DISTINCT FROM s.gym_id
    OR r.coach_id IS NULL
    OR r.client_id IS NULL
  );

UPDATE public.reviews r
SET session_id = NULL
WHERE r.session_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.sessions s
    WHERE s.id = r.session_id
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.reviews'::regclass
      AND conname = 'reviews_session_id_fkey'
  ) THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_session_id_fkey
      FOREIGN KEY (session_id)
      REFERENCES public.sessions(id)
      ON DELETE CASCADE
      NOT VALID;
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- LEGACY GYM LINK REPAIR
-- ----------------------------------------------------------------------------

UPDATE public.users u
SET gym_id = cp.gym_id
FROM public.coach_profiles cp
WHERE u.id = cp.user_id
  AND u.gym_id IS NULL
  AND cp.gym_id IS NOT NULL;

UPDATE public.coach_profiles cp
SET gym_id = u.gym_id
FROM public.users u
WHERE cp.user_id = u.id
  AND cp.gym_id IS NULL
  AND u.gym_id IS NOT NULL;

UPDATE public.users u
SET gym_id = cca.gym_id
FROM (
  SELECT DISTINCT ON (client_id)
    client_id,
    gym_id
  FROM public.coach_client_assignments
  WHERE gym_id IS NOT NULL
  ORDER BY client_id, is_active DESC, assigned_at DESC, id DESC
) cca
WHERE u.id = cca.client_id
  AND u.gym_id IS NULL;

UPDATE public.users u
SET gym_id = cca.gym_id
FROM (
  SELECT DISTINCT ON (coach_id)
    coach_id,
    gym_id
  FROM public.coach_client_assignments
  WHERE gym_id IS NOT NULL
  ORDER BY coach_id, is_active DESC, assigned_at DESC, id DESC
) cca
WHERE u.id = cca.coach_id
  AND u.gym_id IS NULL;

UPDATE public.users u
SET gym_id = src.gym_id
FROM (
  SELECT DISTINCT ON (coach_id)
    coach_id,
    gym_id
  FROM public.sessions
  WHERE coach_id IS NOT NULL
    AND gym_id IS NOT NULL
  ORDER BY coach_id, session_date DESC, start_time DESC NULLS LAST, id DESC
) src
WHERE u.id = src.coach_id
  AND u.gym_id IS NULL;

UPDATE public.users u
SET gym_id = src.gym_id
FROM (
  SELECT DISTINCT ON (client_id)
    client_id,
    gym_id
  FROM public.sessions
  WHERE client_id IS NOT NULL
    AND gym_id IS NOT NULL
  ORDER BY client_id, session_date DESC, start_time DESC NULLS LAST, id DESC
) src
WHERE u.id = src.client_id
  AND u.gym_id IS NULL;

UPDATE public.users u
SET gym_id = src.gym_id
FROM (
  SELECT DISTINCT ON (client_id)
    client_id,
    gym_id
  FROM public.check_ins
  WHERE client_id IS NOT NULL
    AND gym_id IS NOT NULL
  ORDER BY client_id, checked_in_at DESC, id DESC
) src
WHERE u.id = src.client_id
  AND u.gym_id IS NULL;

UPDATE public.users u
SET gym_id = g.id
FROM public.gyms g
WHERE u.id = g.manager_id
  AND u.gym_id IS NULL
  AND u.role IN ('gym_owner', 'gym', 'admin');

WITH ranked_managers AS (
  SELECT DISTINCT ON (u.gym_id)
    u.gym_id,
    u.id AS manager_id
  FROM public.users u
  WHERE u.gym_id IS NOT NULL
    AND u.role IN ('gym_owner', 'gym', 'admin')
  ORDER BY u.gym_id,
           CASE u.role
             WHEN 'gym_owner' THEN 0
             WHEN 'admin' THEN 1
             ELSE 2
           END,
           u.created_at,
           u.id
)
UPDATE public.gyms g
SET manager_id = rm.manager_id
FROM ranked_managers rm
WHERE g.id = rm.gym_id
  AND g.manager_id IS NULL;


-- ----------------------------------------------------------------------------
-- HELPER FUNCTION RESET
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_signup_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT COALESCE(NULLIF(lower(BTRIM(raw_user_meta_data->>'role')), ''), NULLIF(lower(BTRIM(raw_app_meta_data->>'role')), ''))
  FROM auth.users
  WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.user_role(p_user_id uuid)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT COALESCE(
    (SELECT role FROM public.users WHERE id = p_user_id),
    (SELECT COALESCE(NULLIF(lower(BTRIM(raw_user_meta_data->>'role')), ''), NULLIF(lower(BTRIM(raw_app_meta_data->>'role')), '')) FROM auth.users WHERE id = p_user_id)
  );
$$;

CREATE OR REPLACE FUNCTION public.user_gym_id(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT COALESCE(
    (SELECT gym_id FROM public.users WHERE id = p_user_id),
    (SELECT gym_id FROM public.coach_profiles WHERE user_id = p_user_id AND gym_id IS NOT NULL ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST LIMIT 1),
    (SELECT gym_id FROM public.coach_client_assignments WHERE coach_id = p_user_id AND gym_id IS NOT NULL ORDER BY is_active DESC, assigned_at DESC, id DESC LIMIT 1),
    (SELECT gym_id FROM public.coach_client_assignments WHERE client_id = p_user_id AND gym_id IS NOT NULL ORDER BY is_active DESC, assigned_at DESC, id DESC LIMIT 1),
    (SELECT gym_id FROM public.sessions WHERE coach_id = p_user_id AND gym_id IS NOT NULL ORDER BY session_date DESC, start_time DESC NULLS LAST, id DESC LIMIT 1),
    (SELECT gym_id FROM public.sessions WHERE client_id = p_user_id AND gym_id IS NOT NULL ORDER BY session_date DESC, start_time DESC NULLS LAST, id DESC LIMIT 1),
    (SELECT gym_id FROM public.check_ins WHERE client_id = p_user_id AND gym_id IS NOT NULL ORDER BY checked_in_at DESC, id DESC LIMIT 1),
    (SELECT id FROM public.gyms WHERE manager_id = p_user_id ORDER BY created_at ASC LIMIT 1)
  );
$$;

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT COALESCE(public.user_role(auth.uid()), public.get_signup_role());
$$;

CREATE OR REPLACE FUNCTION public.get_my_gym_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT public.user_gym_id(auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.is_gym_manager()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT COALESCE(public.get_my_role(), '') IN ('gym_owner', 'gym', 'admin');
$$;

CREATE OR REPLACE FUNCTION public.manages_gym(p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT p_gym_id IS NOT NULL
     AND public.is_gym_manager()
     AND public.get_my_gym_id() = p_gym_id;
$$;

CREATE OR REPLACE FUNCTION public.is_same_gym_user(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT p_user_id IS NOT NULL
     AND public.user_gym_id(p_user_id) IS NOT NULL
     AND public.user_gym_id(p_user_id) = public.get_my_gym_id();
$$;

CREATE OR REPLACE FUNCTION public.can_manage_client_data(p_client_id uuid, p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN false
    WHEN p_client_id IS NULL THEN false
    WHEN COALESCE(p_gym_id, public.user_gym_id(p_client_id)) IS NULL THEN false
    WHEN COALESCE(p_gym_id, public.user_gym_id(p_client_id)) <> public.get_my_gym_id() THEN false
    WHEN public.is_gym_manager() THEN true
    WHEN public.get_my_role() = 'coach' THEN EXISTS (
      SELECT 1
      FROM public.coach_client_assignments cca
      WHERE cca.coach_id = auth.uid()
        AND cca.client_id = p_client_id
        AND cca.gym_id = COALESCE(p_gym_id, public.user_gym_id(p_client_id))
        AND cca.is_active = true
    )
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION public.can_view_user(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = p_user_id
      AND (
        u.id = auth.uid()
        OR (
          public.is_gym_manager()
          AND COALESCE(u.gym_id, public.user_gym_id(u.id)) = public.get_my_gym_id()
        )
        OR (
          public.get_my_role() = 'coach'
          AND COALESCE(u.gym_id, public.user_gym_id(u.id)) = public.get_my_gym_id()
          AND u.role IN ('client', 'gym_owner', 'gym', 'admin')
        )
        OR (
          public.get_my_role() = 'client'
          AND COALESCE(u.gym_id, public.user_gym_id(u.id)) = public.get_my_gym_id()
          AND u.role IN ('coach', 'gym_owner', 'gym', 'admin')
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_message_user(p_other_user_id uuid, p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT p_other_user_id IS NOT NULL
     AND auth.uid() IS NOT NULL
     AND p_other_user_id <> auth.uid()
     AND COALESCE(p_gym_id, public.user_gym_id(p_other_user_id)) = public.get_my_gym_id()
     AND (
       public.is_gym_manager()
       OR public.can_view_user(p_other_user_id)
     );
$$;


-- ----------------------------------------------------------------------------
-- AUTH PROFILE RECOVERY RPC
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.bootstrap_authenticated_user(text, text, text, text);

CREATE OR REPLACE FUNCTION public.bootstrap_authenticated_user(
  p_role text DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_gym_name text DEFAULT NULL
)
RETURNS public.users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
DECLARE
  v_auth_user auth.users%ROWTYPE;
  v_profile public.users%ROWTYPE;
  v_role text;
  v_name text;
  v_email text;
  v_lang text;
  v_gym_name text;
  v_gym_id uuid;
  v_meta_gym_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_auth_user
  FROM auth.users
  WHERE id = auth.uid();

  SELECT * INTO v_profile
  FROM public.users
  WHERE id = auth.uid();

  v_role := COALESCE(
    NULLIF(lower(BTRIM(v_profile.role)), ''),
    NULLIF(lower(BTRIM(p_role)), ''),
    NULLIF(lower(BTRIM(v_auth_user.raw_user_meta_data->>'role')), ''),
    NULLIF(lower(BTRIM(v_auth_user.raw_app_meta_data->>'role')), ''),
    'client'
  );
  IF v_role NOT IN ('client', 'coach', 'gym_owner', 'gym', 'admin') THEN
    v_role := 'client';
  END IF;

  v_name := COALESCE(
    NULLIF(BTRIM(v_profile.name), ''),
    NULLIF(BTRIM(p_name), ''),
    NULLIF(BTRIM(v_auth_user.raw_user_meta_data->>'name'), ''),
    split_part(COALESCE(v_profile.email, p_email, v_auth_user.email, 'User'), '@', 1),
    'User'
  );

  v_email := COALESCE(
    NULLIF(lower(BTRIM(v_profile.email)), ''),
    NULLIF(lower(BTRIM(p_email)), ''),
    NULLIF(lower(BTRIM(v_auth_user.email)), '')
  );

  v_lang := COALESCE(
    NULLIF(lower(BTRIM(v_profile.language_preference)), ''),
    NULLIF(lower(BTRIM(v_auth_user.raw_user_meta_data->>'language_preference')), ''),
    'fr'
  );
  IF v_lang NOT IN ('fr', 'en', 'ar') THEN
    v_lang := 'fr';
  END IF;

  v_gym_name := COALESCE(
    NULLIF(BTRIM(p_gym_name), ''),
    NULLIF(BTRIM(v_auth_user.raw_user_meta_data->>'gym_name'), '')
  );

  BEGIN
    IF NULLIF(BTRIM(v_auth_user.raw_user_meta_data->>'gym_id'), '') IS NOT NULL THEN
      v_meta_gym_id := (v_auth_user.raw_user_meta_data->>'gym_id')::uuid;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      v_meta_gym_id := NULL;
  END;

  IF v_email IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.users u
       WHERE u.email = v_email
         AND u.id <> auth.uid()
     ) THEN
    v_email := NULL;
  END IF;

  v_gym_id := COALESCE(
    v_profile.gym_id,
    public.user_gym_id(auth.uid()),
    v_meta_gym_id
  );

  IF v_gym_id IS NULL AND v_role IN ('gym_owner', 'gym', 'admin') THEN
    SELECT id INTO v_gym_id
    FROM public.gyms
    WHERE manager_id = auth.uid()
       OR lower(BTRIM(email)) = COALESCE(v_email, lower(BTRIM(email)))
       OR owner_name = v_name
    ORDER BY CASE WHEN manager_id = auth.uid() THEN 0 ELSE 1 END, created_at ASC
    LIMIT 1;
  END IF;

  IF v_gym_id IS NULL AND v_role IN ('gym_owner', 'gym', 'admin') AND v_gym_name IS NOT NULL THEN
    INSERT INTO public.gyms (name, email, owner_name, is_active, manager_id)
    VALUES (v_gym_name, v_email, v_name, true, auth.uid())
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_gym_id;

    IF v_gym_id IS NULL THEN
      SELECT id INTO v_gym_id
      FROM public.gyms
      WHERE manager_id = auth.uid()
         OR name = v_gym_name
      ORDER BY CASE WHEN manager_id = auth.uid() THEN 0 ELSE 1 END, created_at ASC
      LIMIT 1;
    END IF;
  END IF;

  INSERT INTO public.users (
    id,
    name,
    email,
    role,
    gym_id,
    language_preference,
    is_managed,
    is_active
  )
  VALUES (
    auth.uid(),
    v_name,
    v_email,
    v_role,
    v_gym_id,
    v_lang,
    false,
    true
  )
  ON CONFLICT (id) DO UPDATE
  SET
    name = COALESCE(NULLIF(EXCLUDED.name, ''), public.users.name),
    email = COALESCE(public.users.email, EXCLUDED.email),
    role = COALESCE(NULLIF(public.users.role, ''), EXCLUDED.role),
    gym_id = COALESCE(public.users.gym_id, EXCLUDED.gym_id),
    language_preference = COALESCE(NULLIF(public.users.language_preference, ''), EXCLUDED.language_preference),
    is_active = true,
    updated_at = now();

  IF v_gym_id IS NOT NULL AND v_role IN ('gym_owner', 'gym', 'admin') THEN
    UPDATE public.gyms
    SET manager_id = COALESCE(manager_id, auth.uid()),
        email = COALESCE(email, v_email),
        owner_name = COALESCE(owner_name, v_name),
        updated_at = now()
    WHERE id = v_gym_id;
  END IF;

  IF v_role = 'coach' THEN
    IF EXISTS (SELECT 1 FROM public.coach_profiles WHERE user_id = auth.uid()) THEN
      UPDATE public.coach_profiles
      SET gym_id = COALESCE(public.coach_profiles.gym_id, v_gym_id),
          is_active = COALESCE(public.coach_profiles.is_active, true),
          updated_at = now()
      WHERE user_id = auth.uid();
    ELSE
      INSERT INTO public.coach_profiles (user_id, gym_id, is_active, approval_status, approved_at)
      VALUES (
        auth.uid(),
        v_gym_id,
        true,
        CASE WHEN v_gym_id IS NULL THEN 'pending' ELSE 'approved' END,
        CASE WHEN v_gym_id IS NULL THEN NULL ELSE now() END
      );
    END IF;
  ELSIF v_role = 'client' THEN
    IF EXISTS (SELECT 1 FROM public.client_profiles WHERE user_id = auth.uid()) THEN
      UPDATE public.client_profiles
      SET updated_at = now()
      WHERE user_id = auth.uid();
    ELSE
      INSERT INTO public.client_profiles (user_id, payment_status, membership_tier, experience_level)
      VALUES (auth.uid(), 'pending', 'basic', 'beginner');
    END IF;
  END IF;

  SELECT * INTO v_profile
  FROM public.users
  WHERE id = auth.uid();

  RETURN v_profile;
END;
$$;

GRANT EXECUTE ON FUNCTION public.bootstrap_authenticated_user(text, text, text, text) TO authenticated;


-- ----------------------------------------------------------------------------
-- POLICY HOTFIX
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS gyms_select ON public.gyms;
DROP POLICY IF EXISTS gyms_update ON public.gyms;
DROP POLICY IF EXISTS users_select ON public.users;
DROP POLICY IF EXISTS users_insert ON public.users;
DROP POLICY IF EXISTS users_update ON public.users;
DROP POLICY IF EXISTS users_delete ON public.users;
DROP POLICY IF EXISTS sessions_select ON public.sessions;
DROP POLICY IF EXISTS sessions_insert ON public.sessions;
DROP POLICY IF EXISTS sessions_update ON public.sessions;
DROP POLICY IF EXISTS sessions_delete ON public.sessions;
DROP POLICY IF EXISTS reviews_select ON public.reviews;
DROP POLICY IF EXISTS reviews_insert ON public.reviews;
DROP POLICY IF EXISTS reviews_update ON public.reviews;
DROP POLICY IF EXISTS reviews_delete ON public.reviews;

CREATE POLICY gyms_select ON public.gyms
  FOR SELECT
  USING (id = public.get_my_gym_id() OR manager_id = auth.uid());

CREATE POLICY gyms_update ON public.gyms
  FOR UPDATE
  USING (id = public.get_my_gym_id() OR manager_id = auth.uid())
  WITH CHECK (id = public.get_my_gym_id() OR manager_id = auth.uid());

CREATE POLICY users_select ON public.users
  FOR SELECT
  USING (
    id = auth.uid()
    OR (
      COALESCE(gym_id, public.user_gym_id(id)) = public.get_my_gym_id()
      AND (
        public.is_gym_manager()
        OR (
          public.get_my_role() = 'coach'
          AND role IN ('client', 'gym_owner', 'gym', 'admin')
        )
        OR (
          public.get_my_role() = 'client'
          AND role IN ('coach', 'gym_owner', 'gym', 'admin')
        )
      )
    )
  );

CREATE POLICY users_insert ON public.users
  FOR INSERT
  WITH CHECK (
    id = auth.uid()
    OR (
      public.is_gym_manager()
      AND COALESCE(gym_id, public.get_my_gym_id()) = public.get_my_gym_id()
      AND role IN ('coach', 'client')
    )
  );

CREATE POLICY users_update ON public.users
  FOR UPDATE
  USING (
    id = auth.uid()
    OR (
      public.is_gym_manager()
      AND COALESCE(gym_id, public.user_gym_id(id)) = public.get_my_gym_id()
    )
  )
  WITH CHECK (
    id = auth.uid()
    OR (
      public.is_gym_manager()
      AND COALESCE(gym_id, public.get_my_gym_id()) = public.get_my_gym_id()
    )
  );

CREATE POLICY users_delete ON public.users
  FOR DELETE
  USING (
    id = auth.uid()
    OR (
      public.is_gym_manager()
      AND COALESCE(gym_id, public.user_gym_id(id)) = public.get_my_gym_id()
    )
  );

CREATE POLICY sessions_select ON public.sessions
  FOR SELECT
  USING (
    coach_id = auth.uid()
    OR client_id = auth.uid()
    OR (
      gym_id = public.get_my_gym_id()
      AND public.is_gym_manager()
    )
  );

CREATE POLICY sessions_insert ON public.sessions
  FOR INSERT
  WITH CHECK (
    gym_id = public.get_my_gym_id()
    AND public.is_gym_manager()
  );

CREATE POLICY sessions_update ON public.sessions
  FOR UPDATE
  USING (
    (gym_id = public.get_my_gym_id() AND public.is_gym_manager())
    OR coach_id = auth.uid()
  )
  WITH CHECK (
    (gym_id = public.get_my_gym_id() AND public.is_gym_manager())
    OR coach_id = auth.uid()
  );

CREATE POLICY sessions_delete ON public.sessions
  FOR DELETE
  USING (
    gym_id = public.get_my_gym_id()
    AND public.is_gym_manager()
  );

CREATE POLICY reviews_select ON public.reviews
  FOR SELECT
  USING (
    client_id = auth.uid()
    OR coach_id = auth.uid()
    OR (
      gym_id = public.get_my_gym_id()
      AND public.is_gym_manager()
    )
  );

CREATE POLICY reviews_insert ON public.reviews
  FOR INSERT
  WITH CHECK (
    client_id = auth.uid()
    AND COALESCE(gym_id, public.get_my_gym_id()) = public.get_my_gym_id()
  );

CREATE POLICY reviews_update ON public.reviews
  FOR UPDATE
  USING (
    client_id = auth.uid()
    OR (
      gym_id = public.get_my_gym_id()
      AND public.is_gym_manager()
    )
  )
  WITH CHECK (
    client_id = auth.uid()
    OR (
      gym_id = public.get_my_gym_id()
      AND public.is_gym_manager()
    )
  );

CREATE POLICY reviews_delete ON public.reviews
  FOR DELETE
  USING (
    client_id = auth.uid()
    OR (
      gym_id = public.get_my_gym_id()
      AND public.is_gym_manager()
    )
  );
