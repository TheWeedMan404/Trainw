-- ============================================================================
-- TRAINW V14 TEST ACCOUNTS
-- Purpose:
--   - Create/repair the requested coach and client auth accounts
--   - Attach them to the existing gym owner hierarchy for gymtest1@gmail.com
--   - Seed realistic coach/client profile data for production-style testing
-- Safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- AUTH + PROFILE SEED
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  v_now timestamptz := now();
  v_gym_id uuid;
  v_owner_id uuid;
  v_coach_auth_id uuid;
  v_client_auth_id uuid;
  v_coach_profile_id uuid;
  v_password_hash text := crypt('Hamdi2463', gen_salt('bf', 10));
BEGIN
  SELECT g.id, g.manager_id
  INTO v_gym_id, v_owner_id
  FROM public.gyms g
  WHERE lower(BTRIM(g.email)) = 'gymtest1@gmail.com'
  ORDER BY g.created_at ASC
  LIMIT 1;

  IF v_gym_id IS NULL THEN
    RAISE EXCEPTION 'Gym for gymtest1@gmail.com was not found. Create the gym owner account first.';
  END IF;

  -- --------------------------------------------------------------------------
  -- Coach auth account
  -- --------------------------------------------------------------------------

  SELECT au.id
  INTO v_coach_auth_id
  FROM auth.users au
  WHERE lower(BTRIM(au.email)) = 'coachtestv14@gmail.com'
  LIMIT 1;

  IF v_coach_auth_id IS NULL THEN
    v_coach_auth_id := gen_random_uuid();

    INSERT INTO auth.users (
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      is_sso_user,
      is_anonymous
    )
    VALUES (
      v_coach_auth_id,
      'authenticated',
      'authenticated',
      'coachtestv14@gmail.com',
      v_password_hash,
      v_now,
      v_now,
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object(
        'name', 'Coach Test V14',
        'role', 'coach',
        'gym_id', v_gym_id::text,
        'email', 'coachtestv14@gmail.com',
        'email_verified', true,
        'phone_verified', false,
        'sub', v_coach_auth_id::text
      ),
      v_now,
      v_now,
      false,
      false
    );
  ELSE
    UPDATE auth.users
    SET email = 'coachtestv14@gmail.com',
        encrypted_password = v_password_hash,
        email_confirmed_at = COALESCE(email_confirmed_at, v_now),
        confirmed_at = COALESCE(confirmed_at, v_now),
        raw_app_meta_data = jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
        raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
          'name', 'Coach Test V14',
          'role', 'coach',
          'gym_id', v_gym_id::text,
          'email', 'coachtestv14@gmail.com',
          'email_verified', true,
          'phone_verified', false,
          'sub', v_coach_auth_id::text
        ),
        updated_at = v_now,
        deleted_at = NULL,
        banned_until = NULL,
        is_sso_user = false,
        is_anonymous = false
    WHERE id = v_coach_auth_id;
  END IF;

  UPDATE auth.identities
  SET provider_id = 'coachtestv14@gmail.com',
      identity_data = jsonb_build_object(
        'name', 'Coach Test V14',
        'role', 'coach',
        'gym_id', v_gym_id::text,
        'email', 'coachtestv14@gmail.com',
        'email_verified', true,
        'phone_verified', false,
        'sub', v_coach_auth_id::text
      ),
      provider = 'email',
      email = 'coachtestv14@gmail.com',
      updated_at = v_now
  WHERE user_id = v_coach_auth_id
    AND provider = 'email';

  IF NOT EXISTS (
    SELECT 1
    FROM auth.identities ai
    WHERE ai.user_id = v_coach_auth_id
      AND ai.provider = 'email'
  ) THEN
    INSERT INTO auth.identities (
      id,
      user_id,
      provider_id,
      identity_data,
      provider,
      last_sign_in_at,
      created_at,
      updated_at,
      email
    )
    VALUES (
      gen_random_uuid(),
      v_coach_auth_id,
      'coachtestv14@gmail.com',
      jsonb_build_object(
        'name', 'Coach Test V14',
        'role', 'coach',
        'gym_id', v_gym_id::text,
        'email', 'coachtestv14@gmail.com',
        'email_verified', true,
        'phone_verified', false,
        'sub', v_coach_auth_id::text
      ),
      'email',
      v_now,
      v_now,
      v_now,
      'coachtestv14@gmail.com'
    );
  END IF;

  -- --------------------------------------------------------------------------
  -- Client auth account
  -- --------------------------------------------------------------------------

  SELECT au.id
  INTO v_client_auth_id
  FROM auth.users au
  WHERE lower(BTRIM(au.email)) = 'clienttestv14@gmail.com'
  LIMIT 1;

  IF v_client_auth_id IS NULL THEN
    v_client_auth_id := gen_random_uuid();

    INSERT INTO auth.users (
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      is_sso_user,
      is_anonymous
    )
    VALUES (
      v_client_auth_id,
      'authenticated',
      'authenticated',
      'clienttestv14@gmail.com',
      v_password_hash,
      v_now,
      v_now,
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object(
        'name', 'Client Test V14',
        'role', 'client',
        'gym_id', v_gym_id::text,
        'email', 'clienttestv14@gmail.com',
        'email_verified', true,
        'phone_verified', false,
        'sub', v_client_auth_id::text
      ),
      v_now,
      v_now,
      false,
      false
    );
  ELSE
    UPDATE auth.users
    SET email = 'clienttestv14@gmail.com',
        encrypted_password = v_password_hash,
        email_confirmed_at = COALESCE(email_confirmed_at, v_now),
        confirmed_at = COALESCE(confirmed_at, v_now),
        raw_app_meta_data = jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
        raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
          'name', 'Client Test V14',
          'role', 'client',
          'gym_id', v_gym_id::text,
          'email', 'clienttestv14@gmail.com',
          'email_verified', true,
          'phone_verified', false,
          'sub', v_client_auth_id::text
        ),
        updated_at = v_now,
        deleted_at = NULL,
        banned_until = NULL,
        is_sso_user = false,
        is_anonymous = false
    WHERE id = v_client_auth_id;
  END IF;

  UPDATE auth.identities
  SET provider_id = 'clienttestv14@gmail.com',
      identity_data = jsonb_build_object(
        'name', 'Client Test V14',
        'role', 'client',
        'gym_id', v_gym_id::text,
        'email', 'clienttestv14@gmail.com',
        'email_verified', true,
        'phone_verified', false,
        'sub', v_client_auth_id::text
      ),
      provider = 'email',
      email = 'clienttestv14@gmail.com',
      updated_at = v_now
  WHERE user_id = v_client_auth_id
    AND provider = 'email';

  IF NOT EXISTS (
    SELECT 1
    FROM auth.identities ai
    WHERE ai.user_id = v_client_auth_id
      AND ai.provider = 'email'
  ) THEN
    INSERT INTO auth.identities (
      id,
      user_id,
      provider_id,
      identity_data,
      provider,
      last_sign_in_at,
      created_at,
      updated_at,
      email
    )
    VALUES (
      gen_random_uuid(),
      v_client_auth_id,
      'clienttestv14@gmail.com',
      jsonb_build_object(
        'name', 'Client Test V14',
        'role', 'client',
        'gym_id', v_gym_id::text,
        'email', 'clienttestv14@gmail.com',
        'email_verified', true,
        'phone_verified', false,
        'sub', v_client_auth_id::text
      ),
      'email',
      v_now,
      v_now,
      v_now,
      'clienttestv14@gmail.com'
    );
  END IF;

  -- --------------------------------------------------------------------------
  -- Public users + hierarchy
  -- --------------------------------------------------------------------------

  INSERT INTO public.users (
    id,
    name,
    email,
    role,
    gym_id,
    language_preference,
    is_managed,
    is_active
  )
  VALUES (
    v_coach_auth_id,
    'Coach Test V14',
    'coachtestv14@gmail.com',
    'coach',
    v_gym_id,
    'en',
    false,
    true
  )
  ON CONFLICT (id) DO UPDATE
  SET name = EXCLUDED.name,
      email = EXCLUDED.email,
      role = EXCLUDED.role,
      gym_id = EXCLUDED.gym_id,
      language_preference = EXCLUDED.language_preference,
      is_managed = EXCLUDED.is_managed,
      is_active = true,
      updated_at = now();

  INSERT INTO public.users (
    id,
    name,
    email,
    role,
    gym_id,
    language_preference,
    is_managed,
    is_active
  )
  VALUES (
    v_client_auth_id,
    'Client Test V14',
    'clienttestv14@gmail.com',
    'client',
    v_gym_id,
    'en',
    false,
    true
  )
  ON CONFLICT (id) DO UPDATE
  SET name = EXCLUDED.name,
      email = EXCLUDED.email,
      role = EXCLUDED.role,
      gym_id = EXCLUDED.gym_id,
      language_preference = EXCLUDED.language_preference,
      is_managed = EXCLUDED.is_managed,
      is_active = true,
      updated_at = now();

  INSERT INTO public.gym_profiles (user_id, gym_id)
  VALUES (v_owner_id, v_gym_id)
  ON CONFLICT (user_id) DO UPDATE
  SET gym_id = EXCLUDED.gym_id,
      updated_at = now();

  INSERT INTO public.coach_profiles (
    user_id,
    gym_id,
    specialty,
    specialties,
    experience_years,
    sessions_completed,
    price_per_session,
    certifications,
    rating,
    total_reviews,
    bio,
    approval_status,
    approved_at,
    approved_by,
    is_active
  )
  VALUES (
    v_coach_auth_id,
    v_gym_id,
    'Strength Training',
    ARRAY['Strength Training'],
    6,
    215,
    80,
    ARRAY['NASM'],
    4.8,
    48,
    'Example coach profile used for platform testing',
    'approved',
    v_now,
    v_owner_id,
    true
  )
  ON CONFLICT (user_id) DO UPDATE
  SET gym_id = EXCLUDED.gym_id,
      specialty = EXCLUDED.specialty,
      specialties = EXCLUDED.specialties,
      experience_years = EXCLUDED.experience_years,
      sessions_completed = EXCLUDED.sessions_completed,
      price_per_session = EXCLUDED.price_per_session,
      certifications = EXCLUDED.certifications,
      rating = EXCLUDED.rating,
      total_reviews = EXCLUDED.total_reviews,
      bio = EXCLUDED.bio,
      approval_status = EXCLUDED.approval_status,
      approved_at = EXCLUDED.approved_at,
      approved_by = EXCLUDED.approved_by,
      is_active = EXCLUDED.is_active,
      updated_at = now()
  RETURNING id INTO v_coach_profile_id;

  IF v_coach_profile_id IS NULL THEN
    SELECT cp.id
    INTO v_coach_profile_id
    FROM public.coach_profiles cp
    WHERE cp.user_id = v_coach_auth_id
    LIMIT 1;
  END IF;

  INSERT INTO public.client_profiles (
    user_id,
    gym_id,
    coach_id,
    membership_tier,
    fitness_goal,
    weight_kg,
    goal_weight_kg,
    payment_status,
    sessions_completed,
    active_plan,
    progress_notes,
    training_type,
    membership_start_date,
    membership_end_date,
    price_paid,
    experience_level,
    notes
  )
  VALUES (
    v_client_auth_id,
    v_gym_id,
    v_coach_profile_id,
    'monthly',
    'fat loss',
    78,
    72,
    'paid',
    14,
    'strength beginner',
    'test progress tracking',
    'strength beginner',
    CURRENT_DATE - 7,
    CURRENT_DATE + 23,
    150,
    'beginner',
    'Assigned to Coach Test V14 for QA coverage.'
  )
  ON CONFLICT (user_id) DO UPDATE
  SET gym_id = EXCLUDED.gym_id,
      coach_id = EXCLUDED.coach_id,
      membership_tier = EXCLUDED.membership_tier,
      fitness_goal = EXCLUDED.fitness_goal,
      weight_kg = EXCLUDED.weight_kg,
      goal_weight_kg = EXCLUDED.goal_weight_kg,
      payment_status = EXCLUDED.payment_status,
      sessions_completed = EXCLUDED.sessions_completed,
      active_plan = EXCLUDED.active_plan,
      progress_notes = EXCLUDED.progress_notes,
      training_type = EXCLUDED.training_type,
      membership_start_date = EXCLUDED.membership_start_date,
      membership_end_date = EXCLUDED.membership_end_date,
      price_paid = EXCLUDED.price_paid,
      experience_level = EXCLUDED.experience_level,
      notes = EXCLUDED.notes,
      updated_at = now();

  UPDATE public.coach_client_assignments
  SET is_active = false,
      ended_at = COALESCE(ended_at, v_now),
      updated_at = now()
  WHERE client_id = v_client_auth_id
    AND is_active = true
    AND (coach_id IS DISTINCT FROM v_coach_auth_id OR gym_id IS DISTINCT FROM v_gym_id);

  INSERT INTO public.coach_client_assignments (
    id,
    coach_id,
    client_id,
    gym_id,
    assigned_by,
    notes,
    assigned_at,
    is_active
  )
  VALUES (
    '22222222-2222-2222-2222-222222220001',
    v_coach_auth_id,
    v_client_auth_id,
    v_gym_id,
    v_owner_id,
    'Seeded TRAINW V14 QA assignment.',
    v_now,
    true
  )
  ON CONFLICT (id) DO UPDATE
  SET coach_id = EXCLUDED.coach_id,
      client_id = EXCLUDED.client_id,
      gym_id = EXCLUDED.gym_id,
      assigned_by = EXCLUDED.assigned_by,
      notes = EXCLUDED.notes,
      assigned_at = EXCLUDED.assigned_at,
      ended_at = NULL,
      is_active = true,
      updated_at = now();

  INSERT INTO public.weight_logs (
    id,
    client_id,
    gym_id,
    logged_by,
    weight_kg,
    notes,
    logged_at
  )
  VALUES (
    '22222222-2222-2222-2222-222222220002',
    v_client_auth_id,
    v_gym_id,
    v_coach_auth_id,
    78,
    'Initial QA baseline weight.',
    v_now - interval '2 days'
  )
  ON CONFLICT (id) DO UPDATE
  SET client_id = EXCLUDED.client_id,
      gym_id = EXCLUDED.gym_id,
      logged_by = EXCLUDED.logged_by,
      weight_kg = EXCLUDED.weight_kg,
      notes = EXCLUDED.notes,
      logged_at = EXCLUDED.logged_at;

  INSERT INTO public.client_goals (
    id,
    client_id,
    gym_id,
    goal_type,
    target_weight_kg,
    target_date,
    notes,
    created_at
  )
  VALUES (
    '22222222-2222-2222-2222-222222220003',
    v_client_auth_id,
    v_gym_id,
    'fat loss',
    72,
    CURRENT_DATE + 60,
    'QA test goal owned by Coach Test V14.',
    v_now
  )
  ON CONFLICT (id) DO UPDATE
  SET client_id = EXCLUDED.client_id,
      gym_id = EXCLUDED.gym_id,
      goal_type = EXCLUDED.goal_type,
      target_weight_kg = EXCLUDED.target_weight_kg,
      target_date = EXCLUDED.target_date,
      notes = EXCLUDED.notes;
END;
$$;
