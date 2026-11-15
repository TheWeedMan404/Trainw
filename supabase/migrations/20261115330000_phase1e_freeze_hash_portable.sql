-- ============================================================================
-- Round 5 (DB-61 portability fix) — the RLS-helper freeze hash is now
-- reproducible on any fresh cluster.
--
-- The DB-61 formula (20261115300000) hashed proargdefaults::text — the
-- node-tree text of the default expressions. That text embeds the
-- callee's OID (e.g. `FUNCEXPR :funcid 16401` for the auth.uid()
-- defaults on auth_user_email and user_has_membership), and OIDs are
-- assigned in creation order, which differs between clusters: the
-- DB-61 assert passed on the cluster it was built on and fails on any
-- other fresh cluster (found by the rebuilt round-5 harness).
--
-- This migration re-creates assert_rls_helpers_frozen() hashing
-- pg_get_function_arguments(p.oid) instead — the signature WITH its
-- defaults deparsed as SQL text (e.g. `p_user_id uuid DEFAULT
-- auth.uid()`), which is stable across clusters — and updates all 30
-- frozen hashes to the values the new formula computes on the chain as
-- applied. A default-only change is still detected (the deparsed
-- defaults are part of the input), and the formula no longer depends
-- on any OID. To change a helper deliberately from here on: edit its
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
      ('auth_user_email(p_user_id uuid)', 'b712fec33892013c348816e2a60c9cf8'),
      ('caller_holds_permission_in_gym(p_permission_code text, p_gym_id uuid)', 'fe8f52fef48a0ee2438c1e0285975070'),
      ('caller_manages_gym_direct(p_gym_id uuid)', 'e30d4f4148d4a0e610086b7b1f994bc7'),
      ('can_manage_client_data(p_client_id uuid, p_gym_id uuid)', '9eb616dbda71dca6e4a1c8f536ac5ef9'),
      ('can_manage_sessions(p_gym_id uuid)', 'aef9cfafd79bce75667b7b27c817d217'),
      ('can_message_user(p_other_user_id uuid, p_gym_id uuid)', '60ac69aa26d6d8b2184013fa4a991be9'),
      ('can_read_workout_log(p_log_id uuid)', '9d4fb6d0d21b02bb0348b2149c2ab0a2'),
      ('can_read_workout_plan(p_plan_id uuid)', 'cb0f8d763c0da08f10a51df1ad23ac31'),
      ('can_view_user(p_user_id uuid)', '7db566926c32173f969eacb03f32e18d'),
      ('can_write_workout_log(p_log_id uuid)', '4c4e7cc9828956d78a9a4f681226fbf7'),
      ('can_write_workout_plan(p_plan_id uuid)', '91de82339a085136201f86589019fe4b'),
      ('client_membership_is_active(p_client_id uuid, p_reference_date date)', 'b4d773b50ed838ec8e6647d68973965d'),
      ('current_membership(p_requested_gym_id uuid)', 'ce22c7f482d81418ac6e529adde31e3f'),
      ('get_my_gym_id()', '563ac2bc9e08039f7a7fb157cf361920'),
      ('get_my_permissions(p_gym_id uuid)', 'bf5d63072c46f4ed12702e5c023f7751'),
      ('get_my_portal()', 'b0048456919475f88c94eeffd6713d80'),
      ('get_my_role()', '6bfecce236eb1e55e7aa54031544efbc'),
      ('get_signup_role()', '1c17de7442863c8f913b128e3405ef7b'),
      ('has_permission(p_permission_code text, p_gym_id uuid)', '020da71f2c552086a1c31ec170bae15b'),
      ('is_gym_manager()', '57efb2f641b6afad58d9eff51eee6537'),
      ('is_same_gym_user(p_user_id uuid)', 'e8b9e07504322b98eac5338a1900bcd1'),
      ('lock_booking_key(p_key text)', '1b57ece9e3c825e63b36f45156b17932'),
      ('manages_gym(p_gym_id uuid)', '8676e1319e130ead20fce0d5a031cc92'),
      ('membership_is_active_for_access(p_client_id uuid, p_gym_id uuid, p_reference_date date)', 'c90ab575fa0a984e2a269b4eaa7ba80c'),
      ('permission_codes_for_membership(p_membership_id uuid)', '5b42f83662c766785b184c3908788c88'),
      ('safe_uuid(p_value text)', '61a80c4c69579d049678f74fdf363ef1'),
      ('storage_object_is_public(p_bucket text, p_path text)', '90ac3d12c8dd7c2bb4c5c3abb32695a9'),
      ('user_gym_id(p_user_id uuid)', 'a4aaa05e8b85bd2861c1227f44e4b96c'),
      ('user_has_membership(p_gym_id uuid, p_user_id uuid)', '11460628b527af9223efe6bdabbf05e1'),
      ('user_role(p_user_id uuid)', '57e655fcc93a44faa3b2175a9820d033')
  ), actual AS (
    SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS signature,
           md5(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
             || '|' || pg_get_function_result(p.oid)
             || '|' || l.lanname
             || '|' || p.provolatile::text
             || '|' || p.prosecdef::text
             || '|' || COALESCE(array_to_string(p.proconfig, ','), '')
             || '|' || p.prosrc
             || '|' || pg_get_function_arguments(p.oid)) AS definition_hash
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
  'DB-61 freeze (round 5, portable): hash covers DEFAULT expressions via pg_get_function_arguments.';
