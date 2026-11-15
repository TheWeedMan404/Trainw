-- ============================================================================
-- Phase 1 — P1-10 (DB-16, DB-15)
-- Audit: trainw-security-audit-2026-11-14.md
--
-- DB-16: manages_gym() returned true for a holder of manage_branding, so
-- a user granted only the branding permission (to upload a logo) passed
-- every manages_gym policy: payments, sessions, check-in deletions,
-- member credentials, gate logs, devices. manage_branding is removed from
-- manages_gym; branding-only users now need an explicit permission for
-- anything else. The 004 gyms_update policy (restored in migration
-- 20261114000000) and every other manages_gym policy inherit this fix.
--
-- DB-15: user_permissions_manage_v17 let anyone with manage_roles OR
-- manage_staff write user_permissions rows for any user in the gym,
-- including themselves — so a manage_staff holder could self-grant
-- manage_roles, manage_payments and every other permission. Self-targeted
-- writes are now forbidden in both USING and WITH CHECK: a grant must
-- target a different user. (No app flow or RPC writes user_permissions
-- rows for the caller themselves — verified by grep over the repo — so
-- this does not break any legitimate flow.)
--
-- VERIFICATION (no live DB was available when this was written):
--   A branding-only user attempts to insert a payment -> must fail.
--   A manage_staff holder attempts to INSERT a user_permissions row with
--   user_id = their own id -> must fail. The same holder granting
--   manage_roles to another user -> must still work.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DB-16 — manages_gym: admin portal OR manage_staff only.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.manages_gym(p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    public.user_has_membership(p_gym_id)
    AND (
      public.get_my_portal() = 'admin'
      OR public.has_permission('manage_staff', p_gym_id)
    ),
    false
  );
$$;

-- ----------------------------------------------------------------------------
-- DB-15 — forbid self-targeted user_permissions writes.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS user_permissions_manage_v17 ON public.user_permissions;
CREATE POLICY user_permissions_manage_v17 ON public.user_permissions
  FOR ALL
  USING (
    user_id <> auth.uid()
    AND (
      public.has_permission('manage_roles', gym_id)
      OR public.has_permission('manage_staff', gym_id)
    )
  )
  WITH CHECK (
    user_id <> auth.uid()
    AND (
      public.has_permission('manage_roles', gym_id)
      OR public.has_permission('manage_staff', gym_id)
    )
  );
