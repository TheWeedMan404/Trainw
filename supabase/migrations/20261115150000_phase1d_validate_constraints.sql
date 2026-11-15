-- ============================================================================
-- Round 4 (DB-35) — validate every NOT VALID constraint in the chain.
--
-- Migrations 003/005 added 25 CHECK/FK constraints NOT VALID and no later
-- migration ever validated them, so legacy rows could permanently violate
-- the rules new writes must obey (e.g. amount_paid > amount_total, orphan
-- session_id references). Later migrations added more (011, B8, 1c).
--
-- This migration validates ALL of them. It is dynamic on purpose: it
-- validates whatever pg_constraint reports as unvalidated at deploy time,
-- and RAISEs (failing the deploy loudly) if any legacy row violates.
-- On a live DB with violating legacy rows, clean the rows first (see
-- docs/DATA_REPAIR_RUNBOOK.md) and re-run; do NOT work around it by
-- skipping the validation.
--
-- Convention from here on (see the runbook): never add a NOT VALID
-- constraint without validating it in the same migration.
-- ============================================================================

DO $$
DECLARE
  r record;
  v_count integer := 0;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass AS tbl, c.conname AS name
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND c.contype IN ('c', 'f')
      AND NOT c.convalidated
    ORDER BY tbl, name
  LOOP
    RAISE NOTICE 'DB-35 validating %.%', r.tbl, r.name;
    EXECUTE format('ALTER TABLE %s VALIDATE CONSTRAINT %I', r.tbl, r.name);
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE 'DB-35 validated % constraint(s)', v_count;
END $$;

-- After this migration, no public CHECK/FK constraint may remain
-- unvalidated. The assertion below is the tripwire for future
-- migrations: if one adds a NOT VALID constraint without validating it,
-- the next deploy that calls public.assert_no_unvalidated_constraints()
-- (or this check, re-run by hand) fails loudly instead of silently
-- letting legacy rows drift.
CREATE OR REPLACE FUNCTION public.assert_no_unvalidated_constraints()
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(c.conrelid::regclass::text || '.' || c.conname, ', ' ORDER BY 1)
  INTO v_bad
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'public'
    AND c.contype IN ('c', 'f')
    AND NOT c.convalidated;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'unvalidated constraints remain: %', v_bad;
  END IF;
END $$;

SELECT public.assert_no_unvalidated_constraints();

COMMENT ON FUNCTION public.assert_no_unvalidated_constraints() IS
  'DB-35: fails when any public CHECK/FK constraint is NOT VALID. Call after applying migrations that add constraints.';
