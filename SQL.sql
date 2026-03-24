-- =====================================================
-- TRAINW — COMPLETE DATABASE SETUP v3
-- Run this on a CLEAN Supabase project (nuclear reset)
-- Fixes: table names match JS (coach_profiles/client_profiles)
--        description on gyms, fitness_goal on clients
--        measurement columns on clients
--        sessions_insert allows clients
--        indexes on sessions
--        updated_at on key tables
-- =====================================================


-- =====================================================
-- PART 1 — EXTENSIONS
-- =====================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- =====================================================
-- PART 2 — TABLES
-- =====================================================

-- GYMS
CREATE TABLE public.gyms (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name              text NOT NULL,
  address           text,
  phone             text,
  email             text,
  owner_name        text,
  description       text,
  logo_url          text,
  subscription_tier text DEFAULT 'free',
  created_at        timestamptz DEFAULT now(),
  updated_at        timestamptz DEFAULT now()
);

-- USERS (matches auth.users.id exactly)
CREATE TABLE public.users (
  id                  uuid PRIMARY KEY,
  gym_id              uuid REFERENCES public.gyms(id),
  email               text NOT NULL UNIQUE,
  role                text NOT NULL CHECK (role IN ('gym_owner','coach','client')),
  name                text NOT NULL,
  phone               text,
  avatar_url          text,
  language_preference text DEFAULT 'fr',
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now()
);

-- COACH_PROFILES (named coach_profiles to match all JS queries)
CREATE TABLE public.coach_profiles (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       uuid UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  specialty     text,
  hourly_rate   numeric,
  bio           text,
  rating        numeric DEFAULT 0,
  total_reviews integer DEFAULT 0,
  is_active     boolean DEFAULT true,
  instagram_url text,
  whatsapp_number text,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);

-- CLIENT_PROFILES (named client_profiles to match all JS queries)
CREATE TABLE public.client_profiles (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         uuid UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  membership_tier text DEFAULT 'basic',
  fitness_goal    text,
  height_cm       numeric,
  weight_kg       numeric,
  body_fat_pct    numeric,
  goal_weight_kg  numeric,
  notes           text,
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now()
);

-- SESSIONS
CREATE TABLE public.sessions (
  id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  gym_id           uuid REFERENCES public.gyms(id),
  coach_id         uuid REFERENCES public.users(id),
  client_id        uuid REFERENCES public.users(id),
  session_date     date NOT NULL,
  start_time       time NOT NULL,
  end_time         time,
  duration_minutes integer DEFAULT 60,
  type             text DEFAULT 'personal_training',
  status           text DEFAULT 'pending' CHECK (status IN ('pending','confirmed','completed','cancelled')),
  notes            text,
  created_at       timestamptz DEFAULT now(),
  updated_at       timestamptz DEFAULT now()
);

-- PAYMENTS
CREATE TABLE public.payments (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id uuid REFERENCES public.sessions(id),
  gym_id     uuid REFERENCES public.gyms(id),
  amount     numeric NOT NULL,
  status     text DEFAULT 'pending' CHECK (status IN ('pending','paid','refunded')),
  created_at timestamptz DEFAULT now()
);

-- REVIEWS
CREATE TABLE public.reviews (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  coach_id    uuid REFERENCES public.coach_profiles(id),
  client_id   uuid REFERENCES public.client_profiles(id),
  rating      numeric CHECK (rating >= 1 AND rating <= 5),
  comment     text,
  created_at  timestamptz DEFAULT now()
);


-- =====================================================
-- PART 3 — INDEXES (performance)
-- =====================================================
CREATE INDEX idx_users_gym_id       ON public.users(gym_id);
CREATE INDEX idx_users_role         ON public.users(role);
CREATE INDEX idx_sessions_gym_id    ON public.sessions(gym_id);
CREATE INDEX idx_sessions_coach_id  ON public.sessions(coach_id);
CREATE INDEX idx_sessions_client_id ON public.sessions(client_id);
CREATE INDEX idx_sessions_date      ON public.sessions(session_date);
CREATE INDEX idx_coach_profiles_user_id   ON public.coach_profiles(user_id);
CREATE INDEX idx_client_profiles_user_id  ON public.client_profiles(user_id);


-- =====================================================
-- PART 4 — updated_at AUTO-TRIGGER
-- =====================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_gyms_updated_at
  BEFORE UPDATE ON public.gyms
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_coach_profiles_updated_at
  BEFORE UPDATE ON public.coach_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_client_profiles_updated_at
  BEFORE UPDATE ON public.client_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_sessions_updated_at
  BEFORE UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================
-- PART 5 — HELPER FUNCTIONS
-- =====================================================
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT AS $$
  SELECT role FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.get_my_gym_id()
RETURNS UUID AS $$
  SELECT gym_id FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;


-- =====================================================
-- PART 6 — SIGNUP TRIGGER
-- =====================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  v_role   TEXT;
  v_gym_id UUID;
BEGIN
  v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'client');

  -- Gym owner: create gym row first
  IF v_role = 'gym_owner' THEN
    INSERT INTO public.gyms (name, email, owner_name)
    VALUES (
      COALESCE(NEW.raw_user_meta_data->>'gym_name', 'Ma Salle'),
      COALESCE(NEW.email, ''),
      COALESCE(NEW.raw_user_meta_data->>'name', 'Propriétaire')
    )
    RETURNING id INTO v_gym_id;

  -- Coach or client added by gym owner: gym_id in metadata
  ELSIF NEW.raw_user_meta_data->>'gym_id' IS NOT NULL THEN
    v_gym_id := (NEW.raw_user_meta_data->>'gym_id')::UUID;
  END IF;

  -- Create users row
  INSERT INTO public.users (id, name, email, role, gym_id, phone)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', 'Utilisateur'),
    COALESCE(NEW.email, ''),
    v_role,
    v_gym_id,
    COALESCE(NEW.raw_user_meta_data->>'phone', NULL)
  )
  ON CONFLICT (id) DO NOTHING;

  -- Create role profile
  IF v_role = 'coach' THEN
    INSERT INTO public.coach_profiles (user_id, specialty, is_active)
    VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data->>'specialty', NULL),
      true
    )
    ON CONFLICT (user_id) DO NOTHING;
  END IF;

  IF v_role = 'client' THEN
    INSERT INTO public.client_profiles (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'handle_new_user error: % — %', SQLSTATE, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =====================================================
-- PART 7 — ROW LEVEL SECURITY
-- =====================================================
ALTER TABLE gyms            ENABLE ROW LEVEL SECURITY;
ALTER TABLE users           ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE client_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments        ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews         ENABLE ROW LEVEL SECURITY;


-- =====================================================
-- PART 8 — RLS POLICIES
-- =====================================================

-- GYMS
CREATE POLICY "gyms_select" ON gyms FOR SELECT
  USING (id = get_my_gym_id() OR get_my_role() = 'admin');

CREATE POLICY "gyms_insert" ON gyms FOR INSERT
  WITH CHECK (get_my_role() = 'gym_owner');

CREATE POLICY "gyms_update" ON gyms FOR UPDATE
  USING (id = get_my_gym_id() AND get_my_role() = 'gym_owner');

-- USERS
CREATE POLICY "users_select" ON users FOR SELECT
  USING (id = auth.uid() OR gym_id = get_my_gym_id());

CREATE POLICY "users_insert" ON users FOR INSERT
  WITH CHECK (id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));

CREATE POLICY "users_update" ON users FOR UPDATE
  USING (id = auth.uid() OR get_my_role() = 'gym_owner');

-- COACH_PROFILES
CREATE POLICY "coach_profiles_select" ON coach_profiles FOR SELECT
  USING (
    user_id = auth.uid()
    OR (SELECT gym_id FROM users WHERE id = user_id) = get_my_gym_id()
    OR get_my_role() = 'client'
  );

CREATE POLICY "coach_profiles_insert" ON coach_profiles FOR INSERT
  WITH CHECK (user_id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));

CREATE POLICY "coach_profiles_update" ON coach_profiles FOR UPDATE
  USING (user_id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));

-- CLIENT_PROFILES
CREATE POLICY "client_profiles_select" ON client_profiles FOR SELECT
  USING (
    user_id = auth.uid()
    OR get_my_role() = 'gym_owner'
    OR get_my_role() = 'coach'
  );

CREATE POLICY "client_profiles_insert" ON client_profiles FOR INSERT
  WITH CHECK (user_id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));

CREATE POLICY "client_profiles_update" ON client_profiles FOR UPDATE
  USING (user_id = auth.uid());

-- SESSIONS — clients can now insert their own bookings
CREATE POLICY "sessions_select" ON sessions FOR SELECT
  USING (
    gym_id = get_my_gym_id()
    OR coach_id = auth.uid()
    OR client_id = auth.uid()
  );

CREATE POLICY "sessions_insert" ON sessions FOR INSERT
  WITH CHECK (
    gym_id = get_my_gym_id()
    OR coach_id = auth.uid()
    OR client_id = auth.uid()
  );

CREATE POLICY "sessions_update" ON sessions FOR UPDATE
  USING (
    gym_id = get_my_gym_id()
    OR coach_id = auth.uid()
  );

CREATE POLICY "sessions_delete" ON sessions FOR DELETE
  USING (gym_id = get_my_gym_id());

-- PAYMENTS
CREATE POLICY "payments_select" ON payments FOR SELECT
  USING (get_my_role() IN ('gym_owner','admin'));

CREATE POLICY "payments_insert" ON payments FOR INSERT
  WITH CHECK (get_my_role() IN ('gym_owner','admin'));

CREATE POLICY "payments_delete" ON payments FOR DELETE
  USING (get_my_role() = 'gym_owner');

-- REVIEWS
CREATE POLICY "reviews_select" ON reviews FOR SELECT
  USING (true);

CREATE POLICY "reviews_insert" ON reviews FOR INSERT
  WITH CHECK (
    client_id = (SELECT id FROM client_profiles WHERE user_id = auth.uid())
  );


-- =====================================================
-- PART 9 — SCHEMA CACHE REFRESH
-- =====================================================
NOTIFY pgrst, 'reload schema';


-- =====================================================
-- PART 10 — VERIFY
-- =====================================================
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' ORDER BY table_name;

SELECT trigger_name FROM information_schema.triggers
WHERE trigger_name = 'on_auth_user_created';
