-- ============================================================================
-- Round 4 (DB-61) — freeze the RLS helper functions.
--
-- The access helpers were redefined three times (002, 005, 007) with
-- different semantics — e.g. user_gym_id went from "legacy users.gym_id"
-- to a fallback chain to "default gym or membership", and can_view_user
-- went from role-restricted to any-same-gym-member. Which policy
-- behaviour is live depends entirely on migration order, and any
-- environment that missed 007 silently runs the older access model.
--
-- This migration re-creates the helpers verbatim as they stand after
-- the full chain (the frozen definitions), and adds
-- public.assert_rls_helpers_frozen(), which compares the md5 of each
-- helper's live definition against the frozen hash and raises on any
-- drift. From here on, changing a helper means a deliberate new
-- migration AND updating the frozen hash in the assert function.
--
-- Freeze set (30): every function the RLS policies call, plus their
-- transitive dependencies (computed from pg_policy + pg_proc on the
-- applied chain), plus the four access helpers the audit names or the
--
-- Phase 1h (2026-11-15): the 1g commit changed
-- membership_is_active_for_access's freeze clause (raw p_reference_date
-- -> COALESCE with gym_today) without updating this file's frozen hash
-- for it, so a fresh chain apply failed here. Hash recomputed from the
-- current body: 080cc52b8697f1dd16d6ec97a70ca127.
-- gate relies on (can_view_user, client_membership_is_active,
-- membership_is_active_for_access, lock_booking_key). Definitions are
-- ordered so a function is created after the functions it calls.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.caller_holds_permission_in_gym(p_permission_code text, p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.caller_manages_gym_direct(p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_signup_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
 SET row_security TO 'off'
AS $function$
  SELECT COALESCE(NULLIF(lower(BTRIM(raw_user_meta_data->>'role')), ''), NULLIF(lower(BTRIM(raw_app_meta_data->>'role')), ''))
  FROM auth.users
  WHERE id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.lock_booking_key(p_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(COALESCE(p_key, ''), 0));
END;
$function$;

CREATE OR REPLACE FUNCTION public.membership_is_active_for_access(p_client_id uuid, p_gym_id uuid, p_reference_date date DEFAULT CURRENT_DATE)
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
        OR cp.membership_start_date <= p_reference_date
      )
      AND (
        cp.membership_end_date IS NULL
        OR cp.membership_end_date >= p_reference_date
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

CREATE OR REPLACE FUNCTION public.permission_codes_for_membership(p_membership_id uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.safe_uuid(p_value text)
 RETURNS uuid
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
  IF p_value IS NULL OR BTRIM(p_value) = '' THEN
    RETURN NULL;
  END IF;
  RETURN p_value::uuid;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.storage_object_is_public(p_bucket text, p_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.media_assets ma
    WHERE ma.storage_bucket = p_bucket
      AND ma.storage_path = p_path
      AND ma.is_public = true
  ) OR EXISTS (
    SELECT 1 FROM public.milestone_photos mp
    WHERE mp.storage_bucket = p_bucket
      AND mp.storage_path = p_path
      AND mp.is_public = true
  );
$function$;

CREATE OR REPLACE FUNCTION public.user_gym_id(p_user_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    u.default_gym_id,
    (
      SELECT gm.gym_id
      FROM public.gym_memberships gm
      WHERE gm.user_id = p_user_id
        AND gm.status IN ('accepted', 'active')
      ORDER BY gm.is_default DESC, gm.last_active_at DESC NULLS LAST, gm.created_at ASC
      LIMIT 1
    )
  )
  FROM public.users u
  WHERE u.id = p_user_id;
$function$;

CREATE OR REPLACE FUNCTION public.user_has_membership(p_gym_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.gym_memberships gm
    WHERE gm.user_id = p_user_id
      AND gm.gym_id = p_gym_id
      AND gm.status IN ('accepted', 'active')
  );
$function$;

CREATE OR REPLACE FUNCTION public.user_role(p_user_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    u.role,
    (
      SELECT r.code
      FROM public.gym_memberships gm
      JOIN public.roles r
        ON r.id = gm.role_id
      WHERE gm.user_id = p_user_id
        AND gm.status IN ('accepted', 'active')
      ORDER BY gm.is_default DESC, gm.last_active_at DESC NULLS LAST, gm.created_at ASC
      LIMIT 1
    )
  )
  FROM public.users u
  WHERE u.id = p_user_id;
$function$;

CREATE OR REPLACE FUNCTION public.auth_user_email(p_user_id uuid DEFAULT auth.uid())
 RETURNS citext
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.client_membership_is_active(p_client_id uuid, p_reference_date date DEFAULT CURRENT_DATE)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.client_profiles cp
    WHERE cp.user_id = p_client_id
      AND public.membership_is_active_for_access(p_client_id, cp.gym_id, p_reference_date)
  );
$function$;

CREATE OR REPLACE FUNCTION public.current_membership(p_requested_gym_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(membership_id uuid, gym_id uuid, role_id uuid, role_code text, role_name text, portal text, status text, is_default boolean, last_active_at timestamp with time zone, permissions text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH preferred_gym AS (
    SELECT COALESCE(
      p_requested_gym_id,
      (SELECT u.default_gym_id FROM public.users u WHERE u.id = auth.uid())
    ) AS gym_id
  ),
  ranked AS (
    SELECT
      gm.id AS membership_id,
      gm.gym_id,
      gm.role_id,
      r.code AS role_code,
      r.name AS role_name,
      r.portal,
      gm.status,
      gm.is_default,
      gm.last_active_at,
      public.permission_codes_for_membership(gm.id) AS permissions,
      ROW_NUMBER() OVER (
        ORDER BY
          CASE WHEN gm.gym_id = (SELECT gym_id FROM preferred_gym) THEN 0 ELSE 1 END,
          CASE gm.status WHEN 'active' THEN 0 WHEN 'accepted' THEN 1 ELSE 2 END,
          gm.is_default DESC,
          CASE r.code WHEN 'gym_owner' THEN 0 WHEN 'gym_admin' THEN 1 WHEN 'staff' THEN 2 WHEN 'coach' THEN 3 ELSE 4 END,
          gm.last_active_at DESC NULLS LAST,
          gm.created_at ASC
      ) AS rn
    FROM public.gym_memberships gm
    JOIN public.roles r
      ON r.id = gm.role_id
    WHERE gm.user_id = auth.uid()
      AND gm.status IN ('accepted', 'active')
      AND (p_requested_gym_id IS NULL OR gm.gym_id = p_requested_gym_id)
  )
  SELECT
    membership_id,
    gym_id,
    role_id,
    role_code,
    role_name,
    portal,
    status,
    is_default,
    last_active_at,
    permissions
  FROM ranked
  WHERE rn = 1;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_gym_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT gym_id
  FROM public.current_membership(NULL)
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_permissions(p_gym_id uuid DEFAULT NULL::uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT permissions
  FROM public.current_membership(p_gym_id)
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_portal()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT portal
  FROM public.current_membership(NULL)
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT role_code
  FROM public.current_membership(NULL)
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.has_permission(p_permission_code text, p_gym_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(p_permission_code = ANY(public.get_my_permissions(p_gym_id)), false);
$function$;

CREATE OR REPLACE FUNCTION public.is_gym_manager()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(public.get_my_portal() = 'admin', false);
$function$;

CREATE OR REPLACE FUNCTION public.is_same_gym_user(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.gym_memberships target_membership
    WHERE target_membership.user_id = p_user_id
      AND target_membership.status IN ('accepted', 'active')
      AND public.user_has_membership(target_membership.gym_id)
  );
$function$;

CREATE OR REPLACE FUNCTION public.manages_gym(p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    public.user_has_membership(p_gym_id)
    AND (
      public.get_my_portal() = 'admin'
      OR public.has_permission('manage_staff', p_gym_id)
    ),
    false
  );
$function$;

CREATE OR REPLACE FUNCTION public.can_manage_client_data(p_client_id uuid, p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN false
    WHEN p_client_id IS NULL OR p_gym_id IS NULL THEN false
    WHEN NOT public.user_has_membership(p_gym_id) THEN false
    WHEN public.get_my_portal() = 'admin' THEN true
    WHEN public.get_my_portal() = 'coach' THEN EXISTS (
      SELECT 1
      FROM public.coach_client_assignments cca
      WHERE cca.coach_id = auth.uid()
        AND cca.client_id = p_client_id
        AND cca.gym_id = p_gym_id
        AND cca.is_active = true
    )
    ELSE false
  END;
$function$;

CREATE OR REPLACE FUNCTION public.can_manage_sessions(p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    public.user_has_membership(p_gym_id)
    AND (
      public.manages_gym(p_gym_id)
      OR public.has_permission('manage_sessions', p_gym_id)
    ),
    false
  );
$function$;

CREATE OR REPLACE FUNCTION public.can_message_user(p_other_user_id uuid, p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN false
    WHEN p_other_user_id IS NULL OR p_gym_id IS NULL THEN false
    WHEN NOT public.user_has_membership(p_gym_id) THEN false
    WHEN public.get_my_portal() = 'admin' THEN true
    WHEN public.get_my_portal() = 'coach' THEN EXISTS (
      SELECT 1
      FROM public.coach_client_assignments cca
      WHERE cca.coach_id = auth.uid()
        AND cca.client_id = p_other_user_id
        AND cca.gym_id = p_gym_id
        AND cca.is_active = true
    )
    WHEN public.get_my_portal() = 'client' THEN (
      EXISTS (
        SELECT 1
        FROM public.gym_memberships gm
        JOIN public.roles r
          ON r.id = gm.role_id
        WHERE gm.user_id = p_other_user_id
          AND gm.gym_id = p_gym_id
          AND gm.status IN ('accepted', 'active')
          AND r.portal IN ('admin', 'coach')
      )
    )
    ELSE false
  END;
$function$;

CREATE OR REPLACE FUNCTION public.can_read_workout_log(p_log_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.workout_logs wl
    WHERE wl.id = p_log_id
      AND (
        wl.client_id = auth.uid()
        OR public.can_manage_client_data(wl.client_id, wl.gym_id)
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.can_read_workout_plan(p_plan_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.workout_plans wp
    WHERE wp.id = p_plan_id
      AND (
        public.manages_gym(wp.gym_id)
        OR wp.created_by = auth.uid()
        OR wp.client_id = auth.uid()
        OR (wp.client_id IS NOT NULL AND public.can_manage_client_data(wp.client_id, wp.gym_id))
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.can_view_user(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = p_user_id
      AND (
        u.id = auth.uid()
        OR public.is_same_gym_user(p_user_id)
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.can_write_workout_log(p_log_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.workout_logs wl
    WHERE wl.id = p_log_id
      AND (
        wl.client_id = auth.uid()
        OR public.can_manage_client_data(wl.client_id, wl.gym_id)
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.can_write_workout_plan(p_plan_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.workout_plans wp
    WHERE wp.id = p_plan_id
      AND (
        public.manages_gym(wp.gym_id)
        OR wp.created_by = auth.uid()
        OR (
          public.get_my_role() = 'coach'
          AND wp.client_id IS NOT NULL
          AND public.can_manage_client_data(wp.client_id, wp.gym_id)
        )
      )
  );
$function$;

-- ----------------------------------------------------------------------------
-- Freeze assertion.
-- ----------------------------------------------------------------------------
-- The hash is over the stored catalog values (signature, result type,
-- language, volatility, SECURITY DEFINER, proconfig, and the function
-- body prosrc) — not over pg_get_functiondef output, whose rendering can
-- differ between Postgres versions. Any change to a frozen helper's
-- meaning, without updating this table, fails the migration and the
-- test suite. To change a helper deliberately: edit its definition
-- above, re-run the migration, and replace the hash below with the new
-- value from assert_rls_helpers_frozen()'s error message (it lists the
-- drifted signatures), after reviewing the diff.
CREATE OR REPLACE FUNCTION public.assert_rls_helpers_frozen()
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $freeze$
DECLARE
  v_bad text;
BEGIN
  WITH expected(signature, definition_hash) AS (
    VALUES
      ('auth_user_email(p_user_id uuid)', '68813f886337e6bd2e0f1e3e71d27bfd'),
      ('caller_holds_permission_in_gym(p_permission_code text, p_gym_id uuid)', '2afec0f282864f769b6a5c725091d784'),
      ('caller_manages_gym_direct(p_gym_id uuid)', '2d2cc8caa77b341122a605a24c7dab66'),
      ('can_manage_client_data(p_client_id uuid, p_gym_id uuid)', '162814305a7fdc34b557e8e10a41cb7d'),
      ('can_manage_sessions(p_gym_id uuid)', '4ce5d3db59e75df7c9f5dbb53fede941'),
      ('can_message_user(p_other_user_id uuid, p_gym_id uuid)', 'ccc71d2ad5793763bf324fa22ff8fb97'),
      ('can_read_workout_log(p_log_id uuid)', 'a41a103e3be5d780c4c7abd7979ae803'),
      ('can_read_workout_plan(p_plan_id uuid)', '4bea08bfea5b51eb06b292831ba682bc'),
      ('can_view_user(p_user_id uuid)', 'f8dbcbcbb26cf6744e57c4d6bc1659ec'),
      ('can_write_workout_log(p_log_id uuid)', '41c54b06c04a5990abbff3c410784136'),
      ('can_write_workout_plan(p_plan_id uuid)', '1adf43d4b6c044aad740d0bec63db642'),
      ('client_membership_is_active(p_client_id uuid, p_reference_date date)', 'df041e00293c724bdcc91b04fffa7096'),
      ('current_membership(p_requested_gym_id uuid)', '83be8d645898a6780d7beff3b90d97db'),
      ('get_my_gym_id()', '0a82c7547a021a4c51c7c4bae88a0ac4'),
      ('get_my_permissions(p_gym_id uuid)', '0f33fbd61e2477469c6ca8969ec64462'),
      ('get_my_portal()', '2673176cfa8fdf097b01b6a8cee329a7'),
      ('get_my_role()', '19ab56717fe1ff10600c1b97502b7dc6'),
      ('get_signup_role()', '38dd3bd6f7d2204c1b0c33e438a49622'),
      ('has_permission(p_permission_code text, p_gym_id uuid)', 'efad206bf5b2c86873e2348f06cd8dae'),
      ('is_gym_manager()', '88054510fd5cfad7222b4eb9b46ddd6f'),
      ('is_same_gym_user(p_user_id uuid)', '61dbb3359536ba80c501284444e42385'),
      ('lock_booking_key(p_key text)', 'a0ec8b10f159f279d43aa05163710ccd'),
      ('manages_gym(p_gym_id uuid)', '3d67f24e1a9ad1d2a21852e2dece2911'),
      ('membership_is_active_for_access(p_client_id uuid, p_gym_id uuid, p_reference_date date)', '080cc52b8697f1dd16d6ec97a70ca127'),
      ('permission_codes_for_membership(p_membership_id uuid)', 'b4307205e32ac9d478656510daf95349'),
      ('safe_uuid(p_value text)', 'ad93f96932948e740ac01cf02c010ea2'),
      ('storage_object_is_public(p_bucket text, p_path text)', 'b92dad2a3ee8cce1ad4ac22e05566231'),
      ('user_gym_id(p_user_id uuid)', '7f1fdc9a845a1a86adb86ac3d315ac2e'),
      ('user_has_membership(p_gym_id uuid, p_user_id uuid)', '94ac0afc764b1820e42da1ed2cdaab1d'),
      ('user_role(p_user_id uuid)', 'c1e6720d1dffad16835c292af0d723d9')
  ), actual AS (
    SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS signature,
           md5(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
             || '|' || pg_get_function_result(p.oid)
             || '|' || l.lanname
             || '|' || p.provolatile::text
             || '|' || p.prosecdef::text
             || '|' || COALESCE(array_to_string(p.proconfig, ','), '')
             || '|' || p.prosrc) AS definition_hash
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname = 'public'
  )
  SELECT string_agg(e.signature, ', ' ORDER BY e.signature)
  INTO v_bad
  FROM expected e
  LEFT JOIN actual a ON a.signature = e.signature
  WHERE a.signature IS NULL OR a.definition_hash <> e.definition_hash;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'RLS helper definitions drifted from the DB-61 freeze: %', v_bad;
  END IF;
END;
$freeze$;

SELECT public.assert_rls_helpers_frozen();

COMMENT ON FUNCTION public.assert_rls_helpers_frozen() IS
  'DB-61: fails when any frozen RLS helper definition differs from the hash recorded in this migration. Update the hash deliberately (with a reviewed definition change) — never to silence the check.';
