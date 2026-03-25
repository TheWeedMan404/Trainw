-- =====================================================
-- TRAINW — MIGRATION v4
-- Run this in Supabase SQL Editor
-- Safe on existing data — uses IF NOT EXISTS + ALTER
-- =====================================================

-- STEP 1: Rename tables if still old names
ALTER TABLE IF EXISTS public.coaches RENAME TO coach_profiles;
ALTER TABLE IF EXISTS public.clients RENAME TO client_profiles;

-- STEP 2: Add missing columns safely
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS logo_url text;
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS subscription_tier text DEFAULT 'free';

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS avatar_url text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS language_preference text DEFAULT 'fr';

ALTER TABLE public.coach_profiles ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE public.coach_profiles ADD COLUMN IF NOT EXISTS specialty text;
ALTER TABLE public.coach_profiles ADD COLUMN IF NOT EXISTS hourly_rate numeric;
ALTER TABLE public.coach_profiles ADD COLUMN IF NOT EXISTS bio text;
ALTER TABLE public.coach_profiles ADD COLUMN IF NOT EXISTS rating numeric DEFAULT 0;
ALTER TABLE public.coach_profiles ADD COLUMN IF NOT EXISTS total_reviews integer DEFAULT 0;
ALTER TABLE public.coach_profiles ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
ALTER TABLE public.coach_profiles ADD COLUMN IF NOT EXISTS instagram_url text;
ALTER TABLE public.coach_profiles ADD COLUMN IF NOT EXISTS whatsapp_number text;

ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS membership_tier text DEFAULT 'basic';
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS fitness_goal text;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS height_cm numeric;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS weight_kg numeric;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS body_fat_pct numeric;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS goal_weight_kg numeric;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS payment_status text DEFAULT 'paid';
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS age integer;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS training_type text;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS extra_classes text;

ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS gym_id uuid;
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS duration_minutes integer DEFAULT 60;
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS type text DEFAULT 'group_class';
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending';
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS capacity integer DEFAULT 10;
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS session_name text;

-- STEP 3: CRITICAL — Drop old type CHECK constraint that blocks valid types
-- The old constraint only allowed personal_training/group_class
-- New valid types: group_class, group_activity, individual_training, personal_training
DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT conname INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'public.sessions'::regclass
    AND contype = 'c'
    AND conname ILIKE '%type%';
  IF constraint_name IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.sessions DROP CONSTRAINT IF EXISTS ' || quote_ident(constraint_name);
    RAISE NOTICE 'Dropped constraint: %', constraint_name;
  END IF;
END$$;

-- Also drop by exact known names just in case
ALTER TABLE public.sessions DROP CONSTRAINT IF EXISTS sessions_type_check;
ALTER TABLE public.sessions DROP CONSTRAINT IF EXISTS sessions_status_check;

-- STEP 4: Add updated_at columns
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.coach_profiles ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- STEP 5: Helper functions
CREATE OR REPLACE FUNCTION public.get_my_gym_id()
RETURNS UUID AS $$
  SELECT gym_id FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT AS $$
  SELECT role FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- STEP 6: updated_at trigger function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

-- Apply triggers
DROP TRIGGER IF EXISTS trg_gyms_upd    ON public.gyms;
DROP TRIGGER IF EXISTS trg_users_upd   ON public.users;
DROP TRIGGER IF EXISTS trg_coaches_upd ON public.coach_profiles;
DROP TRIGGER IF EXISTS trg_clients_upd ON public.client_profiles;
DROP TRIGGER IF EXISTS trg_sessions_upd ON public.sessions;

CREATE TRIGGER trg_gyms_upd    BEFORE UPDATE ON public.gyms    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_users_upd   BEFORE UPDATE ON public.users   FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_coaches_upd BEFORE UPDATE ON public.coach_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_clients_upd BEFORE UPDATE ON public.client_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_sessions_upd BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- STEP 7: Signup trigger (handle_new_user)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  v_role   TEXT;
  v_gym_id UUID;
BEGIN
  v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'client');

  IF v_role = 'gym_owner' THEN
    INSERT INTO public.gyms (name, email, owner_name)
    VALUES (
      COALESCE(NEW.raw_user_meta_data->>'gym_name', 'Ma Salle'),
      COALESCE(NEW.email, ''),
      COALESCE(NEW.raw_user_meta_data->>'name', 'Propriétaire')
    )
    RETURNING id INTO v_gym_id;
  ELSIF NEW.raw_user_meta_data->>'gym_id' IS NOT NULL THEN
    v_gym_id := (NEW.raw_user_meta_data->>'gym_id')::UUID;
  END IF;

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

  IF v_role = 'coach' THEN
    INSERT INTO public.coach_profiles (user_id, specialty, is_active)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'specialty', NULL), true)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;

  IF v_role = 'client' THEN
    INSERT INTO public.client_profiles (user_id, membership_tier, payment_status)
    VALUES (NEW.id, 'basic', 'paid')
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

-- STEP 8: RLS policies (safe — DROP IF EXISTS then recreate)
ALTER TABLE public.gyms            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions        ENABLE ROW LEVEL SECURITY;

-- GYMS
DROP POLICY IF EXISTS "gyms_select" ON public.gyms;
DROP POLICY IF EXISTS "gyms_insert" ON public.gyms;
DROP POLICY IF EXISTS "gyms_update" ON public.gyms;
CREATE POLICY "gyms_select" ON public.gyms FOR SELECT USING (id = get_my_gym_id());
CREATE POLICY "gyms_insert" ON public.gyms FOR INSERT WITH CHECK (true);
CREATE POLICY "gyms_update" ON public.gyms FOR UPDATE USING (id = get_my_gym_id());

-- USERS
DROP POLICY IF EXISTS "users_select" ON public.users;
DROP POLICY IF EXISTS "users_insert" ON public.users;
DROP POLICY IF EXISTS "users_update" ON public.users;
DROP POLICY IF EXISTS "users_delete" ON public.users;
CREATE POLICY "users_select" ON public.users FOR SELECT USING (id = auth.uid() OR gym_id = get_my_gym_id());
CREATE POLICY "users_insert" ON public.users FOR INSERT WITH CHECK (id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));
CREATE POLICY "users_update" ON public.users FOR UPDATE USING (id = auth.uid() OR get_my_role() = 'gym_owner');
CREATE POLICY "users_delete" ON public.users FOR DELETE USING (get_my_role() = 'gym_owner' OR id = auth.uid());

-- COACH_PROFILES
DROP POLICY IF EXISTS "coach_profiles_select" ON public.coach_profiles;
DROP POLICY IF EXISTS "coach_profiles_insert" ON public.coach_profiles;
DROP POLICY IF EXISTS "coach_profiles_update" ON public.coach_profiles;
DROP POLICY IF EXISTS "coach_profiles_delete" ON public.coach_profiles;
CREATE POLICY "coach_profiles_select" ON public.coach_profiles FOR SELECT
  USING (user_id = auth.uid() OR (SELECT gym_id FROM public.users WHERE id = user_id) = get_my_gym_id() OR get_my_role() = 'client');
CREATE POLICY "coach_profiles_insert" ON public.coach_profiles FOR INSERT
  WITH CHECK (user_id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));
CREATE POLICY "coach_profiles_update" ON public.coach_profiles FOR UPDATE
  USING (user_id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));
CREATE POLICY "coach_profiles_delete" ON public.coach_profiles FOR DELETE
  USING (get_my_role() = 'gym_owner');

-- CLIENT_PROFILES
DROP POLICY IF EXISTS "client_profiles_select" ON public.client_profiles;
DROP POLICY IF EXISTS "client_profiles_insert" ON public.client_profiles;
DROP POLICY IF EXISTS "client_profiles_update" ON public.client_profiles;
DROP POLICY IF EXISTS "client_profiles_delete" ON public.client_profiles;
CREATE POLICY "client_profiles_select" ON public.client_profiles FOR SELECT
  USING (user_id = auth.uid() OR get_my_role() IN ('gym_owner','coach'));
CREATE POLICY "client_profiles_insert" ON public.client_profiles FOR INSERT
  WITH CHECK (user_id = auth.uid() OR get_my_role() IN ('gym_owner','admin'));
CREATE POLICY "client_profiles_update" ON public.client_profiles FOR UPDATE
  USING (user_id = auth.uid() OR get_my_role() = 'gym_owner');
CREATE POLICY "client_profiles_delete" ON public.client_profiles FOR DELETE
  USING (get_my_role() = 'gym_owner');

-- SESSIONS (clients can insert their own bookings)
DROP POLICY IF EXISTS "sessions_select" ON public.sessions;
DROP POLICY IF EXISTS "sessions_insert" ON public.sessions;
DROP POLICY IF EXISTS "sessions_update" ON public.sessions;
DROP POLICY IF EXISTS "sessions_delete" ON public.sessions;
CREATE POLICY "sessions_select" ON public.sessions FOR SELECT
  USING (gym_id = get_my_gym_id() OR coach_id = auth.uid() OR client_id = auth.uid());
CREATE POLICY "sessions_insert" ON public.sessions FOR INSERT
  WITH CHECK (gym_id = get_my_gym_id() OR coach_id = auth.uid() OR client_id = auth.uid());
CREATE POLICY "sessions_update" ON public.sessions FOR UPDATE
  USING (gym_id = get_my_gym_id() OR coach_id = auth.uid());
CREATE POLICY "sessions_delete" ON public.sessions FOR DELETE
  USING (gym_id = get_my_gym_id());

-- STEP 9: Indexes
CREATE INDEX IF NOT EXISTS idx_users_gym_id              ON public.users(gym_id);
CREATE INDEX IF NOT EXISTS idx_users_role                ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_sessions_gym_id           ON public.sessions(gym_id);
CREATE INDEX IF NOT EXISTS idx_sessions_coach_id         ON public.sessions(coach_id);
CREATE INDEX IF NOT EXISTS idx_sessions_client_id        ON public.sessions(client_id);
CREATE INDEX IF NOT EXISTS idx_sessions_date             ON public.sessions(session_date);
CREATE INDEX IF NOT EXISTS idx_coach_profiles_user_id    ON public.coach_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_client_profiles_user_id   ON public.client_profiles(user_id);

-- STEP 10: Reload schema cache
NOTIFY pgrst, 'reload schema';

-- STEP 11: Verify
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;
