-- ═══════════════════════════════════════════════════════════════════════════
-- TRAINW — DB RESET + DEMO SEED
-- Run in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT THIS DOES:
--   1. Adds attendee_count column if missing (needed by the V17 frontend)
--   2. Deletes all sessions, managed coaches, managed clients for your gym
--   3. Inserts 15 coaches + 15 clients + 34 sessions with realistic variety
--      + real session_enrollments (attendee_count is computed from them)
--
-- BEFORE YOU RUN THIS (DB-49, audit 2026-11-14):
--   This script DELETES data, so it never guesses which gym to wipe.
--   1. Pick the gym id, then run in the same SQL Editor session:
--        SELECT set_config('trainw.demo_gym_id', '<gym uuid>', false);
--   2. Run this script.
--   The script REFUSES to run when the setting is missing, when the gym
--   does not exist, and when more than one gym exists in the database
--   (a multi-gym database must be reset gym-by-gym with an adapted
--   script — never with a LIMIT 1 guess).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── STEP 1: Add attendee_count column (safe, idempotent) ─────────────────
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS attendee_count INTEGER DEFAULT 0;

-- ── STEP 2: CLEAN UP ─────────────────────────────────────────────────────
DO $$
DECLARE
  v_gym_id UUID;
BEGIN
  -- DB-49: the gym must be named explicitly (trainw.demo_gym_id).
  -- Never guess with LIMIT 1, and never run on a multi-gym database.
  v_gym_id := NULLIF(BTRIM(current_setting('trainw.demo_gym_id', true)), '')::uuid;
  IF v_gym_id IS NULL THEN
    RAISE EXCEPTION 'Set the target gym first: SELECT set_config(''trainw.demo_gym_id'', ''<gym uuid>'', false); then re-run this script.';
  END IF;
  IF (SELECT count(*) FROM public.gyms) > 1 THEN
    RAISE EXCEPTION 'Refusing: more than one gym exists in this database. This reset script is only safe on a single-gym database.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.gyms WHERE id = v_gym_id) THEN
    RAISE EXCEPTION 'Gym % does not exist.', v_gym_id;
  END IF;

  -- Delete sessions belonging to this gym
  DELETE FROM public.sessions WHERE gym_id = v_gym_id;

  -- Delete client_profiles for managed clients in this gym
  DELETE FROM public.client_profiles
  WHERE user_id IN (
    SELECT id FROM public.users
    WHERE gym_id = v_gym_id
      AND role = 'client'
      AND is_managed = true
  );

  -- Delete managed clients
  DELETE FROM public.users
  WHERE gym_id = v_gym_id
    AND role = 'client'
    AND is_managed = true;

  -- Delete coach_profiles for managed coaches in this gym
  DELETE FROM public.coach_profiles
  WHERE user_id IN (
    SELECT id FROM public.users
    WHERE gym_id = v_gym_id
      AND role = 'coach'
      AND is_managed = true
  );

  -- Delete managed coaches
  DELETE FROM public.users
  WHERE gym_id = v_gym_id
    AND role = 'coach'
    AND is_managed = true;

  RAISE NOTICE 'Cleanup done for gym %', v_gym_id;
END $$;


-- ── STEP 3: INSERT COACHES + CLIENTS + SESSIONS ──────────────────────────
DO $$
DECLARE
  v_gym_id  UUID;

  -- Coach user IDs
  c1  UUID; c2  UUID; c3  UUID; c4  UUID; c5  UUID;
  c6  UUID; c7  UUID; c8  UUID; c9  UUID; c10 UUID;
  c11 UUID; c12 UUID; c13 UUID; c14 UUID; c15 UUID;

  -- Client user IDs
  cl1  UUID; cl2  UUID; cl3  UUID; cl4  UUID; cl5  UUID;
  cl6  UUID; cl7  UUID; cl8  UUID; cl9  UUID; cl10 UUID;
  cl11 UUID; cl12 UUID; cl13 UUID; cl14 UUID; cl15 UUID;

BEGIN
  -- DB-49: the gym must be named explicitly (trainw.demo_gym_id).
  -- Never guess with LIMIT 1, and never run on a multi-gym database.
  v_gym_id := NULLIF(BTRIM(current_setting('trainw.demo_gym_id', true)), '')::uuid;
  IF v_gym_id IS NULL THEN
    RAISE EXCEPTION 'Set the target gym first: SELECT set_config(''trainw.demo_gym_id'', ''<gym uuid>'', false); then re-run this script.';
  END IF;
  IF (SELECT count(*) FROM public.gyms) > 1 THEN
    RAISE EXCEPTION 'Refusing: more than one gym exists in this database. This reset script is only safe on a single-gym database.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.gyms WHERE id = v_gym_id) THEN
    RAISE EXCEPTION 'Gym % does not exist.', v_gym_id;
  END IF;

  -- ── Generate IDs ──────────────────────────────────────────────────────
  c1  := gen_random_uuid(); c2  := gen_random_uuid(); c3  := gen_random_uuid();
  c4  := gen_random_uuid(); c5  := gen_random_uuid(); c6  := gen_random_uuid();
  c7  := gen_random_uuid(); c8  := gen_random_uuid(); c9  := gen_random_uuid();
  c10 := gen_random_uuid(); c11 := gen_random_uuid(); c12 := gen_random_uuid();
  c13 := gen_random_uuid(); c14 := gen_random_uuid(); c15 := gen_random_uuid();

  cl1  := gen_random_uuid(); cl2  := gen_random_uuid(); cl3  := gen_random_uuid();
  cl4  := gen_random_uuid(); cl5  := gen_random_uuid(); cl6  := gen_random_uuid();
  cl7  := gen_random_uuid(); cl8  := gen_random_uuid(); cl9  := gen_random_uuid();
  cl10 := gen_random_uuid(); cl11 := gen_random_uuid(); cl12 := gen_random_uuid();
  cl13 := gen_random_uuid(); cl14 := gen_random_uuid(); cl15 := gen_random_uuid();

  -- ── INSERT 15 COACHES (users table) ───────────────────────────────────
  INSERT INTO public.users (id, name, email, role, gym_id, phone, is_managed) VALUES
    (c1,  'Coach Test 1',  'coach.test.1@trainw.local',  'coach', v_gym_id, '+216 92 001 001', true),
    (c2,  'Coach Test 2',  'coach.test.2@trainw.local',  'coach', v_gym_id, '+216 92 001 002', true),
    (c3,  'Coach Test 3',  'coach.test.3@trainw.local',  'coach', v_gym_id, '+216 92 001 003', true),
    (c4,  'Coach Test 4',  'coach.test.4@trainw.local',  'coach', v_gym_id, '+216 92 001 004', true),
    (c5,  'Coach Test 5',  'coach.test.5@trainw.local',  'coach', v_gym_id, '+216 92 001 005', true),
    (c6,  'Coach Test 6',  'coach.test.6@trainw.local',  'coach', v_gym_id, '+216 92 001 006', true),
    (c7,  'Coach Test 7',  'coach.test.7@trainw.local',  'coach', v_gym_id, '+216 92 001 007', true),
    (c8,  'Coach Test 8',  'coach.test.8@trainw.local',  'coach', v_gym_id, '+216 92 001 008', true),
    (c9,  'Coach Test 9',  'coach.test.9@trainw.local',  'coach', v_gym_id, '+216 92 001 009', true),
    (c10, 'Coach Test 10', 'coach.test.10@trainw.local', 'coach', v_gym_id, '+216 92 001 010', true),
    (c11, 'Coach Test 11', 'coach.test.11@trainw.local', 'coach', v_gym_id, '+216 92 001 011', true),
    (c12, 'Coach Test 12', 'coach.test.12@trainw.local', 'coach', v_gym_id, '+216 92 001 012', true),
    (c13, 'Coach Test 13', 'coach.test.13@trainw.local', 'coach', v_gym_id, '+216 92 001 013', true),
    (c14, 'Coach Test 14', 'coach.test.14@trainw.local', 'coach', v_gym_id, '+216 92 001 014', true),
    (c15, 'Coach Test 15', 'coach.test.15@trainw.local', 'coach', v_gym_id, '+216 92 001 015', true);

  -- ── INSERT 15 COACH PROFILES ──────────────────────────────────────────
  INSERT INTO public.coach_profiles
    (user_id, specialty, hourly_rate, rating, total_reviews, bio, is_active) VALUES
    (c1,  'CrossFit',              65,  4.9, 52, 'Champion régional CrossFit 2022. Spécialiste force et conditionnement.', true),
    (c2,  'Musculation',           55,  4.7, 38, 'Expert hypertrophie et force maximale. 10 ans de compétition bodybuilding.', true),
    (c3,  'Yoga & Pilates',        50,  4.8, 61, 'Certifiée RYT-500. Spécialité yoga thérapeutique et rééducation postale.', true),
    (c4,  'HIIT & Cardio',         45,  4.6, 29, 'Coach cardio intensif. Préparation courses, triathlons, challenges fitness.', true),
    (c5,  'Natation',              70,  4.9, 44, 'Ancien nageur national. Technique nage libre et entraînement compétitif.', true),
    (c6,  'Boxe & Arts Martiaux',  75,  4.8, 33, 'Ceinture noire judo. Coach boxe anglaise et autodéfense.', true),
    (c7,  'Nutrition Sportive',    85,  4.7, 27, 'Diététicien du sport diplômé. Plans nutritionnels personnalisés.', true),
    (c8,  'Rééducation',           80,  4.9, 58, 'Kiné et coach. Reprise après blessure, prévention, mobilité fonctionnelle.', true),
    (c9,  'Cyclisme & Spinning',   50,  4.5, 19, 'Ex-cycliste professionnel. Entraînement vélo route et spinning indoor.', true),
    (c10, 'Zumba & Fitness',       40,  4.6, 36, 'Instructeur Zumba certifié. Cours collectifs tous niveaux.', true),
    (c11, 'Tennis',                90,  4.8, 41, 'Classé ATP juniors. Entraîneur fédéral niveau 3.', true),
    (c12, 'Sports Collectifs',     55,  4.4, 17, 'Préparateur physique football, basket, handball. Clubs locaux.', true),
    (c13, 'Mobilité & Stretching', 40,  4.7, 24, 'Spécialiste mobilité articulaire, récupération active et prévention.', true),
    (c14, 'Prépa Physique Elite',  95,  5.0, 12, 'Préparateur physique haute performance. Athlètes de compétition nationale.', true),
    (c15, 'Fitness Féminin',       55,  4.6, 31, 'Spécialiste fitness féminin, post-partum et remise en forme progressive.', true);

  -- ── INSERT 15 CLIENTS (users table) ───────────────────────────────────
  INSERT INTO public.users (id, name, email, role, gym_id, phone, is_managed) VALUES
    (cl1,  'Client Test 1',  'client.test.1@trainw.local',  'client', v_gym_id, '+216 93 001 001', true),
    (cl2,  'Client Test 2',  'client.test.2@trainw.local',  'client', v_gym_id, '+216 93 001 002', true),
    (cl3,  'Client Test 3',  'client.test.3@trainw.local',  'client', v_gym_id, '+216 93 001 003', true),
    (cl4,  'Client Test 4',  'client.test.4@trainw.local',  'client', v_gym_id, '+216 93 001 004', true),
    (cl5,  'Client Test 5',  'client.test.5@trainw.local',  'client', v_gym_id, '+216 93 001 005', true),
    (cl6,  'Client Test 6',  'client.test.6@trainw.local',  'client', v_gym_id, '+216 93 001 006', true),
    (cl7,  'Client Test 7',  'client.test.7@trainw.local',  'client', v_gym_id, '+216 93 001 007', true),
    (cl8,  'Client Test 8',  'client.test.8@trainw.local',  'client', v_gym_id, '+216 93 001 008', true),
    (cl9,  'Client Test 9',  'client.test.9@trainw.local',  'client', v_gym_id, '+216 93 001 009', true),
    (cl10, 'Client Test 10', 'client.test.10@trainw.local', 'client', v_gym_id, '+216 93 001 010', true),
    (cl11, 'Client Test 11', 'client.test.11@trainw.local', 'client', v_gym_id, '+216 93 001 011', true),
    (cl12, 'Client Test 12', 'client.test.12@trainw.local', 'client', v_gym_id, '+216 93 001 012', true),
    (cl13, 'Client Test 13', 'client.test.13@trainw.local', 'client', v_gym_id, '+216 93 001 013', true),
    (cl14, 'Client Test 14', 'client.test.14@trainw.local', 'client', v_gym_id, '+216 93 001 014', true),
    (cl15, 'Client Test 15', 'client.test.15@trainw.local', 'client', v_gym_id, '+216 93 001 015', true);

  -- ── INSERT 15 CLIENT PROFILES ─────────────────────────────────────────
  -- Variety: paid/unpaid, monthly/quarterly/annual/session, active/expiring/expired
  INSERT INTO public.client_profiles
    (user_id, membership_tier, fitness_goal, training_type, payment_status,
     age, membership_start_date, membership_end_date, price_paid) VALUES

    -- Active, paid, healthy memberships
    (cl1,  'monthly',    'Perte de poids',       'group_class',    'paid',    28,
      CURRENT_DATE - 10,  CURRENT_DATE + 20,  150),
    (cl2,  'quarterly',  'Prise de masse',        'individual',     'paid',    24,
      CURRENT_DATE - 45,  CURRENT_DATE + 45,  400),
    (cl3,  'annual',     'Endurance & Cardio',    'group_activity', 'paid',    35,
      CURRENT_DATE - 90,  CURRENT_DATE + 275, 1400),
    (cl5,  'quarterly',  'CrossFit & Force',      'individual',     'paid',    30,
      CURRENT_DATE - 20,  CURRENT_DATE + 70,  400),
    (cl6,  'annual',     'Yoga & Bien-être',      'group_class',    'paid',    38,
      CURRENT_DATE - 60,  CURRENT_DATE + 305, 1400),
    (cl8,  'annual',     'Performance sportive',  'individual',     'paid',    22,
      CURRENT_DATE - 120, CURRENT_DATE + 245, 1400),
    (cl11, 'monthly',    'Zumba & Danse',         'group_class',    'paid',    27,
      CURRENT_DATE - 8,   CURRENT_DATE + 22,  150),
    (cl13, 'annual',     'Rééducation',           'individual',     'paid',    50,
      CURRENT_DATE - 200, CURRENT_DATE + 165, 1400),
    (cl14, 'quarterly',  'Tennis & Sports',       'group_activity', 'paid',    29,
      CURRENT_DATE - 30,  CURRENT_DATE + 60,  400),

    -- Unpaid / pending
    (cl4,  'monthly',    'Remise en forme',       'group_class',    'pending', 42,
      CURRENT_DATE - 5,   CURRENT_DATE + 25,  0),
    (cl7,  'monthly',    'Perte de poids',        'group_class',    'pending', 26,
      CURRENT_DATE - 3,   CURRENT_DATE + 27,  0),
    (cl12, 'session',    'Boxe & Défense',        'individual',     'pending', 33,
      CURRENT_DATE - 1,   NULL,               0),

    -- Expiring soon (within 7 days)
    (cl9,  'monthly',    'Musculation',           'individual',     'paid',    31,
      CURRENT_DATE - 25,  CURRENT_DATE + 5,   150),
    (cl15, 'monthly',    'Remise en forme',       'group_class',    'paid',    36,
      CURRENT_DATE - 28,  CURRENT_DATE + 2,   150),

    -- Expired
    (cl10, 'quarterly',  'Natation & Cardio',     'group_activity', 'paid',    45,
      CURRENT_DATE - 95,  CURRENT_DATE - 5,   400);

  -- ── INSERT 35 SESSIONS ────────────────────────────────────────────────
  -- Status logic (indicative — the dashboard computes FULL / OPEN SPOTS
  -- from the real attendee_count, which the trigger derives from the
  -- session_enrollments seeded below, not from a hand-written number):
  --   completed  = past date
  --   confirmed  = future, expected full
  --   pending    = future, expected open spots

  INSERT INTO public.sessions
    (gym_id, coach_id, client_id, session_date, start_time,
     duration_minutes, type, session_name, status, capacity, notes)
  VALUES

  -- ── PAST — COMPLETED ─────────────────────────────────────────────────
  (v_gym_id, c1,  cl1,  CURRENT_DATE-21, '07:30:00', 60,  'group_class',        'CrossFit Endurance',      'completed', 12, 'CrossFit'),
  (v_gym_id, c2,  cl2,  CURRENT_DATE-19, '10:00:00', 90,  'individual_training','Séance Masse — Chest Day', 'completed',  1, 'Musculation'),
  (v_gym_id, c3,  cl6,  CURRENT_DATE-17, '09:00:00', 60,  'group_class',        'Yoga Débutant Matin',     'completed', 15, 'Yoga'),
  (v_gym_id, c4,  cl4,  CURRENT_DATE-15, '12:00:00', 45,  'group_class',        'HIIT Express Midi',       'completed', 10, 'HIIT'),
  (v_gym_id, c5,  cl8,  CURRENT_DATE-14, '06:30:00', 90,  'individual_training','Nage Libre — Technique',  'completed',  1, 'Natation'),
  (v_gym_id, c6,  cl12, CURRENT_DATE-12, '18:00:00', 60,  'group_class',        'Boxe Initiation',         'completed',  8, 'Boxe'),
  (v_gym_id, c10, cl11, CURRENT_DATE-10, '17:30:00', 60,  'group_activity',     'Zumba Party Vendredi',    'completed', 20, 'Zumba'),
  (v_gym_id, c7,  cl13, CURRENT_DATE-9,  '14:00:00', 60,  'individual_training','Bilan Nutritionnel Initial','completed', 1, 'Nutrition'),
  (v_gym_id, c11, cl14, CURRENT_DATE-8,  '10:00:00', 90,  'group_activity',     'Tennis Débutants',        'completed',  6, 'Tennis'),
  (v_gym_id, c3,  cl3,  CURRENT_DATE-7,  '09:30:00', 75,  'group_class',        'Yoga Intermédiaire',      'completed', 15, 'Yoga'),
  (v_gym_id, c2,  cl9,  CURRENT_DATE-5,  '16:00:00', 90,  'individual_training','Programme Squat & Deadlift','completed', 1, 'Musculation'),
  (v_gym_id, c1,  cl5,  CURRENT_DATE-4,  '07:00:00', 60,  'group_class',        'CrossFit AMRAP',          'completed', 10, 'CrossFit'),
  (v_gym_id, c8,  cl13, CURRENT_DATE-3,  '15:00:00', 60,  'individual_training','Rééducation Genou S3',    'completed',  1, 'Rééducation'),
  (v_gym_id, c4,  cl7,  CURRENT_DATE-2,  '11:00:00', 45,  'group_class',        'Cardio Brûle-Graisses',   'completed', 10, 'Cardio'),
  (v_gym_id, c9,  cl3,  CURRENT_DATE-1,  '10:00:00', 60,  'group_activity',     'Spinning Intensif',       'completed', 14, 'Cyclisme'),

  -- ── TODAY ─────────────────────────────────────────────────────────────
  (v_gym_id, c1,  cl1,  CURRENT_DATE, '07:00:00', 60,  'group_class',        'CrossFit Elite Matin',     'confirmed', 10, 'CrossFit'),  -- FULL
  (v_gym_id, c3,  cl6,  CURRENT_DATE, '09:00:00', 60,  'group_class',        'Yoga Flow Matinal',        'pending',   15, 'Yoga'),
  (v_gym_id, c4,  cl7,  CURRENT_DATE, '12:00:00', 45,  'group_class',        'HIIT Lunch Break',         'pending',    8, 'HIIT'),
  (v_gym_id, c10, cl11, CURRENT_DATE, '18:30:00', 60,  'group_activity',     'Zumba Soir',               'pending',   20, 'Zumba'),

  -- ── UPCOMING — FULL (confirmed) ───────────────────────────────────────
  (v_gym_id, c1,  cl2,  CURRENT_DATE+1,  '08:00:00', 60,  'group_class',        'CrossFit Strength',       'confirmed', 12, 'CrossFit'),
  (v_gym_id, c3,  cl3,  CURRENT_DATE+2,  '09:00:00', 60,  'group_class',        'Yoga Vinyasa Flow',       'confirmed', 15, 'Yoga'),
  (v_gym_id, c5,  cl8,  CURRENT_DATE+3,  '06:30:00', 90,  'individual_training','Coaching Nage Dos',       'confirmed',  1, 'Natation'),
  (v_gym_id, c1,  cl5,  CURRENT_DATE+5,  '07:30:00', 60,  'group_class',        'CrossFit Competition Prep','confirmed', 10, 'CrossFit'),
  (v_gym_id, c6,  cl12, CURRENT_DATE+6,  '18:00:00', 60,  'group_class',        'Boxe Avancé',             'confirmed',  8, 'Boxe'),

  -- ── UPCOMING — PARTIALLY BOOKED (pending) ────────────────────────────
  (v_gym_id, c2,  cl9,  CURRENT_DATE+1,  '10:00:00', 90,  'individual_training','Séance Force Max',         'pending',   1, 'Musculation'),
  (v_gym_id, c4,  cl4,  CURRENT_DATE+3,  '11:00:00', 45,  'group_class',        'Cardio Intense Mardi',    'pending',   10, 'Cardio'),
  (v_gym_id, c11, cl14, CURRENT_DATE+4,  '10:00:00', 90,  'group_activity',     'Tennis Intermédiaire',    'pending',    6, 'Tennis'),
  (v_gym_id, c10, cl11, CURRENT_DATE+5,  '18:30:00', 60,  'group_activity',     'Zumba Weekend',           'pending',   20, 'Zumba'),
  (v_gym_id, c7,  cl1,  CURRENT_DATE+7,  '11:00:00', 60,  'individual_training','Consultation Nutrition',  'pending',    1, 'Nutrition'),
  (v_gym_id, c14, cl8,  CURRENT_DATE+7,  '09:00:00', 90,  'individual_training','Prépa Physique Elite',    'pending',    1, 'Prépa Physique'),
  (v_gym_id, c3,  cl15, CURRENT_DATE+9,  '09:00:00', 60,  'group_class',        'Yoga Tous Niveaux',       'pending',   15, 'Yoga'),
  (v_gym_id, c9,  cl3,  CURRENT_DATE+10, '10:00:00', 60,  'group_activity',     'Cycling Power Session',   'pending',   12, 'Cyclisme'),
  (v_gym_id, c13, cl13, CURRENT_DATE+11, '15:00:00', 60,  'individual_training','Mobilité & Récupération', 'pending',    1, 'Stretching'),
  (v_gym_id, c15, cl10, CURRENT_DATE+14, '10:00:00', 60,  'group_class',        'Fitness Féminin — Reprise','pending',  10, 'Fitness');

  -- ── SEED ENROLLMENTS (attendee_count is computed from these) ───────
  -- DB-49: attendee_count is owned by sync_session_after_write /
  -- refresh_session_attendee_count (it counts session_enrollments, or 1
  -- for an individual session with a client). Hand-written counts are
  -- overwritten on the next write, so seed real enrollments instead:
  -- every session gets its own client first, group sessions get up to
  -- their capacity (capped at the 15 seeded clients).
  INSERT INTO public.session_enrollments (session_id, client_id, gym_id)
  SELECT s.id, c.user_id, v_gym_id
  FROM public.sessions s
  CROSS JOIN LATERAL (
    SELECT u.id AS user_id,
           ROW_NUMBER() OVER (
             ORDER BY CASE WHEN u.id = s.client_id THEN 0 ELSE 1 END,
                      u.created_at, u.id
           ) AS rn
    FROM public.users u
    WHERE u.gym_id = v_gym_id
      AND u.role = 'client'
      AND u.is_managed = true
  ) c
  WHERE s.gym_id = v_gym_id
    AND c.rn <= CASE
      WHEN s.type IN ('group_class', 'group_activity') THEN LEAST(s.capacity, 15)
      ELSE 1
    END
  ON CONFLICT (session_id, client_id) DO NOTHING;

  RAISE NOTICE '✅ Done. 15 coaches, 15 clients, 34 sessions inserted for gym %', v_gym_id;

END $$;


-- ── STEP 4: VERIFY ───────────────────────────────────────────────────────
SELECT
  (SELECT COUNT(*) FROM public.users WHERE role='coach' AND is_managed=true
    AND gym_id=current_setting('trainw.demo_gym_id', true)::uuid)  AS coaches_inserted,
  (SELECT COUNT(*) FROM public.users WHERE role='client' AND is_managed=true
    AND gym_id=current_setting('trainw.demo_gym_id', true)::uuid)  AS clients_inserted,
  (SELECT COUNT(*) FROM public.sessions
    WHERE gym_id=current_setting('trainw.demo_gym_id', true)::uuid) AS sessions_inserted;

-- ── STEP 5: SESSION BREAKDOWN (what you should see in the dashboard) ─────
SELECT
  status,
  COUNT(*)                                    AS count,
  SUM(attendee_count)                         AS total_attendees,
  ROUND(AVG(attendee_count::numeric / NULLIF(capacity,0) * 100), 1) AS avg_fill_pct
FROM public.sessions
WHERE gym_id = current_setting('trainw.demo_gym_id', true)::uuid
GROUP BY status
ORDER BY status;