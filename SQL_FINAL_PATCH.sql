-- =====================================================
-- TRAINW — FINAL PATCH SQL
-- Run AFTER renaming: coaches → coach_profiles, clients → client_profiles
-- Every statement is safe on existing data.
-- =====================================================

-- Step 1: Rename tables (skip if already done)
ALTER TABLE IF EXISTS public.coaches RENAME TO coach_profiles;
ALTER TABLE IF EXISTS public.clients RENAME TO client_profiles;

-- Step 2: Add missing columns
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS logo_url text;
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS subscription_tier text DEFAULT 'free';

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS gym_id uuid;

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

ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS gym_id uuid;
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS duration_minutes integer DEFAULT 60;
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS type text DEFAULT 'personal_training';
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending';
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS notes text;

-- Step 3: Helper functions
CREATE OR REPLACE FUNCTION public.get_my_gym_id()
RETURNS UUID AS $$
  SELECT gym_id FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT AS $$
  SELECT role FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Step 4: Signup trigger
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
  ELSIF v_role = 'client' THEN
    INSERT INTO public.client_profiles (user_id, membership_tier)
    VALUES (NEW.id, 'basic')
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

-- Step 5: Indexes
CREATE INDEX IF NOT EXISTS idx_users_gym_id              ON public.users(gym_id);
CREATE INDEX IF NOT EXISTS idx_sessions_gym_id           ON public.sessions(gym_id);
CREATE INDEX IF NOT EXISTS idx_sessions_coach_id         ON public.sessions(coach_id);
CREATE INDEX IF NOT EXISTS idx_sessions_client_id        ON public.sessions(client_id);
CREATE INDEX IF NOT EXISTS idx_coach_profiles_user_id    ON public.coach_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_client_profiles_user_id   ON public.client_profiles(user_id);

-- Step 6: Reload
NOTIFY pgrst, 'reload schema';

-- Step 7: Verify
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;
