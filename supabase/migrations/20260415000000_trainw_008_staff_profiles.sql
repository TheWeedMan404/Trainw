CREATE TABLE IF NOT EXISTS public.staff_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  membership_id uuid REFERENCES public.gym_memberships(id) ON DELETE SET NULL,
  job_title text,
  department text,
  employment_type text NOT NULL DEFAULT 'full_time' CHECK (employment_type IN ('full_time', 'part_time', 'freelance', 'intern')),
  hire_date date,
  work_schedule jsonb NOT NULL DEFAULT '{}'::jsonb,
  emergency_contact_name text,
  emergency_contact_phone text,
  national_id text,
  notes text,
  avatar_storage_bucket text,
  avatar_storage_path text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(gym_id, user_id)
);

ALTER TABLE public.staff_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS staff_profiles_select ON public.staff_profiles;
DROP POLICY IF EXISTS staff_profiles_insert ON public.staff_profiles;
DROP POLICY IF EXISTS staff_profiles_update ON public.staff_profiles;
DROP POLICY IF EXISTS staff_profiles_delete ON public.staff_profiles;

CREATE POLICY staff_profiles_select ON public.staff_profiles
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR public.manages_gym(gym_id)
  );

CREATE POLICY staff_profiles_insert ON public.staff_profiles
  FOR INSERT
  WITH CHECK (
    public.has_permission('manage_staff', gym_id)
  );

CREATE POLICY staff_profiles_update ON public.staff_profiles
  FOR UPDATE
  USING (
    public.has_permission('manage_staff', gym_id)
    OR user_id = auth.uid()
  )
  WITH CHECK (
    public.has_permission('manage_staff', gym_id)
    OR user_id = auth.uid()
  );

CREATE POLICY staff_profiles_delete ON public.staff_profiles
  FOR DELETE
  USING (
    public.manages_gym(gym_id)
  );

DROP TRIGGER IF EXISTS set_staff_profiles_updated_at ON public.staff_profiles;
CREATE TRIGGER set_staff_profiles_updated_at
BEFORE UPDATE ON public.staff_profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

INSERT INTO public.permissions (code, name, description, category)
VALUES
  ('view_staff_profiles', 'View staff profiles', 'Read staff member details and schedules.', 'members'),
  ('edit_staff_profiles', 'Edit staff profiles', 'Update staff job info, schedule, and notes.', 'members'),
  ('manage_access_control', 'Manage access control', 'Configure turnstile devices and sync credentials.', 'operations'),
  ('view_access_logs', 'View access logs', 'Read gate access history and attendance logs.', 'operations')
ON CONFLICT (code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

CREATE OR REPLACE FUNCTION public.ensure_gym_default_roles(
  p_gym_id uuid,
  p_created_by uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_id uuid;
BEGIN
  INSERT INTO public.roles (gym_id, code, name, description, portal, is_system, is_default, created_by)
  VALUES
    (p_gym_id, 'gym_owner', 'Gym Owner', 'Full tenant administration access.', 'admin', true, true, p_created_by),
    (p_gym_id, 'gym_admin', 'Gym Admin', 'Operational administration for a tenant.', 'admin', true, false, p_created_by),
    (p_gym_id, 'staff', 'Staff', 'Read-only or operational front-desk staff role.', 'admin', true, false, p_created_by),
    (p_gym_id, 'coach', 'Coach', 'Coach workspace access.', 'coach', true, false, p_created_by),
    (p_gym_id, 'client', 'Client', 'Client workspace access.', 'client', true, false, p_created_by)
  ON CONFLICT (gym_id, code) DO UPDATE
  SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    portal = EXCLUDED.portal,
    is_system = EXCLUDED.is_system,
    updated_at = now();

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'gym_owner';
  PERFORM public.ensure_role_permission_codes(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'edit_clients', 'delete_clients',
    'view_coaches', 'edit_coaches', 'manage_sessions', 'manage_bookings',
    'manage_payments', 'view_analytics', 'manage_staff', 'manage_roles',
    'manage_branding', 'manage_messages', 'manage_checkins', 'manage_classes',
    'manage_media', 'self_manage_profile', 'view_staff_profiles',
    'edit_staff_profiles', 'manage_access_control', 'view_access_logs'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'gym_admin';
  PERFORM public.ensure_role_permission_codes(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'edit_clients', 'delete_clients',
    'view_coaches', 'edit_coaches', 'manage_sessions', 'manage_bookings',
    'manage_payments', 'view_analytics', 'manage_staff', 'manage_branding',
    'manage_messages', 'manage_checkins', 'manage_classes', 'manage_media',
    'self_manage_profile', 'view_staff_profiles', 'edit_staff_profiles',
    'manage_access_control', 'view_access_logs'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'staff';
  PERFORM public.ensure_role_permission_codes(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'view_coaches', 'manage_bookings',
    'manage_messages', 'manage_checkins', 'manage_classes', 'self_manage_profile',
    'view_staff_profiles'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'coach';
  PERFORM public.ensure_role_permission_codes(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'edit_clients', 'manage_sessions',
    'manage_bookings', 'manage_messages', 'manage_media', 'self_manage_profile'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'client';
  PERFORM public.ensure_role_permission_codes(v_role_id, ARRAY[
    'view_dashboard', 'manage_bookings', 'manage_messages', 'manage_media',
    'self_manage_profile'
  ]);
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_staff_profile(
  p_gym_id uuid,
  p_user_id uuid,
  p_job_title text DEFAULT NULL,
  p_department text DEFAULT NULL,
  p_employment_type text DEFAULT 'full_time',
  p_hire_date date DEFAULT NULL,
  p_work_schedule jsonb DEFAULT '{}'::jsonb,
  p_emergency_contact_name text DEFAULT NULL,
  p_emergency_contact_phone text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id uuid;
  v_membership_id uuid;
  v_can_manage boolean := public.has_permission('manage_staff', p_gym_id);
  v_can_edit boolean := public.has_permission('edit_staff_profiles', p_gym_id);
  v_employment_type text := COALESCE(NULLIF(BTRIM(p_employment_type), ''), 'full_time');
  v_work_schedule jsonb := COALESCE(p_work_schedule, '{}'::jsonb);
BEGIN
  IF p_gym_id IS NULL OR p_user_id IS NULL THEN
    RAISE EXCEPTION 'Gym and user are required.';
  END IF;

  IF NOT (v_can_manage OR v_can_edit OR p_user_id = auth.uid()) THEN
    RAISE EXCEPTION 'You do not have permission to update this staff profile.';
  END IF;

  IF v_employment_type NOT IN ('full_time', 'part_time', 'freelance', 'intern') THEN
    RAISE EXCEPTION 'Employment type is invalid.';
  END IF;

  IF jsonb_typeof(v_work_schedule) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Work schedule must be a JSON object.';
  END IF;

  SELECT gm.id
  INTO v_membership_id
  FROM public.gym_memberships gm
  WHERE gm.gym_id = p_gym_id
    AND gm.user_id = p_user_id
    AND gm.status IN ('pending', 'accepted', 'active')
  ORDER BY
    CASE gm.status WHEN 'active' THEN 0 WHEN 'accepted' THEN 1 WHEN 'pending' THEN 2 ELSE 3 END,
    gm.is_default DESC,
    gm.updated_at DESC
  LIMIT 1;

  IF v_membership_id IS NULL THEN
    RAISE EXCEPTION 'The selected user is not a member of this gym.';
  END IF;

  INSERT INTO public.staff_profiles (
    gym_id,
    user_id,
    membership_id,
    job_title,
    department,
    employment_type,
    hire_date,
    work_schedule,
    emergency_contact_name,
    emergency_contact_phone,
    notes
  )
  VALUES (
    p_gym_id,
    p_user_id,
    v_membership_id,
    NULLIF(BTRIM(p_job_title), ''),
    NULLIF(BTRIM(p_department), ''),
    v_employment_type,
    p_hire_date,
    v_work_schedule,
    NULLIF(BTRIM(p_emergency_contact_name), ''),
    NULLIF(BTRIM(p_emergency_contact_phone), ''),
    CASE WHEN v_can_manage THEN NULLIF(BTRIM(p_notes), '') ELSE NULL END
  )
  ON CONFLICT (gym_id, user_id) DO UPDATE
  SET
    membership_id = EXCLUDED.membership_id,
    job_title = EXCLUDED.job_title,
    department = EXCLUDED.department,
    employment_type = EXCLUDED.employment_type,
    hire_date = EXCLUDED.hire_date,
    work_schedule = EXCLUDED.work_schedule,
    emergency_contact_name = EXCLUDED.emergency_contact_name,
    emergency_contact_phone = EXCLUDED.emergency_contact_phone,
    notes = CASE WHEN v_can_manage THEN EXCLUDED.notes ELSE public.staff_profiles.notes END,
    updated_at = now()
  RETURNING id INTO v_profile_id;

  RETURN v_profile_id;
END;
$$;

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
  national_id text,
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
  invite_token text,
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
    sp.national_id,
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
    gm.invite_token,
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

GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff_profiles TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_staff_profile(uuid, uuid, text, text, text, date, jsonb, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_staff_directory(uuid) TO authenticated;

SELECT public.ensure_gym_default_roles(g.id, g.manager_id)
FROM public.gyms g;
