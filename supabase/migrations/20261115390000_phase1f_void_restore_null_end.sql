-- Round 6 (audit closure) — DB-36/DB-65 void reversal: restore a NULL
-- end date exactly.
--
-- BUG (found by the round-6 verification suite): voiding a payment for
-- a member whose pre-settlement membership_end_date was NULL left the
-- end date at the period start (today) instead of NULL. The settle
-- branch stored the pre-settlement end in settled_from_end_date, but a
-- NULL there is indistinguishable from "column never populated" (rows
-- that settled before the column existed), so the reverse branch fell
-- through to the month-subtraction fallback: end - 1 month = today.
-- Status and price were restored correctly, so the member stayed
-- inactive — cosmetic, not a billing hole — but the round-3 claim
-- "reversal restores it exactly" was false for NULL-end members.
--
-- Fix: the settle branch now stores the sentinel DATE '0001-01-01'
-- when the pre-settlement end is NULL, and the reverse branch restores
-- NULL when it sees the sentinel. Pre-existing rows (settled before
-- the column existed) still have a real NULL and still use the fallback.
-- The guard freezes settled_from_end_date on terminal rows and the
-- settle branch only writes it on INSERT, so no guard interaction.
CREATE OR REPLACE FUNCTION public.settle_membership_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- Round 6: a NULL pre-settlement end is stored as the sentinel
    -- 0001-01-01 so the void path can tell "was NULL" apart from
    -- "settled before this column existed" (real NULL -> fallback).
    NEW.settled_from_end_date := COALESCE(v_old_end, DATE '0001-01-01');
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
      CASE WHEN NEW.settled_from_end_date = DATE '0001-01-01' THEN NULL
           WHEN NEW.settled_from_end_date IS NOT NULL THEN NEW.settled_from_end_date
           WHEN membership_end_date IS NULL THEN NULL
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
$function$;
