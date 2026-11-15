-- ============================================================================
-- TRAINW ROUND 9 — PRODUCTION SIGNUP (owner / client / coach) + JOIN FLOW
-- Branch: phase1-security-fixes. User authorised production readiness
-- 2026-11-15 ("Make it production ready, people can sign up...").
--
-- Step-1 audit (verified against the live DB before writing this):
--   1. Gym-owner signup was BROKEN. handle_new_user() creates every signup
--      as a bare client, and bootstrap_authenticated_user() gave the
--      existing profile role precedence over the explicit p_role — so a
--      signup as gym_owner with a gym name stayed role='client' and no
--      gym was ever created. The users upsert preserved the old role too.
--   2. Even if the gym had been created, bootstrap never created a
--      gym_memberships row: the round-2 rewrite dropped the 007 owner
--      membership insert (and the ensure_gym_default_roles call). But
--      get_auth_context reads memberships ONLY, so the owner would have
--      no workspace and the admin dashboard would bounce them to /role.
--   3. Clients/coaches had NO self-serve join path: the only attach path
--      was an owner invite, and /role dead-ended with "no workspaces".
--      A stranger signing up as client/coach could never reach a gym.
--
-- This migration:
--   A. bootstrap_authenticated_user: a FRESH bare client (role='client',
--      no gym, no memberships, manages no gym) may claim the explicit
--      role — gym_owner (only with a gym name: a gym is created and the
--      caller becomes its manager + active gym_owner member) or coach
--      (pending gymless coach profile, as originally designed). Anyone
--      else keeps their existing role. Adoption is unchanged: a gym is
--      adopted ONLY when manager_id is the caller; metadata gym_id is
--      still ignored outright (DB-10/DB-11). The owner membership insert
--      and the default-roles seeding from 007 are restored.
--   B. Join-request flow: list_public_gyms (safe columns only) +
--      request_gym_membership (client/coach only, idempotent) +
--      approve/reject_gym_membership (manage_staff only; requests only —
--      invites still go through the invitee's acceptance, never a
--      manager's approval). No RLS policy is touched: the RPCs check the
--      caller the same way invite_gym_member does.
--
-- VERIFICATION (local throwaway cluster + live project): see the Round 9
-- appendix in PHASE1_IMPLEMENTATION_NOTES.md.
-- ============================================================================

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
  v_is_fresh_bare_client boolean := false;
  v_owner_role_id uuid;
  v_owner_membership_id uuid;
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

  -- Round 9 (production signup): the gym name is resolved first — the
  -- role decision below needs it.
  v_gym_name := COALESCE(
    NULLIF(BTRIM(p_gym_name), ''),
    NULLIF(BTRIM(v_auth_user.raw_user_meta_data->>'gym_name'), '')
  );

  -- Round 9: handle_new_user() creates every signup as a bare client
  -- (role='client', no gym). If that is ALL the caller has — no gym, no
  -- memberships, manages no gym — the profile row is unclaimed and the
  -- caller's explicit role (the signup form's choice) wins. Otherwise the
  -- existing profile role wins (DB-10/DB-11: metadata role is untrusted).
  -- A gym_owner claim additionally needs a gym name: claiming the role
  -- without creating a gym would mint a gymless owner.
  v_is_fresh_bare_client := (
    v_profile.id IS NULL
    OR (
      v_profile.role = 'client'
      AND v_profile.gym_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.gym_memberships gm WHERE gm.user_id = auth.uid())
      AND NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.manager_id = auth.uid())
    )
  );

  IF v_is_fresh_bare_client THEN
    v_role := COALESCE(
      NULLIF(lower(BTRIM(p_role)), ''),
      NULLIF(lower(BTRIM(v_auth_user.raw_user_meta_data->>'role')), ''),
      NULLIF(lower(BTRIM(v_auth_user.raw_app_meta_data->>'role')), ''),
      'client'
    );
    IF v_role IN ('gym_owner', 'gym', 'admin') AND v_gym_name IS NULL THEN
      v_role := 'client';
    END IF;
  ELSE
    v_role := COALESCE(
      NULLIF(lower(BTRIM(v_profile.role)), ''),
      NULLIF(lower(BTRIM(p_role)), ''),
      NULLIF(lower(BTRIM(v_auth_user.raw_user_meta_data->>'role')), ''),
      NULLIF(lower(BTRIM(v_auth_user.raw_app_meta_data->>'role')), ''),
      'client'
    );
  END IF;
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

  -- Round 9: a fresh owner claim that produced no gym is not an owner.
  IF v_is_fresh_bare_client AND v_role IN ('gym_owner', 'gym', 'admin') AND v_gym_id IS NULL THEN
    v_role := 'client';
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
    -- Round 9: a fresh bare client takes the decided role (owner/coach);
    -- anyone else keeps their existing role (DB-10/DB-11).
    role = CASE WHEN v_is_fresh_bare_client THEN EXCLUDED.role ELSE COALESCE(NULLIF(public.users.role, ''), EXCLUDED.role) END,
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

  -- Round 9: make sure the gym has its default roles (the round-2
  -- rewrite dropped the ensure call along with the membership insert),
  -- then restore the 007 owner membership: without a gym_memberships row,
  -- get_auth_context (which reads memberships only) returns no workspace
  -- and the owner can never reach the admin dashboard. Guarded to gyms
  -- this caller manages, so a non-manager can never mint an owner
  -- membership for someone else's gym.
  IF v_gym_id IS NOT NULL
     AND v_role IN ('gym_owner', 'gym', 'admin')
     AND EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = v_gym_id AND g.manager_id = auth.uid()) THEN
    PERFORM public.ensure_gym_default_roles(v_gym_id, auth.uid());

    SELECT id INTO v_owner_role_id
    FROM public.roles
    WHERE gym_id = v_gym_id AND code = 'gym_owner'
    LIMIT 1;

    IF v_owner_role_id IS NOT NULL THEN
      INSERT INTO public.gym_memberships (
        gym_id, user_id, role_id, status, invitation_status,
        invite_email, invited_name, invited_by,
        accepted_at, activated_at, is_default, last_active_at
      )
      VALUES (
        v_gym_id, auth.uid(), v_owner_role_id, 'active', 'accepted',
        v_email, v_name, auth.uid(),
        now(), now(), true, now()
      )
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_owner_membership_id;

      IF v_owner_membership_id IS NOT NULL THEN
        UPDATE public.users
        SET default_gym_id = v_gym_id,
            default_membership_id = v_owner_membership_id,
            updated_at = now()
        WHERE id = auth.uid();
      END IF;
    END IF;
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


-- ----------------------------------------------------------------------------
-- B1 — list_public_gyms: minimal public directory for the join flow.
-- Only non-sensitive columns leave the database (no email, phone,
-- owner, prices, tax ids, or gate PIN hash).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.list_public_gyms()
RETURNS TABLE (
  gym_id uuid,
  name text,
  address text,
  location text,
  logo_storage_bucket text,
  logo_storage_path text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT g.id, g.name, g.address, g.location,
         g.logo_storage_bucket, g.logo_storage_path
  FROM public.gyms g
  WHERE g.is_active = true
  ORDER BY g.name ASC;
$$;

REVOKE ALL ON FUNCTION public.list_public_gyms() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_public_gyms() TO authenticated;

-- ----------------------------------------------------------------------------
-- B2 — request_gym_membership: a signed-in user asks to join a gym as a
-- client or a coach. Idempotent: an existing pending/active request for
-- the same role is returned instead of duplicated. No owner requests:
-- gym ownership comes only from the owner signup flow (bootstrap).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.request_gym_membership(
  p_gym_id uuid,
  p_role_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_role_code text;
  v_role_id uuid;
  v_gym_name text;
  v_existing record;
  v_membership_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to request a membership.';
  END IF;

  v_role_code := lower(BTRIM(COALESCE(p_role_code, '')));
  IF v_role_code NOT IN ('client', 'coach') THEN
    RAISE EXCEPTION 'Join requests are only open for client and coach roles.';
  END IF;

  SELECT g.name INTO v_gym_name
  FROM public.gyms g
  WHERE g.id = p_gym_id AND g.is_active = true;
  IF v_gym_name IS NULL THEN
    RAISE EXCEPTION 'Gym not found.';
  END IF;

  SELECT r.id INTO v_role_id
  FROM public.roles r
  WHERE r.gym_id = p_gym_id AND r.code = v_role_code
  LIMIT 1;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'This gym is not accepting % registrations yet.', v_role_code;
  END IF;

  SELECT gm.id, gm.status INTO v_existing
  FROM public.gym_memberships gm
  WHERE gm.gym_id = p_gym_id
    AND gm.user_id = auth.uid()
    AND gm.role_id = v_role_id
    AND gm.status IN ('pending', 'accepted', 'active')
  ORDER BY gm.created_at DESC
  LIMIT 1;

  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'membership_id', v_existing.id,
      'gym_id', p_gym_id,
      'role_code', v_role_code,
      'status', v_existing.status,
      'already_requested', true
    );
  END IF;

  INSERT INTO public.gym_memberships (
    gym_id, user_id, role_id, status, invitation_status,
    invite_email, invited_name, invited_by, invite_token,
    is_default
  )
  VALUES (
    p_gym_id, auth.uid(), v_role_id, 'pending', 'pending',
    public.auth_user_email(auth.uid()),
    (SELECT name FROM public.users WHERE id = auth.uid()),
    NULL, NULL,
    false
  )
  RETURNING id INTO v_membership_id;

  RETURN jsonb_build_object(
    'membership_id', v_membership_id,
    'gym_id', p_gym_id,
    'role_code', v_role_code,
    'status', 'pending',
    'already_requested', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_gym_membership(uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_gym_membership(uuid, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- B3 — approve_gym_membership: a manage_staff holder approves a join
-- REQUEST (invite_token IS NULL). Invites are NOT approvable here: they
-- carry a token and are accepted by the invitee. On approval the member
-- becomes active, the matching profile is linked to the gym (a coach is
-- approved), and the legacy projection is synced (as accept does).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.approve_gym_membership(p_membership_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_m record;
  v_is_default boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to approve a membership.';
  END IF;

  SELECT gm.id, gm.gym_id, gm.user_id, gm.role_id, gm.status, gm.invite_token,
         r.code AS role_code, r.portal AS portal
  INTO v_m
  FROM public.gym_memberships gm
  JOIN public.roles r ON r.id = gm.role_id
  WHERE gm.id = p_membership_id;

  IF v_m.id IS NULL THEN
    RAISE EXCEPTION 'Membership request not found.';
  END IF;

  IF NOT public.has_permission('manage_staff', v_m.gym_id) THEN
    RAISE EXCEPTION 'You do not have permission to approve members for this gym.';
  END IF;

  IF v_m.invite_token IS NOT NULL THEN
    RAISE EXCEPTION 'Invitations are accepted by the invitee, not approved by the gym.';
  END IF;

  IF v_m.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending request can be approved.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.gym_memberships gm
    WHERE gm.gym_id = v_m.gym_id AND gm.user_id = v_m.user_id
      AND gm.role_id = v_m.role_id AND gm.status IN ('accepted', 'active')
      AND gm.id <> v_m.id
  ) THEN
    RAISE EXCEPTION 'This member is already active in this gym.';
  END IF;

  v_is_default := NOT EXISTS (
    SELECT 1 FROM public.gym_memberships gm
    WHERE gm.user_id = v_m.user_id AND gm.status IN ('accepted', 'active')
  );

  UPDATE public.gym_memberships
  SET status = 'active',
      invitation_status = 'accepted',
      accepted_at = now(),
      activated_at = now(),
      declined_at = NULL,
      revoked_at = NULL,
      is_default = v_is_default,
      last_active_at = now(),
      updated_at = now()
  WHERE id = v_m.id;

  -- Profile link-up. NOTE: neither profile table has a unique
  -- constraint on user_id alone (the uniques are partial
  -- (user_id, gym_id) WHERE gym_id IS NOT NULL), so ON CONFLICT
  -- (user_id) is invalid here — it raises at runtime and rolls the
  -- whole approval back. Use the bootstrap pattern instead: update
  -- the existing row if there is one (a gymless pending coach profile
  -- from signup gets linked + approved), else insert. This also
  -- avoids a second profile row for the same user.
  IF v_m.portal = 'coach' THEN
    IF EXISTS (SELECT 1 FROM public.coach_profiles WHERE user_id = v_m.user_id) THEN
      UPDATE public.coach_profiles
      SET gym_id = COALESCE(public.coach_profiles.gym_id, v_m.gym_id),
          is_active = true,
          approval_status = 'approved',
          approved_at = now(),
          updated_at = now()
      WHERE user_id = v_m.user_id;
    ELSE
      INSERT INTO public.coach_profiles (user_id, gym_id, is_active, approval_status, approved_at)
      VALUES (v_m.user_id, v_m.gym_id, true, 'approved', now());
    END IF;
  ELSIF v_m.portal = 'client' THEN
    IF EXISTS (SELECT 1 FROM public.client_profiles WHERE user_id = v_m.user_id) THEN
      UPDATE public.client_profiles
      SET gym_id = COALESCE(public.client_profiles.gym_id, v_m.gym_id),
          updated_at = now()
      WHERE user_id = v_m.user_id;
    ELSE
      INSERT INTO public.client_profiles (user_id, gym_id, payment_status, membership_tier, experience_level)
      VALUES (v_m.user_id, v_m.gym_id, 'pending', 'basic', 'beginner');
    END IF;
  END IF;

  PERFORM public.sync_legacy_user_membership_projection(v_m.user_id);

  RETURN jsonb_build_object(
    'membership_id', v_m.id,
    'gym_id', v_m.gym_id,
    'role_code', v_m.role_code,
    'portal', v_m.portal,
    'status', 'active'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.approve_gym_membership(uuid) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_gym_membership(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- B4 — reject_gym_membership: a manage_staff holder declines a join
-- request. Same guards as approve (requests only, pending only).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reject_gym_membership(p_membership_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_m record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to decline a membership.';
  END IF;

  SELECT gm.id, gm.gym_id, gm.status, gm.invite_token, r.code AS role_code
  INTO v_m
  FROM public.gym_memberships gm
  JOIN public.roles r ON r.id = gm.role_id
  WHERE gm.id = p_membership_id;

  IF v_m.id IS NULL THEN
    RAISE EXCEPTION 'Membership request not found.';
  END IF;

  IF NOT public.has_permission('manage_staff', v_m.gym_id) THEN
    RAISE EXCEPTION 'You do not have permission to decline members for this gym.';
  END IF;

  IF v_m.invite_token IS NOT NULL THEN
    RAISE EXCEPTION 'Invitations are handled by the invitee, not declined by the gym.';
  END IF;

  IF v_m.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending request can be declined.';
  END IF;

  UPDATE public.gym_memberships
  SET status = 'declined',
      invitation_status = 'declined',
      declined_at = now(),
      updated_at = now()
  WHERE id = v_m.id;

  RETURN jsonb_build_object(
    'membership_id', v_m.id,
    'gym_id', v_m.gym_id,
    'role_code', v_m.role_code,
    'status', 'declined'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reject_gym_membership(uuid) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_gym_membership(uuid) TO authenticated;
