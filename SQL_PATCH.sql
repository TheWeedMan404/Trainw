-- =====================================================
-- TRAINW — SQL PATCH
-- Run this in Supabase SQL Editor ONCE
-- Fixes: owner_id on gyms, measurement columns on clients, RLS policies
-- =====================================================

-- 1. Add owner_id to gyms (needed for fallback gym lookup)
ALTER TABLE public.gyms
  ADD COLUMN IF NOT EXISTS owner_id uuid REFERENCES public.users(id);

-- 2. Add body measurement columns to clients table
ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS height_cm      numeric,
  ADD COLUMN IF NOT EXISTS weight_kg      numeric,
  ADD COLUMN IF NOT EXISTS body_fat_pct   numeric,
  ADD COLUMN IF NOT EXISTS goal_weight_kg numeric;

-- 3. Update RLS on users so gym_owner can update gym_id of their gym's members
DROP POLICY IF EXISTS "users_update" ON users;
CREATE POLICY "users_update" ON users
  FOR UPDATE
  USING (
    id = auth.uid()
    OR get_my_role() = 'gym_owner'
  );

-- 4. Update RLS on clients so gym_owner can insert client rows
DROP POLICY IF EXISTS "clients_insert" ON clients;
CREATE POLICY "clients_insert" ON clients
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    OR get_my_role() IN ('gym_owner', 'admin')
  );

-- 5. Patch existing gym_owner rows to set owner_id = their user id
UPDATE public.gyms g
SET owner_id = u.id
FROM public.users u
WHERE u.role = 'gym_owner'
  AND u.gym_id = g.id
  AND g.owner_id IS NULL;

-- 6. Verify
SELECT id, name, owner_id FROM public.gyms LIMIT 10;
SELECT id, role, gym_id FROM public.users WHERE role = 'gym_owner' LIMIT 10;
SELECT column_name FROM information_schema.columns WHERE table_name = 'clients' ORDER BY column_name;
