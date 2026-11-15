-- ============================================================================
-- TRAINW PHASE 2 — P2-2 SINGLE REVENUE SOURCE (FE-15, FE-16)
-- Audit 2026-11-14. Branch: phase1-security-fixes. Local only — NOT applied
-- to any live DB by this file; the parent applies it.
--
-- What round 3 already did (so this migration does NOT redo it):
--   * Revenue is computed once, from the ledger, in `loadLedgerRevenue`
--     (tw-gym-acc.js) — dashboard (#stat-revenue), analytics
--     (loadAnalytics) and prediction (#pred-monthly) all call that one
--     function. The old v17 revenueFor() list-price estimate is gone;
--     refreshRevenue() in tw-gym-acc-v17.js is a thin wrapper around
--     loadLedgerRevenue. The ai-proxy edge function computes no revenue.
--   * Frontend money parsing is strict (parseMoneyInput): no negatives,
--     no "12abc", no hardcoded 150/400/1400 fallbacks.
--
-- What was still genuinely broken (found by this round, 2026-11-15):
--   1. NO DB CHECK on any money column. `prepare_payment_write` silently
--      clamps negatives with GREATEST(..., 0) — so a -500 payment
--      inserted through the API did NOT fail, it landed as a 0-amount
--      PAID payment and the settlement trigger extended the membership
--      for free. The -500 verify in the audit step could not pass.
--   2. NO upper cap anywhere. parseMoneyInput accepted 999999999; the
--      DB numeric(12,2) columns accept up to ~10 billion.
--   3. Coach rates had NO validation at all: saveEditCoach /
--      submitNewCoach used bare parseFloat() and stored -500 verbatim.
--   4. Revenue was GROSS, not net: loadLedgerRevenue summed amount_paid
--      and ignored amount_refunded, so a partially refunded payment
--      still counted in full. (Frontend fix in the same round; the
--      ledger itself is unchanged.)
--
-- This migration adds the DB side: CHECKs on every price/amount entry
-- point. Cap: 100 000 TND everywhere — ~30x the most expensive Tunisian
-- gym annual plan, so real prices never hit it, typos do.
--
-- Live-data pre-checks (Management API, 2026-11-15, BEFORE writing):
--   * payments: 6 rows. One PENDING row has amount_total=80,
--     amount_paid=0 (the DB-66 credit flow's pending rebooking
--     payment), so amount_paid must allow 0 — but only for non-paid
--     rows; a PAID row with 0 collected would settle a membership for
--     free, so paid rows require amount_paid > 0. All rows satisfy
--     0 < amount_total <= 100000, 0 <= amount_paid <= amount_total.
--   * gyms: all 5 rows price 150/400/1400. coach_profiles: rates are
--     NULL or 80. client_profiles: no price_paid < 0 or > 100000.
--   Hence plain (validated) ADD CONSTRAINT is safe live — no NOT VALID
--   dodge, no data repair (DB-35's assert_no_unvalidated_constraints
--   stays green).
--   * Compatibility with the chain's own writers: book_coach_session
--     only inserts a payment when v_price > 0 (pending, paid=0);
--     apply_member_credit_to_session only ever grows amount_paid up to
--     amount_total (v_take = LEAST(remaining, owed)); the refund RPC
--     only moves amount_refunded (already capped by
--     payments_refund_cap_check). The round-6 suite's payments are all
--     100/150 paid in full.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. payments — the ledger itself.
-- ----------------------------------------------------------------------------
ALTER TABLE public.payments
  ADD CONSTRAINT payments_amount_total_check
    CHECK (amount_total > 0 AND amount_total <= 100000),
  ADD CONSTRAINT payments_amount_paid_check
    CHECK (amount_paid >= 0 AND amount_paid <= 100000
           AND amount_paid <= amount_total),
  ADD CONSTRAINT payments_paid_requires_amount_check
    CHECK (status <> 'paid' OR amount_paid > 0);

-- ----------------------------------------------------------------------------
-- 2. gyms — list prices edited in the gym settings (savePricing).
-- ----------------------------------------------------------------------------
ALTER TABLE public.gyms
  ADD CONSTRAINT gyms_price_monthly_check
    CHECK (price_monthly > 0 AND price_monthly <= 100000),
  ADD CONSTRAINT gyms_price_quarterly_check
    CHECK (price_quarterly > 0 AND price_quarterly <= 100000),
  ADD CONSTRAINT gyms_price_annual_check
    CHECK (price_annual > 0 AND price_annual <= 100000);

-- ----------------------------------------------------------------------------
-- 3. coach_profiles — session rates (manager add/edit coach).
--    NULL means "no rate set"; a rate that is present must be a real price.
-- ----------------------------------------------------------------------------
ALTER TABLE public.coach_profiles
  ADD CONSTRAINT coach_profiles_hourly_rate_check
    CHECK (hourly_rate IS NULL
           OR (hourly_rate > 0 AND hourly_rate <= 100000)),
  ADD CONSTRAINT coach_profiles_price_per_session_check
    CHECK (price_per_session IS NULL
           OR (price_per_session > 0 AND price_per_session <= 100000));

-- ----------------------------------------------------------------------------
-- 4. client_profiles — price_paid is ledger-derived (settlement trigger
--    copies amount_paid), never typed in. Bound it anyway so a bad
--    trigger/manual write cannot park an absurd value on the profile.
-- ----------------------------------------------------------------------------
ALTER TABLE public.client_profiles
  ADD CONSTRAINT client_profiles_price_paid_check
    CHECK (price_paid >= 0 AND price_paid <= 100000);

-- ----------------------------------------------------------------------------
-- VERIFICATION (local suite p22-tests.sql):
--   * -500 payment insert (paid) -> check violation (was: silently
--     clamped to 0 and settled the membership for free).
--   * 0-total payment insert -> check violation.
--   * 100001 payment insert -> check violation.
--   * pending payment 80/0 (the credit-flow shape) -> still inserts.
--   * paid payment 80/80 -> inserts; partial refund 30 -> revenue nets
--     to 50 (loadLedgerRevenue) and the day total nets to 50.
--   * gym price -500 / 0 / 100001 -> check violation; 150 -> ok.
--   * coach rate -500 / 0 / 100001 -> check violation; NULL / 45 -> ok.
--   * client_profiles.price_paid -1 / 100001 -> check violation.
-- ----------------------------------------------------------------------------
