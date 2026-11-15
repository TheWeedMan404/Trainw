-- ============================================================================
-- TRAINW PHASE 1C — PAYMENTS LEDGER (FE-19 / DB-36 / DB-65)
-- Audit 2026-11-14. Branch: phase1-security-fixes. Local only — NOT applied
-- to any live DB.
--
-- What this does, and what it builds on:
--   * The `payments` table already exists (003) and round 2 (B4) already
--     gave it idempotency indexes (DB-17), always-verify-client (DB-18)
--     and no-DELETE (DB-19). This migration turns it into the ledger:
--     append-only rows, settlement, immutability, e-invoicing fields.
--   * FE-19 — "payment" was a free-form `payment_status` flag on
--     client_profiles, written directly by the UI with no amount, method,
--     receipt or audit trail. From here on, `payment_status` and revenue
--     are DERIVED from this ledger; the UI never writes them directly.
--   * DB-36 — no trigger ever updated payment_status / price_paid /
--     membership_end_date when a payment was recorded. The settlement
--     trigger below does that, idempotently.
--   * DB-65 — settled payments are immutable: only the status transitions
--     pending->paid/cancelled/voided and paid->voided/cancelled are
--     allowed, and refunds go through a dedicated RPC.
--
-- Design notes:
--   * `method` (cash/card/bank_transfer) is separate from `provider`
--     ('manual' or a gateway name such as Konnect/Paymee later). A
--     payment records what was COLLECTED: `amount_paid`. `amount_total`
--     is what was owed. `amount_refunded` only grows via
--     `record_payment_refund`.
--   * Settlement is idempotent via `settled_at`: a paid payment settles
--     exactly once (when settled_at is NULL); voiding/cancelling a settled
--     payment reverses it and clears settled_at. Re-running the trigger
--     on an already-settled row is a no-op. Trigger order follows the
--     003 numbering: 10_prepare -> 15_settle -> 20_audit ->
--     80_guard -> 90_upd.
--   * Void = correction of an erroneous payment (keeps the row, reverses
--     settlement, requires a reason). Cancelled = the payment will never
--     happen. Both are terminal. A re-payment is a NEW payment row.
--   * Voiding reverses the end date by the voided payment's period,
--     floored at the membership start date. Caveat: void is meant for the
--     LATEST erroneous payment — voiding an older payment while newer
--     ones exist shortens the end date by that period. (Fixing that would
--     need a full ledger recompute of the end date, which the chain
--     cannot do safely because period_start is per-payment, not
--     chained.)
--   * Deploy-time data checks: the new CHECK constraints assume existing
--     rows are sane (amount_refunded <= amount_paid). If the migration
--     fails on a constraint, fix the offending rows on staging first
--     (void or correct them) and re-apply.
--   * E-invoicing (Tunisia, Loi de Finances 2026 Art. 53, TEIF via
--     TunisieTradeNet from 1 Jan 2026): an e-invoice must carry the
--     invoice number + date, the seller's tax id (matricule fiscal) and
--     identity/address, the buyer's identity/address/tax id, the service
--     description, the price HT, the TVA rate and amount, the total TTC,
--     a unique TTN reference and an electronic signature. Sources:
--     KPMG Circulaire fiscale fevrier 2026; challenges.tn 2026-01-25;
--     bfc.com.tn guide 2026; lapresse.tn 2025-12-30 — all consistent.
--     This migration stores every field EXCEPT the electronic signature
--     and the TTN reference value (both are issued by TTN at submission
--     time, not by Trainw): `ttn_reference` is a nullable column for the
--     value once TTN returns it. FLAG: the exact TEIF field list, the
--     applicable TVA rate for gym services, and the status of the
--     amendment that would delay Art. 53 MUST be verified with an
--     accountant before the first real invoice. No VAT rate is hardcoded
--     here: `vat_rate` is NULL (no VAT) unless the gym sets it.
--   * `gyms.tax_id` / `trade_register` and `client_profiles.tax_id`
--     hold the matricule fiscal / registre de commerce, snapshotted onto
--     each payment at insert so a later change to the gym or member does
--     not rewrite history.
--
-- VERIFICATION (no live DB was available when this was written):
--   * Insert a paid membership payment -> client_profiles shows
--     payment_status='paid', price_paid = amount_paid, end date extended
--     by period_months from the later of (old end date, period_start,
--     today); payments.settled_at is set.
--   * Insert the same payment again (same provider_reference) -> 23505
--     (DB-17 index, B4).
--   * UPDATE the paid payment's amount_total -> must raise (DB-65).
--   * UPDATE the paid payment to status='voided' without a reason ->
--     must raise; with a reason -> succeeds, profile reverts
--     (payment_status recomputed from remaining paid payments, end date
--     rolled back, settled_at cleared).
--   * UPDATE a voided payment's status back to 'paid' -> must raise.
--   * DELETE FROM payments -> denied (no DELETE policy, B4).
--   * record_payment_refund on a paid payment with amount > collected ->
--     must raise; partial refund -> amount_refunded grows, status stays
--     paid; full refund -> status='voided', membership reversed.
--   * Insert a payment naming a client of another gym -> must raise
--     (DB-18, B4).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Ledger columns on the existing payments table.
-- ----------------------------------------------------------------------------

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS method            text,
  ADD COLUMN IF NOT EXISTS period_months     integer,
  ADD COLUMN IF NOT EXISTS period_start      date,
  ADD COLUMN IF NOT EXISTS period_end        date,
  ADD COLUMN IF NOT EXISTS void_reason       text,
  ADD COLUMN IF NOT EXISTS voided_by         uuid REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS voided_at         timestamptz,
  ADD COLUMN IF NOT EXISTS settled_at        timestamptz,
  -- E-invoicing (TEIF) fields. See header: verify with an accountant.
  ADD COLUMN IF NOT EXISTS invoice_number    text,
  ADD COLUMN IF NOT EXISTS invoice_date      date,
  ADD COLUMN IF NOT EXISTS buyer_tax_id      text,
  ADD COLUMN IF NOT EXISTS buyer_name        text,
  ADD COLUMN IF NOT EXISTS buyer_address     text,
  ADD COLUMN IF NOT EXISTS seller_tax_id     text,
  ADD COLUMN IF NOT EXISTS seller_name       text,
  ADD COLUMN IF NOT EXISTS seller_address    text,
  ADD COLUMN IF NOT EXISTS service_description text,
  ADD COLUMN IF NOT EXISTS amount_ht         numeric(12,2),
  ADD COLUMN IF NOT EXISTS vat_rate          numeric(5,4),
  ADD COLUMN IF NOT EXISTS vat_amount        numeric(12,2),
  ADD COLUMN IF NOT EXISTS amount_ttc        numeric(12,2),
  ADD COLUMN IF NOT EXISTS ttn_reference     text,
  ADD COLUMN IF NOT EXISTS e_invoice_status  text NOT NULL DEFAULT 'not_issued';

-- Tax identity for the invoice seller (the gym) and buyer (the member).
ALTER TABLE public.gyms
  ADD COLUMN IF NOT EXISTS tax_id         text,
  ADD COLUMN IF NOT EXISTS trade_register text;

ALTER TABLE public.client_profiles
  ADD COLUMN IF NOT EXISTS tax_id text;

-- Invoice numbers are sequential per gym; the unique index is the guard
-- against two payments sharing one number (the frontend suggests the next
-- number; a collision fails here and the user retries).
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_gym_invoice_number
  ON public.payments (gym_id, invoice_number)
  WHERE invoice_number IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_gym_ttn_reference
  ON public.payments (gym_id, ttn_reference)
  WHERE ttn_reference IS NOT NULL;

-- Money + period + e-invoice sanity. vat_rate is a fraction (0.19 = 19%).
ALTER TABLE public.payments
  ADD CONSTRAINT payments_method_check
    CHECK (method IS NULL OR method IN ('cash', 'card', 'bank_transfer')),
  ADD CONSTRAINT payments_period_months_check
    CHECK (period_months IS NULL OR period_months >= 0),
  ADD CONSTRAINT payments_period_range_check
    CHECK (period_end IS NULL OR period_start IS NULL OR period_end >= period_start),
  ADD CONSTRAINT payments_vat_rate_check
    CHECK (vat_rate IS NULL OR (vat_rate >= 0 AND vat_rate <= 1)),
  ADD CONSTRAINT payments_e_invoice_status_check
    CHECK (e_invoice_status IN ('not_issued', 'pending', 'issued')),
  ADD CONSTRAINT payments_refund_cap_check
    CHECK (amount_refunded >= 0 AND amount_refunded <= amount_paid);

-- ----------------------------------------------------------------------------
-- 2. prepare_payment_write rewrite — B4 logic verbatim, plus ledger
--    defaults. Only INSERT gets the period / e-invoice defaults; UPDATE
--    only normalises status and timestamps.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prepare_payment_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
  v_buyer_name text;
  v_buyer_tax_id text;
  v_seller_name text;
  v_seller_tax_id text;
  v_seller_address text;
BEGIN
  NEW.payment_type := COALESCE(NULLIF(lower(BTRIM(NEW.payment_type)), ''), 'membership');
  NEW.status := COALESCE(NULLIF(lower(BTRIM(NEW.status)), ''), 'pending');
  NEW.provider := COALESCE(NULLIF(lower(BTRIM(NEW.provider)), ''), 'manual');
  NEW.currency_code := COALESCE(NULLIF(upper(BTRIM(NEW.currency_code)), ''), 'TND');
  NEW.notes := NULLIF(BTRIM(NEW.notes), '');
  NEW.invoice_reference := NULLIF(BTRIM(NEW.invoice_reference), '');
  NEW.provider_reference := NULLIF(BTRIM(NEW.provider_reference), '');
  NEW.invoice_number := NULLIF(BTRIM(NEW.invoice_number), '');
  NEW.ttn_reference := NULLIF(BTRIM(NEW.ttn_reference), '');
  NEW.buyer_tax_id := NULLIF(BTRIM(NEW.buyer_tax_id), '');
  NEW.metadata := COALESCE(NEW.metadata, '{}'::jsonb);
  NEW.amount_total := GREATEST(COALESCE(NEW.amount_total, 0), 0);
  NEW.amount_paid := GREATEST(COALESCE(NEW.amount_paid, 0), 0);
  NEW.amount_refunded := GREATEST(COALESCE(NEW.amount_refunded, 0), 0);
  NEW.method := NULLIF(lower(BTRIM(NEW.method)), '');

  IF NEW.status = 'canceled' THEN
    NEW.status := 'cancelled';
  END IF;
  IF NEW.status = 'void' THEN
    NEW.status := 'voided';
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
  ELSIF NEW.status = 'voided' AND NEW.voided_at IS NULL THEN
    NEW.voided_at := now();
  END IF;

  IF NEW.status = 'voided' AND NEW.voided_by IS NULL THEN
    NEW.voided_by := auth.uid();
  END IF;

  -- Ledger defaults: INSERT only, so a later UPDATE never recomputes the
  -- period or rewrites the invoice snapshot.
  IF TG_OP = 'INSERT' THEN
    IF NEW.payment_type = 'membership' THEN
      NEW.period_months := COALESCE(NEW.period_months, 1);
      NEW.period_start := COALESCE(NEW.period_start, NEW.paid_at::date, CURRENT_DATE);
      NEW.period_end := (NEW.period_start + (NEW.period_months || ' months')::interval)::date;
    ELSE
      -- Session / other payments cover no membership period.
      NEW.period_months := 0;
      NEW.period_start := NULL;
      NEW.period_end := NULL;
    END IF;

    -- E-invoice amounts: TTC defaults to the total; HT/VAT derive from
    -- the rate when one is set, otherwise the whole amount is HT.
    NEW.amount_ttc := COALESCE(NEW.amount_ttc, NEW.amount_total);
    IF NEW.vat_rate IS NOT NULL AND NEW.vat_rate > 0 THEN
      NEW.amount_ht := COALESCE(NEW.amount_ht, ROUND(NEW.amount_ttc / (1 + NEW.vat_rate), 2));
      NEW.vat_amount := COALESCE(NEW.vat_amount, NEW.amount_ttc - NEW.amount_ht);
    ELSE
      NEW.amount_ht := COALESCE(NEW.amount_ht, NEW.amount_ttc);
      NEW.vat_amount := COALESCE(NEW.vat_amount, 0);
    END IF;
    NEW.invoice_date := COALESCE(NEW.invoice_date, CURRENT_DATE);
    NEW.service_description := COALESCE(NULLIF(BTRIM(NEW.service_description), ''),
      CASE WHEN NEW.payment_type = 'membership' THEN 'Abonnement salle de sport'
           WHEN NEW.payment_type = 'session' THEN 'Seance'
           ELSE NEW.payment_type END);

    -- Snapshot buyer + seller identity so a later change to the gym or
    -- member does not rewrite invoice history. Best-effort: RLS may hide
    -- a row from the caller, in which case the field stays NULL.
    SELECT u.name, cp.tax_id INTO v_buyer_name, v_buyer_tax_id
    FROM public.users u
    LEFT JOIN public.client_profiles cp
      ON cp.user_id = u.id AND cp.gym_id = NEW.gym_id
    WHERE u.id = NEW.client_id;
    NEW.buyer_name := COALESCE(NEW.buyer_name, v_buyer_name);
    NEW.buyer_tax_id := COALESCE(NEW.buyer_tax_id, v_buyer_tax_id);

    SELECT g.name, g.tax_id, g.address
    INTO v_seller_name, v_seller_tax_id, v_seller_address
    FROM public.gyms g
    WHERE g.id = NEW.gym_id;
    NEW.seller_name := COALESCE(NEW.seller_name, v_seller_name);
    NEW.seller_tax_id := COALESCE(NEW.seller_tax_id, v_seller_tax_id);
    NEW.seller_address := COALESCE(NEW.seller_address, v_seller_address);
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Settlement trigger (DB-36) — trg_payments_15_settle_membership.
--    Runs after 10_prepare (so period/status are normalised) and before
--    the 20_audit log. SECURITY DEFINER so it runs as the function owner
--    and is not blocked by the client_profiles self-update guard (P1-1).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.settle_membership_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base date;
  v_new_end date;
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
    SELECT cp.membership_end_date INTO v_new_end
    FROM public.client_profiles cp
    WHERE cp.user_id = NEW.client_id AND cp.gym_id = NEW.gym_id;

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
    RETURN NEW;
  END IF;

  -- Reverse: a settled payment that is voided or cancelled. The end date
  -- rolls back by this payment's period (floored at the membership
  -- start); status + price_paid are recomputed from the remaining paid
  -- payments, so the profile always reflects the ledger.
  IF TG_OP = 'UPDATE'
    AND OLD.status = 'paid'
    AND NEW.status IN ('voided', 'cancelled')
    AND OLD.settled_at IS NOT NULL THEN

    UPDATE public.client_profiles
    SET membership_end_date = (
      CASE WHEN membership_end_date IS NULL THEN NULL
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

DROP TRIGGER IF EXISTS trg_payments_15_settle_membership ON public.payments;
CREATE TRIGGER trg_payments_15_settle_membership
  BEFORE INSERT OR UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.settle_membership_payment();

-- ----------------------------------------------------------------------------
-- 4. Immutability guard (DB-65) — trg_payments_80_guard_update.
--    BEFORE UPDATE, after settle (80 > 15) and after prepare (10), so it
--    sees normalised status. Raising here rolls the whole statement back.
--    Allowed transitions: pending->paid/cancelled/voided,
--    paid->voided/cancelled. Voided/cancelled rows are terminal.
--    Amounts + identity are frozen once paid; amount_refunded only moves
--    via record_payment_refund, which sets the session flag below.
-- ----------------------------------------------------------------------------

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

DROP TRIGGER IF EXISTS trg_payments_80_guard_update ON public.payments;
CREATE TRIGGER trg_payments_80_guard_update
  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.guard_payment_update();

-- ----------------------------------------------------------------------------
-- 5. Refund RPC (DB-65) — the ONLY way amount_refunded moves.
--    Manager-only (manages_gym). Partial refund keeps the payment paid
--    and keeps price_paid honest; a full refund voids it and the
--    settlement trigger reverses the membership. Every refund writes a
--    payment_events row. The session flag lets the guard tell an RPC
--    refund apart from a direct edit.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_payment_refund(
  p_payment_id uuid,
  p_amount numeric(12,2),
  p_reason text
)
RETURNS public.payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pay public.payments%ROWTYPE;
  v_new_refunded numeric(12,2);
  v_is_latest boolean;
  v_result public.payments%ROWTYPE;
BEGIN
  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'payment not found';
  END IF;
  IF NOT public.manages_gym(v_pay.gym_id) THEN
    RAISE EXCEPTION 'not authorized: only a manager of this gym can refund';
  END IF;
  IF v_pay.status IS DISTINCT FROM 'paid' THEN
    RAISE EXCEPTION 'only a paid payment can be refunded';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'refund amount must be positive';
  END IF;
  IF p_amount > v_pay.amount_paid - v_pay.amount_refunded THEN
    RAISE EXCEPTION 'refund exceeds the collected amount';
  END IF;
  IF NULLIF(BTRIM(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'refund reason is required';
  END IF;

  v_new_refunded := v_pay.amount_refunded + p_amount;
  PERFORM set_config('trainw.allow_payment_refund', 'on', true);

  IF v_new_refunded >= v_pay.amount_paid THEN
    -- Full refund: void the payment; the settlement trigger reverses the
    -- membership (status/price/end date recomputed from the ledger).
    UPDATE public.payments
    SET amount_refunded = v_new_refunded,
        status = 'voided',
        void_reason = 'Refund: ' || BTRIM(p_reason),
        voided_by = auth.uid(),
        voided_at = now()
    WHERE id = p_payment_id;
  ELSE
    UPDATE public.payments
    SET amount_refunded = v_new_refunded
    WHERE id = p_payment_id;

    -- Keep price_paid honest when this is the member's latest paid
    -- membership payment (the one the profile's price_paid reflects).
    SELECT NOT EXISTS (
      SELECT 1 FROM public.payments p
      WHERE p.client_id = v_pay.client_id
        AND p.gym_id = v_pay.gym_id
        AND p.payment_type = 'membership'
        AND p.status = 'paid'
        AND p.id <> v_pay.id
        AND (p.paid_at > v_pay.paid_at
          OR (p.paid_at = v_pay.paid_at AND p.created_at > v_pay.created_at))
    ) INTO v_is_latest;

    IF v_is_latest THEN
      UPDATE public.client_profiles
      SET price_paid = v_pay.amount_paid - v_new_refunded,
          updated_at = now()
      WHERE user_id = v_pay.client_id AND gym_id = v_pay.gym_id;
    END IF;
  END IF;

  INSERT INTO public.payment_events (
    payment_id, gym_id, event_type, previous_status, next_status,
    amount_delta, payload, created_by
  ) VALUES (
    p_payment_id, v_pay.gym_id, 'refunded', v_pay.status,
    CASE WHEN v_new_refunded >= v_pay.amount_paid THEN 'voided' ELSE 'paid' END,
    -p_amount,
    jsonb_build_object('reason', BTRIM(p_reason)),
    auth.uid()
  );

  SELECT * INTO v_result FROM public.payments WHERE id = p_payment_id;
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.record_payment_refund(uuid, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_payment_refund(uuid, numeric, text) TO authenticated;
