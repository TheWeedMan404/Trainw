-- ============================================================================
-- TRAINW V17 PRODUCTION - FOUNDATION
-- Purpose:
--   - Install required extensions
--   - Repair legacy table names
--   - Create and normalize the core multi-tenant tables
--   - Add baseline constraints and indexes
-- Safe to run multiple times on an existing Supabase project.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- EXTENSIONS
-- ----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS citext;


-- ----------------------------------------------------------------------------
-- SAFE LEGACY RENAME
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF to_regclass('public.coaches') IS NOT NULL
     AND to_regclass('public.coach_profiles') IS NULL THEN
    ALTER TABLE public.coaches RENAME TO coach_profiles;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.clients') IS NOT NULL
     AND to_regclass('public.client_profiles') IS NULL THEN
    ALTER TABLE public.clients RENAME TO client_profiles;
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- SHARED FUNCTIONS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


-- ----------------------------------------------------------------------------
-- CORE TABLES
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.gyms (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name              text NOT NULL DEFAULT 'My Gym',
  email             text,
  owner_name        text,
  address           text,
  location          text,
  phone             text,
  description       text,
  logo_url          text,
  timezone          text NOT NULL DEFAULT 'Africa/Tunis',
  country_code      text NOT NULL DEFAULT 'TN',
  currency_code     text NOT NULL DEFAULT 'TND',
  subscription_tier text NOT NULL DEFAULT 'free',
  is_active         boolean NOT NULL DEFAULT true,
  manager_id        uuid,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.users (
  id                  uuid PRIMARY KEY,
  name                text NOT NULL DEFAULT 'User',
  email               text,
  role                text NOT NULL DEFAULT 'client',
  gym_id              uuid,
  phone               text,
  avatar_url          text,
  language_preference text NOT NULL DEFAULT 'fr',
  is_managed          boolean NOT NULL DEFAULT false,
  is_active           boolean NOT NULL DEFAULT true,
  last_seen_at        timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);


-- ----------------------------------------------------------------------------
-- CORE COLUMN PATCHES
-- ----------------------------------------------------------------------------

ALTER TABLE public.gyms
  ADD COLUMN IF NOT EXISTS email             text,
  ADD COLUMN IF NOT EXISTS owner_name        text,
  ADD COLUMN IF NOT EXISTS address           text,
  ADD COLUMN IF NOT EXISTS location          text,
  ADD COLUMN IF NOT EXISTS phone             text,
  ADD COLUMN IF NOT EXISTS description       text,
  ADD COLUMN IF NOT EXISTS logo_url          text,
  ADD COLUMN IF NOT EXISTS timezone          text NOT NULL DEFAULT 'Africa/Tunis',
  ADD COLUMN IF NOT EXISTS country_code      text NOT NULL DEFAULT 'TN',
  ADD COLUMN IF NOT EXISTS currency_code     text NOT NULL DEFAULT 'TND',
  ADD COLUMN IF NOT EXISTS subscription_tier text NOT NULL DEFAULT 'free',
  ADD COLUMN IF NOT EXISTS is_active         boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS manager_id        uuid,
  ADD COLUMN IF NOT EXISTS created_at        timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at        timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS name                text NOT NULL DEFAULT 'User',
  ADD COLUMN IF NOT EXISTS email               text,
  ADD COLUMN IF NOT EXISTS role                text NOT NULL DEFAULT 'client',
  ADD COLUMN IF NOT EXISTS gym_id              uuid,
  ADD COLUMN IF NOT EXISTS phone               text,
  ADD COLUMN IF NOT EXISTS avatar_url          text,
  ADD COLUMN IF NOT EXISTS language_preference text NOT NULL DEFAULT 'fr',
  ADD COLUMN IF NOT EXISTS is_managed          boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_active           boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS last_seen_at        timestamptz,
  ADD COLUMN IF NOT EXISTS created_at          timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at          timestamptz NOT NULL DEFAULT now();


-- ----------------------------------------------------------------------------
-- DATA NORMALIZATION
-- ----------------------------------------------------------------------------

UPDATE public.gyms
SET
  name = COALESCE(NULLIF(BTRIM(name), ''), 'My Gym'),
  email = NULLIF(BTRIM(email), ''),
  owner_name = NULLIF(BTRIM(owner_name), ''),
  address = NULLIF(BTRIM(address), ''),
  location = COALESCE(NULLIF(BTRIM(location), ''), NULLIF(BTRIM(address), '')),
  phone = NULLIF(BTRIM(phone), ''),
  timezone = COALESCE(NULLIF(BTRIM(timezone), ''), 'Africa/Tunis'),
  country_code = COALESCE(NULLIF(upper(BTRIM(country_code)), ''), 'TN'),
  currency_code = COALESCE(NULLIF(upper(BTRIM(currency_code)), ''), 'TND'),
  subscription_tier = COALESCE(NULLIF(lower(BTRIM(subscription_tier)), ''), 'free'),
  is_active = COALESCE(is_active, true),
  created_at = COALESCE(created_at, now()),
  updated_at = COALESCE(updated_at, now());

UPDATE public.users
SET
  name = COALESCE(NULLIF(BTRIM(name), ''), 'User'),
  email = NULLIF(lower(BTRIM(email)), ''),
  role = COALESCE(NULLIF(lower(BTRIM(role)), ''), 'client'),
  phone = NULLIF(BTRIM(phone), ''),
  language_preference = COALESCE(NULLIF(lower(BTRIM(language_preference)), ''), 'fr'),
  is_managed = COALESCE(is_managed, false),
  is_active = COALESCE(is_active, true),
  created_at = COALESCE(created_at, now()),
  updated_at = COALESCE(updated_at, now());

UPDATE public.users
SET role = CASE
  WHEN role IN ('client', 'coach', 'gym_owner', 'gym', 'admin') THEN role
  ELSE 'client'
END;

UPDATE public.users
SET language_preference = CASE
  WHEN language_preference IN ('fr', 'en', 'ar') THEN language_preference
  ELSE 'fr'
END;

UPDATE public.gyms
SET subscription_tier = CASE
  WHEN subscription_tier IN ('free', 'starter', 'pro', 'enterprise') THEN subscription_tier
  ELSE 'free'
END;


-- ----------------------------------------------------------------------------
-- FOREIGN KEY PREPARATION
-- ----------------------------------------------------------------------------

UPDATE public.users u
SET gym_id = NULL
WHERE gym_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.gyms g
    WHERE g.id = u.gym_id
  );

UPDATE public.gyms g
SET manager_id = NULL
WHERE manager_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = g.manager_id
  );

UPDATE public.gyms g
SET manager_id = src.user_id
FROM (
  SELECT DISTINCT ON (u.gym_id)
    u.gym_id,
    u.id AS user_id
  FROM public.users u
  WHERE u.gym_id IS NOT NULL
    AND u.role IN ('gym_owner', 'gym', 'admin')
  ORDER BY u.gym_id,
           CASE u.role
             WHEN 'gym_owner' THEN 0
             WHEN 'admin' THEN 1
             ELSE 2
           END,
           u.created_at,
           u.id
) AS src
WHERE g.id = src.gym_id
  AND g.manager_id IS NULL;


-- ----------------------------------------------------------------------------
-- DUPLICATE EMAIL REPAIR
-- ----------------------------------------------------------------------------

WITH ranked_emails AS (
  SELECT
    id,
    email,
    is_managed,
    ROW_NUMBER() OVER (
      PARTITION BY lower(email)
      ORDER BY is_managed ASC, created_at ASC, id ASC
    ) AS rn
  FROM public.users
  WHERE email IS NOT NULL
)
UPDATE public.users u
SET email = CASE
  WHEN position('@' IN u.email) > 1 THEN
    lower(split_part(u.email, '@', 1) || '+legacy-' || left(u.id::text, 8) || '@' || split_part(u.email, '@', 2))
  ELSE
    lower('managed+' || left(u.id::text, 8) || '@trainw.local')
END
FROM ranked_emails r
WHERE u.id = r.id
  AND r.rn > 1
  AND u.is_managed = true;


-- ----------------------------------------------------------------------------
-- CONSTRAINTS
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.gyms'::regclass
      AND conname = 'gyms_subscription_tier_check'
  ) THEN
    ALTER TABLE public.gyms
      ADD CONSTRAINT gyms_subscription_tier_check
      CHECK (subscription_tier IN ('free', 'starter', 'pro', 'enterprise'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.users'::regclass
      AND conname = 'users_role_check'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_role_check
      CHECK (role IN ('client', 'coach', 'gym_owner', 'gym', 'admin'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.users'::regclass
      AND conname = 'users_language_preference_check'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_language_preference_check
      CHECK (language_preference IN ('fr', 'en', 'ar'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.users'::regclass
      AND conname = 'users_gym_id_fkey'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_gym_id_fkey
      FOREIGN KEY (gym_id)
      REFERENCES public.gyms(id)
      ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.gyms'::regclass
      AND conname = 'gyms_manager_id_fkey'
  ) THEN
    ALTER TABLE public.gyms
      ADD CONSTRAINT gyms_manager_id_fkey
      FOREIGN KEY (manager_id)
      REFERENCES public.users(id)
      ON DELETE SET NULL;
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- UPDATED_AT TRIGGERS
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_gyms_upd ON public.gyms;
CREATE TRIGGER trg_gyms_upd
  BEFORE UPDATE ON public.gyms
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_users_upd ON public.users;
CREATE TRIGGER trg_users_upd
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ----------------------------------------------------------------------------
-- INDEXES
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_gyms_is_active
  ON public.gyms(is_active);

CREATE INDEX IF NOT EXISTS idx_gyms_manager_id
  ON public.gyms(manager_id);

CREATE INDEX IF NOT EXISTS idx_users_gym_role
  ON public.users(gym_id, role, is_active);

CREATE INDEX IF NOT EXISTS idx_users_role
  ON public.users(role);

CREATE INDEX IF NOT EXISTS idx_users_last_seen_at
  ON public.users(last_seen_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_active
  ON public.users (lower(email))
  WHERE email IS NOT NULL AND is_active = true;

