-- 20261115190000 — Phase 1g: live-test repairs (found by P1-13, 2026-11-15).
--
-- Three real defects that passed the local harness but fail on live Supabase:
--
-- FIX 1 — freeze check ignored at the gate (P1-13 C15b):
--   membership_is_active_for_access used the RAW p_reference_date in its
--   freeze clause, while every other clause uses
--   COALESCE(p_reference_date, public.gym_today(p_gym_id)). The gate calls
--   the RPC without p_reference_date (DB-37), so p_reference_date is NULL,
--   NULL BETWEEN ... is NULL, the NOT EXISTS is true, and a frozen member
--   is admitted. Local tests passed because they called the function (or
--   client_membership_is_active, which passes an explicit date) with a
--   date. Fixed: COALESCE in the freeze clause too. Present in
--   20261115110000 / 20261115210000 / 20261115230000; all three source
--   files are fixed the same way, this migration repairs the live DB.
--
-- FIX 2 — invite flow broken live (P1-13 D1, DB-40 again):
--   invite_gym_member calls unqualified gen_random_bytes(18). On Supabase,
--   pgcrypto lives in the `extensions` schema, and this function sets
--   search_path TO 'public', 'auth', 'pg_temp' — so live it raises
--   42883 "function gen_random_bytes(integer) does not exist". Locally
--   pgcrypto was installed in `public`, which masked it. Fixed:
--   extensions.gen_random_bytes(18). Source file 20261115360000 fixed too.
--
-- FIX 3 — credential hashing has the same latent defect (DB-07):
--   hash_member_credential calls unqualified hmac() with
--   SET search_path = public; hmac() also lives in `extensions`, so it
--   would raise 42883 the moment the pepper is set. Fixed here
--   (extensions.hmac) before it can bite; live verification is still
--   blocked on the pepper GUC (see runbook §3). Source file
--   20261115010000 fixed too.
--
-- Verification (live, after apply):
--   * select membership_is_active_for_access(<frozen client>, <gym>) = false
--     with no p_reference_date; gate QR for a frozen member is denied.
--   * invite_gym_member returns a token; accept works; expired invite fails.
--   * hash_member_credential still raises 'pepper is not configured'
--     (not 42883) while the pepper is unset.

-- ----------------------------------------------------------------------------
-- FIX 1 — membership_is_active_for_access (freeze clause).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.membership_is_active_for_access(p_client_id uuid, p_gym_id uuid, p_reference_date date DEFAULT NULL)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.client_profiles cp
    JOIN public.users u
      ON u.id = cp.user_id
    WHERE cp.user_id = p_client_id
      AND cp.gym_id = p_gym_id
      AND u.role = 'client'
      AND COALESCE(u.is_active, true)
      AND (
        cp.payment_status IN ('paid', 'trial', 'waived')
        OR (
          cp.price_paid > 0
          AND cp.payment_status NOT IN ('cancelled', 'refunded', 'overdue')
        )
      )
      AND (
        cp.membership_start_date IS NULL
        OR cp.membership_start_date <= COALESCE(p_reference_date, public.gym_today(p_gym_id))
      )
      AND (
        cp.membership_end_date IS NULL
        OR cp.membership_end_date >= COALESCE(p_reference_date, public.gym_today(p_gym_id))
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.membership_freezes f
        WHERE f.user_id = p_client_id
          AND f.gym_id = p_gym_id
          AND f.status = 'active'
          AND COALESCE(p_reference_date, public.gym_today(p_gym_id)) BETWEEN f.start_date AND f.end_date
      )
  );
$function$;

-- ----------------------------------------------------------------------------
-- FIX 2 — invite_gym_member (extensions.gen_random_bytes).
-- ----------------------------------------------------------------------------

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
    invite_token = encode(extensions.gen_random_bytes(18), 'hex'),
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
      encode(extensions.gen_random_bytes(18), 'hex'),
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

-- ----------------------------------------------------------------------------
-- FIX 3 — hash_member_credential (extensions.hmac).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.hash_member_credential(p_credential_data text)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_pepper text := public.member_credential_pepper();
BEGIN
  IF v_pepper IS NULL THEN
    RAISE EXCEPTION 'member credential pepper is not configured (trainw.member_credential_pepper)';
  END IF;
  IF p_credential_data IS NULL OR BTRIM(p_credential_data) = '' THEN
    RAISE EXCEPTION 'credential data is required';
  END IF;
  -- pgcrypto hmac(): keyed hash; the raw credential never leaves this call.
  -- NOTE: extensions schema — on Supabase pgcrypto lives in `extensions`,
  -- not public, and this function sets search_path = public.
  RETURN encode(extensions.hmac(BTRIM(p_credential_data), v_pepper, 'sha256'), 'hex');
END;
$$;
