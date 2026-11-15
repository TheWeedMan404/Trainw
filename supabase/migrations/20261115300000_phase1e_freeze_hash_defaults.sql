-- ============================================================================
-- Round 5 (DB-61 gap) — the RLS-helper freeze hash now covers DEFAULT
-- expressions.
--
-- The round-4 freeze (20261115210000) hashed signature, result type,
-- language, volatility, SECURITY DEFINER, proconfig, and the body
-- (prosrc) — but NOT proargdefaults, so a default-only change to a
-- frozen helper slipped past the tripwire. Seven frozen helpers carry
-- defaults (auth_user_email, client_membership_is_active,
-- current_membership, get_my_permissions, has_permission,
-- membership_is_active_for_access, user_has_membership).
--
-- This migration re-creates assert_rls_helpers_frozen() with
-- proargdefaults in the formula (the node-tree text of the default
-- expressions, NULL for helpers without defaults) and updates all 30
-- frozen hashes to the values the new formula computes on the chain as
-- applied. To change a helper deliberately from here on: edit its
-- definition, re-run the migration, and replace the hash below with
-- the new value from the assert's error message, after reviewing the
-- diff — same rule as before.
-- ============================================================================

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
      ('auth_user_email(p_user_id uuid)', 'e50929512b649deb65d4100772ae9d50'),
      ('caller_holds_permission_in_gym(p_permission_code text, p_gym_id uuid)', '0a98d2f8991347ffee19cfb2d75bfcb8'),
      ('caller_manages_gym_direct(p_gym_id uuid)', '548214050235afe38aa03f366c38d087'),
      ('can_manage_client_data(p_client_id uuid, p_gym_id uuid)', 'b9628033a90720ba7caca4471c496df8'),
      ('can_manage_sessions(p_gym_id uuid)', 'cc784e66524872890cc2594fae516f5a'),
      ('can_message_user(p_other_user_id uuid, p_gym_id uuid)', 'aeeff5685ae9ec8a178b34a8509b8f51'),
      ('can_read_workout_log(p_log_id uuid)', '61d7bdbf678e2cddba6db7a5619d4bf3'),
      ('can_read_workout_plan(p_plan_id uuid)', '638f3fca80dd91633ccfeb16ce177dfa'),
      ('can_view_user(p_user_id uuid)', 'c523d6491de8fc654dec9386597f9b7f'),
      ('can_write_workout_log(p_log_id uuid)', '8f43ec586d19f1b8ed103728d8d69946'),
      ('can_write_workout_plan(p_plan_id uuid)', '853ba4a0681c30db1c460fdcd69dc1ad'),
      ('client_membership_is_active(p_client_id uuid, p_reference_date date)', '05c6d96971481485f9439abe7e28aa49'),
      ('current_membership(p_requested_gym_id uuid)', '6864a54d8d486a9da1ebba87e6806dc0'),
      ('get_my_gym_id()', '563ac2bc9e08039f7a7fb157cf361920'),
      ('get_my_permissions(p_gym_id uuid)', '0f40f751f184c87dda8528693d5e0fb7'),
      ('get_my_portal()', 'b0048456919475f88c94eeffd6713d80'),
      ('get_my_role()', '6bfecce236eb1e55e7aa54031544efbc'),
      ('get_signup_role()', '1c17de7442863c8f913b128e3405ef7b'),
      ('has_permission(p_permission_code text, p_gym_id uuid)', '4a92fa4601a596bd91e1ee6ebd989920'),
      ('is_gym_manager()', '57efb2f641b6afad58d9eff51eee6537'),
      ('is_same_gym_user(p_user_id uuid)', '701032e5c2f09ace46321003ef054186'),
      ('lock_booking_key(p_key text)', 'cc956374bf0d5cb7b2712a00ba6eea2c'),
      ('manages_gym(p_gym_id uuid)', 'ad5cd1348375b0123704348239917807'),
      ('membership_is_active_for_access(p_client_id uuid, p_gym_id uuid, p_reference_date date)', '549565e242b785fad58db24c4ebfd4fa'),
      ('permission_codes_for_membership(p_membership_id uuid)', '15369a754ec06d830f92256bd1164710'),
      ('safe_uuid(p_value text)', 'd60ca72c6c8ca239e5b2b6d2b2a3017e'),
      ('storage_object_is_public(p_bucket text, p_path text)', 'fffd8c7ac98984651078c9a535c99a2c'),
      ('user_gym_id(p_user_id uuid)', 'beb4c62cc9cccc836885bc47c3578474'),
      ('user_has_membership(p_gym_id uuid, p_user_id uuid)', '2f9457cff0a2a3d57ddee37c1a98b102'),
      ('user_role(p_user_id uuid)', 'd7dd3e9544b7ac7f38dd5ccd44731f6f')
  ), actual AS (
    SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS signature,
           md5(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
             || '|' || pg_get_function_result(p.oid)
             || '|' || l.lanname
             || '|' || p.provolatile::text
             || '|' || p.prosecdef::text
             || '|' || COALESCE(array_to_string(p.proconfig, ','), '')
             || '|' || p.prosrc
             || '|' || COALESCE(p.proargdefaults::text, '')) AS definition_hash
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

-- The new formula must pass on the chain as applied.
SELECT public.assert_rls_helpers_frozen();

COMMENT ON FUNCTION public.assert_rls_helpers_frozen() IS
  'DB-61 freeze (round 5): hash covers DEFAULT expressions via proargdefaults.';
