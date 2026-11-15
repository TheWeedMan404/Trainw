-- Round 6 (audit closure) — fix invite_gym_member.
--
-- BUG 1 (found by the round-6 verification suite, DB-40): the function
-- raised "column reference invite_email is ambiguous" on EVERY call, so
-- the invite flow was completely broken. The UPDATE's WHERE clause used
-- the unqualified name `invite_email`, which collides with the function's
-- OUT parameter of the same name. Fixed by qualifying it with the table.
--
-- BUG 2 (DB-14, owner-role hole): any manage_staff holder could invite
-- someone as gym_owner. Only the gym's manager may assign the
-- gym_owner role; anyone else inviting with that role is refused.
CREATE OR REPLACE FUNCTION public.invite_gym_member(p_gym_id uuid, p_email text, p_name text, p_role_id uuid, p_phone text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(membership_id uuid, invite_token text, existing_user boolean, invite_email text, role_name text, gym_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
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

  SELECT r.id, r.name, r.gym_id, r.code
  INTO v_role
  FROM public.roles r
  WHERE r.id = p_role_id
    AND r.gym_id = p_gym_id;

  IF v_role.id IS NULL THEN
    RAISE EXCEPTION 'Role does not belong to this gym.';
  END IF;

  -- DB-14 (round 6): only the gym's manager may assign the gym_owner
  -- role. A manage_staff holder inviting someone as gym_owner was a
  -- privilege-escalation path (the invitee becomes an owner on accept).
  IF v_role.code = 'gym_owner' AND NOT EXISTS (
    SELECT 1 FROM public.gyms g
    WHERE g.id = p_gym_id AND g.manager_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only the gym manager can assign the gym_owner role.';
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
      -- Round 6: qualify the column — the unqualified name collided
      -- with this function's OUT parameter `invite_email` and made
      -- every invite raise "column reference is ambiguous".
      OR public.gym_memberships.invite_email = v_email
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
$function$;
