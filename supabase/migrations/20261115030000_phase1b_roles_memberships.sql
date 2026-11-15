-- ============================================================================
-- TRAINW PHASE 1B — ROLES + MEMBERSHIPS HARDENING
-- Audit 2026-11-14: DB-12, DB-13, DB-14, DB-40.
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- DB-12 — set_membership_role() never checked that p_role_id belongs to the
--   membership's gym: a manage_staff holder in gym A could assign a role
--   from gym B (whose permissions mean something else there) to a member
--   of gym A. The role must belong to the membership's gym.
-- DB-13 — save_role_definition() let anyone with manage_roles rewrite a
--   SYSTEM role (gym_owner / gym_admin / staff / coach / client): rename
--   it, move it to another portal, or empty its permissions via
--   ensure_role_permission_codes. System roles are now immutable through
--   this RPC — only custom (is_system = false) roles can be edited.
-- DB-14 — the single gym_memberships_manage_v17 FOR ALL policy let any
--   manage_staff holder INSERT/UPDATE/DELETE any membership row, including
--   granting themselves (or anyone) any role. It is replaced by split
--   policies: INSERT/UPDATE require manage_staff for the row's gym, the
--   role must belong to that gym, the target must not be the caller
--   (no self-grants), and status must be in the allowed set. There is NO
--   DELETE policy anymore: memberships end only through the revoke RPC.
--   The same self-grant forbid is added inside set_membership_role() and
--   invite_gym_member() (a manager inviting their own email with a higher
--   role, or re-assigning their own membership's role, is refused).
--   The one legitimate direct write in the app — submitNewClient inserting
--   a manager-created client (status 'active', the gym's client role, a
--   different user) — still passes all three checks.
-- DB-40 — invite_token never expired and re-inviting an ACTIVE member
--   reset them to pending (silently revoking access until they re-accept).
--   New column gym_memberships.invite_expires_at (7 days from invite,
--   refreshed on re-invite); accept_gym_invitation enforces it (a NULL
--   expiry on pre-existing rows is grandfathered, not retro-expired);
--   re-inviting an already-active member is now a no-op returning the
--   existing membership/token instead of resetting them.
--
-- VERIFICATION (no live DB was available when this was written):
--   * set_membership_role with a role from another gym must raise.
--   * save_role_definition on a system role must raise; on a custom role
--     must still work.
--   * Direct INSERT into gym_memberships with user_id = auth.uid() must
--     fail; direct DELETE must fail (no policy); submitNewClient must
--     still create clients.
--   * An invite accepted after 7 days must raise 'expired'; re-inviting
--     an active member must leave status='active' untouched.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DB-40 — invite expiry column.
-- ----------------------------------------------------------------------------

ALTER TABLE public.gym_memberships
  ADD COLUMN IF NOT EXISTS invite_expires_at timestamptz;

-- ----------------------------------------------------------------------------
-- DB-12 + DB-14 — set_membership_role: role-gym check + no self-grants.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_membership_role(
  p_membership_id uuid,
  p_role_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_membership record;
BEGIN
  SELECT gm.id, gm.gym_id, gm.user_id
  INTO v_membership
  FROM public.gym_memberships gm
  WHERE gm.id = p_membership_id;

  IF v_membership.id IS NULL THEN
    RAISE EXCEPTION 'Membership not found.';
  END IF;

  IF NOT public.has_permission('manage_staff', v_membership.gym_id) THEN
    RAISE EXCEPTION 'You do not have permission to assign roles in this gym.';
  END IF;

  -- DB-14: no self-grants — a manager cannot change their own membership's
  -- role (that is how a staff member promotes themselves to gym_owner).
  IF v_membership.user_id IS NOT NULL AND v_membership.user_id = auth.uid() THEN
    RAISE EXCEPTION 'You cannot change your own role.';
  END IF;

  -- DB-12: the new role must belong to the membership's gym.
  IF NOT EXISTS (
    SELECT 1
    FROM public.roles r
    WHERE r.id = p_role_id
      AND r.gym_id = v_membership.gym_id
  ) THEN
    RAISE EXCEPTION 'Role does not belong to this gym.';
  END IF;

  UPDATE public.gym_memberships
  SET
    role_id = p_role_id,
    updated_at = now()
  WHERE id = p_membership_id;

  IF v_membership.user_id IS NOT NULL THEN
    PERFORM public.sync_legacy_user_membership_projection(v_membership.user_id);
  END IF;

  RETURN jsonb_build_object('membership_id', p_membership_id, 'role_id', p_role_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- DB-13 — save_role_definition: refuse edits to system roles.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_role_definition(
  p_gym_id uuid,
  p_role_id uuid DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_code text DEFAULT NULL,
  p_portal text DEFAULT 'client',
  p_description text DEFAULT NULL,
  p_permission_codes text[] DEFAULT ARRAY[]::text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_id uuid;
BEGIN
  IF NOT public.has_permission('manage_roles', p_gym_id) THEN
    RAISE EXCEPTION 'You do not have permission to manage roles for this gym.';
  END IF;

  IF COALESCE(NULLIF(BTRIM(p_name), ''), '') = '' THEN
    RAISE EXCEPTION 'Role name is required.';
  END IF;

  IF COALESCE(NULLIF(BTRIM(p_portal), ''), '') NOT IN ('admin', 'coach', 'client') THEN
    RAISE EXCEPTION 'Role portal must be admin, coach, or client.';
  END IF;

  IF p_role_id IS NULL THEN
    INSERT INTO public.roles (
      gym_id,
      code,
      name,
      description,
      portal,
      is_system,
      is_default,
      created_by
    )
    VALUES (
      p_gym_id,
      public.normalize_role_code(COALESCE(p_code, p_name)),
      BTRIM(p_name),
      NULLIF(BTRIM(p_description), ''),
      BTRIM(p_portal),
      false,
      false,
      auth.uid()
    )
    RETURNING id INTO v_role_id;
  ELSE
    -- DB-13: system roles (gym_owner, gym_admin, staff, coach, client)
    -- are immutable through this RPC. Create a custom role instead.
    IF EXISTS (
      SELECT 1
      FROM public.roles r
      WHERE r.id = p_role_id
        AND r.gym_id = p_gym_id
        AND r.is_system = true
    ) THEN
      RAISE EXCEPTION 'System roles cannot be edited.';
    END IF;

    UPDATE public.roles
    SET
      code = public.normalize_role_code(COALESCE(p_code, p_name)),
      name = BTRIM(p_name),
      description = NULLIF(BTRIM(p_description), ''),
      portal = BTRIM(p_portal),
      updated_at = now()
    WHERE id = p_role_id
      AND gym_id = p_gym_id
    RETURNING id INTO v_role_id;
  END IF;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Role could not be saved.';
  END IF;

  PERFORM public.ensure_role_permission_codes(v_role_id, COALESCE(p_permission_codes, ARRAY[]::text[]));
  RETURN v_role_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- DB-14 — split the gym_memberships manage policy; no DELETE policy.
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS gym_memberships_manage_v17 ON public.gym_memberships;

CREATE POLICY gym_memberships_insert_v17b ON public.gym_memberships
  FOR INSERT
  WITH CHECK (
    public.has_permission('manage_staff', gym_id)
    AND (user_id IS NULL OR user_id <> auth.uid())
    AND EXISTS (
      SELECT 1
      FROM public.roles r
      WHERE r.id = role_id
        AND r.gym_id = gym_memberships.gym_id
    )
    AND status IN ('pending', 'accepted', 'active')
  );

CREATE POLICY gym_memberships_update_v17b ON public.gym_memberships
  FOR UPDATE
  USING (
    public.has_permission('manage_staff', gym_id)
    AND (user_id IS NULL OR user_id <> auth.uid())
  )
  WITH CHECK (
    public.has_permission('manage_staff', gym_id)
    AND (user_id IS NULL OR user_id <> auth.uid())
    AND EXISTS (
      SELECT 1
      FROM public.roles r
      WHERE r.id = role_id
        AND r.gym_id = gym_memberships.gym_id
    )
    AND status IN ('pending', 'accepted', 'active', 'declined', 'revoked')
  );

-- NOTE: there is deliberately NO DELETE policy on gym_memberships anymore.
-- Memberships end only through revoke_gym_membership / 
-- revoke_gym_membership_by_user. A direct DELETE is denied by default.

-- ----------------------------------------------------------------------------
-- DB-14 + DB-40 — invite_gym_member: no self-invites, invite expiry,
-- re-invite of an active member is a no-op.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.invite_gym_member(
  p_gym_id uuid,
  p_email text,
  p_name text,
  p_role_id uuid,
  p_phone text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  membership_id uuid,
  invite_token text,
  existing_user boolean,
  invite_email text,
  role_name text,
  gym_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_email citext;
  v_existing_user_id uuid;
  v_existing_auth_user_id uuid;
  v_role record;
  v_gym_name text;
BEGIN
  IF NOT public.has_permission('manage_staff', p_gym_id) THEN
    RAISE EXCEPTION 'You do not have permission to invite members to this gym.';
  END IF;

  v_email := NULLIF(lower(BTRIM(p_email)), '')::citext;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Invitation email is required.';
  END IF;

  -- DB-14: no self-invites. Inviting your own email with a role is a
  -- self-grant by another name.
  IF v_email = public.auth_user_email(auth.uid()) THEN
    RAISE EXCEPTION 'You cannot invite your own email address.';
  END IF;

  SELECT r.id, r.name, r.gym_id
  INTO v_role
  FROM public.roles r
  WHERE r.id = p_role_id
    AND r.gym_id = p_gym_id;

  IF v_role.id IS NULL THEN
    RAISE EXCEPTION 'Role does not belong to this gym.';
  END IF;

  SELECT g.name INTO v_gym_name
  FROM public.gyms g
  WHERE g.id = p_gym_id;

  SELECT u.id INTO v_existing_user_id
  FROM public.users u
  WHERE u.email = v_email
  LIMIT 1;

  SELECT au.id INTO v_existing_auth_user_id
  FROM auth.users au
  WHERE lower(BTRIM(au.email))::citext = v_email
  LIMIT 1;

  IF v_existing_user_id IS NULL AND v_existing_auth_user_id IS NOT NULL THEN
    INSERT INTO public.users (id, name, email, role, language_preference, is_active)
    VALUES (
      v_existing_auth_user_id,
      COALESCE(NULLIF(BTRIM(p_name), ''), split_part(v_email::text, '@', 1)),
      v_email::text,
      public.map_legacy_role_code((SELECT code FROM public.roles WHERE id = p_role_id)),
      'fr',
      true
    )
    ON CONFLICT (id) DO UPDATE
    SET
      name = COALESCE(NULLIF(BTRIM(EXCLUDED.name), ''), public.users.name),
      email = COALESCE(EXCLUDED.email, public.users.email),
      updated_at = now()
    RETURNING id INTO v_existing_user_id;
  END IF;

  -- DB-40: re-inviting an already-ACTIVE member is a no-op. The old code
  -- reset them to pending (revoking access until they re-accepted).
  SELECT gm.id, gm.invite_token
  INTO membership_id, invite_token
  FROM public.gym_memberships gm
  WHERE gm.gym_id = p_gym_id
    AND gm.status = 'active'
    AND (
      (v_existing_user_id IS NOT NULL AND gm.user_id = v_existing_user_id)
      OR gm.invite_email = v_email
    )
  LIMIT 1;

  IF membership_id IS NOT NULL THEN
    invite_email := v_email::text;
    role_name := v_role.name;
    gym_name := COALESCE(v_gym_name, 'Trainw Gym');
    existing_user := v_existing_user_id IS NOT NULL OR v_existing_auth_user_id IS NOT NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE public.gym_memberships
  SET
    user_id = COALESCE(user_id, v_existing_user_id),
    role_id = p_role_id,
    status = 'pending',
    invitation_status = 'pending',
    invite_email = v_email,
    invited_name = NULLIF(BTRIM(p_name), ''),
    invited_phone = NULLIF(BTRIM(p_phone), ''),
    invite_token = encode(gen_random_bytes(18), 'hex'),
    invite_expires_at = now() + interval '7 days',
    invited_by = auth.uid(),
    invited_at = now(),
    accepted_at = NULL,
    activated_at = NULL,
    declined_at = NULL,
    revoked_at = NULL,
    metadata = COALESCE(p_metadata, '{}'::jsonb),
    updated_at = now()
  WHERE gym_id = p_gym_id
    AND (
      (v_existing_user_id IS NOT NULL AND user_id = v_existing_user_id)
      OR invite_email = v_email
    )
    AND status IN ('pending', 'accepted', 'active')
  RETURNING id, public.gym_memberships.invite_token INTO membership_id, invite_token;

  IF membership_id IS NULL THEN
    INSERT INTO public.gym_memberships (
      gym_id,
      user_id,
      role_id,
      status,
      invitation_status,
      invite_email,
      invited_name,
      invited_phone,
      invite_token,
      invite_expires_at,
      invited_by,
      invited_at,
      metadata
    )
    VALUES (
      p_gym_id,
      v_existing_user_id,
      p_role_id,
      'pending',
      'pending',
      v_email,
      NULLIF(BTRIM(p_name), ''),
      NULLIF(BTRIM(p_phone), ''),
      encode(gen_random_bytes(18), 'hex'),
      now() + interval '7 days',
      auth.uid(),
      now(),
      COALESCE(p_metadata, '{}'::jsonb)
    )
    RETURNING id, public.gym_memberships.invite_token INTO membership_id, invite_token;
  END IF;

  invite_email := v_email::text;
  role_name := v_role.name;
  gym_name := COALESCE(v_gym_name, 'Trainw Gym');
  existing_user := v_existing_user_id IS NOT NULL OR v_existing_auth_user_id IS NOT NULL;

  RETURN NEXT;
END;
$$;

-- ----------------------------------------------------------------------------
-- DB-40 — accept_gym_invitation: enforce invite expiry.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.accept_gym_invitation(
  p_invite_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_email citext;
  v_membership record;
  v_profile public.users%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to accept an invitation.';
  END IF;

  v_email := public.auth_user_email(auth.uid());

  SELECT
    gm.id,
    gm.gym_id,
    gm.role_id,
    gm.status,
    gm.invite_expires_at,
    r.code AS role_code,
    r.portal
  INTO v_membership
  FROM public.gym_memberships gm
  JOIN public.roles r
    ON r.id = gm.role_id
WHERE gm.invite_token = p_invite_token
    AND gm.status = 'pending'
    AND (
      gm.user_id = auth.uid()
      OR gm.user_id IS NULL
      OR gm.invite_email = v_email
    )
  LIMIT 1;

  IF v_membership.id IS NULL THEN
    RAISE EXCEPTION 'Invitation not found or already processed.';
  END IF;

  -- DB-40: invites expire 7 days after they are (re-)sent. A NULL expiry
  -- (rows created before this migration) is grandfathered, not expired.
  IF v_membership.invite_expires_at IS NOT NULL
     AND v_membership.invite_expires_at < now() THEN
    RAISE EXCEPTION 'This invitation has expired. Ask the gym to send a new one.';
  END IF;

  UPDATE public.gym_memberships
  SET
    user_id = auth.uid(),
    status = 'active',
    invitation_status = 'accepted',
    accepted_at = COALESCE(accepted_at, now()),
    activated_at = now(),
    declined_at = NULL,
    revoked_at = NULL,
    is_default = CASE
      WHEN EXISTS (
        SELECT 1
        FROM public.gym_memberships existing_default
        WHERE existing_default.user_id = auth.uid()
          AND existing_default.status IN ('accepted', 'active')
      ) THEN is_default
      ELSE true
    END,
    last_active_at = now(),
    updated_at = now()
  WHERE id = v_membership.id;

  IF v_membership.portal = 'coach' THEN
    INSERT INTO public.coach_profiles (user_id, gym_id, is_active)
    VALUES (auth.uid(), v_membership.gym_id, true)
    ON CONFLICT DO NOTHING;
  ELSIF v_membership.portal = 'client' THEN
    INSERT INTO public.client_profiles (user_id, gym_id, payment_status)
    VALUES (auth.uid(), v_membership.gym_id, 'pending')
    ON CONFLICT DO NOTHING;
  END IF;

  v_profile := public.sync_legacy_user_membership_projection(auth.uid());
  PERFORM public.set_active_gym(v_membership.gym_id);

  RETURN jsonb_build_object(
    'membership_id', v_membership.id,
    'gym_id', v_membership.gym_id,
    'role_code', v_membership.role_code,
    'portal', v_membership.portal,
    'user', to_jsonb(v_profile)
  );
END;
$$;
