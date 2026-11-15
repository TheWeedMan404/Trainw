-- ============================================================================
-- TRAINW PHASE 1B — PUBLIC CLIENT REGISTRATION COLUMNS (NX-05)
-- Audit 2026-11-14. Branch: phase1-security-fixes. Local only.
--
-- The public registration endpoint inserts pending clients with a contact
-- (email and/or phone). Those columns only exist after this migration.
-- GUARDED: the clients table lives in database/schema.sql, NOT in the
-- migration chain (P1-11 territory), so this migration is a no-op when the
-- table does not exist yet. Apply database/schema.sql first (or the
-- equivalent migration-chain port), then this file.
--
-- status: 'pending' (public registration, awaiting gym approval),
-- 'approved' (active client), 'rejected'. DEFAULT 'approved' so that
-- gym-created clients (dashboard create action, which sets no status)
-- stay active immediately, and pre-migration rows backfill as approved.
-- The contact CHECK only constrains pending rows: dashboard-created
-- clients carry no email/phone, and pre-migration rows have none either.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.clients') IS NOT NULL THEN
    ALTER TABLE public.clients
      ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'approved';
    ALTER TABLE public.clients
      ADD COLUMN IF NOT EXISTS email text;
    ALTER TABLE public.clients
      ADD COLUMN IF NOT EXISTS phone text;
    ALTER TABLE public.clients
      ADD COLUMN IF NOT EXISTS contact_verified boolean NOT NULL DEFAULT false;

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = 'public.clients'::regclass
        AND conname = 'clients_status_check'
    ) THEN
      ALTER TABLE public.clients
        ADD CONSTRAINT clients_status_check
        CHECK (status IN ('pending', 'approved', 'rejected'));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = 'public.clients'::regclass
        AND conname = 'clients_pending_contact_check'
    ) THEN
      ALTER TABLE public.clients
        ADD CONSTRAINT clients_pending_contact_check
        CHECK (status <> 'pending' OR email IS NOT NULL OR phone IS NOT NULL);
    END IF;
  END IF;
END $$;
