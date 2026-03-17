-- =====================================================
-- TRAINW — COMPLETE DATABASE SETUP
-- Run once on a clean Supabase project
-- =====================================================


-- =====================================================
-- PART 1 — TABLES
-- =====================================================

-- GYMS
CREATE TABLE public.gyms (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name              text NOT NULL,
  address           text,
  phone             text,
  email             text,
  owner_name        text,
  subscription_tier text DEFAULT 'free',
  created_at        timestamptz DEFAULT now()
);

-- USERS
CREATE TABLE public.users (
  id         uuid PRIMARY KEY,  -- matches auth.users.id exactly
  gym_id     uuid REFERENCES public.gyms(id),
  email      text NOT NULL UNIQUE,
  role       text NOT NULL CHECK (role IN ('gym_owner','coach','client')),
  name       text NOT NULL,
  phone      text,
  created_at timestamptz DEFAULT now()
);
-- Note: no password_hash — Supabase Auth handles passwords, we never store them

-- COACHES
CREATE TABLE public.coaches (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     uuid UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  specialty   text,
  hourly_rate numeric,
  bio         text,
  rating      numeric DEFAULT 0,
  total_reviews integer DEFAULT 0,
  is_active   boolean DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

-- CLIENTS
CREATE TABLE public.clients (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         uuid UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  membership_tier text DEFAULT 'basic',
  start_date      date DEFAULT CURRENT_DATE,
  goal            text,
  notes           text,
  created_at      timestamptz DEFAULT now()
);

-- SESSIONS
CREATE TABLE public.sessions (
  id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  gym_id           uuid REFERENCES public.gyms(id),
  coach_id         uuid REFERENCES public.users(id),
  client_id        uuid REFERENCES public.users(id),
  session_date     date NOT NULL,
  start_time       time NOT NULL,
  duration_minutes integer DEFAULT 60,
  type             text DEFAULT 'personal_training' CHECK (type IN ('personal_training','group_class')),
  status           text DEFAULT 'pending' CHECK (status IN ('pending','confirmed','completed','cancelled')),
  notes            text,
  created_at       timestamptz DEFAULT now()
);

-- PAYMENTS
CREATE TABLE public.payments (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id uuid REFERENCES public.sessions(id),
  amount     numeric NOT NULL,
  status     text DEFAULT 'pending' CHECK (status IN ('pending','paid','refunded')),
  created_at timestamptz DEFAULT now()
);

-- REVIEWS
CREATE TABLE public.reviews (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  coach_id   uuid REFERENCES public.coaches(id),
  client_id  uuid REFERENCES public.clients(id),
  rating     numeric CHECK (rating >= 1 AND rating <= 5),
  comment    text,
  created_at timestamptz DEFAULT now()
);


-- =====================================================
-- PART 2 — HELPER FUNCTIONS
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
-- PART 3 — TRIGGER (auto-create user row on signup)
-- =====================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  v_role   TEXT;
  v_gym_id UUID;
BEGIN
  v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'client');

  -- Gym owner: create gym first, get its id
  IF v_role = 'gym_owner' THEN
    INSERT INTO public.gyms (name, email, owner_name)
    VALUES (
      COALESCE(NEW.raw_user_meta_data->>'gym_name', 'My Gym'),
      COALESCE(NEW.email, ''),
      COALESCE(NEW.raw_user_meta_data->>'name', 'Owner')
    )
    RETURNING id INTO v_gym_id;

  -- Coach/client added by gym owner: gym_id passed in metadata
  ELSIF NEW.raw_user_meta_data->>'gym_id' IS NOT NULL THEN
    v_gym_id := (NEW.raw_user_meta_data->>'gym_id')::UUID;
  END IF;

  -- Create user row (no password_hash — Auth handles it)
  INSERT INTO public.users (id, name, email, role, gym_id, phone)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', 'New User'),
    COALESCE(NEW.email, ''),
    v_role,
    v_gym_id,
    COALESCE(NEW.raw_user_meta_data->>'phone', NULL)
  )
  ON CONFLICT (id) DO NOTHING;

  -- Create role profile
  IF v_role = 'coach' THEN
    INSERT INTO public.coaches (user_id, specialty, hourly_rate, is_active)
    VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data->>'specialty', NULL),
      NULL,
      true
    )
    ON CONFLICT (user_id) DO NOTHING;
  END IF;

  IF v_role = 'client' THEN
    INSERT INTO public.clients (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  -- Never block signup — log and continue
  RAISE LOG 'handle_new_user error: % — %', SQLSTATE, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =====================================================
-- PART 4 — RLS
-- =====================================================

ALTER TABLE gyms     ENABLE ROW LEVEL SECURITY;
ALTER TABLE users    ENABLE ROW LEVEL SECURITY;
ALTER TABLE coaches  ENABLE ROW LEVEL SECURITY;
ALTER TABLE clients  ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews  ENABLE ROW LEVEL SECURITY;


-- =====================================================
-- PART 5 — POLICIES
-- =====================================================

-- GYMS
CREATE POLICY "gyms_select" ON gyms FOR SELECT USING (id = get_my_gym_id() OR get_my_role() = 'admin');
CREATE POLICY "gyms_insert" ON gyms FOR INSERT WITH CHECK (true);
CREATE POLICY "gyms_update" ON gyms FOR UPDATE USING (id = get_my_gym_id() AND get_my_role() = 'gym_owner');

-- USERS
CREATE POLICY "users_select" ON users FOR SELECT USING (id = auth.uid() OR gym_id = get_my_gym_id());
CREATE POLICY "users_insert" ON users FOR INSERT WITH CHECK (id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));
CREATE POLICY "users_update" ON users FOR UPDATE USING (id = auth.uid());

-- COACHES
CREATE POLICY "coaches_select" ON coaches FOR SELECT USING (
  user_id = auth.uid()
  OR (SELECT gym_id FROM users WHERE id = user_id) = get_my_gym_id()
  OR get_my_role() = 'client'
);
CREATE POLICY "coaches_insert" ON coaches FOR INSERT WITH CHECK (user_id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));
CREATE POLICY "coaches_update" ON coaches FOR UPDATE USING (user_id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));

-- CLIENTS
CREATE POLICY "clients_select" ON clients FOR SELECT USING (
  user_id = auth.uid()
  OR get_my_role() = 'gym_owner'
  OR get_my_role() = 'coach'
);
CREATE POLICY "clients_insert" ON clients FOR INSERT WITH CHECK (user_id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));
CREATE POLICY "clients_update" ON clients FOR UPDATE USING (user_id = auth.uid());

-- SESSIONS
CREATE POLICY "sessions_select" ON sessions FOR SELECT USING (
  gym_id = get_my_gym_id()
  OR coach_id = auth.uid()
  OR client_id = auth.uid()
);
CREATE POLICY "sessions_insert" ON sessions FOR INSERT WITH CHECK (gym_id = get_my_gym_id() OR get_my_role() = 'admin');
CREATE POLICY "sessions_update" ON sessions FOR UPDATE USING (gym_id = get_my_gym_id() OR coach_id = auth.uid());

-- PAYMENTS
CREATE POLICY "payments_select" ON payments FOR SELECT USING (get_my_role() IN ('gym_owner','admin'));
CREATE POLICY "payments_insert" ON payments FOR INSERT WITH CHECK (get_my_role() IN ('gym_owner','admin'));

-- REVIEWS
CREATE POLICY "reviews_select" ON reviews FOR SELECT USING (true);
CREATE POLICY "reviews_insert" ON reviews FOR INSERT WITH CHECK (
  client_id = (SELECT id FROM clients WHERE user_id = auth.uid())
);


-- =====================================================
-- VERIFY
-- =====================================================

SELECT trigger_name, event_object_schema, event_object_table
FROM information_schema.triggers
WHERE trigger_name = 'on_auth_user_created';

SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' ORDER BY table_name;