-- ============================================================================
-- TRAINW V17 PRODUCTION - BOOKING, PAYMENTS, REVIEWS
-- Purpose:
--   - Create the production-safe booking and payment layer
--   - Add audit history for session lifecycle changes
--   - Enforce overlap, capacity, and review integrity
--   - Provide RPCs used by the V17 app
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PAYMENTS
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.payments (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id              uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  client_id           uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  session_id          uuid,
  created_by          uuid REFERENCES public.users(id) ON DELETE SET NULL,
  payment_type        text NOT NULL DEFAULT 'membership',
  status              text NOT NULL DEFAULT 'pending',
  provider            text NOT NULL DEFAULT 'manual',
  currency_code       text NOT NULL DEFAULT 'TND',
  amount_total        numeric(12,2) NOT NULL DEFAULT 0,
  amount_paid         numeric(12,2) NOT NULL DEFAULT 0,
  amount_refunded     numeric(12,2) NOT NULL DEFAULT 0,
  invoice_reference   text,
  provider_reference  text,
  due_at              timestamptz,
  paid_at             timestamptz,
  cancelled_at        timestamptz,
  notes               text,
  metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS gym_id             uuid,
  ADD COLUMN IF NOT EXISTS client_id          uuid,
  ADD COLUMN IF NOT EXISTS session_id         uuid,
  ADD COLUMN IF NOT EXISTS created_by         uuid,
  ADD COLUMN IF NOT EXISTS payment_type       text,
  ADD COLUMN IF NOT EXISTS status             text,
  ADD COLUMN IF NOT EXISTS provider           text,
  ADD COLUMN IF NOT EXISTS currency_code      text,
  ADD COLUMN IF NOT EXISTS amount_total       numeric(12,2),
  ADD COLUMN IF NOT EXISTS amount_paid        numeric(12,2),
  ADD COLUMN IF NOT EXISTS amount_refunded    numeric(12,2),
  ADD COLUMN IF NOT EXISTS invoice_reference  text,
  ADD COLUMN IF NOT EXISTS provider_reference text,
  ADD COLUMN IF NOT EXISTS due_at             timestamptz,
  ADD COLUMN IF NOT EXISTS paid_at            timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_at       timestamptz,
  ADD COLUMN IF NOT EXISTS notes              text,
  ADD COLUMN IF NOT EXISTS metadata           jsonb,
  ADD COLUMN IF NOT EXISTS created_at         timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at         timestamptz;

ALTER TABLE public.payments
  ALTER COLUMN payment_type SET DEFAULT 'membership',
  ALTER COLUMN status SET DEFAULT 'pending',
  ALTER COLUMN provider SET DEFAULT 'manual',
  ALTER COLUMN currency_code SET DEFAULT 'TND',
  ALTER COLUMN amount_total SET DEFAULT 0,
  ALTER COLUMN amount_paid SET DEFAULT 0,
  ALTER COLUMN amount_refunded SET DEFAULT 0,
  ALTER COLUMN metadata SET DEFAULT '{}'::jsonb,
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET DEFAULT now();

CREATE TABLE IF NOT EXISTS public.payment_events (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id       uuid NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  gym_id           uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  event_type       text NOT NULL,
  previous_status  text,
  next_status      text,
  amount_delta     numeric(12,2),
  payload          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.payment_events
  ADD COLUMN IF NOT EXISTS payment_id   uuid,
  ADD COLUMN IF NOT EXISTS gym_id       uuid,
  ADD COLUMN IF NOT EXISTS event_type   text,
  ADD COLUMN IF NOT EXISTS previous_status text,
  ADD COLUMN IF NOT EXISTS next_status  text,
  ADD COLUMN IF NOT EXISTS amount_delta numeric(12,2),
  ADD COLUMN IF NOT EXISTS payload      jsonb,
  ADD COLUMN IF NOT EXISTS created_by   uuid,
  ADD COLUMN IF NOT EXISTS created_at   timestamptz;

ALTER TABLE public.payment_events
  ALTER COLUMN payload SET DEFAULT '{}'::jsonb,
  ALTER COLUMN created_at SET DEFAULT now();


-- ----------------------------------------------------------------------------
-- BOOKINGS
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.sessions (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id             uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  coach_id           uuid REFERENCES public.users(id) ON DELETE SET NULL,
  client_id          uuid REFERENCES public.users(id) ON DELETE SET NULL,
  class_id           uuid REFERENCES public.gym_classes(id) ON DELETE SET NULL,
  payment_id         uuid,
  session_date       date NOT NULL DEFAULT CURRENT_DATE,
  start_time         time,
  end_time           time,
  duration_minutes   integer NOT NULL DEFAULT 60,
  type               text NOT NULL DEFAULT 'group_class',
  status             text NOT NULL DEFAULT 'pending',
  notes              text,
  capacity           integer NOT NULL DEFAULT 10,
  attendee_count     integer NOT NULL DEFAULT 0,
  session_name       text NOT NULL DEFAULT 'Session',
  booked_at          timestamptz NOT NULL DEFAULT now(),
  confirmed_at       timestamptz,
  cancelled_at       timestamptz,
  completed_at       timestamptz,
  no_show_at         timestamptz,
  cancellation_reason text,
  booking_source     text NOT NULL DEFAULT 'gym_manager',
  created_by         uuid REFERENCES public.users(id) ON DELETE SET NULL,
  updated_by         uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS class_id            uuid,
  ADD COLUMN IF NOT EXISTS payment_id          uuid,
  ADD COLUMN IF NOT EXISTS end_time            time,
  ADD COLUMN IF NOT EXISTS booked_at           timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS confirmed_at        timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_at        timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at        timestamptz,
  ADD COLUMN IF NOT EXISTS no_show_at          timestamptz,
  ADD COLUMN IF NOT EXISTS cancellation_reason text,
  ADD COLUMN IF NOT EXISTS booking_source      text NOT NULL DEFAULT 'gym_manager',
  ADD COLUMN IF NOT EXISTS created_by          uuid,
  ADD COLUMN IF NOT EXISTS updated_by          uuid;

CREATE TABLE IF NOT EXISTS public.session_enrollments (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  client_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id       uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  enrolled_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (session_id, client_id)
);

ALTER TABLE public.session_enrollments
  ADD COLUMN IF NOT EXISTS gym_id uuid;

CREATE TABLE IF NOT EXISTS public.coach_availability (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id      uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id        uuid REFERENCES public.gyms(id) ON DELETE CASCADE,
  day_of_week   integer NOT NULL,
  start_time    time NOT NULL,
  end_time      time NOT NULL,
  slot_minutes  integer NOT NULL DEFAULT 60,
  is_active     boolean NOT NULL DEFAULT true,
  valid_from    date,
  valid_until   date,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.coach_availability
  ADD COLUMN IF NOT EXISTS valid_from date,
  ADD COLUMN IF NOT EXISTS valid_until date;

CREATE TABLE IF NOT EXISTS public.reviews (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  uuid NOT NULL UNIQUE REFERENCES public.sessions(id) ON DELETE CASCADE,
  coach_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  client_id   uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id      uuid REFERENCES public.gyms(id) ON DELETE SET NULL,
  rating      integer NOT NULL,
  comment     text,
  is_visible  boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS session_id uuid,
  ADD COLUMN IF NOT EXISTS coach_id uuid,
  ADD COLUMN IF NOT EXISTS client_id uuid,
  ADD COLUMN IF NOT EXISTS gym_id uuid,
  ADD COLUMN IF NOT EXISTS rating integer,
  ADD COLUMN IF NOT EXISTS comment text,
  ADD COLUMN IF NOT EXISTS is_visible boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

ALTER TABLE public.reviews
  ALTER COLUMN is_visible SET DEFAULT true,
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET DEFAULT now();

CREATE TABLE IF NOT EXISTS public.session_status_history (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id       uuid NOT NULL,
  gym_id           uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  event_type       text NOT NULL,
  previous_status  text,
  new_status       text NOT NULL,
  reason           text,
  metadata         jsonb NOT NULL DEFAULT '{}'::jsonb,
  session_snapshot jsonb,
  changed_by       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  changed_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.session_status_history
  ADD COLUMN IF NOT EXISTS session_id       uuid,
  ADD COLUMN IF NOT EXISTS gym_id           uuid,
  ADD COLUMN IF NOT EXISTS event_type       text,
  ADD COLUMN IF NOT EXISTS previous_status  text,
  ADD COLUMN IF NOT EXISTS new_status       text,
  ADD COLUMN IF NOT EXISTS reason           text,
  ADD COLUMN IF NOT EXISTS metadata         jsonb,
  ADD COLUMN IF NOT EXISTS session_snapshot jsonb,
  ADD COLUMN IF NOT EXISTS changed_by       uuid,
  ADD COLUMN IF NOT EXISTS changed_at       timestamptz;

ALTER TABLE public.session_status_history
  ALTER COLUMN metadata SET DEFAULT '{}'::jsonb,
  ALTER COLUMN changed_at SET DEFAULT now();


-- ----------------------------------------------------------------------------
-- DATA BACKFILL AND CONSTRAINT PREPARATION
-- ----------------------------------------------------------------------------

UPDATE public.payments
SET
  payment_type = COALESCE(NULLIF(lower(BTRIM(payment_type)), ''), 'membership'),
  status = COALESCE(NULLIF(lower(BTRIM(status)), ''), 'pending'),
  provider = COALESCE(NULLIF(lower(BTRIM(provider)), ''), 'manual'),
  currency_code = COALESCE(NULLIF(upper(BTRIM(currency_code)), ''), 'TND'),
  amount_total = GREATEST(COALESCE(amount_total, 0), 0),
  amount_paid = LEAST(
    GREATEST(COALESCE(amount_paid, 0), 0),
    GREATEST(COALESCE(amount_total, 0), 0)
  ),
  amount_refunded = LEAST(
    GREATEST(COALESCE(amount_refunded, 0), 0),
    LEAST(
      GREATEST(COALESCE(amount_paid, 0), 0),
      GREATEST(COALESCE(amount_total, 0), 0)
    )
  ),
  metadata = COALESCE(metadata, '{}'::jsonb),
  created_at = COALESCE(created_at, now()),
  updated_at = COALESCE(updated_at, now());

UPDATE public.payments
SET status = CASE
  WHEN status IN ('pending', 'authorized', 'paid', 'failed', 'cancelled', 'refunded', 'partially_refunded') THEN status
  ELSE 'pending'
END,
payment_type = CASE
  WHEN payment_type IN ('membership', 'session', 'package', 'adjustment', 'refund') THEN payment_type
  ELSE 'membership'
END,
provider = CASE
  WHEN provider IN ('manual', 'cash', 'stripe', 'terminal', 'bank_transfer', 'other') THEN provider
  ELSE 'manual'
END;

UPDATE public.sessions
SET
  duration_minutes = GREATEST(COALESCE(duration_minutes, 60), 15),
  capacity = GREATEST(COALESCE(capacity, 10), 1),
  attendee_count = GREATEST(COALESCE(attendee_count, 0), 0),
  type = COALESCE(NULLIF(lower(BTRIM(type)), ''), 'group_class'),
  status = COALESCE(NULLIF(lower(BTRIM(status)), ''), 'pending'),
  session_name = COALESCE(NULLIF(BTRIM(session_name), ''), 'Session'),
  booked_at = COALESCE(booked_at, created_at, now()),
  created_at = COALESCE(created_at, now()),
  updated_at = COALESCE(updated_at, now()),
  created_by = COALESCE(created_by, client_id),
  gym_id = COALESCE(
    gym_id,
    (SELECT u.gym_id FROM public.users u WHERE u.id = sessions.client_id),
    (SELECT u.gym_id FROM public.users u WHERE u.id = sessions.coach_id)
  ),
  end_time = COALESCE(
    end_time,
    CASE
      WHEN start_time IS NOT NULL THEN (start_time + make_interval(mins => GREATEST(COALESCE(duration_minutes, 60), 15)))::time
      ELSE NULL
    END
  ),
  booking_source = COALESCE(NULLIF(lower(BTRIM(booking_source)), ''), 'gym_manager')
WHERE true;

UPDATE public.sessions
SET type = CASE
  WHEN type IN ('group_class', 'group_activity', 'individual_training', 'assessment', 'open_gym', 'other') THEN type
  WHEN type IN ('individual', 'personal', 'personal_training') THEN 'individual_training'
  ELSE 'group_class'
END,
status = CASE
  WHEN status IN ('pending', 'confirmed', 'completed', 'cancelled', 'no_show') THEN status
  WHEN status = 'canceled' THEN 'cancelled'
  ELSE 'pending'
END,
booking_source = CASE
  WHEN booking_source IN ('client', 'gym_manager', 'coach', 'system') THEN booking_source
  ELSE 'gym_manager'
END;

UPDATE public.sessions
SET confirmed_at = CASE
      WHEN status IN ('confirmed', 'completed', 'no_show') THEN COALESCE(
        confirmed_at,
        completed_at,
        no_show_at,
        booked_at,
        updated_at,
        created_at,
        now()
      )
      ELSE confirmed_at
    END,
    cancelled_at = CASE
      WHEN status = 'cancelled' AND cancelled_at IS NULL THEN COALESCE(updated_at, created_at, now())
      ELSE cancelled_at
    END,
    completed_at = CASE
      WHEN status = 'completed' AND completed_at IS NULL THEN COALESCE(
        updated_at,
        confirmed_at,
        booked_at,
        created_at,
        now()
      )
      ELSE completed_at
    END,
    no_show_at = CASE
      WHEN status = 'no_show' AND no_show_at IS NULL THEN COALESCE(
        updated_at,
        confirmed_at,
        booked_at,
        created_at,
        now()
      )
      ELSE no_show_at
    END,
    capacity = CASE
      WHEN type IN ('individual_training', 'assessment') THEN 1
      ELSE GREATEST(COALESCE(capacity, 10), 1)
    END,
    end_time = CASE
      WHEN start_time IS NULL THEN NULL
      WHEN end_time IS NOT NULL AND end_time > start_time THEN end_time
      WHEN (start_time + make_interval(mins => GREATEST(COALESCE(duration_minutes, 60), 15)))::time > start_time THEN
        (start_time + make_interval(mins => GREATEST(COALESCE(duration_minutes, 60), 15)))::time
      WHEN start_time < time '23:59:00' THEN time '23:59:00'
      ELSE NULL
    END,
    attendee_count = CASE
      WHEN type IN ('individual_training', 'assessment') THEN
        CASE WHEN client_id IS NOT NULL THEN 1 ELSE 0 END
      ELSE LEAST(
        GREATEST(COALESCE(attendee_count, 0), 0),
        GREATEST(COALESCE(capacity, 10), 1)
      )
    END;

UPDATE public.session_enrollments se
SET gym_id = s.gym_id
FROM public.sessions s
WHERE s.id = se.session_id
  AND (se.gym_id IS NULL OR se.gym_id <> s.gym_id);

UPDATE public.coach_availability ca
SET
  gym_id = COALESCE(ca.gym_id, u.gym_id),
  day_of_week = LEAST(GREATEST(COALESCE(ca.day_of_week, 0), 0), 6),
  slot_minutes = GREATEST(COALESCE(ca.slot_minutes, 60), 15),
  end_time = CASE
    WHEN ca.start_time IS NULL THEN ca.end_time
    WHEN ca.end_time IS NOT NULL AND ca.end_time > ca.start_time THEN ca.end_time
    WHEN (ca.start_time + make_interval(mins => GREATEST(COALESCE(ca.slot_minutes, 60), 15)))::time > ca.start_time THEN
      (ca.start_time + make_interval(mins => GREATEST(COALESCE(ca.slot_minutes, 60), 15)))::time
    WHEN ca.start_time < time '23:59:00' THEN time '23:59:00'
    ELSE NULL
  END,
  is_active = CASE
    WHEN ca.start_time IS NULL THEN false
    ELSE COALESCE(ca.is_active, true)
  END,
  created_at = COALESCE(ca.created_at, now()),
  updated_at = COALESCE(ca.updated_at, now()),
  valid_until = CASE
    WHEN valid_from IS NOT NULL AND valid_until IS NOT NULL AND valid_until < valid_from THEN valid_from
    ELSE valid_until
  END
FROM public.users u
WHERE u.id = ca.coach_id;

UPDATE public.reviews
SET
  rating = LEAST(GREATEST(COALESCE(rating, 3), 1), 5),
  comment = NULLIF(BTRIM(comment), ''),
  is_visible = COALESCE(is_visible, true),
  created_at = COALESCE(created_at, now()),
  updated_at = COALESCE(updated_at, now());

UPDATE public.reviews r
SET
  coach_id = COALESCE(r.coach_id, s.coach_id),
  client_id = COALESCE(r.client_id, s.client_id),
  gym_id = COALESCE(r.gym_id, s.gym_id),
  rating = LEAST(GREATEST(COALESCE(r.rating, 3), 1), 5)
FROM public.sessions s
WHERE s.id = r.session_id;

UPDATE public.session_status_history
SET
  event_type = CASE
    WHEN lower(BTRIM(event_type)) IN ('created', 'updated', 'deleted') THEN lower(BTRIM(event_type))
    WHEN replace(replace(lower(BTRIM(event_type)), '-', '_'), ' ', '_') IN (
      'status_changed',
      'statuschange',
      'statuschanged',
      'state_changed'
    ) THEN 'status_changed'
    ELSE 'updated'
  END,
  previous_status = NULLIF(lower(BTRIM(previous_status)), ''),
  new_status = COALESCE(NULLIF(lower(BTRIM(new_status)), ''), 'updated'),
  reason = NULLIF(BTRIM(reason), ''),
  metadata = COALESCE(metadata, '{}'::jsonb),
  changed_at = COALESCE(changed_at, now());

UPDATE public.session_status_history ssh
SET gym_id = COALESCE(ssh.gym_id, s.gym_id)
FROM public.sessions s
WHERE s.id = ssh.session_id
  AND (ssh.gym_id IS NULL OR ssh.gym_id <> s.gym_id);

UPDATE public.sessions s
SET payment_id = NULL,
    updated_at = now()
WHERE s.payment_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.payments p
    WHERE p.id = s.payment_id
  );

UPDATE public.payments p
SET session_id = NULL,
    notes = CONCAT_WS(' | ', p.notes, 'Detached orphan session reference during V17 migration'),
    updated_at = now()
WHERE p.session_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.sessions s
    WHERE s.id = p.session_id
  );

UPDATE public.check_ins ci
SET source_session_id = NULL,
    notes = CONCAT_WS(' | ', ci.notes, 'Detached orphan session reference during V17 migration')
WHERE ci.source_session_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.sessions s
    WHERE s.id = ci.source_session_id
  );


-- ----------------------------------------------------------------------------
-- SAFETY CONSTRAINTS
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.payments'::regclass
      AND conname = 'payments_type_check'
  ) THEN
    ALTER TABLE public.payments
      ADD CONSTRAINT payments_type_check
      CHECK (payment_type IN ('membership', 'session', 'package', 'adjustment', 'refund')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.payments'::regclass
      AND conname = 'payments_status_check'
  ) THEN
    ALTER TABLE public.payments
      ADD CONSTRAINT payments_status_check
      CHECK (status IN ('pending', 'authorized', 'paid', 'failed', 'cancelled', 'refunded', 'partially_refunded')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.payments'::regclass
      AND conname = 'payments_provider_check'
  ) THEN
    ALTER TABLE public.payments
      ADD CONSTRAINT payments_provider_check
      CHECK (provider IN ('manual', 'cash', 'stripe', 'terminal', 'bank_transfer', 'other')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.payments'::regclass
      AND conname = 'payments_amounts_check'
  ) THEN
    ALTER TABLE public.payments
      ADD CONSTRAINT payments_amounts_check
      CHECK (
        amount_total >= 0
        AND amount_paid >= 0
        AND amount_refunded >= 0
        AND amount_paid <= amount_total
        AND amount_refunded <= amount_paid
      ) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sessions'::regclass
      AND conname = 'sessions_type_check'
  ) THEN
    ALTER TABLE public.sessions
      ADD CONSTRAINT sessions_type_check
      CHECK (type IN ('group_class', 'group_activity', 'individual_training', 'assessment', 'open_gym', 'other')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sessions'::regclass
      AND conname = 'sessions_status_check'
  ) THEN
    ALTER TABLE public.sessions
      ADD CONSTRAINT sessions_status_check
      CHECK (status IN ('pending', 'confirmed', 'completed', 'cancelled', 'no_show')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sessions'::regclass
      AND conname = 'sessions_booking_source_check'
  ) THEN
    ALTER TABLE public.sessions
      ADD CONSTRAINT sessions_booking_source_check
      CHECK (booking_source IN ('client', 'gym_manager', 'coach', 'system')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sessions'::regclass
      AND conname = 'sessions_capacity_counts_check'
  ) THEN
    ALTER TABLE public.sessions
      ADD CONSTRAINT sessions_capacity_counts_check
      CHECK (capacity > 0 AND attendee_count >= 0 AND attendee_count <= capacity) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sessions'::regclass
      AND conname = 'sessions_time_order_check'
  ) THEN
    ALTER TABLE public.sessions
      ADD CONSTRAINT sessions_time_order_check
      CHECK (start_time IS NULL OR end_time IS NULL OR end_time > start_time) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sessions'::regclass
      AND conname = 'sessions_completed_requires_confirmed'
  ) THEN
    ALTER TABLE public.sessions
      ADD CONSTRAINT sessions_completed_requires_confirmed
      CHECK (status <> 'completed' OR confirmed_at IS NOT NULL) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sessions'::regclass
      AND conname = 'sessions_no_show_requires_confirmed'
  ) THEN
    ALTER TABLE public.sessions
      ADD CONSTRAINT sessions_no_show_requires_confirmed
      CHECK (status <> 'no_show' OR confirmed_at IS NOT NULL) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.coach_availability'::regclass
      AND conname = 'coach_availability_day_check'
  ) THEN
    ALTER TABLE public.coach_availability
      ADD CONSTRAINT coach_availability_day_check
      CHECK (day_of_week BETWEEN 0 AND 6) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.coach_availability'::regclass
      AND conname = 'coach_availability_slot_minutes_check'
  ) THEN
    ALTER TABLE public.coach_availability
      ADD CONSTRAINT coach_availability_slot_minutes_check
      CHECK (slot_minutes BETWEEN 15 AND 240) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.coach_availability'::regclass
      AND conname = 'coach_availability_time_order_check'
  ) THEN
    ALTER TABLE public.coach_availability
      ADD CONSTRAINT coach_availability_time_order_check
      CHECK (end_time > start_time) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.coach_availability'::regclass
      AND conname = 'coach_availability_valid_range_check'
  ) THEN
    ALTER TABLE public.coach_availability
      ADD CONSTRAINT coach_availability_valid_range_check
      CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.reviews'::regclass
      AND conname = 'reviews_rating_check'
  ) THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_rating_check
      CHECK (rating BETWEEN 1 AND 5) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.session_status_history'::regclass
      AND conname = 'session_status_history_event_type_check'
  ) THEN
    ALTER TABLE public.session_status_history
      ADD CONSTRAINT session_status_history_event_type_check
      CHECK (event_type IN ('created', 'status_changed', 'updated')) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sessions'::regclass
      AND conname = 'sessions_payment_id_fkey'
  ) THEN
    ALTER TABLE public.sessions
      ADD CONSTRAINT sessions_payment_id_fkey
      FOREIGN KEY (payment_id)
      REFERENCES public.payments(id)
      ON DELETE SET NULL
      NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.payments'::regclass
      AND conname = 'payments_session_id_fkey'
  ) THEN
    ALTER TABLE public.payments
      ADD CONSTRAINT payments_session_id_fkey
      FOREIGN KEY (session_id)
      REFERENCES public.sessions(id)
      ON DELETE SET NULL
      NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.check_ins'::regclass
      AND conname = 'check_ins_source_session_id_fkey'
  ) THEN
    ALTER TABLE public.check_ins
      ADD CONSTRAINT check_ins_source_session_id_fkey
      FOREIGN KEY (source_session_id)
      REFERENCES public.sessions(id)
      ON DELETE SET NULL
      NOT VALID;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- CONFLICT REPAIR
-- ----------------------------------------------------------------------------

WITH normalized_availability AS (
  SELECT
    ca.id,
    ca.coach_id,
    COALESCE(ca.gym_id, u.gym_id) AS normalized_gym_id,
    ca.day_of_week,
    COALESCE(ca.valid_from, '-infinity'::date) AS normalized_valid_from,
    COALESCE(ca.valid_until, 'infinity'::date) AS normalized_valid_until,
    ca.start_time,
    ca.end_time,
    ca.created_at,
    ROW_NUMBER() OVER (
      PARTITION BY ca.coach_id,
                   COALESCE(ca.gym_id, u.gym_id),
                   ca.day_of_week,
                   COALESCE(ca.valid_from, '-infinity'::date),
                   COALESCE(ca.valid_until, 'infinity'::date),
                   ca.start_time,
                   ca.end_time
      ORDER BY ca.created_at ASC, ca.id ASC
    ) AS rn
  FROM public.coach_availability ca
  LEFT JOIN public.users u
    ON u.id = ca.coach_id
  WHERE ca.is_active = true
)
UPDATE public.coach_availability ca
SET is_active = false,
    updated_at = now()
FROM normalized_availability na
WHERE ca.id = na.id
  AND na.rn > 1
  AND ca.is_active = true;

WITH conflicting_availability AS (
  SELECT DISTINCT later.id
  FROM public.coach_availability earlier
  JOIN public.coach_availability later
    ON later.id <> earlier.id
   AND later.coach_id = earlier.coach_id
   AND COALESCE(later.gym_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = COALESCE(earlier.gym_id, '00000000-0000-0000-0000-000000000000'::uuid)
   AND later.day_of_week = earlier.day_of_week
   AND later.is_active = true
   AND earlier.is_active = true
   AND daterange(
         COALESCE(later.valid_from, '-infinity'::date),
         COALESCE(later.valid_until + 1, 'infinity'::date),
         '[)'
       ) && daterange(
         COALESCE(earlier.valid_from, '-infinity'::date),
         COALESCE(earlier.valid_until + 1, 'infinity'::date),
         '[)'
       )
   AND later.start_time IS NOT NULL
   AND later.end_time IS NOT NULL
   AND earlier.start_time IS NOT NULL
   AND earlier.end_time IS NOT NULL
   AND later.start_time < earlier.end_time
   AND earlier.start_time < later.end_time
   AND (
     COALESCE(later.created_at, now()) > COALESCE(earlier.created_at, now())
     OR (
       COALESCE(later.created_at, now()) = COALESCE(earlier.created_at, now())
       AND later.id > earlier.id
     )
   )
)
UPDATE public.coach_availability ca
SET is_active = false,
    updated_at = now()
FROM conflicting_availability c
WHERE ca.id = c.id
  AND ca.is_active = true;

WITH conflicting_sessions AS (
  SELECT DISTINCT later.id
  FROM public.sessions earlier
  JOIN public.sessions later
    ON later.id <> earlier.id
   AND later.session_date = earlier.session_date
   AND COALESCE(later.status, 'pending') IN ('pending', 'confirmed')
   AND COALESCE(earlier.status, 'pending') IN ('pending', 'confirmed')
   AND (
     (
       later.coach_id IS NOT NULL
       AND later.coach_id = earlier.coach_id
     )
     OR (
       later.client_id IS NOT NULL
       AND later.client_id = earlier.client_id
     )
   )
   AND later.start_time IS NOT NULL
   AND earlier.start_time IS NOT NULL
   AND COALESCE(later.end_time, (later.start_time + make_interval(mins => COALESCE(later.duration_minutes, 60)))::time)
       > earlier.start_time
   AND COALESCE(earlier.end_time, (earlier.start_time + make_interval(mins => COALESCE(earlier.duration_minutes, 60)))::time)
       > later.start_time
   AND (
     COALESCE(later.confirmed_at, later.booked_at, later.created_at, now())
       > COALESCE(earlier.confirmed_at, earlier.booked_at, earlier.created_at, now())
     OR (
       COALESCE(later.confirmed_at, later.booked_at, later.created_at, now())
         = COALESCE(earlier.confirmed_at, earlier.booked_at, earlier.created_at, now())
       AND later.id > earlier.id
     )
   )
)
UPDATE public.sessions s
SET status = 'cancelled',
    cancelled_at = COALESCE(s.cancelled_at, now()),
    cancellation_reason = COALESCE(NULLIF(s.cancellation_reason, ''), 'migration_overlap_cleanup'),
    updated_at = now()
FROM conflicting_sessions c
WHERE s.id = c.id
  AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed');


-- ----------------------------------------------------------------------------
-- BOOKING HELPERS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.client_membership_is_active(
  p_client_id uuid,
  p_reference_date date DEFAULT CURRENT_DATE
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.client_profiles cp
    JOIN public.users u
      ON u.id = cp.user_id
    WHERE cp.user_id = p_client_id
      AND u.role = 'client'
      AND (
        cp.payment_status IN ('paid', 'trial', 'waived')
        OR (
          cp.price_paid > 0
          AND cp.payment_status NOT IN ('cancelled', 'refunded', 'overdue')
        )
      )
      AND (
        cp.membership_end_date IS NULL
        OR cp.membership_end_date >= p_reference_date
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.session_effective_end_time(
  p_start_time time,
  p_end_time time,
  p_duration_minutes integer
)
RETURNS time
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    p_end_time,
    CASE
      WHEN p_start_time IS NULL THEN NULL
      ELSE (p_start_time + make_interval(mins => GREATEST(COALESCE(p_duration_minutes, 60), 15)))::time
    END
  );
$$;

CREATE OR REPLACE FUNCTION public.session_time_range(
  p_session_date date,
  p_start_time time,
  p_end_time time,
  p_duration_minutes integer
)
RETURNS tsrange
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_session_date IS NULL OR p_start_time IS NULL THEN NULL
    ELSE tsrange(
      (p_session_date + p_start_time)::timestamp,
      (p_session_date + public.session_effective_end_time(p_start_time, p_end_time, p_duration_minutes))::timestamp,
      '[)'
    )
  END;
$$;

CREATE OR REPLACE FUNCTION public.lock_booking_key(p_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(COALESCE(p_key, ''), 0));
END;
$$;


-- ----------------------------------------------------------------------------
-- AUDIT PREPARATION
-- ----------------------------------------------------------------------------

ALTER TABLE public.session_status_history
  ADD COLUMN IF NOT EXISTS session_snapshot jsonb;

DO $$
DECLARE
  v_constraint_name text;
  v_attnum smallint;
BEGIN
  SELECT attnum
  INTO v_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.session_status_history'::regclass
    AND attname = 'session_id'
    AND NOT attisdropped;

  IF v_attnum IS NOT NULL THEN
    FOR v_constraint_name IN
      SELECT conname
      FROM pg_constraint
      WHERE conrelid = 'public.session_status_history'::regclass
        AND contype = 'f'
        AND conkey = ARRAY[v_attnum]
    LOOP
      EXECUTE format(
        'ALTER TABLE public.session_status_history DROP CONSTRAINT %I',
        v_constraint_name
      );
    END LOOP;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.session_status_history'::regclass
      AND conname = 'session_status_history_event_type_check'
  ) THEN
    ALTER TABLE public.session_status_history
      DROP CONSTRAINT session_status_history_event_type_check;
  END IF;

  ALTER TABLE public.session_status_history
    ADD CONSTRAINT session_status_history_event_type_check
    CHECK (event_type IN ('created', 'status_changed', 'updated', 'deleted')) NOT VALID;
END $$;


-- ----------------------------------------------------------------------------
-- PREPARE AND VALIDATE TRIGGERS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prepare_payment_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
BEGIN
  NEW.payment_type := COALESCE(NULLIF(lower(BTRIM(NEW.payment_type)), ''), 'membership');
  NEW.status := COALESCE(NULLIF(lower(BTRIM(NEW.status)), ''), 'pending');
  NEW.provider := COALESCE(NULLIF(lower(BTRIM(NEW.provider)), ''), 'manual');
  NEW.currency_code := COALESCE(NULLIF(upper(BTRIM(NEW.currency_code)), ''), 'TND');
  NEW.notes := NULLIF(BTRIM(NEW.notes), '');
  NEW.invoice_reference := NULLIF(BTRIM(NEW.invoice_reference), '');
  NEW.provider_reference := NULLIF(BTRIM(NEW.provider_reference), '');
  NEW.metadata := COALESCE(NEW.metadata, '{}'::jsonb);
  NEW.amount_total := GREATEST(COALESCE(NEW.amount_total, 0), 0);
  NEW.amount_paid := GREATEST(COALESCE(NEW.amount_paid, 0), 0);
  NEW.amount_refunded := GREATEST(COALESCE(NEW.amount_refunded, 0), 0);

  IF NEW.status = 'canceled' THEN
    NEW.status := 'cancelled';
  END IF;

  IF NEW.session_id IS NOT NULL THEN
    SELECT *
    INTO v_session
    FROM public.sessions s
    WHERE s.id = NEW.session_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'validation_error: payment session does not exist';
    END IF;

    NEW.gym_id := COALESCE(NEW.gym_id, v_session.gym_id);
    NEW.client_id := COALESCE(NEW.client_id, v_session.client_id);

    IF NEW.gym_id IS DISTINCT FROM v_session.gym_id THEN
      RAISE EXCEPTION 'validation_error: payment gym must match session gym';
    END IF;

    IF v_session.client_id IS NOT NULL AND NEW.client_id IS DISTINCT FROM v_session.client_id THEN
      RAISE EXCEPTION 'validation_error: payment client must match session client';
    END IF;
  END IF;

  IF NEW.status = 'paid' AND NEW.paid_at IS NULL THEN
    NEW.paid_at := now();
  ELSIF NEW.status = 'cancelled' AND NEW.cancelled_at IS NULL THEN
    NEW.cancelled_at := now();
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.prepare_session_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.duration_minutes := GREATEST(COALESCE(NEW.duration_minutes, 60), 15);
  NEW.type := COALESCE(NULLIF(lower(BTRIM(NEW.type)), ''), 'group_class');
  NEW.status := COALESCE(NULLIF(lower(BTRIM(NEW.status)), ''), 'pending');
  NEW.booking_source := COALESCE(NULLIF(lower(BTRIM(NEW.booking_source)), ''), 'gym_manager');
  NEW.notes := NULLIF(BTRIM(NEW.notes), '');
  NEW.cancellation_reason := NULLIF(BTRIM(NEW.cancellation_reason), '');
  NEW.session_name := COALESCE(
    NULLIF(BTRIM(NEW.session_name), ''),
    CASE
      WHEN NEW.type IN ('individual_training', 'assessment') THEN 'Coach Session'
      WHEN NEW.type = 'open_gym' THEN 'Open Gym'
      ELSE 'Session'
    END
  );
  NEW.booked_at := COALESCE(NEW.booked_at, NEW.created_at, now());
  NEW.gym_id := COALESCE(
    NEW.gym_id,
    (SELECT u.gym_id FROM public.users u WHERE u.id = NEW.client_id),
    (SELECT u.gym_id FROM public.users u WHERE u.id = NEW.coach_id),
    (SELECT gc.gym_id FROM public.gym_classes gc WHERE gc.id = NEW.class_id)
  );

  IF NEW.type IN ('individual', 'personal', 'personal_training') THEN
    NEW.type := 'individual_training';
  END IF;

  IF NEW.status = 'canceled' THEN
    NEW.status := 'cancelled';
  END IF;

  NEW.end_time := public.session_effective_end_time(NEW.start_time, NEW.end_time, NEW.duration_minutes);
  NEW.capacity := GREATEST(
    COALESCE(
      NEW.capacity,
      CASE
        WHEN NEW.type IN ('individual_training', 'assessment') THEN 1
        ELSE 10
      END
    ),
    1
  );

  IF NEW.type IN ('individual_training', 'assessment') THEN
    NEW.capacity := 1;
    NEW.attendee_count := CASE WHEN NEW.client_id IS NOT NULL THEN 1 ELSE 0 END;
  ELSE
    NEW.attendee_count := LEAST(
      GREATEST(COALESCE(NEW.attendee_count, 0), 0),
      NEW.capacity
    );
  END IF;

  IF NEW.status = 'confirmed' THEN
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, now());
  ELSIF NEW.status = 'cancelled' THEN
    NEW.cancelled_at := COALESCE(NEW.cancelled_at, now());
  ELSIF NEW.status = 'completed' THEN
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NEW.booked_at, now());
    NEW.completed_at := COALESCE(NEW.completed_at, now());
  ELSIF NEW.status = 'no_show' THEN
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NEW.booked_at, now());
    NEW.no_show_at := COALESCE(NEW.no_show_at, now());
  END IF;

  NEW.created_by := COALESCE(NEW.created_by, auth.uid(), NEW.client_id);
  NEW.updated_by := COALESCE(auth.uid(), NEW.updated_by, NEW.created_by);

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_coach_availability_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_coach_gym_id uuid;
BEGIN
  SELECT u.gym_id
  INTO v_coach_gym_id
  FROM public.users u
  WHERE u.id = NEW.coach_id
    AND u.role = 'coach';

  IF v_coach_gym_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: availability coach must be an existing coach';
  END IF;

  NEW.gym_id := COALESCE(NEW.gym_id, v_coach_gym_id);
  IF NEW.gym_id IS DISTINCT FROM v_coach_gym_id THEN
    RAISE EXCEPTION 'validation_error: availability gym must match coach gym';
  END IF;

  PERFORM public.lock_booking_key(
    format(
      'availability:%s:%s:%s',
      NEW.coach_id,
      COALESCE(NEW.gym_id::text, 'none'),
      NEW.day_of_week
    )
  );

  IF NEW.is_active = true AND EXISTS (
    SELECT 1
    FROM public.coach_availability ca
    WHERE ca.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND ca.coach_id = NEW.coach_id
      AND COALESCE(ca.gym_id, NEW.gym_id) = NEW.gym_id
      AND ca.day_of_week = NEW.day_of_week
      AND ca.is_active = true
      AND daterange(
            COALESCE(ca.valid_from, '-infinity'::date),
            COALESCE(ca.valid_until + 1, 'infinity'::date),
            '[)'
          ) && daterange(
            COALESCE(NEW.valid_from, '-infinity'::date),
            COALESCE(NEW.valid_until + 1, 'infinity'::date),
            '[)'
          )
      AND ca.start_time IS NOT NULL
      AND ca.end_time IS NOT NULL
      AND NEW.start_time IS NOT NULL
      AND NEW.end_time IS NOT NULL
      AND ca.start_time < NEW.end_time
      AND NEW.start_time < ca.end_time
  ) THEN
    RAISE EXCEPTION 'conflict: availability overlaps an existing active window';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_session_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_coach_gym_id uuid;
  v_client_gym_id uuid;
  v_class_gym_id uuid;
  v_payment_gym_id uuid;
  v_payment_client_id uuid;
  v_active_enrollment_count integer;
  v_range tsrange;
BEGIN
  IF NEW.gym_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: session gym is required';
  END IF;

  IF NEW.status IN ('pending', 'confirmed', 'completed', 'no_show')
     AND NEW.start_time IS NULL THEN
    RAISE EXCEPTION 'validation_error: active sessions require a start time';
  END IF;

  IF NEW.coach_id IS NOT NULL THEN
    SELECT u.gym_id
    INTO v_coach_gym_id
    FROM public.users u
    WHERE u.id = NEW.coach_id
      AND u.role = 'coach';

    IF v_coach_gym_id IS NULL THEN
      RAISE EXCEPTION 'validation_error: session coach must be a coach user';
    END IF;

    IF v_coach_gym_id IS DISTINCT FROM NEW.gym_id THEN
      RAISE EXCEPTION 'validation_error: coach must belong to the session gym';
    END IF;
  END IF;

  IF NEW.client_id IS NOT NULL THEN
    SELECT u.gym_id
    INTO v_client_gym_id
    FROM public.users u
    WHERE u.id = NEW.client_id
      AND u.role = 'client';

    IF v_client_gym_id IS NULL THEN
      RAISE EXCEPTION 'validation_error: session client must be a client user';
    END IF;

    IF v_client_gym_id IS DISTINCT FROM NEW.gym_id THEN
      RAISE EXCEPTION 'validation_error: client must belong to the session gym';
    END IF;
  END IF;

  IF NEW.class_id IS NOT NULL THEN
    SELECT gc.gym_id
    INTO v_class_gym_id
    FROM public.gym_classes gc
    WHERE gc.id = NEW.class_id;

    IF v_class_gym_id IS NULL THEN
      RAISE EXCEPTION 'validation_error: linked class does not exist';
    END IF;

    IF v_class_gym_id IS DISTINCT FROM NEW.gym_id THEN
      RAISE EXCEPTION 'validation_error: linked class must belong to the session gym';
    END IF;
  END IF;

  IF NEW.payment_id IS NOT NULL THEN
    SELECT p.gym_id, p.client_id
    INTO v_payment_gym_id, v_payment_client_id
    FROM public.payments p
    WHERE p.id = NEW.payment_id;

    IF v_payment_gym_id IS NULL THEN
      RAISE EXCEPTION 'validation_error: linked payment does not exist';
    END IF;

    IF v_payment_gym_id IS DISTINCT FROM NEW.gym_id THEN
      RAISE EXCEPTION 'validation_error: linked payment must belong to the session gym';
    END IF;

    IF NEW.client_id IS NOT NULL
       AND v_payment_client_id IS NOT NULL
       AND v_payment_client_id IS DISTINCT FROM NEW.client_id THEN
      RAISE EXCEPTION 'validation_error: linked payment must belong to the session client';
    END IF;
  END IF;

  IF NEW.type IN ('individual_training', 'assessment')
     AND NEW.status IN ('confirmed', 'completed', 'no_show')
     AND NEW.client_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: individual sessions must have a client';
  END IF;

  IF NEW.status IN ('completed', 'no_show')
     AND NEW.session_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'invalid_state: future sessions cannot be completed or marked no-show';
  END IF;

  SELECT COUNT(*)
  INTO v_active_enrollment_count
  FROM public.session_enrollments se
  WHERE se.session_id = COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

  IF NEW.type NOT IN ('individual_training', 'assessment')
     AND v_active_enrollment_count > NEW.capacity THEN
    RAISE EXCEPTION 'validation_error: session capacity is below existing enrollments';
  END IF;

  IF NEW.status IN ('pending', 'confirmed')
     AND NEW.start_time IS NOT NULL
     AND NEW.end_time IS NOT NULL THEN
    v_range := public.session_time_range(
      NEW.session_date,
      NEW.start_time,
      NEW.end_time,
      NEW.duration_minutes
    );

    IF NEW.coach_id IS NOT NULL THEN
      PERFORM public.lock_booking_key(
        format('session:coach:%s:%s', NEW.coach_id, NEW.session_date)
      );

      IF EXISTS (
        SELECT 1
        FROM public.sessions s
        WHERE s.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
          AND s.coach_id = NEW.coach_id
          AND s.session_date = NEW.session_date
          AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
          AND public.session_time_range(
                s.session_date,
                s.start_time,
                s.end_time,
                s.duration_minutes
              ) && v_range
      ) THEN
        RAISE EXCEPTION 'conflict: coach already has a session in that slot';
      END IF;
    END IF;

    IF NEW.client_id IS NOT NULL THEN
      PERFORM public.lock_booking_key(
        format('session:client:%s:%s', NEW.client_id, NEW.session_date)
      );

      IF EXISTS (
        SELECT 1
        FROM public.sessions s
        WHERE s.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
          AND s.client_id = NEW.client_id
          AND s.session_date = NEW.session_date
          AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
          AND public.session_time_range(
                s.session_date,
                s.start_time,
                s.end_time,
                s.duration_minutes
              ) && v_range
      ) THEN
        RAISE EXCEPTION 'conflict: client already has a session in that slot';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_session_enrollment_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
  v_client_gym_id uuid;
  v_range tsrange;
  v_enrollment_count integer;
BEGIN
  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = NEW.session_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'validation_error: enrollment session does not exist';
  END IF;

  NEW.gym_id := v_session.gym_id;

  IF COALESCE(v_session.status, 'pending') NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'invalid_state: enrollments are only allowed for pending or confirmed sessions';
  END IF;

  SELECT u.gym_id
  INTO v_client_gym_id
  FROM public.users u
  WHERE u.id = NEW.client_id
    AND u.role = 'client';

  IF v_client_gym_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: enrollment client must be an existing client';
  END IF;

  IF v_client_gym_id IS DISTINCT FROM v_session.gym_id THEN
    RAISE EXCEPTION 'validation_error: enrollment client must belong to the session gym';
  END IF;

  PERFORM public.lock_booking_key(format('enrollment:session:%s', NEW.session_id));
  PERFORM public.lock_booking_key(format('enrollment:client:%s:%s', NEW.client_id, v_session.session_date));

  IF v_session.type IN ('individual_training', 'assessment') THEN
    IF v_session.client_id IS NOT NULL AND v_session.client_id IS DISTINCT FROM NEW.client_id THEN
      RAISE EXCEPTION 'validation_error: individual session already belongs to a different client';
    END IF;
  ELSE
    SELECT COUNT(*)
    INTO v_enrollment_count
    FROM public.session_enrollments se
    WHERE se.session_id = NEW.session_id
      AND se.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

    IF v_enrollment_count >= v_session.capacity THEN
      RAISE EXCEPTION 'conflict: session capacity has been reached';
    END IF;
  END IF;

  v_range := public.session_time_range(
    v_session.session_date,
    v_session.start_time,
    v_session.end_time,
    v_session.duration_minutes
  );

  IF v_range IS NOT NULL AND (
    EXISTS (
      SELECT 1
      FROM public.sessions s
      WHERE s.id <> v_session.id
        AND s.client_id = NEW.client_id
        AND s.session_date = v_session.session_date
        AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
        AND public.session_time_range(
              s.session_date,
              s.start_time,
              s.end_time,
              s.duration_minutes
            ) && v_range
    )
    OR EXISTS (
      SELECT 1
      FROM public.session_enrollments se
      JOIN public.sessions s
        ON s.id = se.session_id
      WHERE se.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
        AND se.client_id = NEW.client_id
        AND s.id <> v_session.id
        AND s.session_date = v_session.session_date
        AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
        AND public.session_time_range(
              s.session_date,
              s.start_time,
              s.end_time,
              s.duration_minutes
            ) && v_range
    )
  ) THEN
    RAISE EXCEPTION 'conflict: client already has another overlapping booking';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.prepare_review_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
BEGIN
  NEW.comment := NULLIF(BTRIM(NEW.comment), '');

  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = NEW.session_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'validation_error: review session does not exist';
  END IF;

  IF COALESCE(v_session.status, 'pending') <> 'completed' THEN
    RAISE EXCEPTION 'invalid_state: only completed sessions can be reviewed';
  END IF;

  NEW.gym_id := COALESCE(NEW.gym_id, v_session.gym_id);
  NEW.coach_id := v_session.coach_id;
  NEW.client_id := v_session.client_id;

  RETURN NEW;
END;
$$;


-- ----------------------------------------------------------------------------
-- MAINTENANCE TRIGGERS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.refresh_session_attendee_count(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF p_session_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.sessions s
  SET attendee_count = CASE
        WHEN s.type IN ('individual_training', 'assessment') THEN
          CASE WHEN s.client_id IS NOT NULL THEN 1 ELSE 0 END
        ELSE LEAST(
          s.capacity,
          COALESCE((
            SELECT COUNT(*)
            FROM public.session_enrollments se
            WHERE se.session_id = s.id
          ), 0)
        )
      END
  WHERE s.id = p_session_id
    AND s.attendee_count IS DISTINCT FROM CASE
      WHEN s.type IN ('individual_training', 'assessment') THEN
        CASE WHEN s.client_id IS NOT NULL THEN 1 ELSE 0 END
      ELSE LEAST(
        s.capacity,
        COALESCE((
          SELECT COUNT(*)
          FROM public.session_enrollments se
          WHERE se.session_id = s.id
        ), 0)
      )
    END;
END;
$$;

DROP TRIGGER IF EXISTS trg_reviews_refresh_stats ON public.reviews;
DROP FUNCTION IF EXISTS public.refresh_coach_review_stats(uuid);
DROP FUNCTION IF EXISTS public.handle_review_stats();

CREATE OR REPLACE FUNCTION public.refresh_coach_review_stats(p_coach_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF p_coach_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.coach_profiles cp
  SET rating = COALESCE(src.avg_rating, 0),
      total_reviews = COALESCE(src.total_reviews, 0),
      updated_at = now()
  FROM (
    SELECT
      r.coach_id,
      ROUND(AVG(r.rating)::numeric, 2) AS avg_rating,
      COUNT(*) AS total_reviews
    FROM public.reviews r
    WHERE r.coach_id = p_coach_id
    GROUP BY r.coach_id
  ) AS src
  WHERE cp.user_id = p_coach_id;

  UPDATE public.coach_profiles cp
  SET rating = 0,
      total_reviews = 0,
      updated_at = now()
  WHERE cp.user_id = p_coach_id
    AND NOT EXISTS (
      SELECT 1
      FROM public.reviews r
      WHERE r.coach_id = p_coach_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_session_enrollment_counts()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  PERFORM public.refresh_session_attendee_count(COALESCE(NEW.session_id, OLD.session_id));
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_session_after_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  PERFORM public.refresh_session_attendee_count(NEW.id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_reviews_after_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM public.refresh_coach_review_stats(OLD.coach_id);
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM public.refresh_coach_review_stats(NEW.coach_id);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.log_payment_event()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_event_type text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.payment_events (
      payment_id,
      gym_id,
      event_type,
      previous_status,
      next_status,
      amount_delta,
      payload,
      created_by
    )
    VALUES (
      NEW.id,
      NEW.gym_id,
      'created',
      NULL,
      NEW.status,
      NEW.amount_paid,
      to_jsonb(NEW),
      COALESCE(NEW.created_by, auth.uid())
    );

    RETURN NEW;
  END IF;

  IF ROW(
    OLD.status,
    OLD.amount_total,
    OLD.amount_paid,
    OLD.amount_refunded,
    OLD.provider_reference,
    OLD.cancelled_at,
    OLD.paid_at
  ) IS NOT DISTINCT FROM ROW(
    NEW.status,
    NEW.amount_total,
    NEW.amount_paid,
    NEW.amount_refunded,
    NEW.provider_reference,
    NEW.cancelled_at,
    NEW.paid_at
  ) THEN
    RETURN NEW;
  END IF;

  v_event_type := CASE
    WHEN OLD.status IS DISTINCT FROM NEW.status THEN 'status_changed'
    ELSE 'updated'
  END;

  INSERT INTO public.payment_events (
    payment_id,
    gym_id,
    event_type,
    previous_status,
    next_status,
    amount_delta,
    payload,
    created_by
  )
  VALUES (
    NEW.id,
    NEW.gym_id,
    v_event_type,
    OLD.status,
    NEW.status,
    COALESCE(NEW.amount_paid, 0) - COALESCE(OLD.amount_paid, 0),
    jsonb_build_object(
      'old', to_jsonb(OLD),
      'new', to_jsonb(NEW)
    ),
    COALESCE(NEW.created_by, auth.uid())
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_session_status_event()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_event_type text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.session_status_history (
      session_id,
      gym_id,
      event_type,
      previous_status,
      new_status,
      reason,
      metadata,
      session_snapshot,
      changed_by
    )
    VALUES (
      NEW.id,
      NEW.gym_id,
      'created',
      NULL,
      NEW.status,
      NEW.cancellation_reason,
      jsonb_build_object(
        'booking_source', NEW.booking_source,
        'type', NEW.type
      ),
      to_jsonb(NEW),
      COALESCE(NEW.created_by, auth.uid())
    );

    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.session_status_history (
      session_id,
      gym_id,
      event_type,
      previous_status,
      new_status,
      reason,
      metadata,
      session_snapshot,
      changed_by
    )
    VALUES (
      OLD.id,
      OLD.gym_id,
      'deleted',
      OLD.status,
      COALESCE(OLD.status, 'cancelled'),
      OLD.cancellation_reason,
      jsonb_build_object('deleted', true),
      to_jsonb(OLD),
      auth.uid()
    );

    RETURN OLD;
  END IF;

  IF ROW(
    OLD.status,
    OLD.session_date,
    OLD.start_time,
    OLD.end_time,
    OLD.duration_minutes,
    OLD.type,
    OLD.coach_id,
    OLD.client_id,
    OLD.capacity,
    OLD.notes,
    OLD.cancellation_reason,
    OLD.payment_id,
    OLD.class_id,
    OLD.booking_source
  ) IS NOT DISTINCT FROM ROW(
    NEW.status,
    NEW.session_date,
    NEW.start_time,
    NEW.end_time,
    NEW.duration_minutes,
    NEW.type,
    NEW.coach_id,
    NEW.client_id,
    NEW.capacity,
    NEW.notes,
    NEW.cancellation_reason,
    NEW.payment_id,
    NEW.class_id,
    NEW.booking_source
  ) THEN
    RETURN NEW;
  END IF;

  v_event_type := CASE
    WHEN OLD.status IS DISTINCT FROM NEW.status THEN 'status_changed'
    ELSE 'updated'
  END;

  INSERT INTO public.session_status_history (
    session_id,
    gym_id,
    event_type,
    previous_status,
    new_status,
    reason,
    metadata,
    session_snapshot,
    changed_by
  )
  VALUES (
    NEW.id,
    NEW.gym_id,
    v_event_type,
    OLD.status,
    NEW.status,
    COALESCE(NEW.cancellation_reason, OLD.cancellation_reason),
    jsonb_build_object(
      'old', to_jsonb(OLD),
      'new', to_jsonb(NEW)
    ),
    to_jsonb(NEW),
    COALESCE(NEW.updated_by, auth.uid(), NEW.created_by)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sessions_booking_sync ON public.sessions;
DROP TRIGGER IF EXISTS trg_sessions_upd ON public.sessions;
DROP TRIGGER IF EXISTS trg_coach_availability_upd ON public.coach_availability;
DROP TRIGGER IF EXISTS trg_reviews_upd ON public.reviews;
DROP TRIGGER IF EXISTS trg_reviews_refresh_stats ON public.reviews;

DROP TRIGGER IF EXISTS trg_payments_10_prepare ON public.payments;
CREATE TRIGGER trg_payments_10_prepare
  BEFORE INSERT OR UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.prepare_payment_write();

DROP TRIGGER IF EXISTS trg_payments_90_upd ON public.payments;
CREATE TRIGGER trg_payments_90_upd
  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_payments_20_audit ON public.payments;
CREATE TRIGGER trg_payments_20_audit
  AFTER INSERT OR UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.log_payment_event();

DROP TRIGGER IF EXISTS trg_sessions_10_prepare ON public.sessions;
CREATE TRIGGER trg_sessions_10_prepare
  BEFORE INSERT OR UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.prepare_session_write();

DROP TRIGGER IF EXISTS trg_sessions_20_validate ON public.sessions;
CREATE TRIGGER trg_sessions_20_validate
  BEFORE INSERT OR UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.validate_session_write();

DROP TRIGGER IF EXISTS trg_sessions_90_upd ON public.sessions;
CREATE TRIGGER trg_sessions_90_upd
  BEFORE UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_sessions_30_sync ON public.sessions;
CREATE TRIGGER trg_sessions_30_sync
  AFTER INSERT OR UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.sync_session_after_write();

DROP TRIGGER IF EXISTS trg_sessions_40_audit ON public.sessions;
CREATE TRIGGER trg_sessions_40_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.log_session_status_event();

DROP TRIGGER IF EXISTS trg_coach_availability_10_validate ON public.coach_availability;
CREATE TRIGGER trg_coach_availability_10_validate
  BEFORE INSERT OR UPDATE ON public.coach_availability
  FOR EACH ROW EXECUTE FUNCTION public.validate_coach_availability_write();

DROP TRIGGER IF EXISTS trg_coach_availability_90_upd ON public.coach_availability;
CREATE TRIGGER trg_coach_availability_90_upd
  BEFORE UPDATE ON public.coach_availability
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_session_enrollments_10_validate ON public.session_enrollments;
CREATE TRIGGER trg_session_enrollments_10_validate
  BEFORE INSERT OR UPDATE ON public.session_enrollments
  FOR EACH ROW EXECUTE FUNCTION public.validate_session_enrollment_write();

DROP TRIGGER IF EXISTS trg_session_enrollments_20_sync ON public.session_enrollments;
CREATE TRIGGER trg_session_enrollments_20_sync
  AFTER INSERT OR UPDATE OR DELETE ON public.session_enrollments
  FOR EACH ROW EXECUTE FUNCTION public.sync_session_enrollment_counts();

DROP TRIGGER IF EXISTS trg_reviews_10_prepare ON public.reviews;
CREATE TRIGGER trg_reviews_10_prepare
  BEFORE INSERT OR UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.prepare_review_write();

DROP TRIGGER IF EXISTS trg_reviews_90_upd ON public.reviews;
CREATE TRIGGER trg_reviews_90_upd
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_reviews_20_refresh ON public.reviews;
CREATE TRIGGER trg_reviews_20_refresh
  AFTER INSERT OR UPDATE OR DELETE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.refresh_reviews_after_write();


-- ----------------------------------------------------------------------------
-- BOOKING RPCS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_bookable_slots(
  p_coach_id uuid,
  p_session_date date
)
RETURNS TABLE (
  slot_time text,
  slot_end_time text,
  slot_minutes integer,
  price_per_session numeric
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH coach_data AS (
    SELECT
      u.id AS coach_id,
      COALESCE(cp.gym_id, u.gym_id) AS gym_id,
      cp.approval_status,
      cp.is_active,
      COALESCE(cp.price_per_session, cp.hourly_rate, 0) AS price_per_session
    FROM public.users u
    JOIN public.coach_profiles cp
      ON cp.user_id = u.id
    WHERE u.id = p_coach_id
      AND u.role = 'coach'
  ),
  windows AS (
    SELECT
      ca.start_time,
      ca.end_time,
      ca.slot_minutes,
      cd.price_per_session
    FROM public.coach_availability ca
    JOIN coach_data cd
      ON TRUE
    WHERE p_session_date IS NOT NULL
      AND p_session_date >= CURRENT_DATE
      AND ca.coach_id = p_coach_id
      AND ca.is_active = true
      AND cd.approval_status = 'approved'
      AND cd.is_active = true
      AND COALESCE(ca.gym_id, cd.gym_id) = public.get_my_gym_id()
      AND ca.day_of_week = EXTRACT(DOW FROM p_session_date)::integer
      AND (ca.valid_from IS NULL OR p_session_date >= ca.valid_from)
      AND (ca.valid_until IS NULL OR p_session_date <= ca.valid_until)
  ),
  raw_slots AS (
    SELECT
      gs.slot_start_ts,
      (gs.slot_start_ts + make_interval(mins => w.slot_minutes)) AS slot_end_ts,
      w.slot_minutes,
      w.price_per_session
    FROM windows w
    CROSS JOIN LATERAL generate_series(
      p_session_date + w.start_time,
      p_session_date + w.end_time - make_interval(mins => w.slot_minutes),
      make_interval(mins => w.slot_minutes)
    ) AS gs(slot_start_ts)
  )
  SELECT
    to_char(rs.slot_start_ts, 'HH24:MI') AS slot_time,
    to_char(rs.slot_end_ts, 'HH24:MI') AS slot_end_time,
    rs.slot_minutes,
    rs.price_per_session
  FROM raw_slots rs
  WHERE rs.slot_start_ts > now()
    AND NOT EXISTS (
      SELECT 1
      FROM public.sessions s
      WHERE s.coach_id = p_coach_id
        AND s.session_date = p_session_date
        AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
        AND public.session_time_range(
              s.session_date,
              s.start_time,
              s.end_time,
              s.duration_minutes
            ) && tsrange(rs.slot_start_ts, rs.slot_end_ts, '[)')
    )
  ORDER BY rs.slot_start_ts;
$$;

CREATE OR REPLACE FUNCTION public.book_coach_session(
  p_coach_id uuid,
  p_session_date date,
  p_start_time time,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_client_id uuid := auth.uid();
  v_client_gym_id uuid := public.get_my_gym_id();
  v_coach_gym_id uuid;
  v_slot_minutes integer;
  v_price numeric(10,2);
  v_session_id uuid;
  v_payment_id uuid;
  v_assignment_id uuid;
BEGIN
  IF v_client_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required: you must be logged in';
  END IF;

  IF public.get_my_role() <> 'client' THEN
    RAISE EXCEPTION 'forbidden: only clients can book coach sessions';
  END IF;

  IF v_client_gym_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: client must belong to a gym';
  END IF;

  IF NOT public.client_membership_is_active(v_client_id, p_session_date) THEN
    RAISE EXCEPTION 'forbidden: membership must be active before booking';
  END IF;

  IF p_session_date IS NULL OR p_start_time IS NULL THEN
    RAISE EXCEPTION 'validation_error: date and start time are required';
  END IF;

  IF p_session_date < CURRENT_DATE
     OR (p_session_date = CURRENT_DATE AND p_start_time <= LOCALTIME) THEN
    RAISE EXCEPTION 'validation_error: booking time must be in the future';
  END IF;

  SELECT
    COALESCE(cp.gym_id, u.gym_id),
    ca.slot_minutes,
    COALESCE(cp.price_per_session, cp.hourly_rate, 0)
  INTO
    v_coach_gym_id,
    v_slot_minutes,
    v_price
  FROM public.users u
  JOIN public.coach_profiles cp
    ON cp.user_id = u.id
  JOIN public.coach_availability ca
    ON ca.coach_id = u.id
  WHERE u.id = p_coach_id
    AND u.role = 'coach'
    AND cp.approval_status = 'approved'
    AND cp.is_active = true
    AND ca.is_active = true
    AND ca.day_of_week = EXTRACT(DOW FROM p_session_date)::integer
    AND p_start_time >= ca.start_time
    AND public.session_effective_end_time(p_start_time, NULL, ca.slot_minutes) <= ca.end_time
    AND MOD(
          EXTRACT(EPOCH FROM (p_start_time - ca.start_time))::integer / 60,
          ca.slot_minutes
        ) = 0
    AND (ca.valid_from IS NULL OR p_session_date >= ca.valid_from)
    AND (ca.valid_until IS NULL OR p_session_date <= ca.valid_until)
  ORDER BY ca.start_time
  LIMIT 1;

  IF v_coach_gym_id IS NULL OR v_coach_gym_id IS DISTINCT FROM v_client_gym_id THEN
    RAISE EXCEPTION 'forbidden: coach is not available for your gym';
  END IF;

  IF v_slot_minutes IS NULL THEN
    RAISE EXCEPTION 'not_bookable: selected slot does not match coach availability';
  END IF;

  PERFORM public.lock_booking_key(format('session:coach:%s:%s', p_coach_id, p_session_date));
  PERFORM public.lock_booking_key(format('session:client:%s:%s', v_client_id, p_session_date));

  INSERT INTO public.sessions (
    gym_id,
    coach_id,
    client_id,
    session_date,
    start_time,
    duration_minutes,
    type,
    status,
    notes,
    capacity,
    session_name,
    booking_source,
    created_by,
    updated_by
  )
  VALUES (
    v_client_gym_id,
    p_coach_id,
    v_client_id,
    p_session_date,
    p_start_time,
    v_slot_minutes,
    'individual_training',
    'pending',
    NULLIF(BTRIM(COALESCE(p_notes, '')), ''),
    1,
    'Coach Session',
    'client',
    v_client_id,
    v_client_id
  )
  RETURNING id INTO v_session_id;

  IF COALESCE(v_price, 0) > 0 THEN
    INSERT INTO public.payments (
      gym_id,
      client_id,
      session_id,
      created_by,
      payment_type,
      status,
      provider,
      amount_total,
      amount_paid,
      currency_code,
      metadata
    )
    VALUES (
      v_client_gym_id,
      v_client_id,
      v_session_id,
      v_client_id,
      'session',
      'pending',
      'manual',
      v_price,
      0,
      'TND',
      jsonb_build_object('source', 'book_coach_session')
    )
    RETURNING id INTO v_payment_id;

    UPDATE public.sessions
    SET payment_id = v_payment_id,
        updated_by = v_client_id
    WHERE id = v_session_id;
  END IF;

  SELECT cca.id
  INTO v_assignment_id
  FROM public.coach_client_assignments cca
  WHERE cca.coach_id = p_coach_id
    AND cca.client_id = v_client_id
    AND cca.gym_id = v_client_gym_id
  ORDER BY cca.is_active DESC, cca.assigned_at DESC, cca.created_at DESC, cca.id DESC
  LIMIT 1;

  IF v_assignment_id IS NULL THEN
    INSERT INTO public.coach_client_assignments (
      coach_id,
      client_id,
      gym_id,
      assigned_by,
      assigned_at,
      is_active
    )
    VALUES (
      p_coach_id,
      v_client_id,
      v_client_gym_id,
      v_client_id,
      now(),
      true
    );
  ELSE
    UPDATE public.coach_client_assignments
    SET is_active = true,
        ended_at = NULL,
        assigned_at = now(),
        assigned_by = COALESCE(assigned_by, v_client_id),
        updated_at = now()
    WHERE id = v_assignment_id;
  END IF;

  RETURN v_session_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_to_session_booking(
  p_session_id uuid,
  p_decision text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
  v_decision text := lower(BTRIM(COALESCE(p_decision, '')));
BEGIN
  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: session does not exist';
  END IF;

  IF NOT (public.manages_gym(v_session.gym_id) OR v_session.coach_id = auth.uid()) THEN
    RAISE EXCEPTION 'forbidden: you cannot update this booking';
  END IF;

  IF COALESCE(v_session.status, 'pending') <> 'pending' THEN
    RAISE EXCEPTION 'invalid_state: only pending sessions can be confirmed or rejected';
  END IF;

  IF v_decision NOT IN ('confirmed', 'cancelled') THEN
    RAISE EXCEPTION 'validation_error: decision must be confirmed or cancelled';
  END IF;

  UPDATE public.sessions
  SET status = v_decision,
      confirmed_at = CASE WHEN v_decision = 'confirmed' THEN COALESCE(confirmed_at, now()) ELSE confirmed_at END,
      cancelled_at = CASE WHEN v_decision = 'cancelled' THEN COALESCE(cancelled_at, now()) ELSE cancelled_at END,
      cancellation_reason = CASE
        WHEN v_decision = 'cancelled' THEN COALESCE(cancellation_reason, 'rejected_by_coach')
        ELSE cancellation_reason
      END,
      updated_by = auth.uid()
  WHERE id = p_session_id;

  IF v_decision = 'cancelled' AND v_session.payment_id IS NOT NULL THEN
    UPDATE public.payments
    SET status = CASE
          WHEN status IN ('pending', 'authorized') THEN 'cancelled'
          ELSE status
        END,
        cancelled_at = CASE
          WHEN status IN ('pending', 'authorized') THEN COALESCE(cancelled_at, now())
          ELSE cancelled_at
        END
    WHERE id = v_session.payment_id;
  END IF;

  RETURN p_session_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_session_booking(
  p_session_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
  v_reason text;
BEGIN
  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: session does not exist';
  END IF;

  IF NOT (
    public.manages_gym(v_session.gym_id)
    OR v_session.client_id = auth.uid()
    OR v_session.coach_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'forbidden: you cannot cancel this session';
  END IF;

  IF COALESCE(v_session.status, 'pending') NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'invalid_state: only pending or confirmed sessions can be cancelled';
  END IF;

  v_reason := NULLIF(BTRIM(COALESCE(p_reason, '')), '');
  IF v_reason IS NULL THEN
    v_reason := CASE
      WHEN v_session.client_id = auth.uid() THEN 'cancelled_by_client'
      WHEN v_session.coach_id = auth.uid() THEN 'cancelled_by_coach'
      ELSE 'cancelled_by_manager'
    END;
  END IF;

  UPDATE public.sessions
  SET status = 'cancelled',
      cancelled_at = COALESCE(cancelled_at, now()),
      cancellation_reason = v_reason,
      updated_by = auth.uid()
  WHERE id = p_session_id;

  IF v_session.payment_id IS NOT NULL THEN
    UPDATE public.payments
    SET status = CASE
          WHEN status IN ('pending', 'authorized') THEN 'cancelled'
          ELSE status
        END,
        cancelled_at = CASE
          WHEN status IN ('pending', 'authorized') THEN COALESCE(cancelled_at, now())
          ELSE cancelled_at
        END
    WHERE id = v_session.payment_id;
  END IF;

  RETURN p_session_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_session_booking(p_session_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
BEGIN
  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: session does not exist';
  END IF;

  IF NOT (public.manages_gym(v_session.gym_id) OR v_session.coach_id = auth.uid()) THEN
    RAISE EXCEPTION 'forbidden: you cannot complete this session';
  END IF;

  IF COALESCE(v_session.status, 'pending') <> 'confirmed' THEN
    RAISE EXCEPTION 'invalid_state: only confirmed sessions can be completed';
  END IF;

  IF v_session.session_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'invalid_state: future sessions cannot be completed';
  END IF;

  UPDATE public.sessions
  SET status = 'completed',
      completed_at = COALESCE(completed_at, now()),
      updated_by = auth.uid()
  WHERE id = p_session_id;

  RETURN p_session_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_session_no_show(p_session_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
BEGIN
  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: session does not exist';
  END IF;

  IF NOT (public.manages_gym(v_session.gym_id) OR v_session.coach_id = auth.uid()) THEN
    RAISE EXCEPTION 'forbidden: you cannot update this session';
  END IF;

  IF COALESCE(v_session.status, 'pending') <> 'confirmed' THEN
    RAISE EXCEPTION 'invalid_state: only confirmed sessions can be marked no-show';
  END IF;

  UPDATE public.sessions
  SET status = 'no_show',
      no_show_at = COALESCE(no_show_at, now()),
      updated_by = auth.uid()
  WHERE id = p_session_id;

  RETURN p_session_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_session_review(
  p_session_id uuid,
  p_rating integer,
  p_comment text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
  v_review_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication_required: you must be logged in';
  END IF;

  IF public.get_my_role() <> 'client' THEN
    RAISE EXCEPTION 'forbidden: only clients can leave reviews';
  END IF;

  IF p_rating IS NULL OR p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'validation_error: rating must be between 1 and 5';
  END IF;

  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: session does not exist';
  END IF;

  IF v_session.client_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'forbidden: you can only review your own sessions';
  END IF;

  IF COALESCE(v_session.status, 'pending') <> 'completed' THEN
    RAISE EXCEPTION 'invalid_state: only completed sessions can be reviewed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.reviews r
    WHERE r.session_id = p_session_id
  ) THEN
    RAISE EXCEPTION 'conflict: a review already exists for this session';
  END IF;

  INSERT INTO public.reviews (
    session_id,
    coach_id,
    client_id,
    gym_id,
    rating,
    comment
  )
  VALUES (
    p_session_id,
    v_session.coach_id,
    v_session.client_id,
    v_session.gym_id,
    p_rating,
    NULLIF(BTRIM(COALESCE(p_comment, '')), '')
  )
  RETURNING id INTO v_review_id;

  RETURN v_review_id;
END;
$$;


-- ----------------------------------------------------------------------------
-- INDEXES
-- ----------------------------------------------------------------------------

WITH ranked_session_payments AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY session_id
      ORDER BY
        CASE status
          WHEN 'paid' THEN 0
          WHEN 'authorized' THEN 1
          WHEN 'pending' THEN 2
          ELSE 3
        END,
        created_at DESC,
        id DESC
    ) AS rn
  FROM public.payments
  WHERE session_id IS NOT NULL
)
UPDATE public.payments p
SET session_id = NULL,
    notes = CONCAT_WS(' | ', p.notes, 'Detached duplicate session payment during V17 migration'),
    updated_at = now()
FROM ranked_session_payments rsp
WHERE p.id = rsp.id
  AND rsp.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_session_id
  ON public.payments(session_id)
  WHERE session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payments_gym_status_created_at
  ON public.payments(gym_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payments_client_status_due_at
  ON public.payments(client_id, status, due_at);

CREATE INDEX IF NOT EXISTS idx_payment_events_payment_created_at
  ON public.payment_events(payment_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sessions_gym_schedule
  ON public.sessions(gym_id, session_date, start_time);

CREATE INDEX IF NOT EXISTS idx_sessions_gym_status_schedule
  ON public.sessions(gym_id, status, session_date, start_time);

CREATE INDEX IF NOT EXISTS idx_sessions_upcoming_coach
  ON public.sessions(coach_id, session_date, start_time)
  WHERE coach_id IS NOT NULL AND status IN ('pending', 'confirmed');

CREATE INDEX IF NOT EXISTS idx_sessions_upcoming_client
  ON public.sessions(client_id, session_date, start_time)
  WHERE client_id IS NOT NULL AND status IN ('pending', 'confirmed');

CREATE INDEX IF NOT EXISTS idx_sessions_payment_id
  ON public.sessions(payment_id)
  WHERE payment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_class_id
  ON public.sessions(class_id)
  WHERE class_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_session_enrollments_session
  ON public.session_enrollments(session_id, enrolled_at DESC);

CREATE INDEX IF NOT EXISTS idx_session_enrollments_client
  ON public.session_enrollments(client_id, enrolled_at DESC);

CREATE INDEX IF NOT EXISTS idx_coach_availability_lookup
  ON public.coach_availability(
    coach_id,
    day_of_week,
    is_active,
    valid_from,
    valid_until,
    start_time
  );

CREATE INDEX IF NOT EXISTS idx_reviews_coach_created_at
  ON public.reviews(coach_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reviews_client_created_at
  ON public.reviews(client_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_session_status_history_session_changed_at
  ON public.session_status_history(session_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_session_status_history_gym_changed_at
  ON public.session_status_history(gym_id, changed_at DESC);
