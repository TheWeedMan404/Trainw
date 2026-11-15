-- ============================================================================
-- TRAINW ROUND 7 — DB-66 CREDIT (user decision 2026-11-15: CREDIT)
-- Branch: phase1-security-fixes. Local only until applied live.
--
-- POLICY: a no-show credits the member for rebooking; the money stays in
-- the gym. The session's payment stays 'paid' and the profile stays
-- 'paid' (verified live in P1-13, R6b) — the credit is a separate
-- balance the member spends on a later booking.
--
-- DESIGN (ledger-style, like the payments ledger in 20261115100000):
--   * public.member_credits — append-only credit balance per member:
--     gym, client, original amount, amount remaining, source session +
--     source payment, status (available / fully_applied / expired),
--     created_by, timestamps. One credit per no-show session, enforced
--     by a partial unique index on source_session_id — a retry of
--     mark_session_no_show can never double-credit.
--   * public.member_credit_applications — append-only audit of every
--     application (which credit paid how much of which payment/session).
--   * Writes happen ONLY inside the SECURITY DEFINER RPCs below. RLS
--     is ON with SELECT-only policies (the gym's managers, or the
--     owning client); there are no INSERT/UPDATE/DELETE policies for
--     app roles.
--   * public.mark_session_no_show is extended: after the status flip
--     it inserts the credit in the SAME transaction, so a no-show is
--     never recorded without its credit (fail closed).
--   * public.apply_member_credit_to_session(p_session_id) applies the
--     client's available credits (oldest first, FIFO) to the session's
--     PENDING payment: amount_paid grows by the applied amount and the
--     payment becomes 'paid' when fully covered. The ledger's
--     immutability guard explicitly allows amount changes on pending
--     rows, and the settlement trigger ignores session payments, so
--     this does not touch any membership.
--   * public.get_member_credit_balance(p_client_id, p_gym_id) returns
--     the available balance (self or the gym's manager only).
--
-- WHAT IS CREDITED: only the amount actually collected for the
-- session — payment.amount_paid minus amount_refunded, and only when
-- the session's payment is 'paid'. An unpaid (pending) session owes
-- the gym nothing, so there is nothing to credit; a free session
-- (no payment, price 0) credits nothing. Sessions marked no-show
-- BEFORE this migration get no credit (no backfill — the money trail
-- for those is the payments ledger).
--
-- FRONTEND HOOK (follow-up, not in this migration): after
-- book_coach_session returns a new session, the client (or the gym
-- dashboard) calls apply_member_credit_to_session(new_session_id)
-- when the member holds credit; get_member_credit_balance drives the
-- "you have X TND credit" display. The apply RPC is a separate call
-- on purpose — auto-applying inside book_coach_session would change
-- the booking contract for every client.
--
-- VERIFICATION (local throwaway cluster, then live):
--   * Book + confirm + pay a session, mark no-show → credit row with
--     amount = the paid price, status available; re-marking no-show
--     creates no second credit.
--   * No-show on an unpaid (pending) session → no credit row.
--   * No-show on a free session (price 0, no payment) → no credit row.
--   * Rebook the same price, apply credit → payment 'paid' with
--     amount_paid = price, credit fully_applied, application row
--     recorded; balance 0 afterwards.
--   * Partial credit (credit 50, new session 80) → amount_paid 50,
--     payment stays pending, remaining owed 30.
--   * Cross-gym apply (client B / manager B on gym A) → forbidden.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. member_credits — append-only credit balance.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.member_credits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  amount_remaining numeric(12,2) NOT NULL
    CHECK (amount_remaining >= 0 AND amount_remaining <= amount),
  source_session_id uuid REFERENCES public.sessions(id) ON DELETE SET NULL,
  source_payment_id uuid REFERENCES public.payments(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'available'
    CHECK (status IN ('available', 'fully_applied', 'expired')),
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  applied_at timestamptz,
  CHECK (status <> 'fully_applied' OR amount_remaining = 0),
  CHECK (status <> 'available' OR amount_remaining > 0)
);

-- One credit per no-show session: the double-credit guard.
CREATE UNIQUE INDEX IF NOT EXISTS uq_member_credits_source_session
  ON public.member_credits (source_session_id)
  WHERE source_session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_member_credits_client_available
  ON public.member_credits (gym_id, client_id, created_at)
  WHERE status = 'available' AND amount_remaining > 0;

ALTER TABLE public.member_credits ENABLE ROW LEVEL SECURITY;

-- Writes only inside the SECURITY DEFINER RPCs below: no
-- INSERT/UPDATE/DELETE policies for app roles.
CREATE POLICY member_credits_select_manager ON public.member_credits
  FOR SELECT USING (public.manages_gym(gym_id));
CREATE POLICY member_credits_select_self ON public.member_credits
  FOR SELECT USING (client_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 2. member_credit_applications — append-only audit of each application.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.member_credit_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  credit_id uuid NOT NULL REFERENCES public.member_credits(id) ON DELETE CASCADE,
  gym_id uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  payment_id uuid NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  session_id uuid REFERENCES public.sessions(id) ON DELETE SET NULL,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  applied_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_member_credit_applications_payment
  ON public.member_credit_applications (payment_id);
CREATE INDEX IF NOT EXISTS idx_member_credit_applications_credit
  ON public.member_credit_applications (credit_id);

ALTER TABLE public.member_credit_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY member_credit_applications_select_manager ON public.member_credit_applications
  FOR SELECT USING (public.manages_gym(gym_id));
CREATE POLICY member_credit_applications_select_self ON public.member_credit_applications
  FOR SELECT USING (client_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 3. mark_session_no_show — now records the credit atomically.
--    Body is the 20261115320000 version verbatim, plus the credit block.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.mark_session_no_show(p_session_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
  v_payment_id uuid;
  v_paid numeric(12,2);
  v_refunded numeric(12,2);
  v_credit_amount numeric(12,2);
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

  -- Idempotent retry: already no_show returns success.
  IF COALESCE(v_session.status, 'pending') = 'no_show' THEN
    RETURN p_session_id;
  END IF;

  IF COALESCE(v_session.status, 'pending') <> 'confirmed' THEN
    RAISE EXCEPTION 'invalid_state: only confirmed sessions can be marked no-show';
  END IF;

  UPDATE public.sessions
  SET status = 'no_show',
      no_show_at = COALESCE(no_show_at, now()),
      updated_by = auth.uid()
  WHERE id = p_session_id;

  -- DB-66 (CREDIT): the member already paid for this session, so the
  -- net collected amount becomes a credit for rebooking. The payment
  -- stays 'paid' and the profile stays 'paid' — money stays in the
  -- gym. Only a 'paid' session payment credits anything: an unpaid
  -- (pending) session owes nothing, and a free session (no payment)
  -- has no amount to credit. The partial unique index on
  -- source_session_id is the double-credit guard; the early return
  -- above means a retry never reaches this block at all.
  IF v_session.client_id IS NOT NULL AND v_session.payment_id IS NOT NULL THEN
    SELECT p.id, p.amount_paid, p.amount_refunded
    INTO v_payment_id, v_paid, v_refunded
    FROM public.payments p
    WHERE p.id = v_session.payment_id
      AND p.status = 'paid';

    IF v_payment_id IS NOT NULL THEN
      v_credit_amount := COALESCE(v_paid, 0) - COALESCE(v_refunded, 0);
      IF v_credit_amount > 0 THEN
        INSERT INTO public.member_credits (
          gym_id, client_id, amount, amount_remaining,
          source_session_id, source_payment_id, created_by
        ) VALUES (
          v_session.gym_id, v_session.client_id,
          v_credit_amount, v_credit_amount,
          p_session_id, v_payment_id, auth.uid()
        )
        ON CONFLICT (source_session_id) WHERE source_session_id IS NOT NULL DO NOTHING;
      END IF;
    END IF;
  END IF;

  RETURN p_session_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. apply_member_credit_to_session — spend available credit on a rebook.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.apply_member_credit_to_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.sessions%ROWTYPE;
  v_payment public.payments%ROWTYPE;
  v_owed numeric(12,2);
  v_applied numeric(12,2) := 0;
  v_credit public.member_credits%ROWTYPE;
  v_take numeric(12,2);
BEGIN
  SELECT *
  INTO v_session
  FROM public.sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: session does not exist';
  END IF;

  IF v_session.client_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: session has no client';
  END IF;

  IF NOT (v_session.client_id = auth.uid() OR public.manages_gym(v_session.gym_id)) THEN
    RAISE EXCEPTION 'forbidden: only the client or a manager of this gym can apply credit';
  END IF;

  IF v_session.payment_id IS NULL THEN
    RAISE EXCEPTION 'validation_error: session has no payment to apply credit to';
  END IF;

  SELECT *
  INTO v_payment
  FROM public.payments p
  WHERE p.id = v_session.payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: session payment does not exist';
  END IF;

  IF v_payment.status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'invalid_state: credit can only be applied to a pending payment (status: %)', v_payment.status;
  END IF;

  v_owed := GREATEST(COALESCE(v_payment.amount_total, 0) - COALESCE(v_payment.amount_paid, 0), 0);
  IF v_owed <= 0 THEN
    RETURN jsonb_build_object('applied', 0, 'remaining_owed', 0, 'payment_status', v_payment.status);
  END IF;

  -- Oldest available credit first (FIFO). The advisory-free row locks
  -- (FOR UPDATE) serialize concurrent applies for the same member.
  FOR v_credit IN
    SELECT *
    FROM public.member_credits
    WHERE gym_id = v_session.gym_id
      AND client_id = v_session.client_id
      AND status = 'available'
      AND amount_remaining > 0
    ORDER BY created_at ASC, id ASC
    FOR UPDATE
  LOOP
    EXIT WHEN v_owed <= 0;
    v_take := LEAST(v_credit.amount_remaining, v_owed);

    UPDATE public.member_credits
    SET amount_remaining = amount_remaining - v_take,
        status = CASE WHEN amount_remaining - v_take <= 0 THEN 'fully_applied' ELSE 'available' END,
        applied_at = CASE WHEN amount_remaining - v_take <= 0 THEN COALESCE(applied_at, now()) ELSE applied_at END
    WHERE id = v_credit.id;

    INSERT INTO public.member_credit_applications
      (credit_id, gym_id, client_id, payment_id, session_id, amount, applied_by)
    VALUES (v_credit.id, v_session.gym_id, v_session.client_id, v_payment.id, p_session_id, v_take, auth.uid());

    v_applied := v_applied + v_take;
    v_owed := v_owed - v_take;
  END LOOP;

  IF v_applied > 0 THEN
    -- The ledger guard allows amount changes on pending rows; the
    -- settlement trigger ignores session payments, so this touches no
    -- membership. The credit is recorded as paid value, and the
    -- prepare trigger stamps paid_at when the payment becomes 'paid'.
    UPDATE public.payments
    SET amount_paid = COALESCE(amount_paid, 0) + v_applied,
        status = CASE
          WHEN COALESCE(amount_paid, 0) + v_applied >= COALESCE(amount_total, 0) THEN 'paid'
          ELSE 'pending'
        END,
        metadata = COALESCE(metadata, '{}'::jsonb)
          || jsonb_build_object('credit_applied',
               COALESCE((metadata->>'credit_applied')::numeric, 0) + v_applied)
    WHERE id = v_payment.id;
  END IF;

  SELECT *
  INTO v_payment
  FROM public.payments p
  WHERE p.id = v_payment.id;

  RETURN jsonb_build_object(
    'applied', v_applied,
    'remaining_owed', GREATEST(COALESCE(v_payment.amount_total, 0) - COALESCE(v_payment.amount_paid, 0), 0),
    'payment_status', v_payment.status
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. get_member_credit_balance — available balance (self or manager).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_member_credit_balance(p_client_id uuid, p_gym_id uuid)
RETURNS numeric(12,2)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(SUM(amount_remaining), 0)
  FROM public.member_credits
  WHERE gym_id = p_gym_id
    AND client_id = p_client_id
    AND status = 'available'
    AND amount_remaining > 0
    AND (p_client_id = auth.uid() OR public.manages_gym(p_gym_id));
$$;
