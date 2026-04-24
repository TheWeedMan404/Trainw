-- ============================================================================
-- TRAINW V17 PRODUCTION - TURNSTILE AND ACCESS CONTROL
-- Purpose:
--   - Add production-safe member credential storage
--   - Add permanent access-attempt auditing for gate hardware
--   - Support RFID / fingerprint / face validation through one RPC
--   - Preserve compatibility with the existing QR gate session flow
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ENUMS
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'member_credential_type'
  ) THEN
    CREATE TYPE public.member_credential_type AS ENUM (
      'rfid_card',
      'fingerprint',
      'face'
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'gate_access_credential_type'
  ) THEN
    CREATE TYPE public.gate_access_credential_type AS ENUM (
      'qr',
      'rfid_card',
      'fingerprint',
      'face',
      'manual'
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'member_credential_type'
      AND e.enumlabel = 'rfid_card'
  ) THEN
    ALTER TYPE public.member_credential_type ADD VALUE 'rfid_card';
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'member_credential_type'
      AND e.enumlabel = 'fingerprint'
  ) THEN
    ALTER TYPE public.member_credential_type ADD VALUE 'fingerprint';
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'member_credential_type'
      AND e.enumlabel = 'face'
  ) THEN
    ALTER TYPE public.member_credential_type ADD VALUE 'face';
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'gate_access_credential_type'
      AND e.enumlabel = 'qr'
  ) THEN
    ALTER TYPE public.gate_access_credential_type ADD VALUE 'qr';
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'gate_access_credential_type'
      AND e.enumlabel = 'rfid_card'
  ) THEN
    ALTER TYPE public.gate_access_credential_type ADD VALUE 'rfid_card';
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'gate_access_credential_type'
      AND e.enumlabel = 'fingerprint'
  ) THEN
    ALTER TYPE public.gate_access_credential_type ADD VALUE 'fingerprint';
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'gate_access_credential_type'
      AND e.enumlabel = 'face'
  ) THEN
    ALTER TYPE public.gate_access_credential_type ADD VALUE 'face';
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'gate_access_credential_type'
      AND e.enumlabel = 'manual'
  ) THEN
    ALTER TYPE public.gate_access_credential_type ADD VALUE 'manual';
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;


-- ----------------------------------------------------------------------------
-- CHECK-IN COMPATIBILITY
-- ----------------------------------------------------------------------------

UPDATE public.check_ins
SET method = CASE
  WHEN method IN ('manual', 'qr', 'qr_gate', 'rfid_card', 'fingerprint', 'face', 'system') THEN method
  ELSE 'manual'
END
WHERE method IS DISTINCT FROM CASE
  WHEN method IN ('manual', 'qr', 'qr_gate', 'rfid_card', 'fingerprint', 'face', 'system') THEN method
  ELSE 'manual'
END;

ALTER TABLE public.check_ins
  DROP CONSTRAINT IF EXISTS check_ins_method_check;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.check_ins'::regclass
      AND conname = 'check_ins_method_check'
  ) THEN
    ALTER TABLE public.check_ins
      ADD CONSTRAINT check_ins_method_check
      CHECK (method IN ('manual', 'qr', 'qr_gate', 'rfid_card', 'fingerprint', 'face', 'system')) NOT VALID;
  END IF;
END $$;

ALTER TABLE public.gate_sessions
  ADD COLUMN IF NOT EXISTS device_id text;

CREATE INDEX IF NOT EXISTS idx_gate_sessions_gym_device
  ON public.gate_sessions(gym_id, device_id)
  WHERE device_id IS NOT NULL;


-- ----------------------------------------------------------------------------
-- MEMBER CREDENTIALS
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.member_credentials (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id           uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  client_id        uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type             public.member_credential_type NOT NULL,
  credential_data  text NOT NULL,
  label            text,
  is_active        boolean NOT NULL DEFAULT true,
  enrolled_by      uuid REFERENCES public.users(id) ON DELETE SET NULL,
  enrolled_at      timestamptz NOT NULL DEFAULT now(),
  last_used_at     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.member_credentials
  ADD COLUMN IF NOT EXISTS gym_id          uuid,
  ADD COLUMN IF NOT EXISTS client_id       uuid,
  ADD COLUMN IF NOT EXISTS type            public.member_credential_type,
  ADD COLUMN IF NOT EXISTS credential_data text,
  ADD COLUMN IF NOT EXISTS label           text,
  ADD COLUMN IF NOT EXISTS is_active       boolean,
  ADD COLUMN IF NOT EXISTS enrolled_by     uuid,
  ADD COLUMN IF NOT EXISTS enrolled_at     timestamptz,
  ADD COLUMN IF NOT EXISTS last_used_at    timestamptz,
  ADD COLUMN IF NOT EXISTS created_at      timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at      timestamptz;

ALTER TABLE public.member_credentials
  ALTER COLUMN is_active SET DEFAULT true,
  ALTER COLUMN enrolled_at SET DEFAULT now(),
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET DEFAULT now();

UPDATE public.member_credentials
SET
  credential_data = NULLIF(BTRIM(credential_data), ''),
  label = NULLIF(BTRIM(label), ''),
  is_active = COALESCE(is_active, true),
  enrolled_at = COALESCE(enrolled_at, created_at, now()),
  created_at = COALESCE(created_at, now()),
  updated_at = COALESCE(updated_at, now());

UPDATE public.member_credentials
SET last_used_at = NULL
WHERE last_used_at IS NOT NULL
  AND last_used_at < created_at;

ALTER TABLE public.member_credentials
  ALTER COLUMN gym_id SET NOT NULL,
  ALTER COLUMN client_id SET NOT NULL,
  ALTER COLUMN type SET NOT NULL,
  ALTER COLUMN credential_data SET NOT NULL,
  ALTER COLUMN is_active SET NOT NULL,
  ALTER COLUMN enrolled_at SET NOT NULL,
  ALTER COLUMN created_at SET NOT NULL,
  ALTER COLUMN updated_at SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.member_credentials'::regclass
      AND conname = 'member_credentials_non_blank_data'
  ) THEN
    ALTER TABLE public.member_credentials
      ADD CONSTRAINT member_credentials_non_blank_data
      CHECK (BTRIM(credential_data) <> '') NOT VALID;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_member_credentials_gym_type_data_idx
  ON public.member_credentials(gym_id, type, credential_data);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.member_credentials'::regclass
      AND conname = 'member_credentials_gym_type_credential_data_key'
  ) THEN
    ALTER TABLE public.member_credentials
      ADD CONSTRAINT member_credentials_gym_type_credential_data_key
      UNIQUE USING INDEX uq_member_credentials_gym_type_data_idx;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_member_credentials_active_lookup
  ON public.member_credentials(gym_id, type, credential_data)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_member_credentials_client_gym
  ON public.member_credentials(client_id, gym_id);

CREATE INDEX IF NOT EXISTS idx_member_credentials_gym_client_active
  ON public.member_credentials(gym_id, client_id, is_active);


-- ----------------------------------------------------------------------------
-- ACCESS AUDIT
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.gate_access_log (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id           uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  client_id        uuid REFERENCES public.users(id) ON DELETE SET NULL,
  credential_type  public.gate_access_credential_type NOT NULL,
  credential_ref   text,
  access_granted   boolean NOT NULL,
  denial_reason    text,
  device_id        text,
  attempted_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.gate_access_log
  ADD COLUMN IF NOT EXISTS gym_id          uuid,
  ADD COLUMN IF NOT EXISTS client_id       uuid,
  ADD COLUMN IF NOT EXISTS credential_type public.gate_access_credential_type,
  ADD COLUMN IF NOT EXISTS credential_ref  text,
  ADD COLUMN IF NOT EXISTS access_granted  boolean,
  ADD COLUMN IF NOT EXISTS denial_reason   text,
  ADD COLUMN IF NOT EXISTS device_id       text,
  ADD COLUMN IF NOT EXISTS attempted_at    timestamptz;

ALTER TABLE public.gate_access_log
  ALTER COLUMN attempted_at SET DEFAULT now();

UPDATE public.gate_access_log
SET
  credential_ref = NULLIF(BTRIM(credential_ref), ''),
  denial_reason = NULLIF(BTRIM(denial_reason), ''),
  device_id = NULLIF(BTRIM(device_id), ''),
  attempted_at = COALESCE(attempted_at, now());

ALTER TABLE public.gate_access_log
  ALTER COLUMN gym_id SET NOT NULL,
  ALTER COLUMN credential_type SET NOT NULL,
  ALTER COLUMN access_granted SET NOT NULL,
  ALTER COLUMN attempted_at SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.gate_access_log'::regclass
      AND conname = 'gate_access_log_denial_reason_check'
  ) THEN
    ALTER TABLE public.gate_access_log
      ADD CONSTRAINT gate_access_log_denial_reason_check
      CHECK (access_granted = true OR NULLIF(BTRIM(denial_reason), '') IS NOT NULL) NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_gate_access_log_gym_attempted_at
  ON public.gate_access_log(gym_id, attempted_at DESC);

CREATE INDEX IF NOT EXISTS idx_gate_access_log_client_attempted_at
  ON public.gate_access_log(client_id, attempted_at DESC)
  WHERE client_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_gate_access_log_gym_granted_attempted_at
  ON public.gate_access_log(gym_id, access_granted, attempted_at DESC);


-- ----------------------------------------------------------------------------
-- HELPERS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.turnstile_truncate_credential_ref(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_value IS NULL OR NULLIF(BTRIM(p_value), '') IS NULL THEN NULL
    WHEN char_length(BTRIM(p_value)) <= 18 THEN BTRIM(p_value)
    ELSE left(BTRIM(p_value), 8) || '...' || right(BTRIM(p_value), 4)
  END;
$$;

CREATE OR REPLACE FUNCTION public.validate_member_credential(
  p_gym_id uuid,
  p_credential_type text,
  p_credential_data text,
  p_device_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_today date := CURRENT_DATE;
  v_type_text text := lower(BTRIM(COALESCE(p_credential_type, '')));
  v_type public.member_credential_type;
  v_log_type public.gate_access_credential_type;
  v_credential_data text := BTRIM(COALESCE(p_credential_data, ''));
  v_device_id text := NULLIF(BTRIM(COALESCE(p_device_id, '')), '');
  v_credential_ref text := public.turnstile_truncate_credential_ref(p_credential_data);
  v_client_id uuid;
  v_client_name text;
  v_membership_start_date date;
  v_membership_end_date date;
  v_payment_status text;
  v_is_user_active boolean;
  v_days_left integer;
BEGIN
  IF p_gym_id IS NULL OR v_type_text = '' OR v_credential_data = '' THEN
    RETURN jsonb_build_object(
      'access', false,
      'reason', 'invalid_credential'
    );
  END IF;

  IF v_type_text NOT IN ('rfid_card', 'fingerprint', 'face') THEN
    RETURN jsonb_build_object(
      'access', false,
      'reason', 'invalid_credential'
    );
  END IF;

  v_type := v_type_text::public.member_credential_type;
  v_log_type := v_type_text::public.gate_access_credential_type;

  PERFORM public.lock_booking_key(
    format('turnstile:credential:%s:%s:%s', p_gym_id, v_type_text, v_credential_data)
  );

  SELECT
    mc.client_id,
    u.name,
    cp.membership_start_date,
    cp.membership_end_date,
    lower(BTRIM(COALESCE(cp.payment_status, ''))),
    COALESCE(u.is_active, true)
  INTO
    v_client_id,
    v_client_name,
    v_membership_start_date,
    v_membership_end_date,
    v_payment_status,
    v_is_user_active
  FROM public.member_credentials mc
  JOIN public.users u
    ON u.id = mc.client_id
  LEFT JOIN public.client_profiles cp
    ON cp.user_id = mc.client_id
  WHERE mc.gym_id = p_gym_id
    AND mc.type = v_type
    AND mc.credential_data = v_credential_data
    AND mc.is_active = true
    AND u.role = 'client'
  FOR UPDATE OF mc;

  IF v_client_id IS NULL THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      NULL,
      v_log_type,
      v_credential_ref,
      false,
      'invalid_credential',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'invalid_credential'
    );
  END IF;

  IF COALESCE(v_is_user_active, true) = false
     OR v_membership_start_date IS NULL
     OR v_membership_start_date > v_today THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      v_client_id,
      v_log_type,
      v_credential_ref,
      false,
      'membership_inactive',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'membership_inactive'
    );
  END IF;

  IF v_membership_end_date IS NOT NULL
     AND v_membership_end_date < v_today THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      v_client_id,
      v_log_type,
      v_credential_ref,
      false,
      'membership_expired',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'membership_expired'
    );
  END IF;

  IF v_payment_status <> 'paid' THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      v_client_id,
      v_log_type,
      v_credential_ref,
      false,
      'payment_unpaid',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'payment_unpaid'
    );
  END IF;

  PERFORM public.lock_booking_key(
    format('turnstile:client:%s:%s', v_client_id, p_gym_id)
  );

  IF EXISTS (
    SELECT 1
    FROM public.check_ins ci
    WHERE ci.gym_id = p_gym_id
      AND ci.client_id = v_client_id
      AND ci.checked_in_at >= (v_now - interval '2 hours')
  ) THEN
    INSERT INTO public.gate_access_log (
      gym_id,
      client_id,
      credential_type,
      credential_ref,
      access_granted,
      denial_reason,
      device_id,
      attempted_at
    )
    VALUES (
      p_gym_id,
      v_client_id,
      v_log_type,
      v_credential_ref,
      false,
      'duplicate_recent_checkin',
      v_device_id,
      v_now
    );

    RETURN jsonb_build_object(
      'access', false,
      'reason', 'duplicate_recent_checkin'
    );
  END IF;

  v_days_left := CASE
    WHEN v_membership_end_date IS NULL THEN NULL
    ELSE GREATEST(v_membership_end_date - v_today, 0)
  END;

  INSERT INTO public.check_ins (
    gym_id,
    client_id,
    checked_in_at,
    method,
    notes
  )
  VALUES (
    p_gym_id,
    v_client_id,
    v_now,
    v_type_text,
    jsonb_build_object(
      'source', 'turnstile',
      'device_id', v_device_id,
      'client_name', COALESCE(v_client_name, 'Client'),
      'days_left', v_days_left
    )::text
  );

  UPDATE public.member_credentials
  SET last_used_at = v_now
  WHERE gym_id = p_gym_id
    AND client_id = v_client_id
    AND type = v_type
    AND credential_data = v_credential_data;

  INSERT INTO public.gate_access_log (
    gym_id,
    client_id,
    credential_type,
    credential_ref,
    access_granted,
    denial_reason,
    device_id,
    attempted_at
  )
  VALUES (
    p_gym_id,
    v_client_id,
    v_log_type,
    v_credential_ref,
    true,
    NULL,
    v_device_id,
    v_now
  );

  RETURN jsonb_build_object(
    'access', true,
    'client_id', v_client_id,
    'client_name', COALESCE(v_client_name, 'Client'),
    'days_left', v_days_left
  );
END;
$$;


-- ----------------------------------------------------------------------------
-- TRIGGERS
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_member_credentials_90_upd ON public.member_credentials;
CREATE TRIGGER trg_member_credentials_90_upd
  BEFORE UPDATE ON public.member_credentials
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ----------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------

ALTER TABLE public.member_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gate_access_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS member_credentials_select ON public.member_credentials;
DROP POLICY IF EXISTS member_credentials_insert ON public.member_credentials;
DROP POLICY IF EXISTS member_credentials_update ON public.member_credentials;
DROP POLICY IF EXISTS member_credentials_delete ON public.member_credentials;
DROP POLICY IF EXISTS gate_access_log_select ON public.gate_access_log;
DROP POLICY IF EXISTS gate_access_log_insert_service ON public.gate_access_log;

CREATE POLICY member_credentials_select ON public.member_credentials
  FOR SELECT
  USING (public.manages_gym(gym_id));

CREATE POLICY member_credentials_insert ON public.member_credentials
  FOR INSERT
  WITH CHECK (
    public.manages_gym(gym_id)
    AND public.user_gym_id(client_id) = gym_id
    AND public.user_role(client_id) = 'client'
    AND (enrolled_by IS NULL OR public.is_same_gym_user(enrolled_by))
  );

CREATE POLICY member_credentials_update ON public.member_credentials
  FOR UPDATE
  USING (public.manages_gym(gym_id))
  WITH CHECK (
    public.manages_gym(gym_id)
    AND public.user_gym_id(client_id) = gym_id
    AND public.user_role(client_id) = 'client'
    AND (enrolled_by IS NULL OR public.is_same_gym_user(enrolled_by))
  );

CREATE POLICY member_credentials_delete ON public.member_credentials
  FOR DELETE
  USING (public.manages_gym(gym_id));

CREATE POLICY gate_access_log_select ON public.gate_access_log
  FOR SELECT
  USING (public.manages_gym(gym_id));

CREATE POLICY gate_access_log_insert_service ON public.gate_access_log
  FOR INSERT
  WITH CHECK (auth.role() = 'service_role');


-- ----------------------------------------------------------------------------
-- GRANTS
-- ----------------------------------------------------------------------------

REVOKE ALL ON TABLE public.member_credentials FROM PUBLIC;
REVOKE ALL ON TABLE public.gate_access_log FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_member_credential(uuid, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.turnstile_truncate_credential_ref(text) FROM PUBLIC;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.member_credentials TO authenticated;
GRANT SELECT ON public.gate_access_log TO authenticated;
GRANT INSERT ON public.gate_access_log TO service_role;
GRANT EXECUTE ON FUNCTION public.validate_member_credential(uuid, text, text, text) TO service_role;

