-- ============================================================================
-- TRAINW 013 ADDITIONS
-- Purpose:
--   - Add personal records tracking
--   - Add milestone photo storage metadata
--   - Add managed gym devices
--   - Allow selected personal tables to operate without a gym_id
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PERSONAL RECORDS
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.personal_records (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id          uuid REFERENCES public.gyms(id) ON DELETE CASCADE,
  exercise_name   text NOT NULL,
  value           numeric(10,2) NOT NULL,
  unit            text NOT NULL DEFAULT 'kg' CHECK (unit IN ('kg', 'reps', 'seconds', 'minutes', 'km')),
  achieved_at     timestamptz NOT NULL DEFAULT now(),
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE IF EXISTS public.personal_records
  ADD COLUMN IF NOT EXISTS id uuid,
  ADD COLUMN IF NOT EXISTS client_id uuid,
  ADD COLUMN IF NOT EXISTS gym_id uuid,
  ADD COLUMN IF NOT EXISTS exercise_name text,
  ADD COLUMN IF NOT EXISTS value numeric(10,2),
  ADD COLUMN IF NOT EXISTS unit text,
  ADD COLUMN IF NOT EXISTS achieved_at timestamptz,
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz;

UPDATE public.personal_records
SET unit = 'kg'
WHERE unit IS NULL;

UPDATE public.personal_records
SET achieved_at = now()
WHERE achieved_at IS NULL;

UPDATE public.personal_records
SET created_at = now()
WHERE created_at IS NULL;

UPDATE public.personal_records
SET id = gen_random_uuid()
WHERE id IS NULL;

ALTER TABLE IF EXISTS public.personal_records
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN unit SET DEFAULT 'kg',
  ALTER COLUMN achieved_at SET DEFAULT now(),
  ALTER COLUMN created_at SET DEFAULT now();

ALTER TABLE IF EXISTS public.personal_records
  ALTER COLUMN id SET NOT NULL,
  ALTER COLUMN client_id SET NOT NULL,
  ALTER COLUMN exercise_name SET NOT NULL,
  ALTER COLUMN value SET NOT NULL,
  ALTER COLUMN unit SET NOT NULL,
  ALTER COLUMN achieved_at SET NOT NULL,
  ALTER COLUMN created_at SET NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'personal_records'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.personal_records'::regclass
      AND conname = 'personal_records_pkey'
  ) THEN
    ALTER TABLE public.personal_records
      ADD CONSTRAINT personal_records_pkey PRIMARY KEY (id);
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'personal_records'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.personal_records'::regclass
      AND conname = 'personal_records_client_id_fkey'
  ) THEN
    ALTER TABLE public.personal_records
      ADD CONSTRAINT personal_records_client_id_fkey
      FOREIGN KEY (client_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'personal_records'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.personal_records'::regclass
      AND conname = 'personal_records_gym_id_fkey'
  ) THEN
    ALTER TABLE public.personal_records
      ADD CONSTRAINT personal_records_gym_id_fkey
      FOREIGN KEY (gym_id) REFERENCES public.gyms(id) ON DELETE CASCADE;
  END IF;
END $$;

ALTER TABLE IF EXISTS public.personal_records
  DROP CONSTRAINT IF EXISTS personal_records_unit_check;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'personal_records'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.personal_records'::regclass
      AND conname = 'personal_records_unit_check'
  ) THEN
    ALTER TABLE public.personal_records
      ADD CONSTRAINT personal_records_unit_check
      CHECK (unit IN ('kg', 'reps', 'seconds', 'minutes', 'km'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_personal_records_client_exercise_achieved_at
  ON public.personal_records(client_id, exercise_name, achieved_at DESC);


-- ----------------------------------------------------------------------------
-- MILESTONE PHOTOS
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.milestone_photos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id          uuid REFERENCES public.gyms(id) ON DELETE CASCADE,
  storage_bucket  text NOT NULL DEFAULT 'trainw-media',
  storage_path    text NOT NULL,
  caption         text,
  is_public       boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE IF EXISTS public.milestone_photos
  ADD COLUMN IF NOT EXISTS id uuid,
  ADD COLUMN IF NOT EXISTS client_id uuid,
  ADD COLUMN IF NOT EXISTS gym_id uuid,
  ADD COLUMN IF NOT EXISTS storage_bucket text,
  ADD COLUMN IF NOT EXISTS storage_path text,
  ADD COLUMN IF NOT EXISTS caption text,
  ADD COLUMN IF NOT EXISTS is_public boolean,
  ADD COLUMN IF NOT EXISTS created_at timestamptz;

UPDATE public.milestone_photos
SET storage_bucket = 'trainw-media'
WHERE storage_bucket IS NULL;

UPDATE public.milestone_photos
SET is_public = false
WHERE is_public IS NULL;

UPDATE public.milestone_photos
SET created_at = now()
WHERE created_at IS NULL;

UPDATE public.milestone_photos
SET id = gen_random_uuid()
WHERE id IS NULL;

ALTER TABLE IF EXISTS public.milestone_photos
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN storage_bucket SET DEFAULT 'trainw-media',
  ALTER COLUMN is_public SET DEFAULT false,
  ALTER COLUMN created_at SET DEFAULT now();

ALTER TABLE IF EXISTS public.milestone_photos
  ALTER COLUMN id SET NOT NULL,
  ALTER COLUMN client_id SET NOT NULL,
  ALTER COLUMN storage_bucket SET NOT NULL,
  ALTER COLUMN storage_path SET NOT NULL,
  ALTER COLUMN is_public SET NOT NULL,
  ALTER COLUMN created_at SET NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'milestone_photos'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.milestone_photos'::regclass
      AND conname = 'milestone_photos_pkey'
  ) THEN
    ALTER TABLE public.milestone_photos
      ADD CONSTRAINT milestone_photos_pkey PRIMARY KEY (id);
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'milestone_photos'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.milestone_photos'::regclass
      AND conname = 'milestone_photos_client_id_fkey'
  ) THEN
    ALTER TABLE public.milestone_photos
      ADD CONSTRAINT milestone_photos_client_id_fkey
      FOREIGN KEY (client_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'milestone_photos'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.milestone_photos'::regclass
      AND conname = 'milestone_photos_gym_id_fkey'
  ) THEN
    ALTER TABLE public.milestone_photos
      ADD CONSTRAINT milestone_photos_gym_id_fkey
      FOREIGN KEY (gym_id) REFERENCES public.gyms(id) ON DELETE CASCADE;
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- DEVICES
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.devices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id          uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  device_id       text NOT NULL,
  name            text NOT NULL,
  type            text NOT NULL CHECK (type IN ('qr_scanner', 'rfid_reader', 'fingerprint_reader', 'face_scanner')),
  is_active       boolean NOT NULL DEFAULT true,
  last_seen_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT devices_gym_id_device_id_key UNIQUE (gym_id, device_id)
);

ALTER TABLE IF EXISTS public.devices
  ADD COLUMN IF NOT EXISTS id uuid,
  ADD COLUMN IF NOT EXISTS gym_id uuid,
  ADD COLUMN IF NOT EXISTS device_id text,
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS type text,
  ADD COLUMN IF NOT EXISTS is_active boolean,
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS created_at timestamptz;

UPDATE public.devices
SET is_active = true
WHERE is_active IS NULL;

UPDATE public.devices
SET created_at = now()
WHERE created_at IS NULL;

UPDATE public.devices
SET id = gen_random_uuid()
WHERE id IS NULL;

ALTER TABLE IF EXISTS public.devices
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN is_active SET DEFAULT true,
  ALTER COLUMN created_at SET DEFAULT now();

ALTER TABLE IF EXISTS public.devices
  ALTER COLUMN id SET NOT NULL,
  ALTER COLUMN gym_id SET NOT NULL,
  ALTER COLUMN device_id SET NOT NULL,
  ALTER COLUMN name SET NOT NULL,
  ALTER COLUMN type SET NOT NULL,
  ALTER COLUMN is_active SET NOT NULL,
  ALTER COLUMN created_at SET NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'devices'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.devices'::regclass
      AND conname = 'devices_pkey'
  ) THEN
    ALTER TABLE public.devices
      ADD CONSTRAINT devices_pkey PRIMARY KEY (id);
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'devices'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.devices'::regclass
      AND conname = 'devices_gym_id_fkey'
  ) THEN
    ALTER TABLE public.devices
      ADD CONSTRAINT devices_gym_id_fkey
      FOREIGN KEY (gym_id) REFERENCES public.gyms(id) ON DELETE CASCADE;
  END IF;
END $$;

ALTER TABLE IF EXISTS public.devices
  DROP CONSTRAINT IF EXISTS devices_type_check;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'devices'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.devices'::regclass
      AND conname = 'devices_type_check'
  ) THEN
    ALTER TABLE public.devices
      ADD CONSTRAINT devices_type_check
      CHECK (type IN ('qr_scanner', 'rfid_reader', 'fingerprint_reader', 'face_scanner'));
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'devices'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.devices'::regclass
      AND conname = 'devices_gym_id_device_id_key'
  ) THEN
    ALTER TABLE public.devices
      ADD CONSTRAINT devices_gym_id_device_id_key UNIQUE (gym_id, device_id);
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- NULLABLE GYM_ID PATCHES
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'weight_logs'
      AND column_name = 'gym_id'
  ) THEN
    ALTER TABLE public.weight_logs
      ALTER COLUMN gym_id DROP NOT NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'client_goals'
      AND column_name = 'gym_id'
  ) THEN
    ALTER TABLE public.client_goals
      ALTER COLUMN gym_id DROP NOT NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'workout_plans'
      AND column_name = 'gym_id'
  ) THEN
    ALTER TABLE public.workout_plans
      ALTER COLUMN gym_id DROP NOT NULL;
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------

ALTER TABLE IF EXISTS public.personal_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.milestone_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.devices ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'personal_records'
      AND policyname = 'personal_records_select'
  ) THEN
    CREATE POLICY personal_records_select ON public.personal_records
      FOR SELECT
      USING (
        client_id = auth.uid()
        OR (gym_id IS NOT NULL AND public.manages_gym(gym_id))
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'personal_records'
      AND policyname = 'personal_records_insert'
  ) THEN
    CREATE POLICY personal_records_insert ON public.personal_records
      FOR INSERT
      WITH CHECK (client_id = auth.uid());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'personal_records'
      AND policyname = 'personal_records_delete'
  ) THEN
    CREATE POLICY personal_records_delete ON public.personal_records
      FOR DELETE
      USING (client_id = auth.uid());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'milestone_photos'
      AND policyname = 'milestone_photos_select'
  ) THEN
    CREATE POLICY milestone_photos_select ON public.milestone_photos
      FOR SELECT
      USING (
        client_id = auth.uid()
        OR (gym_id IS NOT NULL AND public.manages_gym(gym_id))
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'milestone_photos'
      AND policyname = 'milestone_photos_insert'
  ) THEN
    CREATE POLICY milestone_photos_insert ON public.milestone_photos
      FOR INSERT
      WITH CHECK (client_id = auth.uid());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'milestone_photos'
      AND policyname = 'milestone_photos_delete'
  ) THEN
    CREATE POLICY milestone_photos_delete ON public.milestone_photos
      FOR DELETE
      USING (client_id = auth.uid());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'devices'
      AND policyname = 'devices_select'
  ) THEN
    CREATE POLICY devices_select ON public.devices
      FOR SELECT
      USING (public.manages_gym(gym_id));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'devices'
      AND policyname = 'devices_insert'
  ) THEN
    CREATE POLICY devices_insert ON public.devices
      FOR INSERT
      WITH CHECK (public.manages_gym(gym_id));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'devices'
      AND policyname = 'devices_update'
  ) THEN
    CREATE POLICY devices_update ON public.devices
      FOR UPDATE
      USING (public.manages_gym(gym_id))
      WITH CHECK (public.manages_gym(gym_id));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'devices'
      AND policyname = 'devices_delete'
  ) THEN
    CREATE POLICY devices_delete ON public.devices
      FOR DELETE
      USING (public.manages_gym(gym_id));
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- GRANTS
-- ----------------------------------------------------------------------------

REVOKE ALL ON TABLE public.personal_records FROM PUBLIC;
REVOKE ALL ON TABLE public.milestone_photos FROM PUBLIC;
REVOKE ALL ON TABLE public.devices FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

GRANT SELECT, INSERT, DELETE ON TABLE public.personal_records TO authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.milestone_photos TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.devices TO authenticated;

GRANT ALL ON TABLE public.personal_records TO service_role;
GRANT ALL ON TABLE public.milestone_photos TO service_role;
GRANT ALL ON TABLE public.devices TO service_role;

-- No new SQL functions are introduced in this migration, so no additional
-- FUNCTION EXECUTE grants are required here.
