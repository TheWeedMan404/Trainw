-- =============================================================================
-- Phase 2 — P2-6: close the remaining privilege paths (live re-run findings).
--
-- Live attack matrix (2026-11-15, project Trainw) found ONE real regression
-- and one low-severity oracle; everything else in the P2-6 step held:
--
-- 1. REGRESSION — upsert_staff_profile: anonymous privilege bypass (DB-54
--    family). The guard was
--        IF NOT (v_can_manage OR v_can_edit OR p_user_id = auth.uid()) ...
--    For an unauthenticated caller auth.uid() IS NULL, so
--    `p_user_id = NULL` is NULL and `NOT (false OR false OR NULL)` is NULL
--    -- the IF never fires. Proven live: an anon call created staff_profiles
--    row 6b213dc5-2194-4b94-8f17-3a116bc9c735 for test-a-client in Gym A.
--    Fix: raise unless signed in, before the permission check. Also gates
--    hire_date on manage_staff (mirroring the BEFORE UPDATE trigger,
--    which only fires on UPDATE — a self-caller could otherwise set
--    hire_date on INSERT). Note the gate is has_permission('manage_staff'),
--    not manages_gym(): the latter is true for every admin-portal staff
--    member, which is exactly why the trigger tests manage_staff (round 6).
--
-- 2. LOW — user_role / user_gym_id: unauthenticated oracle. Both are
--    SECURITY DEFINER RLS helpers granted to anon via the PUBLIC default;
--    anon could read any user's role ("client") and gym_id by UUID.
--    Fix: return NULL when auth.uid() IS NULL. Policy behaviour is
--    unchanged: every policy compares these against get_my_gym_id(), which
--    is already NULL for anon, so anon policy evaluation is identical.
--    (Edge functions do not call them; the local suite does not call them
--    directly.) The DB-61 freeze hashes for both functions are updated
--    below (assert re-created, same as P2-8 did in 20261116140000).
--
-- 3. Hardening (round-9 pattern): REVOKE EXECUTE FROM anon, PUBLIC on the
--    17 app-facing RPCs the matrix probed, GRANT TO authenticated. All are
--    called only after sign-in; in-function guards already rejected anon,
--    but the grants are the defence in depth round 9 established for the
--    other 36 functions. Policy machinery (has_permission, manages_gym,
--    can_*, get_my_*, get_auth_context) is deliberately NOT revoked.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. upsert_staff_profile: fail closed for anonymous callers; manager-only
--    hire_date on INSERT as well as UPDATE.
-- ---------------------------------------------------------------------------
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
  -- P2-6: hire_date is manager-only (matches trg_staff_profiles_enforce_gym,
  -- which only fires on UPDATE). A self-caller could otherwise set it on
  -- the INSERT leg of this upsert. Gate on has_permission('manage_staff'),
  -- NOT manages_gym(): the latter is true for every admin-portal staff
  -- member (Staff role portal is 'admin'), which is exactly why the
  -- trigger tests manage_staff (round 6). On the UPDATE leg a non-manager
  -- keeps the stored value (same preserve-pattern as notes below) so the
  -- trigger's manager-only check never trips on a NULL forced by us.
  v_hire_date date := CASE WHEN v_can_manage THEN p_hire_date ELSE NULL END;
BEGIN
  -- P2-6: `p_user_id = auth.uid()` is NULL (not false) for anonymous
  -- callers, so the permission check below silently passed for anon.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to update a staff profile.';
  END IF;

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
    v_hire_date,
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
    hire_date = CASE WHEN v_can_manage THEN EXCLUDED.hire_date ELSE public.staff_profiles.hire_date END,
    work_schedule = EXCLUDED.work_schedule,
    emergency_contact_name = EXCLUDED.emergency_contact_name,
    emergency_contact_phone = EXCLUDED.emergency_contact_phone,
    notes = CASE WHEN v_can_manage THEN EXCLUDED.notes ELSE public.staff_profiles.notes END,
    updated_at = now()
  RETURNING id INTO v_profile_id;

  RETURN v_profile_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. user_role / user_gym_id: no data for anonymous callers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.user_role(p_user_id uuid)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN NULL::text ELSE COALESCE(
    (SELECT role FROM public.users WHERE id = p_user_id),
    (SELECT COALESCE(NULLIF(lower(BTRIM(raw_user_meta_data->>'role')), ''), NULLIF(lower(BTRIM(raw_app_meta_data->>'role')), '')) FROM auth.users WHERE id = p_user_id)
  ) END;
$$;

CREATE OR REPLACE FUNCTION public.user_gym_id(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN NULL::uuid ELSE COALESCE(
    (SELECT gym_id FROM public.users WHERE id = p_user_id),
    (SELECT gym_id FROM public.coach_profiles WHERE user_id = p_user_id AND gym_id IS NOT NULL ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST LIMIT 1),
    (SELECT gym_id FROM public.coach_client_assignments WHERE coach_id = p_user_id AND gym_id IS NOT NULL ORDER BY is_active DESC, assigned_at DESC, id DESC LIMIT 1),
    (SELECT gym_id FROM public.coach_client_assignments WHERE client_id = p_user_id AND gym_id IS NOT NULL ORDER BY is_active DESC, assigned_at DESC, id DESC LIMIT 1),
    (SELECT gym_id FROM public.sessions WHERE coach_id = p_user_id AND gym_id IS NOT NULL ORDER BY session_date DESC, start_time DESC NULLS LAST, id DESC LIMIT 1),
    (SELECT gym_id FROM public.sessions WHERE client_id = p_user_id AND gym_id IS NOT NULL ORDER BY session_date DESC, start_time DESC NULLS LAST, id DESC LIMIT 1),
    (SELECT gym_id FROM public.check_ins WHERE client_id = p_user_id AND gym_id IS NOT NULL ORDER BY checked_in_at DESC, id DESC LIMIT 1),
    (SELECT id FROM public.gyms WHERE manager_id = p_user_id ORDER BY created_at ASC LIMIT 1)
  ) END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Revoke anonymous EXECUTE on the app-facing RPCs (round-9 pattern).
--    The DO block is idempotent: it only acts when the function exists.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.upsert_staff_profile(uuid, uuid, text, text, text, date, jsonb, text, text, text)',
    'public.get_staff_directory(uuid)',
    'public.get_staff_directory_sensitive(uuid)',
    'public.list_gym_member_directory(uuid)',
    'public.invite_gym_member(uuid, text, text, uuid, text, jsonb)',
    'public.set_membership_role(uuid, uuid)',
    'public.save_role_definition(uuid, uuid, text, text, text, text, text[])',
    'public.revoke_gate_session(uuid)',
    'public.accept_gym_invitation(text)',
    'public.decline_gym_invitation(text)',
    'public.apply_member_credit_to_session(uuid)',
    'public.get_member_credit_balance(uuid, uuid)',
    'public.revoke_gym_membership(uuid)',
    'public.revoke_gym_membership_by_user(uuid, uuid)',
    'public.set_active_gym(uuid)',
    'public.bootstrap_authenticated_user(text, text, text, text)',
    'public.list_role_matrix(uuid)'
  ] LOOP
    IF to_regprocedure(v_sig) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon, PUBLIC', v_sig);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_sig);
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 4. DB-61 freeze resync: user_role / user_gym_id changed above, so their
--    expected hashes must follow (same pattern as P2-8, 20261116140000).
--    Assert re-created VERBATIM from 20261116140000 except the two hashes
--    (computed with the portable formula on a fresh chain apply:
--    user_gym_id 48660b5bb08fa1f3076b2c85e853c71e,
--    user_role 37b47cd2c1988dab1fb3c9d1c3071a7b). The trailing SELECT proves
--    the assert passes on the database it is applied to.
-- ---------------------------------------------------------------------------
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
      ('membership_is_active_for_access(p_client_id uuid, p_gym_id uuid, p_reference_date date)', '3a70bd4a318b5ee8b55ce0473161e5a8'),
      ('permission_codes_for_membership(p_membership_id uuid)', '5b42f83662c766785b184c3908788c88'),
      ('safe_uuid(p_value text)', '61a80c4c69579d049678f74fdf363ef1'),
      ('storage_object_is_public(p_bucket text, p_path text)', '90ac3d12c8dd7c2bb4c5c3abb32695a9'),
      ('user_gym_id(p_user_id uuid)', '48660b5bb08fa1f3076b2c85e853c71e'),
      ('user_has_membership(p_gym_id uuid, p_user_id uuid)', '11460628b527af9223efe6bdabbf05e1'),
      ('user_role(p_user_id uuid)', '37b47cd2c1988dab1fb3c9d1c3071a7b')
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

-- The resynced freeze must pass on the database it is applied to.
SELECT public.assert_rls_helpers_frozen();

COMMENT ON FUNCTION public.assert_rls_helpers_frozen() IS
  'DB-61 freeze (round 5, portable): hash covers DEFAULT expressions via pg_get_function_arguments. Resynced live 2026-11-15 (P2-8); user_role/user_gym_id resynced 2026-11-15 (P2-6).';
