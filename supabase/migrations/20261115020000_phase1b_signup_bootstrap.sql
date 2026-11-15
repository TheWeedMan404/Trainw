-- ============================================================================
-- TRAINW PHASE 1B — SIGNUP + BOOTSTRAP TRUST BOUNDARY
-- Audit 2026-11-14: DB-10, DB-11.
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- DB-10 — handle_new_user() trusted raw_user_meta_data: a caller could
--   sign up with role='gym_owner' (or 'admin') and gym_id=<any gym> and get
--   a users row with that role/gym, plus an auto-approved coach profile when
--   a gym_id was supplied. From here on the trigger IGNORES role and gym_id
--   from metadata entirely: every signup is role='client' with no gym.
--   Gyms are created only by the gym-owner signup flow (admin API +
--   provision_new_gym, after email confirmation — see NX-02) or by
--   bootstrap when the caller already manages a gym; coach profiles are
--   created only via invite (accept_gym_invitation) or by a manager.
--   The ON CONFLICT upsert still preserves an existing role/gym_id when the
--   trigger re-runs for a user that already has a profile row.
-- DB-11 — bootstrap_authenticated_user() adopted an existing gym by
--   manager_id OR email match OR owner_name match, and re-adopted by gym
--   name after a failed insert. An attacker could create an account with
--   the victim gym's owner email/name in metadata and inherit the gym.
--   From here on bootstrap adopts a gym ONLY when gyms.manager_id is the
--   caller (the caller's own gym), or creates a NEW gym when the caller is
--   an owner/admin with a gym name. Metadata gym_id is ignored outright.
--   Also fixed while here: the ON CONFLICT upsert forced is_active = true
--   on every login, silently re-activating banned users (noted in the
--   round-1 notes as out of scope then; fixed here because this migration
--   rewrites the function anyway). is_active is now set only on INSERT.
--   And: coach profiles created by bootstrap are always approval_status
--   'pending' — bootstrap no longer auto-approves a coach just because a
--   gym_id is present (self-approval through the back door).
--   The users_insert policy is tightened in the same spirit: a self-insert
--   (id = auth.uid()) may only create role='client' with gym_id NULL.
--
-- VERIFICATION (no live DB was available when this was written):
--   * Sign up with user_metadata {role:'gym_owner', gym_id:<victim gym>}:
--     the users row must be role='client', gym_id NULL, no coach profile,
--     no gym created.
--   * Sign up normally, then call bootstrap with metadata naming another
--     gym's owner email/name: the caller must NOT adopt that gym.
--   * A banned user (is_active=false) logging in must stay is_active=false.
--   * The gym-owner signup flow (NX-02) must still work end to end.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DB-10 — handle_new_user: ignore role/gym_id from metadata.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_name      text;
  v_phone     text;
BEGIN
  -- DB-10: role and gym_id from raw_user_meta_data are untrusted client
  -- input. Every signup is a plain client with no gym; privilege and gym
  -- membership come only from invite / bootstrap / the owner flow.
  v_name := COALESCE(NULLIF(BTRIM(NEW.raw_user_meta_data->>'name'), ''), 'User');
  v_phone := NULLIF(BTRIM(NEW.raw_user_meta_data->>'phone'), '');

  INSERT INTO public.users (
    id, name, email, role, gym_id, phone, language_preference, is_managed, is_active
  )
  VALUES (
    NEW.id,
    v_name,
    NULLIF(lower(BTRIM(NEW.email)), ''),
    'client',
    NULL,
    v_phone,
    COALESCE(NULLIF(lower(BTRIM(NEW.raw_user_meta_data->>'language_preference')), ''), 'fr'),
    false,
    true
  )
  ON CONFLICT (id) DO UPDATE
  SET
    name = COALESCE(NULLIF(EXCLUDED.name, ''), public.users.name),
    email = COALESCE(public.users.email, EXCLUDED.email),
    role = COALESCE(NULLIF(public.users.role, ''), EXCLUDED.role),
    gym_id = COALESCE(public.users.gym_id, EXCLUDED.gym_id),
    phone = COALESCE(public.users.phone, EXCLUDED.phone),
    language_preference = COALESCE(public.users.language_preference, EXCLUDED.language_preference),
    updated_at = now();

  -- DB-10: no gym is ever created here, no manager_id is ever set here,
  -- and no coach profile is auto-created. A client profile is the only
  -- side effect of a signup.
  IF NOT EXISTS (
    SELECT 1
    FROM public.client_profiles cp
    WHERE cp.user_id = NEW.id
  ) THEN
    INSERT INTO public.client_profiles (
      user_id, membership_tier, payment_status, experience_level
    )
    VALUES (
      NEW.id,
      'basic',
      'pending',
      'beginner'
    );
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG 'handle_new_user error for %: % - %', NEW.id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- DB-10 — users_insert: a self-insert may only create a gymless client.
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS users_insert ON public.users;
CREATE POLICY users_insert ON public.users
  FOR INSERT
  WITH CHECK (
    (
      id = auth.uid()
      AND role = 'client'
      AND gym_id IS NULL
    )
    OR (
      public.is_gym_manager()
      AND COALESCE(gym_id, public.get_my_gym_id()) = public.get_my_gym_id()
      AND role IN ('coach', 'client')
    )
  );

-- ----------------------------------------------------------------------------
-- DB-11 — bootstrap_authenticated_user: no adoption by email/name/metadata.
-- ----------------------------------------------------------------------------

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

  -- DB-11: metadata gym_id is ignored outright (it is client-supplied).
  -- The gym comes only from the caller's existing profile, their default
  -- membership, a gym they already manage, or a newly created gym below.

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
    public.user_gym_id(auth.uid())
  );

  -- DB-11: adopt ONLY a gym the caller already manages. The old email /
  -- owner_name match is gone: anyone could have registered with a victim
  -- gym's owner email or name and inherited the gym.
  IF v_gym_id IS NULL AND v_role IN ('gym_owner', 'gym', 'admin') THEN
    SELECT id INTO v_gym_id
    FROM public.gyms
    WHERE manager_id = auth.uid()
    ORDER BY created_at ASC
    LIMIT 1;
  END IF;

  IF v_gym_id IS NULL AND v_role IN ('gym_owner', 'gym', 'admin') AND v_gym_name IS NOT NULL THEN
    INSERT INTO public.gyms (name, email, owner_name, is_active, manager_id)
    VALUES (v_gym_name, v_email, v_name, true, auth.uid())
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_gym_id;

    -- DB-11: after a failed insert, re-adopt ONLY by manager_id. The old
    -- name-match fallback is gone for the same reason as above.
    IF v_gym_id IS NULL THEN
      SELECT id INTO v_gym_id
      FROM public.gyms
      WHERE manager_id = auth.uid()
      ORDER BY created_at ASC
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
    updated_at = now();
  -- NOTE: is_active is deliberately NOT set here anymore. The old version
  -- forced is_active = true on every login, silently re-activating banned
  -- users. A banned user stays banned until a manager re-activates them.

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
      -- DB-10/DB-11: a coach profile created here is PENDING. The old code
      -- auto-approved it whenever a gym_id was present — a self-approval
      -- through the back door.
      INSERT INTO public.coach_profiles (user_id, gym_id, is_active, approval_status, approved_at)
      VALUES (
        auth.uid(),
        v_gym_id,
        true,
        'pending',
        NULL
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
