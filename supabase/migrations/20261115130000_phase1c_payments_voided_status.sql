-- ============================================================================
-- TRAINW PHASE 1C — WIDEN payments_status_check TO INCLUDE 'voided'
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- WHY THIS FILE EXISTS (found by local verification 2026-11-15, real
-- PostgreSQL 16): the ledger migration (20261115100000) uses 'voided' as
-- the void status everywhere (settlement reversal, guard trigger, refund
-- RPC, frontend), but the chain's payments_status_check — created by
-- 20260408182000_trainw_003 (line ~511) — allows only
-- ('pending','authorized','paid','failed','cancelled','refunded',
-- 'partially_refunded'). Every void therefore failed with:
--   ERROR: new row for relation "payments" violates check constraint
--   "payments_status_check"
-- The ledger migration never widened the constraint. This file drops and
-- re-creates it with 'voided' added, then VALIDATEs it (existing rows
-- already satisfy the old, narrower list, so validation cannot fail on
-- a chain-applied database). The 1c ledger file itself is NOT edited.
-- ============================================================================

ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_status_check;
ALTER TABLE public.payments ADD CONSTRAINT payments_status_check
  CHECK (status IN ('pending', 'authorized', 'paid', 'failed', 'cancelled', 'refunded', 'partially_refunded', 'voided')) NOT VALID;
ALTER TABLE public.payments VALIDATE CONSTRAINT payments_status_check;
