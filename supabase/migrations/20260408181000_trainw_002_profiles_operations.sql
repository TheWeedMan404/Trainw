-- ============================================================================
-- TRAINW V16 PRODUCTION - PROFILES AND OPERATIONS
-- Purpose:
--   - Create and normalize coach/client/profile-side tables
--   - Add communication, workout, check-in, and gate-access structures
--   - Create helper functions used by RLS and app flows
--   - Keep compatibility with the existing V14 frontend and RPC callers
-- ============================================================================

-- ----------------------------------------------------------------------------
-- USER PROFILES
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.coach_profiles (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id             uuid REFERENCES public.gyms(id) ON DELETE SET NULL,
  specialty          text,
  specialties        text[],
  experience_years   integer,
  sessions_completed integer NOT NULL DEFAULT 0,
  hourly_rate        numeric(10,2),
  price_per_session  numeric(10,2),
  certifications     text[],
  bio                text,
  rating             numeric(4,2) NOT NULL DEFAULT 0,
  total_reviews      integer NOT NULL DEFAULT 0,
  approval_status    text NOT NULL DEFAULT 'approved',
  approved_at        timestamptz,
  approved_by        uuid,
  is_active          boolean NOT NULL DEFAULT true,
  instagram_url      text,
  whatsapp_number    text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.coach_profiles
  ADD COLUMN IF NOT EXISTS user_id            uuid,
  ADD COLUMN IF NOT EXISTS gym_id             uuid,
  ADD COLUMN IF NOT EXISTS specialty          text,
  ADD COLUMN IF NOT EXISTS specialties        text[],
  ADD COLUMN IF NOT EXISTS experience_years   integer,
  ADD COLUMN IF NOT EXISTS sessions_completed integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hourly_rate        numeric(10,2),
  ADD COLUMN IF NOT EXISTS price_per_session  numeric(10,2),
  ADD COLUMN IF NOT EXISTS certifications     text[],
  ADD COLUMN IF NOT EXISTS bio                text,
  ADD COLUMN IF NOT EXISTS rating             numeric(4,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_reviews      integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS approval_status    text NOT NULL DEFAULT 'approved',
  ADD COLUMN IF NOT EXISTS approved_at        timestamptz,
  ADD COLUMN IF NOT EXISTS approved_by        uuid,
  ADD COLUMN IF NOT EXISTS is_active          boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS instagram_url      text,
  ADD COLUMN IF NOT EXISTS whatsapp_number    text,
  ADD COLUMN IF NOT EXISTS created_at         timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at         timestamptz NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS public.specialty_tags (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        citext NOT NULL UNIQUE,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.coach_specialties (
  coach_user_id  uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  specialty_id   uuid NOT NULL REFERENCES public.specialty_tags(id) ON DELETE CASCADE,
  gym_id         uuid REFERENCES public.gyms(id) ON DELETE CASCADE,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (coach_user_id, specialty_id)
);

ALTER TABLE public.coach_specialties
  ADD COLUMN IF NOT EXISTS gym_id uuid;

CREATE TABLE IF NOT EXISTS public.client_profiles (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id                 uuid REFERENCES public.gyms(id) ON DELETE SET NULL,
  coach_id               uuid,
  membership_tier        text NOT NULL DEFAULT 'basic',
  fitness_goal           text,
  height_cm              numeric(6,2),
  weight_kg              numeric(6,2),
  body_fat_pct           numeric(5,2),
  goal_weight_kg         numeric(6,2),
  payment_status         text NOT NULL DEFAULT 'pending',
  sessions_completed     integer NOT NULL DEFAULT 0,
  active_plan            text,
  progress_notes         text,
  age                    integer,
  training_type          text,
  extra_classes          text,
  membership_start_date  date,
  membership_end_date    date,
  price_paid             numeric(12,2) NOT NULL DEFAULT 0,
  membership_notes       text,
  experience_level       text NOT NULL DEFAULT 'beginner',
  notes                  text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.client_profiles
  ADD COLUMN IF NOT EXISTS user_id                uuid,
  ADD COLUMN IF NOT EXISTS gym_id                 uuid,
  ADD COLUMN IF NOT EXISTS coach_id               uuid,
  ADD COLUMN IF NOT EXISTS membership_tier        text NOT NULL DEFAULT 'basic',
  ADD COLUMN IF NOT EXISTS fitness_goal           text,
  ADD COLUMN IF NOT EXISTS height_cm              numeric(6,2),
  ADD COLUMN IF NOT EXISTS weight_kg              numeric(6,2),
  ADD COLUMN IF NOT EXISTS body_fat_pct           numeric(5,2),
  ADD COLUMN IF NOT EXISTS goal_weight_kg         numeric(6,2),
  ADD COLUMN IF NOT EXISTS payment_status         text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS sessions_completed     integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS active_plan            text,
  ADD COLUMN IF NOT EXISTS progress_notes         text,
  ADD COLUMN IF NOT EXISTS age                    integer,
  ADD COLUMN IF NOT EXISTS training_type          text,
  ADD COLUMN IF NOT EXISTS extra_classes          text,
  ADD COLUMN IF NOT EXISTS membership_start_date  date,
  ADD COLUMN IF NOT EXISTS membership_end_date    date,
  ADD COLUMN IF NOT EXISTS price_paid             numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS membership_notes       text,
  ADD COLUMN IF NOT EXISTS experience_level       text NOT NULL DEFAULT 'beginner',
  ADD COLUMN IF NOT EXISTS notes                  text,
  ADD COLUMN IF NOT EXISTS created_at             timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at             timestamptz NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS public.coach_client_assignments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id      uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  client_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id        uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  assigned_by   uuid REFERENCES public.users(id) ON DELETE SET NULL,
  notes         text,
  assigned_at   timestamptz NOT NULL DEFAULT now(),
  ended_at      timestamptz,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.coach_client_assignments
  ADD COLUMN IF NOT EXISTS assigned_by uuid,
  ADD COLUMN IF NOT EXISTS notes       text,
  ADD COLUMN IF NOT EXISTS ended_at    timestamptz,
  ADD COLUMN IF NOT EXISTS created_at  timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at  timestamptz NOT NULL DEFAULT now();


-- ----------------------------------------------------------------------------
-- COMMUNICATION AND GYM STRUCTURE
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.messages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id        uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  sender_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  receiver_id   uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content       text NOT NULL,
  is_read       boolean NOT NULL DEFAULT false,
  is_automated  boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.gym_classes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id            uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  created_by        uuid REFERENCES public.users(id) ON DELETE SET NULL,
  coach_id          uuid REFERENCES public.users(id) ON DELETE SET NULL,
  name              text NOT NULL,
  description       text,
  schedule_day      text,
  start_time        time,
  duration_minutes  integer NOT NULL DEFAULT 60,
  capacity          integer NOT NULL DEFAULT 20,
  is_active         boolean NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.gym_classes
  ADD COLUMN IF NOT EXISTS created_by        uuid,
  ADD COLUMN IF NOT EXISTS coach_id          uuid,
  ADD COLUMN IF NOT EXISTS description       text,
  ADD COLUMN IF NOT EXISTS schedule_day      text,
  ADD COLUMN IF NOT EXISTS start_time        time,
  ADD COLUMN IF NOT EXISTS duration_minutes  integer NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS capacity          integer NOT NULL DEFAULT 20,
  ADD COLUMN IF NOT EXISTS is_active         boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at        timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at        timestamptz NOT NULL DEFAULT now();


-- ----------------------------------------------------------------------------
-- BODY METRICS AND PROGRAMMING
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.weight_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id          uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  logged_by       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  weight_kg       numeric(6,2) NOT NULL,
  body_fat_pct    numeric(5,2),
  muscle_mass_kg  numeric(6,2),
  notes           text,
  logged_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workout_plans (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id              uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  created_by          uuid REFERENCES public.users(id) ON DELETE SET NULL,
  client_id           uuid REFERENCES public.users(id) ON DELETE CASCADE,
  title               text NOT NULL,
  goal                text,
  frequency_per_week  integer,
  description         text,
  is_template         boolean NOT NULL DEFAULT false,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workout_exercises (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id        uuid NOT NULL REFERENCES public.workout_plans(id) ON DELETE CASCADE,
  day_label      text,
  exercise_name  text NOT NULL,
  sets           integer,
  reps           text,
  rest_seconds   integer,
  notes          text,
  order_index    integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.workout_logs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id         uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id            uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  plan_id           uuid REFERENCES public.workout_plans(id) ON DELETE SET NULL,
  logged_by         uuid REFERENCES public.users(id) ON DELETE SET NULL,
  completed_at      timestamptz NOT NULL DEFAULT now(),
  duration_minutes  integer,
  notes             text,
  perceived_effort  integer
);

CREATE TABLE IF NOT EXISTS public.workout_log_sets (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  log_id         uuid NOT NULL REFERENCES public.workout_logs(id) ON DELETE CASCADE,
  exercise_name  text NOT NULL,
  set_number     integer,
  reps_done      integer,
  weight_kg      numeric(6,2),
  notes          text
);

CREATE TABLE IF NOT EXISTS public.client_goals (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id         uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id            uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  goal_type         text,
  target_weight_kg  numeric(6,2),
  target_date       date,
  notes             text,
  created_at        timestamptz NOT NULL DEFAULT now()
);


-- ----------------------------------------------------------------------------
-- ACCESS AND CHECK-IN
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.check_ins (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id             uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  client_id          uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_by         uuid REFERENCES public.users(id) ON DELETE SET NULL,
  source_session_id  uuid,
  checked_in_at      timestamptz NOT NULL DEFAULT now(),
  method             text NOT NULL DEFAULT 'manual',
  notes              text
);

ALTER TABLE public.check_ins
  ADD COLUMN IF NOT EXISTS created_by        uuid,
  ADD COLUMN IF NOT EXISTS source_session_id uuid,
  ADD COLUMN IF NOT EXISTS notes             text;

CREATE TABLE IF NOT EXISTS public.gate_sessions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id   uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id      uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  token       text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  used        boolean NOT NULL DEFAULT false,
  used_at     timestamptz
);

ALTER TABLE public.gate_sessions
  ADD COLUMN IF NOT EXISTS used_at timestamptz;


-- ----------------------------------------------------------------------------
-- DATA BACKFILL AND NORMALIZATION
-- ----------------------------------------------------------------------------

UPDATE public.coach_profiles cp
SET
  user_id = COALESCE(cp.user_id, cp.id),
  gym_id = COALESCE(cp.gym_id, u.gym_id),
  specialty = NULLIF(BTRIM(cp.specialty), ''),
  specialties = COALESCE(
    cp.specialties,
    CASE
      WHEN NULLIF(BTRIM(cp.specialty), '') IS NULL THEN NULL
      ELSE string_to_array(regexp_replace(BTRIM(cp.specialty), '\s*,\s*', ',', 'g'), ',')
    END
  ),
  experience_years = CASE
    WHEN cp.experience_years IS NOT NULL AND cp.experience_years < 0 THEN NULL
    ELSE cp.experience_years
  END,
  hourly_rate = CASE
    WHEN cp.hourly_rate IS NOT NULL AND cp.hourly_rate < 0 THEN NULL
    ELSE cp.hourly_rate
  END,
  price_per_session = COALESCE(
    CASE WHEN cp.price_per_session IS NOT NULL AND cp.price_per_session >= 0 THEN cp.price_per_session END,
    CASE WHEN cp.hourly_rate IS NOT NULL AND cp.hourly_rate >= 0 THEN cp.hourly_rate END
  ),
  rating = GREATEST(COALESCE(cp.rating, 0), 0),
  total_reviews = GREATEST(COALESCE(cp.total_reviews, 0), 0),
  approval_status = COALESCE(NULLIF(lower(BTRIM(cp.approval_status)), ''), CASE WHEN COALESCE(cp.is_active, true) THEN 'approved' ELSE 'pending' END),
  approved_at = COALESCE(cp.approved_at, CASE WHEN COALESCE(cp.is_active, true) THEN COALESCE(cp.updated_at, cp.created_at, now()) END),
  is_active = COALESCE(cp.is_active, true),
  created_at = COALESCE(cp.created_at, now()),
  updated_at = COALESCE(cp.updated_at, now())
FROM public.users u
WHERE u.id = COALESCE(cp.user_id, cp.id);

UPDATE public.coach_profiles
SET approval_status = CASE
  WHEN approval_status IN ('pending', 'approved', 'rejected') THEN approval_status
  ELSE 'approved'
END;

INSERT INTO public.coach_profiles (user_id, gym_id, specialty, specialties, approval_status, approved_at, is_active)
SELECT
  u.id,
  u.gym_id,
  NULL,
  NULL,
  'approved',
  now(),
  true
FROM public.users u
WHERE u.role = 'coach'
  AND NOT EXISTS (
    SELECT 1
    FROM public.coach_profiles cp
    WHERE cp.user_id = u.id
  );

DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN
    SELECT user_id
    FROM public.coach_profiles
    WHERE user_id IS NOT NULL
    GROUP BY user_id
    HAVING COUNT(*) > 1
  LOOP
    DELETE FROM public.coach_profiles cp
    WHERE cp.user_id = rec.user_id
      AND cp.id <> (
        SELECT cp_keep.id
        FROM public.coach_profiles cp_keep
        WHERE cp_keep.user_id = rec.user_id
        ORDER BY COALESCE(cp_keep.updated_at, cp_keep.created_at, now()) DESC, cp_keep.id DESC
        LIMIT 1
      );
  END LOOP;
END $$;

UPDATE public.client_profiles
SET
  membership_tier = COALESCE(NULLIF(lower(BTRIM(membership_tier)), ''), 'basic'),
  payment_status = COALESCE(NULLIF(lower(BTRIM(payment_status)), ''), 'pending'),
  experience_level = COALESCE(NULLIF(lower(BTRIM(experience_level)), ''), 'beginner'),
  notes = COALESCE(notes, membership_notes),
  price_paid = GREATEST(COALESCE(price_paid, 0), 0),
  age = CASE WHEN age BETWEEN 10 AND 120 THEN age ELSE NULL END,
  body_fat_pct = CASE WHEN body_fat_pct BETWEEN 0 AND 100 THEN body_fat_pct ELSE NULL END,
  created_at = COALESCE(created_at, now()),
  updated_at = COALESCE(updated_at, now())
WHERE true;

UPDATE public.client_profiles
SET membership_tier = CASE
  WHEN membership_tier IN ('basic', 'monthly', 'quarterly', 'annual', 'session', 'trial', 'custom') THEN membership_tier
  ELSE 'basic'
END;

UPDATE public.client_profiles
SET payment_status = CASE
  WHEN payment_status IN ('pending', 'paid', 'overdue', 'cancelled', 'trial', 'waived', 'refunded') THEN payment_status
  ELSE 'pending'
END;

UPDATE public.client_profiles
SET experience_level = CASE
  WHEN experience_level IN ('beginner', 'intermediate', 'advanced', 'elite') THEN experience_level
  ELSE 'beginner'
END;

INSERT INTO public.client_profiles (user_id, membership_tier, payment_status, experience_level)
SELECT
  u.id,
  'basic',
  'pending',
  'beginner'
FROM public.users u
WHERE u.role = 'client'
  AND NOT EXISTS (
    SELECT 1
    FROM public.client_profiles cp
    WHERE cp.user_id = u.id
  );

DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN
    SELECT user_id
    FROM public.client_profiles
    WHERE user_id IS NOT NULL
    GROUP BY user_id
    HAVING COUNT(*) > 1
  LOOP
    DELETE FROM public.client_profiles cp
    WHERE cp.user_id = rec.user_id
      AND cp.id <> (
        SELECT cp_keep.id
        FROM public.client_profiles cp_keep
        WHERE cp_keep.user_id = rec.user_id
        ORDER BY COALESCE(cp_keep.updated_at, cp_keep.created_at, now()) DESC, cp_keep.id DESC
        LIMIT 1
      );
  END LOOP;
END $$;

INSERT INTO public.specialty_tags (name)
SELECT DISTINCT TRIM(s.name_part)
FROM (
  SELECT unnest(COALESCE(cp.specialties, ARRAY[]::text[])) AS name_part
  FROM public.coach_profiles cp
  UNION ALL
  SELECT cp.specialty
  FROM public.coach_profiles cp
) AS s
WHERE TRIM(COALESCE(s.name_part, '')) <> ''
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.coach_specialties (coach_user_id, specialty_id, gym_id)
SELECT DISTINCT
  cp.user_id,
  st.id,
  COALESCE(cp.gym_id, u.gym_id)
FROM public.coach_profiles cp
JOIN public.users u
  ON u.id = cp.user_id
JOIN LATERAL (
  SELECT TRIM(value_item) AS normalized_name
  FROM unnest(
    COALESCE(cp.specialties, ARRAY[]::text[]) ||
    CASE
      WHEN NULLIF(BTRIM(cp.specialty), '') IS NULL THEN ARRAY[]::text[]
      ELSE ARRAY[cp.specialty]
    END
  ) AS value_item
) AS names ON names.normalized_name <> ''
JOIN public.specialty_tags st
  ON st.name = names.normalized_name
ON CONFLICT (coach_user_id, specialty_id) DO NOTHING;

UPDATE public.coach_client_assignments
SET
  is_active = COALESCE(is_active, true),
  created_at = COALESCE(created_at, assigned_at, now()),
  updated_at = COALESCE(updated_at, assigned_at, now()),
  assigned_at = COALESCE(assigned_at, created_at, now()),
  ended_at = CASE WHEN COALESCE(is_active, true) = false THEN COALESCE(ended_at, now()) ELSE ended_at END;

WITH ranked_assignments AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY coach_id, client_id, gym_id
      ORDER BY is_active DESC, assigned_at DESC, id DESC
    ) AS rn
  FROM public.coach_client_assignments
)
UPDATE public.coach_client_assignments a
SET is_active = false,
    ended_at = COALESCE(a.ended_at, now()),
    updated_at = now()
FROM ranked_assignments r
WHERE a.id = r.id
  AND r.rn > 1
  AND a.is_active = true;

UPDATE public.messages
SET content = BTRIM(content)
WHERE content IS NOT NULL;

UPDATE public.gym_classes
SET
  duration_minutes = GREATEST(COALESCE(duration_minutes, 60), 15),
  capacity = GREATEST(COALESCE(capacity, 20), 1),
  is_active = COALESCE(is_active, true),
  created_at = COALESCE(created_at, now()),
  updated_at = COALESCE(updated_at, now());

UPDATE public.weight_logs
SET body_fat_pct = CASE WHEN body_fat_pct BETWEEN 0 AND 100 THEN body_fat_pct ELSE NULL END
WHERE body_fat_pct IS NOT NULL;

UPDATE public.workout_plans
SET
  frequency_per_week = CASE
    WHEN frequency_per_week BETWEEN 1 AND 14 THEN frequency_per_week
    ELSE NULL
  END,
  created_at = COALESCE(created_at, now()),
  updated_at = COALESCE(updated_at, now());

UPDATE public.gate_sessions
SET
  token = BTRIM(token),
  used = COALESCE(used, false),
  used_at = CASE WHEN used = true THEN COALESCE(used_at, now()) ELSE used_at END
WHERE token IS NOT NULL;

WITH ranked_gate_tokens AS (
  SELECT
    id,
    ROW_NUMBER() OVER (PARTITION BY token ORDER BY created_at DESC, id DESC) AS rn
  FROM public.gate_sessions
  WHERE token IS NOT NULL
)
UPDATE public.gate_sessions gs
SET token = gs.token || '.dup.' || left(gs.id::text, 8)
FROM ranked_gate_tokens r
WHERE gs.id = r.id
  AND r.rn > 1;


-- ----------------------------------------------------------------------------
-- SAFETY CONSTRAINTS
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.coach_profiles'::regclass
      AND conname = 'coach_profiles_approval_status_check'
  ) THEN
    ALTER TABLE public.coach_profiles
      ADD CONSTRAINT coach_profiles_approval_status_check
      CHECK (approval_status IN ('pending', 'approved', 'rejected'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.coach_profiles'::regclass
      AND conname = 'coach_profiles_rating_range_check'
  ) THEN
    ALTER TABLE public.coach_profiles
      ADD CONSTRAINT coach_profiles_rating_range_check
      CHECK (rating BETWEEN 0 AND 5);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.client_profiles'::regclass
      AND conname = 'client_profiles_membership_tier_check'
  ) THEN
    ALTER TABLE public.client_profiles
      ADD CONSTRAINT client_profiles_membership_tier_check
      CHECK (membership_tier IN ('basic', 'monthly', 'quarterly', 'annual', 'session', 'trial', 'custom'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.client_profiles'::regclass
      AND conname = 'client_profiles_payment_status_check'
  ) THEN
    ALTER TABLE public.client_profiles
      ADD CONSTRAINT client_profiles_payment_status_check
      CHECK (payment_status IN ('pending', 'paid', 'overdue', 'cancelled', 'trial', 'waived', 'refunded'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.client_profiles'::regclass
      AND conname = 'client_profiles_experience_level_check'
  ) THEN
    ALTER TABLE public.client_profiles
      ADD CONSTRAINT client_profiles_experience_level_check
      CHECK (experience_level IN ('beginner', 'intermediate', 'advanced', 'elite'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.client_profiles'::regclass
      AND conname = 'client_profiles_membership_dates_check'
  ) THEN
    ALTER TABLE public.client_profiles
      ADD CONSTRAINT client_profiles_membership_dates_check
      CHECK (
        membership_end_date IS NULL
        OR membership_start_date IS NULL
        OR membership_end_date >= membership_start_date
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.messages'::regclass
      AND conname = 'messages_sender_receiver_check'
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_sender_receiver_check
      CHECK (sender_id <> receiver_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.weight_logs'::regclass
      AND conname = 'weight_logs_positive_weight_check'
  ) THEN
    ALTER TABLE public.weight_logs
      ADD CONSTRAINT weight_logs_positive_weight_check
      CHECK (weight_kg > 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.weight_logs'::regclass
      AND conname = 'weight_logs_body_fat_range_check'
  ) THEN
    ALTER TABLE public.weight_logs
      ADD CONSTRAINT weight_logs_body_fat_range_check
      CHECK (body_fat_pct IS NULL OR body_fat_pct BETWEEN 0 AND 100);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.workout_plans'::regclass
      AND conname = 'workout_plans_frequency_check'
  ) THEN
    ALTER TABLE public.workout_plans
      ADD CONSTRAINT workout_plans_frequency_check
      CHECK (frequency_per_week IS NULL OR frequency_per_week BETWEEN 1 AND 14);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.workout_exercises'::regclass
      AND conname = 'workout_exercises_sets_check'
  ) THEN
    ALTER TABLE public.workout_exercises
      ADD CONSTRAINT workout_exercises_sets_check
      CHECK (sets IS NULL OR sets > 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.workout_exercises'::regclass
      AND conname = 'workout_exercises_rest_check'
  ) THEN
    ALTER TABLE public.workout_exercises
      ADD CONSTRAINT workout_exercises_rest_check
      CHECK (rest_seconds IS NULL OR rest_seconds >= 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.workout_logs'::regclass
      AND conname = 'workout_logs_effort_check'
  ) THEN
    ALTER TABLE public.workout_logs
      ADD CONSTRAINT workout_logs_effort_check
      CHECK (perceived_effort IS NULL OR perceived_effort BETWEEN 1 AND 10);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.workout_log_sets'::regclass
      AND conname = 'workout_log_sets_set_number_check'
  ) THEN
    ALTER TABLE public.workout_log_sets
      ADD CONSTRAINT workout_log_sets_set_number_check
      CHECK (set_number IS NULL OR set_number > 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.workout_log_sets'::regclass
      AND conname = 'workout_log_sets_reps_check'
  ) THEN
    ALTER TABLE public.workout_log_sets
      ADD CONSTRAINT workout_log_sets_reps_check
      CHECK (reps_done IS NULL OR reps_done >= 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.check_ins'::regclass
      AND conname = 'check_ins_method_check'
  ) THEN
    ALTER TABLE public.check_ins
      ADD CONSTRAINT check_ins_method_check
      CHECK (method IN ('manual', 'qr', 'qr_gate', 'system'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.gate_sessions'::regclass
      AND conname = 'gate_sessions_expiry_check'
  ) THEN
    ALTER TABLE public.gate_sessions
      ADD CONSTRAINT gate_sessions_expiry_check
      CHECK (expires_at > created_at);
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- HELPER FUNCTIONS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_my_gym_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT gym_id
  FROM public.users
  WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role
  FROM public.users
  WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_signup_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT COALESCE(raw_user_meta_data->>'role', raw_app_meta_data->>'role')
  FROM auth.users
  WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.user_gym_id(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT gym_id
  FROM public.users
  WHERE id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION public.user_role(p_user_id uuid)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role
  FROM public.users
  WHERE id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION public.is_gym_manager()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT COALESCE(public.get_my_role(), public.get_signup_role()) IN ('gym_owner', 'gym', 'admin');
$$;

CREATE OR REPLACE FUNCTION public.manages_gym(p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT p_gym_id IS NOT NULL
     AND public.is_gym_manager()
     AND public.get_my_gym_id() = p_gym_id;
$$;

CREATE OR REPLACE FUNCTION public.is_same_gym_user(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT p_user_id IS NOT NULL
     AND public.user_gym_id(p_user_id) IS NOT NULL
     AND public.user_gym_id(p_user_id) = public.get_my_gym_id();
$$;

CREATE OR REPLACE FUNCTION public.can_manage_client_data(p_client_id uuid, p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN false
    WHEN p_client_id IS NULL OR p_gym_id IS NULL THEN false
    WHEN p_gym_id <> public.get_my_gym_id() THEN false
    WHEN public.is_gym_manager() THEN public.user_gym_id(p_client_id) = p_gym_id
    WHEN public.get_my_role() = 'coach' THEN EXISTS (
      SELECT 1
      FROM public.coach_client_assignments cca
      WHERE cca.coach_id = auth.uid()
        AND cca.client_id = p_client_id
        AND cca.gym_id = p_gym_id
        AND cca.is_active = true
    )
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION public.can_view_user(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = p_user_id
      AND (
        u.id = auth.uid()
        OR public.manages_gym(u.gym_id)
        OR (
          public.get_my_role() = 'coach'
          AND (
            (u.role IN ('gym_owner', 'gym', 'admin') AND u.gym_id = public.get_my_gym_id())
            OR public.can_manage_client_data(u.id, u.gym_id)
          )
        )
        OR (
          public.get_my_role() = 'client'
          AND u.gym_id = public.get_my_gym_id()
          AND (
            u.role IN ('gym_owner', 'gym', 'admin')
            OR EXISTS (
              SELECT 1
              FROM public.coach_client_assignments cca
              WHERE cca.client_id = auth.uid()
                AND cca.coach_id = u.id
                AND cca.gym_id = public.get_my_gym_id()
                AND cca.is_active = true
            )
          )
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_message_user(p_other_user_id uuid, p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN false
    WHEN p_other_user_id IS NULL OR p_gym_id IS NULL THEN false
    WHEN p_gym_id <> public.get_my_gym_id() THEN false
    WHEN public.user_gym_id(p_other_user_id) <> p_gym_id THEN false
    WHEN public.is_gym_manager() THEN true
    WHEN public.get_my_role() = 'coach' THEN EXISTS (
      SELECT 1
      FROM public.coach_client_assignments cca
      WHERE cca.coach_id = auth.uid()
        AND cca.client_id = p_other_user_id
        AND cca.gym_id = p_gym_id
        AND cca.is_active = true
    )
    WHEN public.get_my_role() = 'client' THEN (
      EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = p_other_user_id
          AND u.gym_id = p_gym_id
          AND u.role IN ('gym_owner', 'gym', 'admin')
      )
      OR EXISTS (
        SELECT 1
        FROM public.coach_client_assignments cca
        WHERE cca.client_id = auth.uid()
          AND cca.coach_id = p_other_user_id
          AND cca.gym_id = p_gym_id
          AND cca.is_active = true
      )
    )
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION public.can_read_workout_plan(p_plan_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.can_write_workout_plan(p_plan_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.can_read_workout_log(p_log_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.workout_logs wl
    WHERE wl.id = p_log_id
      AND (
        wl.client_id = auth.uid()
        OR public.can_manage_client_data(wl.client_id, wl.gym_id)
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_write_workout_log(p_log_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.workout_logs wl
    WHERE wl.id = p_log_id
      AND (
        wl.client_id = auth.uid()
        OR public.can_manage_client_data(wl.client_id, wl.gym_id)
      )
  );
$$;


-- ----------------------------------------------------------------------------
-- AUTH SIGNUP TRIGGER
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_role      text;
  v_gym_id    uuid;
  v_name      text;
  v_phone     text;
  v_gym_name  text;
BEGIN
  v_role := COALESCE(NULLIF(lower(BTRIM(NEW.raw_user_meta_data->>'role')), ''), 'client');
  IF v_role NOT IN ('client', 'coach', 'gym_owner', 'gym', 'admin') THEN
    v_role := 'client';
  END IF;

  v_name := COALESCE(NULLIF(BTRIM(NEW.raw_user_meta_data->>'name'), ''), 'User');
  v_phone := NULLIF(BTRIM(NEW.raw_user_meta_data->>'phone'), '');
  v_gym_name := NULLIF(BTRIM(NEW.raw_user_meta_data->>'gym_name'), '');
  v_gym_id := NULL;

  IF NULLIF(BTRIM(NEW.raw_user_meta_data->>'gym_id'), '') IS NOT NULL THEN
    BEGIN
      v_gym_id := (NEW.raw_user_meta_data->>'gym_id')::uuid;
    EXCEPTION
      WHEN OTHERS THEN
        v_gym_id := NULL;
    END;
  END IF;

  IF v_role IN ('gym_owner', 'gym', 'admin') AND v_gym_id IS NULL THEN
    INSERT INTO public.gyms (name, email, owner_name, is_active)
    VALUES (
      COALESCE(v_gym_name, 'My Gym'),
      NULLIF(lower(BTRIM(NEW.email)), ''),
      v_name,
      true
    )
    RETURNING id INTO v_gym_id;
  END IF;

  INSERT INTO public.users (
    id, name, email, role, gym_id, phone, language_preference, is_managed, is_active
  )
  VALUES (
    NEW.id,
    v_name,
    NULLIF(lower(BTRIM(NEW.email)), ''),
    v_role,
    v_gym_id,
    v_phone,
    COALESCE(NULLIF(lower(BTRIM(NEW.raw_user_meta_data->>'language_preference')), ''), 'fr'),
    false,
    true
  )
  ON CONFLICT (id) DO UPDATE
  SET
    name = COALESCE(NULLIF(EXCLUDED.name, ''), public.users.name),
    email = COALESCE(public.users.email, EXCLUDED.email),
    role = COALESCE(NULLIF(public.users.role, ''), EXCLUDED.role),
    gym_id = COALESCE(public.users.gym_id, EXCLUDED.gym_id),
    phone = COALESCE(public.users.phone, EXCLUDED.phone),
    language_preference = COALESCE(public.users.language_preference, EXCLUDED.language_preference),
    updated_at = now();

  IF v_gym_id IS NOT NULL AND v_role IN ('gym_owner', 'gym', 'admin') THEN
    UPDATE public.gyms
    SET manager_id = COALESCE(manager_id, NEW.id)
    WHERE id = v_gym_id;
  END IF;

  IF v_role = 'coach'
     AND NOT EXISTS (
       SELECT 1
       FROM public.coach_profiles cp
       WHERE cp.user_id = NEW.id
     ) THEN
    INSERT INTO public.coach_profiles (
      user_id, gym_id, specialty, specialties, is_active, approval_status, approved_at
    )
    VALUES (
      NEW.id,
      v_gym_id,
      NULLIF(BTRIM(NEW.raw_user_meta_data->>'specialty'), ''),
      CASE
        WHEN NULLIF(BTRIM(NEW.raw_user_meta_data->>'specialty'), '') IS NULL THEN NULL
        ELSE ARRAY[NULLIF(BTRIM(NEW.raw_user_meta_data->>'specialty'), '')]
      END,
      true,
      CASE WHEN v_gym_id IS NULL THEN 'pending' ELSE 'approved' END,
      CASE WHEN v_gym_id IS NULL THEN NULL ELSE now() END
    );
  ELSIF v_role = 'client'
     AND NOT EXISTS (
       SELECT 1
       FROM public.client_profiles cp
       WHERE cp.user_id = NEW.id
     ) THEN
    INSERT INTO public.client_profiles (
      user_id, membership_tier, payment_status, experience_level
    )
    VALUES (
      NEW.id,
      'basic',
      'pending',
      'beginner'
    );
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG 'handle_new_user error for %: % - %', NEW.id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ----------------------------------------------------------------------------
-- UPDATED_AT TRIGGERS
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'coach_profiles',
    'client_profiles',
    'coach_client_assignments',
    'gym_classes',
    'workout_plans'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_upd ON public.%I', table_name, table_name);
    EXECUTE format(
      'CREATE TRIGGER trg_%s_upd BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()',
      table_name,
      table_name
    );
  END LOOP;
END $$;


-- ----------------------------------------------------------------------------
-- INDEXES
-- ----------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_coach_profiles_user_id
  ON public.coach_profiles(user_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_client_profiles_user_id
  ON public.client_profiles(user_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_assignments_active_pair
  ON public.coach_client_assignments(coach_id, client_id, gym_id)
  WHERE is_active = true;

CREATE UNIQUE INDEX IF NOT EXISTS uq_gate_sessions_token
  ON public.gate_sessions(token);

CREATE INDEX IF NOT EXISTS idx_coach_profiles_gym_status
  ON public.coach_profiles(gym_id, approval_status, is_active);

CREATE INDEX IF NOT EXISTS idx_coach_profiles_rating
  ON public.coach_profiles(rating DESC, total_reviews DESC);

CREATE INDEX IF NOT EXISTS idx_coach_specialties_gym
  ON public.coach_specialties(gym_id, coach_user_id);

CREATE INDEX IF NOT EXISTS idx_client_profiles_membership
  ON public.client_profiles(payment_status, membership_end_date);

CREATE INDEX IF NOT EXISTS idx_assignments_client
  ON public.coach_client_assignments(client_id, is_active);

CREATE INDEX IF NOT EXISTS idx_assignments_coach
  ON public.coach_client_assignments(coach_id, is_active);

CREATE INDEX IF NOT EXISTS idx_messages_participants
  ON public.messages(gym_id, sender_id, receiver_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_gym_classes_gym_active
  ON public.gym_classes(gym_id, is_active, start_time);

CREATE INDEX IF NOT EXISTS idx_weight_logs_client_logged_at
  ON public.weight_logs(client_id, logged_at DESC);

CREATE INDEX IF NOT EXISTS idx_weight_logs_gym_logged_at
  ON public.weight_logs(gym_id, logged_at DESC);

CREATE INDEX IF NOT EXISTS idx_workout_plans_client_updated_at
  ON public.workout_plans(client_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_workout_plans_creator_updated_at
  ON public.workout_plans(created_by, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_workout_exercises_plan_order
  ON public.workout_exercises(plan_id, order_index);

CREATE INDEX IF NOT EXISTS idx_workout_logs_client_completed_at
  ON public.workout_logs(client_id, completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_workout_log_sets_log
  ON public.workout_log_sets(log_id, set_number);

CREATE INDEX IF NOT EXISTS idx_client_goals_client_created_at
  ON public.client_goals(client_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_check_ins_client_checked_in_at
  ON public.check_ins(client_id, checked_in_at DESC);

CREATE INDEX IF NOT EXISTS idx_check_ins_gym_checked_in_at
  ON public.check_ins(gym_id, checked_in_at DESC);

CREATE INDEX IF NOT EXISTS idx_gate_sessions_client_expiry
  ON public.gate_sessions(client_id, expires_at DESC);

CREATE INDEX IF NOT EXISTS idx_gate_sessions_gym_expiry
  ON public.gate_sessions(gym_id, expires_at DESC);
