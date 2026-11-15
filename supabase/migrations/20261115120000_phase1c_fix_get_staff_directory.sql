-- ============================================================================
-- TRAINW PHASE 1C — FIX B5 get_staff_directory RETURN-TYPE CHANGE
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- WHY THIS FILE EXISTS (found by local verification 2026-11-15, real
-- PostgreSQL 16): migration 20261115050000_phase1b_directories.sql (B5)
-- FAILS on a fresh apply with:
--   ERROR: cannot change return type of existing function
-- at its CREATE OR REPLACE FUNCTION public.get_staff_directory(p_gym_id).
-- 012 defined get_staff_directory() WITH national_id + invite_token
-- columns; B5 removes both (DB-20) — but CREATE OR REPLACE cannot change
-- a function's return type, so the statement fails and ON_ERROR_STOP
-- aborts the rest of B5 (admin_audit_log, get_staff_directory_sensitive,
-- list_gym_member_directory, revoke_gate_session never apply).
-- The fix is DROP + CREATE. B5 itself is NOT edited (never edit existing
-- migrations); this file drops the old function, then re-applies B5's
-- get_staff_directory definition verbatim (B5 lines 315-436) followed by
-- the remainder of B5 (lines 437-614) that never applied.
-- ============================================================================

DROP FUNCTION IF EXISTS public.get_staff_directory(uuid);

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
