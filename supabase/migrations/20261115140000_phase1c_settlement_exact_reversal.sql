-- ============================================================================
-- TRAINW PHASE 1C — EXACT SETTLEMENT REVERSAL (VOID MUST RESTORE THE END DATE)
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- WHY THIS FILE EXISTS (found by local verification 2026-11-15, real
-- PostgreSQL 16): the ledger migration (20261115100000) reverses a voided
-- payment by subtracting its period from the end date:
--   end_date - (period_months || ' months')
-- Postgres month arithmetic is NOT symmetric around month-ends:
--   2026-11-30 + 3 months = 2027-02-28, and 2027-02-28 - 3 months =
--   2026-11-28. So settling then voiding a quarterly payment made on
--   2026-11-30 silently loses 2 days of membership. (A 1-month payment
--   round-trips exactly, which is why the 1-month tests passed and the
--   3-month test caught it.)
-- Fix: record the pre-settlement end date in the new column
-- settled_from_end_date when a payment settles, and restore it exactly
-- on reversal (falling back to the month subtraction for payments that
-- settled before this column existed). The guard trigger also freezes
-- settled_from_end_date on paid/voided rows so the restore target cannot
-- be tampered with. The 1c ledger file itself is NOT edited.
-- ============================================================================

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS settled_from_end_date date;

CREATE OR REPLACE FUNCTION public.settle_membership_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base date;
  v_new_end date;
  v_old_end date;
  v_any_paid boolean;
  v_latest_paid numeric(12,2);
BEGIN
  IF NEW.payment_type IS DISTINCT FROM 'membership' THEN
    RETURN NEW;
  END IF;

  -- Settle: a paid membership payment that has not settled yet.
  IF NEW.status = 'paid' AND NEW.settled_at IS NULL THEN
    -- Renewal semantics: extend from the later of the current end date,
    -- the purchased period start, and today — so an early renewal adds
    -- on top of the remaining time instead of overwriting it.
    -- v_old_end is recorded in settled_from_end_date so a later void can
    -- restore the end date exactly (month arithmetic is not symmetric
    -- around month-ends — see the header of this migration).
    SELECT cp.membership_end_date INTO v_old_end
    FROM public.client_profiles cp
    WHERE cp.user_id = NEW.client_id AND cp.gym_id = NEW.gym_id;
    v_new_end := v_old_end;

    v_base := GREATEST(
      COALESCE(v_new_end, CURRENT_DATE),
      COALESCE(NEW.period_start, CURRENT_DATE),
      CURRENT_DATE
    );
    v_new_end := (v_base + (COALESCE(NEW.period_months, 1) || ' months')::interval)::date;

    UPDATE public.client_profiles
    SET payment_status = 'paid',
        price_paid = NEW.amount_paid,
        membership_start_date = COALESCE(
          membership_start_date, NEW.period_start, CURRENT_DATE),
        membership_end_date = v_new_end,
        updated_at = now()
    WHERE user_id = NEW.client_id AND gym_id = NEW.gym_id;
    -- No profile row (legacy client without a backfilled profile): the
    -- payment still lands in the ledger; the profile stays as-is. The
    -- B8 backfill creates the missing rows for existing clients.

    NEW.settled_at := now();
    NEW.settled_from_end_date := v_old_end;
    RETURN NEW;
  END IF;

  -- Reverse: a settled payment that is voided or cancelled. The end date
  -- is restored exactly to the value recorded when this payment settled
  -- (settled_from_end_date); the month-subtraction fallback only applies
  -- to payments that settled before that column existed. Status +
  -- price_paid are recomputed from the remaining paid payments, so the
  -- profile always reflects the ledger.
  IF TG_OP = 'UPDATE'
    AND OLD.status = 'paid'
    AND NEW.status IN ('voided', 'cancelled')
    AND OLD.settled_at IS NOT NULL THEN

    UPDATE public.client_profiles
    SET membership_end_date = (
      CASE WHEN membership_end_date IS NULL THEN NULL
           WHEN NEW.settled_from_end_date IS NOT NULL THEN NEW.settled_from_end_date
           ELSE GREATEST(
             COALESCE(membership_start_date, CURRENT_DATE),
             (membership_end_date - (COALESCE(NEW.period_months, 1) || ' months')::interval)::date
           )
      END),
        updated_at = now()
    WHERE user_id = NEW.client_id AND gym_id = NEW.gym_id;

    SELECT EXISTS (
      SELECT 1 FROM public.payments p
      WHERE p.client_id = NEW.client_id
        AND p.gym_id = NEW.gym_id
        AND p.payment_type = 'membership'
        AND p.status = 'paid'
        AND p.id <> NEW.id
        AND (p.period_end IS NULL OR p.period_end >= CURRENT_DATE)
    ) INTO v_any_paid;

    SELECT p.amount_paid INTO v_latest_paid
    FROM public.payments p
    WHERE p.client_id = NEW.client_id
      AND p.gym_id = NEW.gym_id
      AND p.payment_type = 'membership'
      AND p.status = 'paid'
      AND p.id <> NEW.id
    ORDER BY p.paid_at DESC NULLS LAST, p.created_at DESC
    LIMIT 1;

    UPDATE public.client_profiles
    SET payment_status = CASE WHEN v_any_paid THEN 'paid' ELSE 'pending' END,
        price_paid = COALESCE(v_latest_paid, 0),
        updated_at = now()
    WHERE user_id = NEW.client_id AND gym_id = NEW.gym_id;

    NEW.settled_at := NULL;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_payment_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_refund_allowed boolean;
BEGIN
  v_refund_allowed :=
    COALESCE(current_setting('trainw.allow_payment_refund', true), '') = 'on';

  -- Terminal rows: only notes/metadata may change.
  IF OLD.status IN ('voided', 'cancelled') THEN
    IF OLD.status IS DISTINCT FROM NEW.status
      OR OLD.amount_total IS DISTINCT FROM NEW.amount_total
      OR OLD.amount_paid IS DISTINCT FROM NEW.amount_paid
      OR OLD.amount_refunded IS DISTINCT FROM NEW.amount_refunded
      OR OLD.provider IS DISTINCT FROM NEW.provider
      OR OLD.provider_reference IS DISTINCT FROM NEW.provider_reference
      OR OLD.invoice_reference IS DISTINCT FROM NEW.invoice_reference
      OR OLD.invoice_number IS DISTINCT FROM NEW.invoice_number
      OR OLD.amount_ht IS DISTINCT FROM NEW.amount_ht
      OR OLD.vat_rate IS DISTINCT FROM NEW.vat_rate
      OR OLD.vat_amount IS DISTINCT FROM NEW.vat_amount
      OR OLD.amount_ttc IS DISTINCT FROM NEW.amount_ttc
      OR OLD.client_id IS DISTINCT FROM NEW.client_id
      OR OLD.gym_id IS DISTINCT FROM NEW.gym_id
      OR OLD.session_id IS DISTINCT FROM NEW.session_id
      OR OLD.payment_type IS DISTINCT FROM NEW.payment_type
      OR OLD.currency_code IS DISTINCT FROM NEW.currency_code
      OR OLD.period_months IS DISTINCT FROM NEW.period_months
      OR OLD.period_start IS DISTINCT FROM NEW.period_start
      OR OLD.period_end IS DISTINCT FROM NEW.period_end
      OR OLD.method IS DISTINCT FROM NEW.method
      OR OLD.paid_at IS DISTINCT FROM NEW.paid_at
      OR OLD.cancelled_at IS DISTINCT FROM NEW.cancelled_at
      OR OLD.voided_at IS DISTINCT FROM NEW.voided_at
      OR OLD.voided_by IS DISTINCT FROM NEW.voided_by
      OR OLD.void_reason IS DISTINCT FROM NEW.void_reason
      OR OLD.settled_at IS DISTINCT FROM NEW.settled_at
      OR OLD.settled_from_end_date IS DISTINCT FROM NEW.settled_from_end_date
    THEN
      RAISE EXCEPTION 'payment_immutable: a voided/cancelled payment cannot be changed';
    END IF;
    RETURN NEW;
  END IF;

  -- Paid rows: status may only move to voided/cancelled (with a reason
  -- for a void); money + identity fields are frozen.
  IF OLD.status = 'paid' THEN
    IF NEW.status NOT IN ('paid', 'voided', 'cancelled') THEN
      RAISE EXCEPTION 'payment_immutable: paid payments can only be voided or cancelled';
    END IF;
    IF NEW.status = 'voided' AND NULLIF(BTRIM(COALESCE(NEW.void_reason, '')), '') IS NULL THEN
      RAISE EXCEPTION 'payment_immutable: voiding a payment requires a reason';
    END IF;
    IF OLD.amount_total IS DISTINCT FROM NEW.amount_total
      OR OLD.amount_paid IS DISTINCT FROM NEW.amount_paid
      OR OLD.provider IS DISTINCT FROM NEW.provider
      OR OLD.provider_reference IS DISTINCT FROM NEW.provider_reference
      OR OLD.invoice_reference IS DISTINCT FROM NEW.invoice_reference
      OR OLD.invoice_number IS DISTINCT FROM NEW.invoice_number
      OR OLD.amount_ht IS DISTINCT FROM NEW.amount_ht
      OR OLD.vat_rate IS DISTINCT FROM NEW.vat_rate
      OR OLD.vat_amount IS DISTINCT FROM NEW.vat_amount
      OR OLD.amount_ttc IS DISTINCT FROM NEW.amount_ttc
      OR OLD.client_id IS DISTINCT FROM NEW.client_id
      OR OLD.gym_id IS DISTINCT FROM NEW.gym_id
      OR OLD.session_id IS DISTINCT FROM NEW.session_id
      OR OLD.payment_type IS DISTINCT FROM NEW.payment_type
      OR OLD.currency_code IS DISTINCT FROM NEW.currency_code
      OR OLD.period_months IS DISTINCT FROM NEW.period_months
      OR OLD.period_start IS DISTINCT FROM NEW.period_start
      OR OLD.period_end IS DISTINCT FROM NEW.period_end
      OR OLD.method IS DISTINCT FROM NEW.method
      OR OLD.settled_from_end_date IS DISTINCT FROM NEW.settled_from_end_date
    THEN
      RAISE EXCEPTION 'payment_immutable: a paid payment''s amounts and identity cannot be changed';
    END IF;
    IF OLD.amount_refunded IS DISTINCT FROM NEW.amount_refunded
      AND NOT v_refund_allowed THEN
      RAISE EXCEPTION 'payment_immutable: refunds must go through record_payment_refund';
    END IF;
    RETURN NEW;
  END IF;

  -- Pending rows (drafts): amounts may still be corrected, but identity
  -- and the status machine are fixed.
  IF OLD.status = 'pending' THEN
    IF NEW.status NOT IN ('pending', 'paid', 'cancelled', 'voided') THEN
      RAISE EXCEPTION 'payment_immutable: invalid status transition from pending';
    END IF;
    IF NEW.status = 'voided' AND NULLIF(BTRIM(COALESCE(NEW.void_reason, '')), '') IS NULL THEN
      RAISE EXCEPTION 'payment_immutable: voiding a payment requires a reason';
    END IF;
    IF OLD.client_id IS DISTINCT FROM NEW.client_id
      OR OLD.gym_id IS DISTINCT FROM NEW.gym_id THEN
      RAISE EXCEPTION 'payment_immutable: a payment cannot move to another client or gym';
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;
