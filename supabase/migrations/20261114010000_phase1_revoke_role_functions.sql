-- ============================================================================
-- Phase 1 — P1-4 (DB-03, DB-04)
-- Audit: trainw-security-audit-2026-11-14.md
--
-- The two role-management functions were SECURITY DEFINER with no
-- authorisation check and, for ensure_gym_default_roles, an explicit
-- GRANT EXECUTE TO authenticated (ensure_role_permission_codes relied on
-- the default PUBLIC EXECUTE). Anyone holding the anon key could call
-- them via PostgREST and wipe/rewrite any gym's roles and permissions.
--
-- This migration:
--   1. Revokes EXECUTE from PUBLIC and from authenticated on both
--      functions, so they are no longer reachable as RPCs. Internal
--      callers are unaffected: SECURITY DEFINER functions run as the
--      function owner, and migrations run as the table owner.
--   2. Replaces both functions with versions that check the caller:
--      allowed when there is no authenticated caller (migration / owner
--      context, auth.uid() IS NULL), when the caller is the gym's
--      manager (gyms.manager_id = auth.uid()), or when the caller holds
--      manage_roles for that gym. Anything else raises.
--   3. The ensure_gym_default_roles body below is the 012 version
--      (20260415000000_trainw_012_staff_profiles.sql:78), reproduced
--      verbatim apart from the added check — including its expanded
--      permission sets (view_staff_profiles, edit_staff_profiles,
--      manage_access_control, view_access_logs). The
--      ensure_role_permission_codes body is the 007 version, verbatim
--      apart from the added check.
--
-- Internal callers and why the check still lets them through:
--   * Migrations (007:1745, 012:378) call ensure_gym_default_roles as the
--     owner: auth.uid() IS NULL -> allowed.
--   * bootstrap_authenticated_user creates the gym with
--     manager_id = auth.uid() and then calls ensure_gym_default_roles:
--     the manager branch allows it (the membership does not exist yet at
--     that point, so a manage_roles-only check would have broken signup).
--   * save_role_definition already checks manage_roles before calling
--     ensure_role_permission_codes, and is SECURITY DEFINER.
--
-- VERIFICATION (no live DB was available when this was written):
--   As an authenticated non-admin user, SELECT both functions via the API
--   -> must fail with permission denied. Sign up as a new gym owner ->
--   must still work (bootstrap path). Deploy the migration to staging ->
--   the 007/012 backfill calls must still run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Remove RPC exposure.
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.ensure_role_permission_codes(uuid, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_role_permission_codes(uuid, text[]) FROM authenticated;
REVOKE ALL ON FUNCTION public.ensure_gym_default_roles(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_gym_default_roles(uuid, uuid) FROM authenticated;

-- ----------------------------------------------------------------------------
-- 2a. ensure_role_permission_codes — same body as 007, plus authorisation.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_role_permission_codes(
  p_role_id uuid,
  p_permission_codes text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gym_id uuid;
BEGIN
  SELECT gym_id INTO v_gym_id FROM public.roles WHERE id = p_role_id;
  IF v_gym_id IS NULL THEN
    RAISE EXCEPTION 'role not found: %', p_role_id;
  END IF;

  -- P1-4: only the gym's manager, a manage_roles holder for that gym, or a
  -- server-side/owner context (no authenticated caller) may rewrite a
  -- role's permissions.
  IF auth.uid() IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = v_gym_id AND g.manager_id = auth.uid()) THEN
      NULL; -- gym manager: allowed
    ELSIF public.has_permission('manage_roles', v_gym_id) THEN
      NULL; -- manage_roles holder: allowed
    ELSE
      RAISE EXCEPTION 'permission denied: manage_roles required for gym %', v_gym_id;
    END IF;
  END IF;

  DELETE FROM public.role_permissions
  WHERE role_id = p_role_id;

  INSERT INTO public.role_permissions (role_id, permission_id)
  SELECT
    p_role_id,
    p.id
  FROM public.permissions p
  WHERE p.code = ANY(COALESCE(p_permission_codes, ARRAY[]::text[]));
END;
$$;

-- ----------------------------------------------------------------------------
-- 2b. ensure_gym_default_roles — same body as 012, plus authorisation.
-- ----------------------------------------------------------------------------
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
  -- P1-4: same authorisation as ensure_role_permission_codes above.
  IF auth.uid() IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = p_gym_id AND g.manager_id = auth.uid()) THEN
      NULL; -- gym manager: allowed
    ELSIF public.has_permission('manage_roles', p_gym_id) THEN
      NULL; -- manage_roles holder: allowed
    ELSE
      RAISE EXCEPTION 'permission denied: manage_roles required for gym %', p_gym_id;
    END IF;
  END IF;

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
