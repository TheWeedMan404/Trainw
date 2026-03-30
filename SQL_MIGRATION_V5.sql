-- =====================================================
-- TRAINW — MIGRATION v5
-- Run ONCE in Supabase SQL Editor (safe on existing data)
-- Adds: check_ins, messages, gym_classes tables + RLS
-- Fixes: sessions type constraint, client gym_id linking
-- =====================================================

-- ── 1. Carry forward all v4 columns (idempotent) ────────
ALTER TABLE public.gyms            ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.gyms            ADD COLUMN IF NOT EXISTS logo_url text;
ALTER TABLE public.gyms            ADD COLUMN IF NOT EXISTS subscription_tier text DEFAULT 'free';
ALTER TABLE public.gyms            ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE public.users           ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE public.users           ADD COLUMN IF NOT EXISTS avatar_url text;
ALTER TABLE public.users           ADD COLUMN IF NOT EXISTS language_preference text DEFAULT 'fr';
ALTER TABLE public.users           ADD COLUMN IF NOT EXISTS is_managed boolean DEFAULT false;
-- is_managed=true means added by gym owner, no real auth account, can't self-login
ALTER TABLE public.users           ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE public.coach_profiles  ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE public.coach_profiles  ADD COLUMN IF NOT EXISTS specialty text;
ALTER TABLE public.coach_profiles  ADD COLUMN IF NOT EXISTS hourly_rate numeric;
ALTER TABLE public.coach_profiles  ADD COLUMN IF NOT EXISTS bio text;
ALTER TABLE public.coach_profiles  ADD COLUMN IF NOT EXISTS rating numeric DEFAULT 0;
ALTER TABLE public.coach_profiles  ADD COLUMN IF NOT EXISTS total_reviews integer DEFAULT 0;
ALTER TABLE public.coach_profiles  ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
ALTER TABLE public.coach_profiles  ADD COLUMN IF NOT EXISTS instagram_url text;
ALTER TABLE public.coach_profiles  ADD COLUMN IF NOT EXISTS whatsapp_number text;
ALTER TABLE public.coach_profiles  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

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
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE public.sessions        ADD COLUMN IF NOT EXISTS gym_id uuid;
ALTER TABLE public.sessions        ADD COLUMN IF NOT EXISTS duration_minutes integer DEFAULT 60;
ALTER TABLE public.sessions        ADD COLUMN IF NOT EXISTS type text DEFAULT 'group_class';
ALTER TABLE public.sessions        ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending';
ALTER TABLE public.sessions        ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.sessions        ADD COLUMN IF NOT EXISTS capacity integer DEFAULT 10;
ALTER TABLE public.sessions        ADD COLUMN IF NOT EXISTS session_name text;
ALTER TABLE public.sessions        ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- ── 2. Drop old type CHECK constraints (the v4 bug) ──────
DO $$
DECLARE constraint_name text;
BEGIN
  SELECT conname INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'public.sessions'::regclass AND contype = 'c' AND conname ILIKE '%type%';
  IF constraint_name IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.sessions DROP CONSTRAINT IF EXISTS ' || quote_ident(constraint_name);
  END IF;
END$$;
ALTER TABLE public.sessions DROP CONSTRAINT IF EXISTS sessions_type_check;
ALTER TABLE public.sessions DROP CONSTRAINT IF EXISTS sessions_status_check;

-- ── 3. NEW: check_ins table ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.check_ins (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  gym_id         uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  client_id      uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  checked_in_at  timestamptz DEFAULT now(),
  method         text DEFAULT 'manual', -- 'manual' | 'qr'
  notes          text
);
CREATE INDEX IF NOT EXISTS idx_check_ins_gym_id    ON public.check_ins(gym_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_client_id ON public.check_ins(client_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_date      ON public.check_ins(checked_in_at);

-- ── 4. NEW: messages table ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.messages (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  gym_id         uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  sender_id      uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  receiver_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content        text NOT NULL,
  is_read        boolean DEFAULT false,
  is_automated   boolean DEFAULT false,
  created_at     timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_messages_gym_id     ON public.messages(gym_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender     ON public.messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver   ON public.messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_created    ON public.messages(created_at);

-- ── 5. NEW: gym_classes table (custom classes per gym) ────
CREATE TABLE IF NOT EXISTS public.gym_classes (
  id               uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  gym_id           uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  name             text NOT NULL,
  description      text,
  coach_id         uuid REFERENCES public.users(id),
  schedule_day     text,  -- 'Lundi','Mardi',etc.
  start_time       time,
  duration_minutes integer DEFAULT 60,
  capacity         integer DEFAULT 20,
  is_active        boolean DEFAULT true,
  created_at       timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_gym_classes_gym_id ON public.gym_classes(gym_id);

-- ── 6. Updated_at trigger ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_gyms_upd      ON public.gyms;
DROP TRIGGER IF EXISTS trg_users_upd     ON public.users;
DROP TRIGGER IF EXISTS trg_coaches_upd   ON public.coach_profiles;
DROP TRIGGER IF EXISTS trg_clients_upd   ON public.client_profiles;
DROP TRIGGER IF EXISTS trg_sessions_upd  ON public.sessions;
CREATE TRIGGER trg_gyms_upd     BEFORE UPDATE ON public.gyms            FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_users_upd    BEFORE UPDATE ON public.users           FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_coaches_upd  BEFORE UPDATE ON public.coach_profiles  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_clients_upd  BEFORE UPDATE ON public.client_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_sessions_upd BEFORE UPDATE ON public.sessions        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 7. Helper functions ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_gym_id()
RETURNS UUID AS $$
  SELECT gym_id FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT AS $$
  SELECT role FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ── 8. handle_new_user trigger ────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE v_role text; v_gym_id uuid;
BEGIN
  v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'client');
  IF v_role = 'gym_owner' THEN
    INSERT INTO public.gyms (name, email, owner_name)
    VALUES (
      COALESCE(NEW.raw_user_meta_data->>'gym_name', 'Ma Salle'),
      COALESCE(NEW.email, ''),
      COALESCE(NEW.raw_user_meta_data->>'name', 'Propriétaire')
    ) RETURNING id INTO v_gym_id;
  ELSIF NEW.raw_user_meta_data->>'gym_id' IS NOT NULL THEN
    v_gym_id := (NEW.raw_user_meta_data->>'gym_id')::UUID;
  END IF;
  INSERT INTO public.users (id, name, email, role, gym_id, phone)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', 'Utilisateur'),
    COALESCE(NEW.email, ''),
    v_role, v_gym_id,
    COALESCE(NEW.raw_user_meta_data->>'phone', NULL)
  ) ON CONFLICT (id) DO NOTHING;
  IF v_role = 'coach' THEN
    INSERT INTO public.coach_profiles (user_id, specialty, is_active)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'specialty', NULL), true)
    ON CONFLICT (user_id) DO NOTHING;
  ELSIF v_role = 'client' THEN
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

-- ── 9. RLS — existing tables ──────────────────────────────
ALTER TABLE public.gyms            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions        ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "gyms_select" ON public.gyms;
DROP POLICY IF EXISTS "gyms_insert" ON public.gyms;
DROP POLICY IF EXISTS "gyms_update" ON public.gyms;
CREATE POLICY "gyms_select" ON public.gyms FOR SELECT USING (id = get_my_gym_id());
CREATE POLICY "gyms_insert" ON public.gyms FOR INSERT WITH CHECK (true);
CREATE POLICY "gyms_update" ON public.gyms FOR UPDATE USING (id = get_my_gym_id());

DROP POLICY IF EXISTS "users_select" ON public.users;
DROP POLICY IF EXISTS "users_insert" ON public.users;
DROP POLICY IF EXISTS "users_update" ON public.users;
DROP POLICY IF EXISTS "users_delete" ON public.users;
CREATE POLICY "users_select" ON public.users FOR SELECT USING (id = auth.uid() OR gym_id = get_my_gym_id());
CREATE POLICY "users_insert" ON public.users FOR INSERT WITH CHECK (
  id = auth.uid()                        -- self-registration
  OR get_my_role() IN ('gym_owner','admin')  -- owner adding managed clients/coaches
);
CREATE POLICY "users_update" ON public.users FOR UPDATE USING (id = auth.uid() OR get_my_role() = 'gym_owner');
CREATE POLICY "users_delete" ON public.users FOR DELETE USING (get_my_role() = 'gym_owner' OR id = auth.uid());

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

DROP POLICY IF EXISTS "client_profiles_select" ON public.client_profiles;
DROP POLICY IF EXISTS "client_profiles_insert" ON public.client_profiles;
DROP POLICY IF EXISTS "client_profiles_update" ON public.client_profiles;
DROP POLICY IF EXISTS "client_profiles_delete" ON public.client_profiles;
-- FIXED: scope by gym — gym_owner can only see clients who belong to their gym
CREATE POLICY "client_profiles_select" ON public.client_profiles FOR SELECT
  USING (
    user_id = auth.uid()
    OR (SELECT gym_id FROM public.users WHERE id = user_id) = get_my_gym_id()
  );
CREATE POLICY "client_profiles_insert" ON public.client_profiles FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    OR get_my_role() IN ('gym_owner','admin')
  );
CREATE POLICY "client_profiles_update" ON public.client_profiles FOR UPDATE
  USING (
    user_id = auth.uid()
    OR (
      get_my_role() = 'gym_owner'
      AND (SELECT gym_id FROM public.users WHERE id = user_id) = get_my_gym_id()
    )
  );
CREATE POLICY "client_profiles_delete" ON public.client_profiles FOR DELETE
  USING (
    get_my_role() = 'gym_owner'
    AND (SELECT gym_id FROM public.users WHERE id = user_id) = get_my_gym_id()
  );

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

-- ── 10. RLS — new tables ──────────────────────────────────
ALTER TABLE public.check_ins  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

-- CHECK_INS: gym owner + coaches see all; client sees own
DROP POLICY IF EXISTS "check_ins_select" ON public.check_ins;
DROP POLICY IF EXISTS "check_ins_insert" ON public.check_ins;
DROP POLICY IF EXISTS "check_ins_delete" ON public.check_ins;
CREATE POLICY "check_ins_select" ON public.check_ins FOR SELECT
  USING (gym_id = get_my_gym_id() OR client_id = auth.uid());
CREATE POLICY "check_ins_insert" ON public.check_ins FOR INSERT
  WITH CHECK (gym_id = get_my_gym_id() OR get_my_role() IN ('gym_owner','coach'));
CREATE POLICY "check_ins_delete" ON public.check_ins FOR DELETE
  USING (gym_id = get_my_gym_id());

-- MESSAGES: participants of the message can see it
DROP POLICY IF EXISTS "messages_select" ON public.messages;
DROP POLICY IF EXISTS "messages_insert" ON public.messages;
DROP POLICY IF EXISTS "messages_update" ON public.messages;
CREATE POLICY "messages_select" ON public.messages FOR SELECT
  USING (gym_id = get_my_gym_id() OR sender_id = auth.uid() OR receiver_id = auth.uid());
CREATE POLICY "messages_insert" ON public.messages FOR INSERT
  WITH CHECK (gym_id = get_my_gym_id() AND (sender_id = auth.uid() OR get_my_role() = 'gym_owner'));
CREATE POLICY "messages_update" ON public.messages FOR UPDATE
  USING (receiver_id = auth.uid());

-- GYM_CLASSES: scoped to gym
DROP POLICY IF EXISTS "gym_classes_select" ON public.gym_classes;
DROP POLICY IF EXISTS "gym_classes_insert" ON public.gym_classes;
DROP POLICY IF EXISTS "gym_classes_update" ON public.gym_classes;
DROP POLICY IF EXISTS "gym_classes_delete" ON public.gym_classes;
CREATE POLICY "gym_classes_select" ON public.gym_classes FOR SELECT
  USING (gym_id = get_my_gym_id());
CREATE POLICY "gym_classes_insert" ON public.gym_classes FOR INSERT
  WITH CHECK (gym_id = get_my_gym_id() AND get_my_role() = 'gym_owner');
CREATE POLICY "gym_classes_update" ON public.gym_classes FOR UPDATE
  USING (gym_id = get_my_gym_id() AND get_my_role() = 'gym_owner');
CREATE POLICY "gym_classes_delete" ON public.gym_classes FOR DELETE
  USING (gym_id = get_my_gym_id() AND get_my_role() = 'gym_owner');

-- PAYMENTS: gym scoped with user self-access
DROP POLICY IF EXISTS "payments_select" ON public.payments;
DROP POLICY IF EXISTS "payments_insert" ON public.payments;
DROP POLICY IF EXISTS "payments_update" ON public.payments;
CREATE POLICY "payments_select" ON public.payments FOR SELECT
  USING (gym_id = get_my_gym_id() OR user_id = auth.uid());
CREATE POLICY "payments_insert" ON public.payments FOR INSERT
  WITH CHECK (gym_id = get_my_gym_id() OR get_my_role() IN ('gym_owner', 'admin'));
CREATE POLICY "payments_update" ON public.payments FOR UPDATE
  USING (gym_id = get_my_gym_id());

-- REVIEWS: gym scoped, client-owned, coach can read own reviews
DROP POLICY IF EXISTS "reviews_select" ON public.reviews;
DROP POLICY IF EXISTS "reviews_insert" ON public.reviews;
CREATE POLICY "reviews_select" ON public.reviews FOR SELECT
  USING (
    gym_id = get_my_gym_id()
    OR client_id = auth.uid()
    OR coach_id IN (
      SELECT id
      FROM public.coach_profiles
      WHERE user_id = auth.uid()
    )
  );
CREATE POLICY "reviews_insert" ON public.reviews FOR INSERT
  WITH CHECK (client_id = auth.uid());

-- ── 11. All indexes ───────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_users_gym_id            ON public.users(gym_id);
CREATE INDEX IF NOT EXISTS idx_users_role              ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_sessions_gym_id         ON public.sessions(gym_id);
CREATE INDEX IF NOT EXISTS idx_sessions_coach_id       ON public.sessions(coach_id);
CREATE INDEX IF NOT EXISTS idx_sessions_client_id      ON public.sessions(client_id);
CREATE INDEX IF NOT EXISTS idx_sessions_date           ON public.sessions(session_date);
CREATE INDEX IF NOT EXISTS idx_coach_profiles_user_id  ON public.coach_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_client_profiles_user_id ON public.client_profiles(user_id);


-- ── V5.1: Membership tracking columns ────────────────────
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS membership_start_date date;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS membership_end_date   date;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS price_paid            numeric DEFAULT 0;
ALTER TABLE public.client_profiles ADD COLUMN IF NOT EXISTS membership_notes      text;

-- ── V5.1: gyms custom pricing ────────────────────────────
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS price_monthly   numeric DEFAULT 150;
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS price_quarterly numeric DEFAULT 400;
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS price_annual    numeric DEFAULT 1400;

NOTIFY pgrst, 'reload schema';

-- ── 12. Reload schema cache ───────────────────────────────
NOTIFY pgrst, 'reload schema';

-- ── 13. Verify ────────────────────────────────────────────
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;
