-- ============================================================================
-- TRAINW PHASE 1B — DIRECTORIES + RPC EXPOSURE HARDENING
-- Audit 2026-11-14: DB-20, DB-21, DB-42, DB-43, DB-44, DB-55.
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- DB-20 — get_staff_directory() returned invite_token and national_id for
--   every non-revoked member to anyone with view_staff_profiles (which the
--   default staff role has). Both columns are removed from the function.
--   They are exposed only through the new
--   public.get_staff_directory_sensitive(p_gym_id), which requires
--   manage_staff for the gym and writes an audit row to the new
--   public.admin_audit_log table before returning anything. No frontend
--   caller exists yet (invite links come from the invite_gym_member RPC
--   return value, not the directory) — the function is the audited path
--   for a future UI that needs these fields.
-- DB-21 — list_gym_member_directory() was readable by ANY member of the
--   gym (its only gate was user_has_membership). It is now restricted to
--   staff: the caller must hold 'view_clients' in the gym (raw-table,
--   deny-aware check — staff, coach and admin roles hold it; plain
--   clients do not) or manage the gym.
-- DB-42/43/44 — auth_user_email(), permission_codes_for_membership() and
--   sync_legacy_user_membership_projection() were granted to PUBLIC
--   (default PUBLIC EXECUTE) with no caller check: any authenticated user
--   could read any user's email, any membership's permission set, or any
--   user's projected role/gym. All three are now revoked from PUBLIC,
--   granted to authenticated only, and check the caller first.
--   The checks use ONLY raw-table lookups (gyms.manager_id, memberships,
--   roles, role_permissions, permissions, user_permissions) through the
--   helpers below. They deliberately do NOT call manages_gym /
--   has_permission / get_my_permissions: current_membership() calls
--   permission_codes_for_membership() for the caller's own memberships,
--   so any manages_gym call inside it would recurse infinitely
--   (manages_gym -> has_permission -> get_my_permissions ->
--   current_membership -> permission_codes_for_membership -> ...).
-- DB-55 — gate_sessions_select let only the session owner read a session;
--   a manager could not see (or revoke) their own gym's terminal sessions.
--   The SELECT policy now also allows manages_gym(gym_id), and the new
--   manager-only RPC public.revoke_gate_session(p_session_id) invalidates
--   a session (used=true) for managers of that gym.
--
-- VERIFICATION (no live DB was available when this was written):
--   * get_staff_directory must not return invite_token / national_id
--     columns at all; get_staff_directory_sensitive without manage_staff
--     must raise, and with it must return the fields + write an audit row.
--   * A plain client calling list_gym_member_directory must get no rows;
--     a coach/staff member must still get the directory.
--   * SELECT auth_user_email(<other user>) / permission_codes_for_membership
--     (<other gym's membership>) as a plain authenticated user must raise.
--   * A manager must be able to SELECT gate_sessions for their gym and
--     revoke one via revoke_gate_session; a non-manager must not.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Shared direct-check helpers (raw tables only — see header on recursion).
-- ----------------------------------------------------------------------------

-- True when the caller is the gym's manager, or holds an admin-portal
-- membership in the gym.
CREATE OR REPLACE FUNCTION public.caller_manages_gym_direct(p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.gyms g
    WHERE g.id = p_gym_id
      AND g.manager_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.gym_memberships gm
    JOIN public.roles r
      ON r.id = gm.role_id
    WHERE gm.user_id = auth.uid()
      AND gm.gym_id = p_gym_id
      AND r.portal = 'admin'
      AND gm.status IN ('accepted', 'active')
  );
$$;

-- True when the caller's effective permissions in the gym include the given
-- code: granted by their role and NOT denied by a user_permissions override.
-- Raw-table check (no has_permission call) so it is safe to use inside
-- permission_codes_for_membership().
CREATE OR REPLACE FUNCTION public.caller_holds_permission_in_gym(
  p_permission_code text,
  p_gym_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.gym_memberships gm
    JOIN public.role_permissions rp
      ON rp.role_id = gm.role_id
    JOIN public.permissions p
      ON p.id = rp.permission_id
    WHERE gm.user_id = auth.uid()
      AND gm.gym_id = p_gym_id
      AND gm.status IN ('accepted', 'active')
      AND p.code = p_permission_code
      AND NOT EXISTS (
        SELECT 1
        FROM public.user_permissions up
        WHERE up.user_id = auth.uid()
          AND up.gym_id = p_gym_id
          AND up.permission_id = p.id
          AND up.effect = 'deny'
      )
  );
$$;

-- ----------------------------------------------------------------------------
-- DB-42 — auth_user_email: own email, or manager/viewer of the target's gym.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.auth_user_email(p_user_id uuid DEFAULT auth.uid())
RETURNS citext
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid()
     AND NOT EXISTS (
       SELECT 1
       FROM public.gym_memberships gm
       WHERE gm.user_id = p_user_id
         AND gm.status IN ('accepted', 'active')
         AND (
           public.caller_manages_gym_direct(gm.gym_id)
           OR public.caller_holds_permission_in_gym('view_clients', gm.gym_id)
         )
     ) THEN
    RAISE EXCEPTION 'Not allowed to read this email.';
  END IF;

  RETURN (
    SELECT NULLIF(lower(BTRIM(u.email)), '')::citext
    FROM auth.users u
    WHERE u.id = p_user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.auth_user_email(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_user_email(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- DB-43 — permission_codes_for_membership: own membership, or a staff reader.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.permission_codes_for_membership(
  p_membership_id uuid
)
RETURNS text[]
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_gym_id uuid;
  v_user_id uuid;
  v_result text[];
BEGIN
  SELECT gm.gym_id, gm.user_id INTO v_gym_id, v_user_id
  FROM public.gym_memberships gm
  WHERE gm.id = p_membership_id;

  IF v_gym_id IS NULL THEN
    RETURN ARRAY[]::text[];
  END IF;

  -- DB-43: the caller must be the membership's user, manage the gym, or
  -- hold view_clients there (directory readers: staff/coach/manager).
  -- Direct checks only — see the header note on recursion.
  IF v_user_id IS DISTINCT FROM auth.uid()
     AND NOT public.caller_manages_gym_direct(v_gym_id)
     AND NOT public.caller_holds_permission_in_gym('view_clients', v_gym_id) THEN
    RAISE EXCEPTION 'Not allowed to read permissions for this membership.';
  END IF;

  -- Body below is the 007 version verbatim: role codes UNION explicit
  -- allows, minus explicit denies (a deny wins over both).
  WITH membership_row AS (
    SELECT gm.id, gm.user_id, gm.gym_id, gm.role_id
    FROM public.gym_memberships gm
    WHERE gm.id = p_membership_id
  ), role_codes AS (
    SELECT p.code
    FROM membership_row mr
    JOIN public.role_permissions rp
      ON rp.role_id = mr.role_id
    JOIN public.permissions p
      ON p.id = rp.permission_id
  ), denied_codes AS (
    SELECT p.code
    FROM membership_row mr
    JOIN public.user_permissions up
      ON up.user_id = mr.user_id
     AND up.gym_id = mr.gym_id
     AND up.effect = 'deny'
    JOIN public.permissions p
      ON p.id = up.permission_id
  ), allowed_codes AS (
    SELECT p.code
    FROM membership_row mr
    JOIN public.user_permissions up
      ON up.user_id = mr.user_id
     AND up.gym_id = mr.gym_id
     AND up.effect = 'allow'
    JOIN public.permissions p
      ON p.id = up.permission_id
  )
  SELECT COALESCE(
    ARRAY(
      SELECT DISTINCT code
      FROM (
        SELECT code FROM role_codes
        UNION
        SELECT code FROM allowed_codes
      ) merged
      WHERE code NOT IN (SELECT code FROM denied_codes)
      ORDER BY code
    ),
    ARRAY[]::text[]
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.permission_codes_for_membership(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.permission_codes_for_membership(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- DB-44 — sync_legacy_user_membership_projection: self, or a manager of the
-- target's gym (direct checks only — same recursion note as above).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sync_legacy_user_membership_projection(
  p_user_id uuid
)
RETURNS public.users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_membership record;
  v_profile public.users%ROWTYPE;
BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid()
     AND NOT EXISTS (
       SELECT 1
       FROM public.gym_memberships gm
       WHERE gm.user_id = p_user_id
         AND gm.status IN ('accepted', 'active')
         AND (
           public.caller_manages_gym_direct(gm.gym_id)
           OR public.caller_holds_permission_in_gym('manage_staff', gm.gym_id)
         )
     ) THEN
    RAISE EXCEPTION 'Not allowed to sync this user.';
  END IF;

  SELECT
    gm.id AS membership_id,
    gm.gym_id,
    r.code AS role_code
  INTO v_membership
  FROM public.gym_memberships gm
  JOIN public.roles r
    ON r.id = gm.role_id
  WHERE gm.user_id = p_user_id
    AND gm.status IN ('accepted', 'active')
  ORDER BY
    gm.is_default DESC,
    gm.last_active_at DESC NULLS LAST,
    gm.created_at ASC
  LIMIT 1;

  -- Body below is the 007 version verbatim (no early return: with no
  -- membership the UPDATE nulls the gym/default columns and keeps role).
  UPDATE public.users
  SET
    gym_id = v_membership.gym_id,
    default_gym_id = v_membership.gym_id,
    default_membership_id = v_membership.membership_id,
    role = COALESCE(v_membership.role_code, role),
    updated_at = now()
  WHERE id = p_user_id
  RETURNING * INTO v_profile;

  RETURN v_profile;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_legacy_user_membership_projection(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_legacy_user_membership_projection(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- DB-20 — get_staff_directory: no invite_token / national_id anymore.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_staff_directory(p_gym_id uuid)
RETURNS TABLE (
  staff_profile_id uuid,
  gym_id uuid,
  user_id uuid,
  profile_membership_id uuid,
  job_title text,
  department text,
  employment_type text,
  hire_date date,
  work_schedule jsonb,
  emergency_contact_name text,
  emergency_contact_phone text,
  notes text,
  avatar_storage_bucket text,
  avatar_storage_path text,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  name text,
  email text,
  phone text,
  avatar_url text,
  membership_id uuid,
  status text,
  invitation_status text,
  invite_email text,
  invited_name text,
  invited_phone text,
  invited_at timestamptz,
  role_name text,
  role_code text,
  portal text,
  permissions text[]
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    sp.id AS staff_profile_id,
    gm.gym_id,
    gm.user_id,
    sp.membership_id AS profile_membership_id,
    COALESCE(sp.job_title, NULLIF(BTRIM(gm.metadata->>'job_title'), '')) AS job_title,
    COALESCE(sp.department, NULLIF(BTRIM(gm.metadata->>'department'), '')) AS department,
    COALESCE(
      sp.employment_type,
      CASE
        WHEN NULLIF(BTRIM(gm.metadata->>'employment_type'), '') IN ('full_time', 'part_time', 'freelance', 'intern')
          THEN NULLIF(BTRIM(gm.metadata->>'employment_type'), '')
        ELSE 'full_time'
      END
    ) AS employment_type,
    COALESCE(
      sp.hire_date,
      CASE
        WHEN NULLIF(BTRIM(gm.metadata->>'hire_date'), '') ~ '^\d{4}-\d{2}-\d{2}$'
          THEN (gm.metadata->>'hire_date')::date
        ELSE NULL
      END
    ) AS hire_date,
    COALESCE(
      sp.work_schedule,
      CASE
        WHEN jsonb_typeof(gm.metadata->'work_schedule') = 'object' THEN gm.metadata->'work_schedule'
        ELSE '{}'::jsonb
      END
    ) AS work_schedule,
    sp.emergency_contact_name,
    sp.emergency_contact_phone,
    CASE WHEN public.has_permission('manage_staff', p_gym_id) THEN sp.notes ELSE NULL END AS notes,
    sp.avatar_storage_bucket,
    sp.avatar_storage_path,
    COALESCE(sp.is_active, gm.status IN ('pending', 'accepted', 'active')) AS is_active,
    sp.created_at,
    sp.updated_at,
    COALESCE(u.name, gm.invited_name, split_part(gm.invite_email::text, '@', 1), 'Pending user') AS name,
    COALESCE(u.email, gm.invite_email::text) AS email,
    COALESCE(u.phone, gm.invited_phone) AS phone,
    u.avatar_url,
    gm.id AS membership_id,
    gm.status,
    gm.invitation_status,
    gm.invite_email::text AS invite_email,
    gm.invited_name,
    gm.invited_phone,
    gm.invited_at,
    r.name AS role_name,
    r.code AS role_code,
    r.portal,
    public.permission_codes_for_membership(gm.id) AS permissions
  FROM public.gym_memberships gm
  JOIN public.roles r
    ON r.id = gm.role_id
  LEFT JOIN public.users u
    ON u.id = gm.user_id
  LEFT JOIN LATERAL (
    SELECT sp_row.*
    FROM public.staff_profiles sp_row
    WHERE sp_row.gym_id = gm.gym_id
      AND (
        (gm.user_id IS NOT NULL AND sp_row.user_id = gm.user_id)
        OR sp_row.membership_id = gm.id
      )
    ORDER BY CASE WHEN gm.user_id IS NOT NULL AND sp_row.user_id = gm.user_id THEN 0 ELSE 1 END
    LIMIT 1
  ) sp ON true
  WHERE gm.gym_id = p_gym_id
    AND gm.status <> 'revoked'
    AND (
      public.manages_gym(p_gym_id)
      OR public.has_permission('view_staff_profiles', p_gym_id)
      OR public.has_permission('edit_staff_profiles', p_gym_id)
      OR public.has_permission('manage_staff', p_gym_id)
    )
  ORDER BY
    COALESCE(NULLIF(BTRIM(COALESCE(sp.department, gm.metadata->>'department')), ''), 'zzzz'),
    COALESCE(NULLIF(BTRIM(COALESCE(sp.job_title, gm.metadata->>'job_title')), ''), 'zzzz'),
    COALESCE(u.name, gm.invited_name, gm.invite_email::text);
$$;

-- DB-20 — audited path for the two sensitive fields. Requires manage_staff
-- and writes one audit row per call. No frontend caller exists yet.
CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  gym_id uuid REFERENCES public.gyms(id) ON DELETE CASCADE,
  action text NOT NULL,
  target_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  target_membership_id uuid REFERENCES public.gym_memberships(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_audit_log_select ON public.admin_audit_log;
CREATE POLICY admin_audit_log_select ON public.admin_audit_log
  FOR SELECT
  USING (public.manages_gym(gym_id));

REVOKE ALL ON TABLE public.admin_audit_log FROM PUBLIC;
GRANT SELECT ON public.admin_audit_log TO authenticated;

CREATE OR REPLACE FUNCTION public.get_staff_directory_sensitive(p_gym_id uuid)
RETURNS TABLE (
  membership_id uuid,
  user_id uuid,
  invite_token text,
  national_id text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_permission('manage_staff', p_gym_id) THEN
    RAISE EXCEPTION 'You do not have permission to view sensitive staff data for this gym.';
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, gym_id, action)
  VALUES (auth.uid(), p_gym_id, 'staff_directory_sensitive_read');

  RETURN QUERY
  SELECT
    gm.id AS membership_id,
    gm.user_id,
    gm.invite_token,
    sp.national_id
  FROM public.gym_memberships gm
  LEFT JOIN LATERAL (
    SELECT sp_row.national_id
    FROM public.staff_profiles sp_row
    WHERE sp_row.gym_id = gm.gym_id
      AND (
        (gm.user_id IS NOT NULL AND sp_row.user_id = gm.user_id)
        OR sp_row.membership_id = gm.id
      )
    ORDER BY CASE WHEN gm.user_id IS NOT NULL AND sp_row.user_id = gm.user_id THEN 0 ELSE 1 END
    LIMIT 1
  ) sp ON true
  WHERE gm.gym_id = p_gym_id
    AND gm.status <> 'revoked'
  ORDER BY gm.created_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_directory_sensitive(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- DB-21 — list_gym_member_directory: staff only (view_clients holders).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.list_gym_member_directory(
  p_gym_id uuid
)
RETURNS TABLE (
  membership_id uuid,
  gym_id uuid,
  user_id uuid,
  name text,
  email text,
  phone text,
  role_id uuid,
  role_code text,
  role_name text,
  portal text,
  status text,
  invitation_status text,
  permissions text[],
  avatar_storage_bucket text,
  avatar_storage_path text,
  invite_email text,
  invited_at timestamptz,
  last_active_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    gm.id AS membership_id,
    gm.gym_id,
    gm.user_id,
    COALESCE(u.name, gm.invited_name, split_part(gm.invite_email::text, '@', 1), 'Pending user') AS name,
    COALESCE(u.email, gm.invite_email::text) AS email,
    COALESCE(u.phone, gm.invited_phone) AS phone,
    r.id AS role_id,
    r.code AS role_code,
    r.name AS role_name,
    r.portal,
    gm.status,
    gm.invitation_status,
    public.permission_codes_for_membership(gm.id) AS permissions,
    u.avatar_storage_bucket,
    u.avatar_storage_path,
    gm.invite_email::text,
    gm.invited_at,
    gm.last_active_at
  FROM public.gym_memberships gm
  JOIN public.roles r
    ON r.id = gm.role_id
  LEFT JOIN public.users u
    ON u.id = gm.user_id
  WHERE gm.gym_id = p_gym_id
    AND (
      public.caller_manages_gym_direct(p_gym_id)
      OR public.caller_holds_permission_in_gym('view_clients', p_gym_id)
    )
  ORDER BY
    CASE gm.status WHEN 'active' THEN 0 WHEN 'pending' THEN 1 WHEN 'accepted' THEN 2 ELSE 3 END,
    r.portal,
    COALESCE(u.name, gm.invited_name, gm.invite_email::text);
$$;

-- ----------------------------------------------------------------------------
-- DB-55 — gate_sessions readable by managers; manager-only revoke RPC.
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS gate_sessions_select ON public.gate_sessions;
CREATE POLICY gate_sessions_select ON public.gate_sessions
  FOR SELECT
  USING (
    client_id = auth.uid()
    OR public.manages_gym(gym_id)
  );

CREATE OR REPLACE FUNCTION public.revoke_gate_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gym_id uuid;
BEGIN
  SELECT gym_id INTO v_gym_id
  FROM public.gate_sessions
  WHERE id = p_session_id;

  IF v_gym_id IS NULL THEN
    RAISE EXCEPTION 'Session not found.';
  END IF;

  IF NOT public.manages_gym(v_gym_id) THEN
    RAISE EXCEPTION 'You do not manage this gym.';
  END IF;

  UPDATE public.gate_sessions
  SET used = true,
      used_at = now()
  WHERE id = p_session_id;

  RETURN jsonb_build_object('session_id', p_session_id, 'status', 'revoked');
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_gate_session(uuid) TO authenticated;
