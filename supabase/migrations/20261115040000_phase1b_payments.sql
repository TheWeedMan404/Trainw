-- ============================================================================
-- TRAINW PHASE 1B — PAYMENTS IDEMPOTENCY + INTEGRITY
-- Audit 2026-11-14: DB-17, DB-18, DB-19.
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- DB-17 — payments had no idempotency protection: a retried webhook / a
--   double-submitted form could create the same charge twice. Two partial
--   unique indexes (only where the reference is present):
--     (gym_id, provider, provider_reference) and (gym_id, invoice_reference).
--   NOTE: CREATE UNIQUE INDEX fails if duplicate rows already exist. Apply
--   to staging first; if it fails, dedupe the existing rows (keep the
--   earliest, void the rest) and re-apply. This is a deploy-time data
--   check, not something this migration can do blindly.
-- DB-18 — prepare_payment_write() only validated the client when a
--   session_id was present; a payment with no session could name any
--   client_id (or none). It now always verifies, through the SECURITY
--   DEFINER helper below (so the check is not subject to the caller's RLS):
--   client_id is required, the user must exist with role 'client', and the
--   client must belong to NEW.gym_id — either via a client_profiles row
--   for that gym or via the legacy users.gym_id default (manager-created
--   clients have a profile with gym_id NULL until the Phase 1b backfill;
--   the users.gym_id leg keeps their payments working).
-- DB-19 — payments could be DELETEd outright (payments_delete policy let
--   managers delete), erasing the money record and — via ON DELETE CASCADE
--   — its payment_events audit trail. The DELETE policy is dropped (there
--   is no DELETE policy anymore: payments are cancelled/voided via status,
--   never deleted), and the payment_events FK is changed to ON DELETE
--   RESTRICT so the audit trail can never be cascade-deleted with its
--   payment. The FK constraint name is looked up dynamically because the
--   original migration relied on Postgres' default naming.
--
-- VERIFICATION (no live DB was available when this was written):
--   * Inserting two payments with the same (gym, provider, reference)
--     must fail on the second; same for invoice_reference.
--   * Inserting a payment with a client from another gym (or a coach's
--     user id, or NULL client) must raise a validation error.
--   * DELETE FROM payments must be denied for a manager (no policy);
--     deleting a payment row as owner with events present must fail on
--     the RESTRICT FK.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DB-17 — idempotency unique indexes.
-- ----------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_gym_provider_ref
  ON public.payments (gym_id, provider, provider_reference)
  WHERE provider_reference IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_gym_invoice_ref
  ON public.payments (gym_id, invoice_reference)
  WHERE invoice_reference IS NOT NULL;

-- ----------------------------------------------------------------------------
-- DB-18 — client verification helper + prepare_payment_write rewrite.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.payment_client_belongs_to_gym(
  p_client_id uuid,
  p_gym_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    LEFT JOIN public.client_profiles cp
      ON cp.user_id = u.id
     AND cp.gym_id = p_gym_id
    WHERE u.id = p_client_id
      AND u.role = 'client'
      AND (
        cp.user_id IS NOT NULL
        OR u.gym_id = p_gym_id
      )
  );
$$;

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

  -- DB-18: a payment always names a real client of THIS gym. This runs
  -- whether or not a session_id is present (the old code only checked the
  -- session path).
  IF NEW.client_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: payment client is required';
  END IF;

  IF NOT public.payment_client_belongs_to_gym(NEW.client_id, NEW.gym_id) THEN
    RAISE EXCEPTION 'validation_error: payment client does not belong to this gym';
  END IF;

  IF NEW.status = 'paid' AND NEW.paid_at IS NULL THEN
    NEW.paid_at := now();
  ELSIF NEW.status = 'cancelled' AND NEW.cancelled_at IS NULL THEN
    NEW.cancelled_at := now();
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- DB-19 — payments are never deleted; payment_events survive their payment.
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS payments_delete ON public.payments;
-- NOTE: no DELETE policy is created. Payments are cancelled/voided via
-- status; a DELETE is denied by default (RLS enabled, no policy).

-- payment_events.payment_id FK: ON DELETE CASCADE -> ON DELETE RESTRICT.
DO $$
DECLARE
  v_constraint_name text;
BEGIN
  SELECT c.conname INTO v_constraint_name
  FROM pg_constraint c
  JOIN pg_attribute a
    ON a.attrelid = c.conrelid
   AND a.attnum = ANY(c.conkey)
  WHERE c.conrelid = 'public.payment_events'::regclass
    AND c.contype = 'f'
    AND c.confrelid = 'public.payments'::regclass
    AND a.attname = 'payment_id';

  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE public.payment_events DROP CONSTRAINT %I',
      v_constraint_name
    );
  END IF;
END $$;

ALTER TABLE public.payment_events
  ADD CONSTRAINT payment_events_payment_id_fkey
  FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE RESTRICT;
