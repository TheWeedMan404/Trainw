-- ============================================================================
-- TRAINW V14 DEMO SEED
-- Purpose:
--   - Seed a realistic multi-role demo gym for local testing
--   - Stay idempotent and safe to re-run
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CORE IDENTIFIERS
-- ----------------------------------------------------------------------------

-- Gym
--   11111111-1111-1111-1111-111111111111
-- Manager
--   11111111-1111-1111-1111-111111111001
-- Coach
--   11111111-1111-1111-1111-111111111101
-- Client A
--   11111111-1111-1111-1111-111111111201
-- Client B
--   11111111-1111-1111-1111-111111111202

-- ----------------------------------------------------------------------------
-- GYM AND USERS
-- ----------------------------------------------------------------------------

INSERT INTO public.gyms (
  id,
  name,
  email,
  owner_name,
  phone,
  address,
  description,
  subscription_tier,
  is_active,
  manager_id
)
VALUES (
  '11111111-1111-1111-1111-111111111111',
  'Trainw Demo Gym',
  'demo-gym@trainw.local',
  'Nadia Ben Salem',
  '+216 70 000 001',
  'Lac 1, Tunis',
  'Seeded SaaS demo gym for TRAINW V14.',
  'pro',
  true,
  '11111111-1111-1111-1111-111111111001'
)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    email = EXCLUDED.email,
    owner_name = EXCLUDED.owner_name,
    phone = EXCLUDED.phone,
    address = EXCLUDED.address,
    description = EXCLUDED.description,
    subscription_tier = EXCLUDED.subscription_tier,
    is_active = EXCLUDED.is_active,
    manager_id = EXCLUDED.manager_id,
    updated_at = now();

INSERT INTO public.users (id, name, email, role, gym_id, phone, is_managed, is_active)
VALUES
  ('11111111-1111-1111-1111-111111111001', 'Nadia Ben Salem', 'owner.demo@trainw.local', 'gym_owner', '11111111-1111-1111-1111-111111111111', '+216 70 000 010', true, true),
  ('11111111-1111-1111-1111-111111111101', 'Youssef Trabelsi', 'coach.demo@trainw.local', 'coach', '11111111-1111-1111-1111-111111111111', '+216 70 000 011', true, true),
  ('11111111-1111-1111-1111-111111111201', 'Leila Mansour', 'client.a@trainw.local', 'client', '11111111-1111-1111-1111-111111111111', '+216 70 000 021', true, true),
  ('11111111-1111-1111-1111-111111111202', 'Karim Jaziri', 'client.b@trainw.local', 'client', '11111111-1111-1111-1111-111111111111', '+216 70 000 022', true, true)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    email = EXCLUDED.email,
    role = EXCLUDED.role,
    gym_id = EXCLUDED.gym_id,
    phone = EXCLUDED.phone,
    is_managed = EXCLUDED.is_managed,
    is_active = EXCLUDED.is_active,
    updated_at = now();


-- ----------------------------------------------------------------------------
-- PROFILES AND SPECIALTIES
-- ----------------------------------------------------------------------------

INSERT INTO public.coach_profiles (
  user_id,
  gym_id,
  specialty,
  specialties,
  experience_years,
  price_per_session,
  bio,
  approval_status,
  approved_at,
  approved_by,
  is_active
)
VALUES (
  '11111111-1111-1111-1111-111111111101',
  '11111111-1111-1111-1111-111111111111',
  'Strength & Conditioning',
  ARRAY['Strength & Conditioning', 'Mobility'],
  7,
  75,
  'Head coach for progressive strength training and mobility work.',
  'approved',
  now(),
  '11111111-1111-1111-1111-111111111001',
  true
)
ON CONFLICT (user_id) DO UPDATE
SET gym_id = EXCLUDED.gym_id,
    specialty = EXCLUDED.specialty,
    specialties = EXCLUDED.specialties,
    experience_years = EXCLUDED.experience_years,
    price_per_session = EXCLUDED.price_per_session,
    bio = EXCLUDED.bio,
    approval_status = EXCLUDED.approval_status,
    approved_at = EXCLUDED.approved_at,
    approved_by = EXCLUDED.approved_by,
    is_active = EXCLUDED.is_active,
    updated_at = now();

INSERT INTO public.client_profiles (
  user_id,
  membership_tier,
  fitness_goal,
  payment_status,
  training_type,
  membership_start_date,
  membership_end_date,
  price_paid,
  experience_level
)
VALUES
  ('11111111-1111-1111-1111-111111111201', 'monthly', 'Lose fat and build consistency', 'paid', 'hybrid', CURRENT_DATE - 10, CURRENT_DATE + 20, 120, 'beginner'),
  ('11111111-1111-1111-1111-111111111202', 'quarterly', 'Build strength', 'paid', 'strength', CURRENT_DATE - 20, CURRENT_DATE + 70, 320, 'intermediate')
ON CONFLICT (user_id) DO UPDATE
SET membership_tier = EXCLUDED.membership_tier,
    fitness_goal = EXCLUDED.fitness_goal,
    payment_status = EXCLUDED.payment_status,
    training_type = EXCLUDED.training_type,
    membership_start_date = EXCLUDED.membership_start_date,
    membership_end_date = EXCLUDED.membership_end_date,
    price_paid = EXCLUDED.price_paid,
    experience_level = EXCLUDED.experience_level,
    updated_at = now();

INSERT INTO public.specialty_tags (name)
VALUES ('Strength & Conditioning'), ('Mobility')
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.coach_specialties (coach_user_id, specialty_id, gym_id)
SELECT
  '11111111-1111-1111-1111-111111111101',
  st.id,
  '11111111-1111-1111-1111-111111111111'
FROM public.specialty_tags st
WHERE st.name IN ('Strength & Conditioning', 'Mobility')
ON CONFLICT (coach_user_id, specialty_id) DO NOTHING;


-- ----------------------------------------------------------------------------
-- ASSIGNMENTS AND AVAILABILITY
-- ----------------------------------------------------------------------------

INSERT INTO public.coach_client_assignments (
  id,
  coach_id,
  client_id,
  gym_id,
  assigned_by,
  assigned_at,
  is_active
)
VALUES
  ('11111111-1111-1111-1111-111111112001', '11111111-1111-1111-1111-111111111101', '11111111-1111-1111-1111-111111111201', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111001', now() - interval '14 days', true),
  ('11111111-1111-1111-1111-111111112002', '11111111-1111-1111-1111-111111111101', '11111111-1111-1111-1111-111111111202', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111001', now() - interval '10 days', true)
ON CONFLICT (id) DO UPDATE
SET coach_id = EXCLUDED.coach_id,
    client_id = EXCLUDED.client_id,
    gym_id = EXCLUDED.gym_id,
    assigned_by = EXCLUDED.assigned_by,
    assigned_at = EXCLUDED.assigned_at,
    is_active = EXCLUDED.is_active,
    updated_at = now();

INSERT INTO public.coach_availability (
  id,
  coach_id,
  gym_id,
  day_of_week,
  start_time,
  end_time,
  slot_minutes,
  is_active
)
VALUES
  ('11111111-1111-1111-1111-111111113001', '11111111-1111-1111-1111-111111111101', '11111111-1111-1111-1111-111111111111', 1, '08:00', '12:00', 60, true),
  ('11111111-1111-1111-1111-111111113002', '11111111-1111-1111-1111-111111111101', '11111111-1111-1111-1111-111111111111', 3, '14:00', '18:00', 60, true)
ON CONFLICT (id) DO UPDATE
SET coach_id = EXCLUDED.coach_id,
    gym_id = EXCLUDED.gym_id,
    day_of_week = EXCLUDED.day_of_week,
    start_time = EXCLUDED.start_time,
    end_time = EXCLUDED.end_time,
    slot_minutes = EXCLUDED.slot_minutes,
    is_active = EXCLUDED.is_active,
    updated_at = now();


-- ----------------------------------------------------------------------------
-- CLASSES, PROGRAMMING, AND BODY METRICS
-- ----------------------------------------------------------------------------

INSERT INTO public.gym_classes (
  id,
  gym_id,
  created_by,
  coach_id,
  name,
  description,
  schedule_day,
  start_time,
  duration_minutes,
  capacity,
  is_active
)
VALUES (
  '11111111-1111-1111-1111-111111114001',
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111001',
  '11111111-1111-1111-1111-111111111101',
  'Strength Fundamentals',
  'Small-group strength foundations session.',
  'Monday',
  '18:00',
  60,
  12,
  true
)
ON CONFLICT (id) DO UPDATE
SET gym_id = EXCLUDED.gym_id,
    created_by = EXCLUDED.created_by,
    coach_id = EXCLUDED.coach_id,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    schedule_day = EXCLUDED.schedule_day,
    start_time = EXCLUDED.start_time,
    duration_minutes = EXCLUDED.duration_minutes,
    capacity = EXCLUDED.capacity,
    is_active = EXCLUDED.is_active,
    updated_at = now();

INSERT INTO public.workout_plans (
  id,
  gym_id,
  created_by,
  client_id,
  title,
  goal,
  frequency_per_week,
  description,
  is_template
)
VALUES (
  '11111111-1111-1111-1111-111111115001',
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111101',
  '11111111-1111-1111-1111-111111111201',
  'Client A Strength Base',
  'Consistency and progressive overload',
  3,
  'Three-day foundational program.',
  false
)
ON CONFLICT (id) DO UPDATE
SET gym_id = EXCLUDED.gym_id,
    created_by = EXCLUDED.created_by,
    client_id = EXCLUDED.client_id,
    title = EXCLUDED.title,
    goal = EXCLUDED.goal,
    frequency_per_week = EXCLUDED.frequency_per_week,
    description = EXCLUDED.description,
    is_template = EXCLUDED.is_template,
    updated_at = now();

DELETE FROM public.workout_exercises
WHERE plan_id = '11111111-1111-1111-1111-111111115001';

INSERT INTO public.workout_exercises (
  plan_id,
  day_label,
  exercise_name,
  sets,
  reps,
  rest_seconds,
  order_index
)
VALUES
  ('11111111-1111-1111-1111-111111115001', 'Day 1', 'Goblet Squat', 4, '8', 90, 1),
  ('11111111-1111-1111-1111-111111115001', 'Day 1', 'Push-Up', 4, '10', 60, 2),
  ('11111111-1111-1111-1111-111111115001', 'Day 2', 'Romanian Deadlift', 4, '8', 90, 3);

INSERT INTO public.weight_logs (
  id,
  client_id,
  gym_id,
  logged_by,
  weight_kg,
  body_fat_pct,
  logged_at
)
VALUES (
  '11111111-1111-1111-1111-111111116001',
  '11111111-1111-1111-1111-111111111201',
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111101',
  78.4,
  24.1,
  now() - interval '2 days'
)
ON CONFLICT (id) DO UPDATE
SET client_id = EXCLUDED.client_id,
    gym_id = EXCLUDED.gym_id,
    logged_by = EXCLUDED.logged_by,
    weight_kg = EXCLUDED.weight_kg,
    body_fat_pct = EXCLUDED.body_fat_pct,
    logged_at = EXCLUDED.logged_at;

INSERT INTO public.client_goals (
  id,
  client_id,
  gym_id,
  goal_type,
  target_weight_kg,
  target_date,
  notes
)
VALUES (
  '11111111-1111-1111-1111-111111117001',
  '11111111-1111-1111-1111-111111111201',
  '11111111-1111-1111-1111-111111111111',
  'fat_loss',
  72.0,
  CURRENT_DATE + 90,
  'Target body-composition phase.'
)
ON CONFLICT (id) DO UPDATE
SET client_id = EXCLUDED.client_id,
    gym_id = EXCLUDED.gym_id,
    goal_type = EXCLUDED.goal_type,
    target_weight_kg = EXCLUDED.target_weight_kg,
    target_date = EXCLUDED.target_date,
    notes = EXCLUDED.notes;


-- ----------------------------------------------------------------------------
-- BOOKINGS, PAYMENTS, REVIEWS, AND ACTIVITY
-- ----------------------------------------------------------------------------

INSERT INTO public.sessions (
  id,
  gym_id,
  coach_id,
  client_id,
  class_id,
  session_date,
  start_time,
  duration_minutes,
  type,
  status,
  session_name,
  notes,
  capacity,
  booking_source,
  created_by,
  updated_by
)
VALUES
  (
    '11111111-1111-1111-1111-111111118001',
    '11111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111101',
    '11111111-1111-1111-1111-111111111201',
    NULL,
    CURRENT_DATE + 2,
    '09:00',
    60,
    'individual_training',
    'confirmed',
    'Private Strength Session',
    'Focus on squat patterning.',
    1,
    'gym_manager',
    '11111111-1111-1111-1111-111111111001',
    '11111111-1111-1111-1111-111111111001'
  ),
  (
    '11111111-1111-1111-1111-111111118002',
    '11111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111101',
    '11111111-1111-1111-1111-111111111202',
    NULL,
    CURRENT_DATE - 7,
    '10:00',
    60,
    'individual_training',
    'completed',
    'Completed Review Session',
    'Form review and progression planning.',
    1,
    'gym_manager',
    '11111111-1111-1111-1111-111111111001',
    '11111111-1111-1111-1111-111111111001'
  ),
  (
    '11111111-1111-1111-1111-111111118003',
    '11111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111101',
    NULL,
    '11111111-1111-1111-1111-111111114001',
    CURRENT_DATE + 3,
    '18:00',
    60,
    'group_class',
    'confirmed',
    'Strength Fundamentals',
    'Seeded class session.',
    12,
    'system',
    '11111111-1111-1111-1111-111111111001',
    '11111111-1111-1111-1111-111111111001'
  )
ON CONFLICT (id) DO UPDATE
SET gym_id = EXCLUDED.gym_id,
    coach_id = EXCLUDED.coach_id,
    client_id = EXCLUDED.client_id,
    class_id = EXCLUDED.class_id,
    session_date = EXCLUDED.session_date,
    start_time = EXCLUDED.start_time,
    duration_minutes = EXCLUDED.duration_minutes,
    type = EXCLUDED.type,
    status = EXCLUDED.status,
    session_name = EXCLUDED.session_name,
    notes = EXCLUDED.notes,
    capacity = EXCLUDED.capacity,
    booking_source = EXCLUDED.booking_source,
    created_by = EXCLUDED.created_by,
    updated_by = EXCLUDED.updated_by;

INSERT INTO public.session_enrollments (
  id,
  session_id,
  client_id,
  gym_id,
  enrolled_at
)
VALUES
  ('11111111-1111-1111-1111-111111119001', '11111111-1111-1111-1111-111111118003', '11111111-1111-1111-1111-111111111201', '11111111-1111-1111-1111-111111111111', now() - interval '1 day'),
  ('11111111-1111-1111-1111-111111119002', '11111111-1111-1111-1111-111111118003', '11111111-1111-1111-1111-111111111202', '11111111-1111-1111-1111-111111111111', now() - interval '1 day')
ON CONFLICT (session_id, client_id) DO UPDATE
SET gym_id = EXCLUDED.gym_id,
    enrolled_at = EXCLUDED.enrolled_at;

INSERT INTO public.payments (
  id,
  gym_id,
  client_id,
  session_id,
  created_by,
  payment_type,
  status,
  provider,
  currency_code,
  amount_total,
  amount_paid,
  paid_at
)
VALUES
  (
    '11111111-1111-1111-1111-111111120001',
    '11111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111201',
    '11111111-1111-1111-1111-111111118001',
    '11111111-1111-1111-1111-111111111001',
    'session',
    'pending',
    'manual',
    'TND',
    75,
    0,
    NULL
  ),
  (
    '11111111-1111-1111-1111-111111120002',
    '11111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111202',
    '11111111-1111-1111-1111-111111118002',
    '11111111-1111-1111-1111-111111111001',
    'session',
    'paid',
    'cash',
    'TND',
    75,
    75,
    now() - interval '7 days'
  )
ON CONFLICT (id) DO UPDATE
SET gym_id = EXCLUDED.gym_id,
    client_id = EXCLUDED.client_id,
    session_id = EXCLUDED.session_id,
    created_by = EXCLUDED.created_by,
    payment_type = EXCLUDED.payment_type,
    status = EXCLUDED.status,
    provider = EXCLUDED.provider,
    currency_code = EXCLUDED.currency_code,
    amount_total = EXCLUDED.amount_total,
    amount_paid = EXCLUDED.amount_paid,
    paid_at = EXCLUDED.paid_at,
    updated_at = now();

UPDATE public.sessions
SET payment_id = '11111111-1111-1111-1111-111111120001'
WHERE id = '11111111-1111-1111-1111-111111118001';

UPDATE public.sessions
SET payment_id = '11111111-1111-1111-1111-111111120002'
WHERE id = '11111111-1111-1111-1111-111111118002';

INSERT INTO public.reviews (
  id,
  session_id,
  coach_id,
  client_id,
  gym_id,
  rating,
  comment,
  is_visible
)
VALUES (
  '11111111-1111-1111-1111-111111121001',
  '11111111-1111-1111-1111-111111118002',
  '11111111-1111-1111-1111-111111111101',
  '11111111-1111-1111-1111-111111111202',
  '11111111-1111-1111-1111-111111111111',
  5,
  'Excellent session with clear progression cues.',
  true
)
ON CONFLICT (session_id) DO UPDATE
SET coach_id = EXCLUDED.coach_id,
    client_id = EXCLUDED.client_id,
    gym_id = EXCLUDED.gym_id,
    rating = EXCLUDED.rating,
    comment = EXCLUDED.comment,
    is_visible = EXCLUDED.is_visible,
    updated_at = now();

INSERT INTO public.check_ins (
  id,
  gym_id,
  client_id,
  created_by,
  checked_in_at,
  method
)
VALUES (
  '11111111-1111-1111-1111-111111122001',
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111201',
  '11111111-1111-1111-1111-111111111001',
  now() - interval '6 hours',
  'manual'
)
ON CONFLICT (id) DO UPDATE
SET gym_id = EXCLUDED.gym_id,
    client_id = EXCLUDED.client_id,
    created_by = EXCLUDED.created_by,
    checked_in_at = EXCLUDED.checked_in_at,
    method = EXCLUDED.method;

INSERT INTO public.gate_sessions (
  id,
  client_id,
  gym_id,
  token,
  created_at,
  expires_at,
  used
)
VALUES (
  '11111111-1111-1111-1111-111111123001',
  '11111111-1111-1111-1111-111111111201',
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111201.11111111-1111-1111-1111-111111111111.demo-token.seed',
  now(),
  now() + interval '1 minute',
  false
)
ON CONFLICT (id) DO UPDATE
SET client_id = EXCLUDED.client_id,
    gym_id = EXCLUDED.gym_id,
    token = EXCLUDED.token,
    created_at = EXCLUDED.created_at,
    expires_at = EXCLUDED.expires_at,
    used = EXCLUDED.used;

INSERT INTO public.messages (
  id,
  gym_id,
  sender_id,
  receiver_id,
  content,
  is_read,
  is_automated,
  created_at
)
VALUES (
  '11111111-1111-1111-1111-111111124001',
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111101',
  '11111111-1111-1111-1111-111111111201',
  'Great job this week. Keep your tempo controlled on squats.',
  false,
  false,
  now() - interval '12 hours'
)
ON CONFLICT (id) DO UPDATE
SET gym_id = EXCLUDED.gym_id,
    sender_id = EXCLUDED.sender_id,
    receiver_id = EXCLUDED.receiver_id,
    content = EXCLUDED.content,
    is_read = EXCLUDED.is_read,
    is_automated = EXCLUDED.is_automated,
    created_at = EXCLUDED.created_at;


-- ============================================================================
-- V17 DEMO ACCOUNTS: gym_admin + staff/receptionist
-- ============================================================================
-- IMPORTANT: Before running this block, create these two accounts manually
-- in the Supabase Auth dashboard (Authentication > Users > Add user):
--
--   Email: admin@lakeclub.tn     Password: LakeClub2026!
--   Email: reception@lakeclub.tn Password: LakeClub2026!
--
-- Then update the two UUIDs below to match the ones generated by Supabase Auth.
-- These placeholder UUIDs are safe to run as-is for local/demo environments
-- where you control the auth seeding.
-- ============================================================================

INSERT INTO public.users (id, name, email, role, gym_id, phone, is_managed, is_active)
VALUES
  ('22222222-2222-2222-2222-222222222001', 'Sami Admin',       'admin@lakeclub.tn',     'gym_admin', '11111111-1111-1111-1111-111111111111', '+216 70 100 001', false, true),
  ('22222222-2222-2222-2222-222222222002', 'Rim Receptionist', 'reception@lakeclub.tn', 'staff',     '11111111-1111-1111-1111-111111111111', '+216 70 100 002', false, true)
ON CONFLICT (id) DO UPDATE
SET name        = EXCLUDED.name,
    email       = EXCLUDED.email,
    role        = EXCLUDED.role,
    gym_id      = EXCLUDED.gym_id,
    phone       = EXCLUDED.phone,
    is_managed  = EXCLUDED.is_managed,
    is_active   = EXCLUDED.is_active,
    updated_at  = now();

-- After inserting, bootstrap auth links (replace UUIDs with real ones from auth.users):
-- SELECT public.bootstrap_authenticated_user('gym_admin', 'Sami Admin',       'admin@lakeclub.tn');
-- SELECT public.bootstrap_authenticated_user('staff',     'Rim Receptionist', 'reception@lakeclub.tn');
