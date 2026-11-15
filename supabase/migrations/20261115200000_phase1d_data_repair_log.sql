-- ============================================================================
-- Round 4 (DB-50) — data repairs get a log and a runbook; they no longer
-- live silently inside migrations.
--
-- Migrations 003 and 004 performed destructive data repair on deploy:
-- 003 deactivated duplicate/conflicting availability windows and
-- cancelled overlapping sessions; 004 DELETE'd orphan rows across 20+
-- tables (profiles, messages, classes, sessions, payments, reviews,
-- ...). A deploy could silently cancel real bookings and delete real
-- user data to satisfy new constraints, with no backup step, no dry-run,
-- and no record of what was removed.
--
-- Those two migrations are NOT edited (the rule for this round). Instead:
--   * this migration creates public.data_repair_log — every future
--     data repair records each affected row here BEFORE changing it
--     (row snapshot as jsonb), so nothing is ever deleted silently
--     again;
--   * docs/DATA_REPAIR_RUNBOOK.md is the reviewed, backed-up,
--     idempotent repair procedure executed separately from DDL;
--   * scripts/data-repair-audit.sql is the dry-run: it reports what
--     the historical repairs would touch today, without changing
--     anything.
-- The log table is service-role only (RLS on, no policies, no
-- authenticated grant — same model as the DB-41 service_role-only
-- tables).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.data_repair_log (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  performed_at     timestamptz NOT NULL DEFAULT now(),
  performed_by     text NOT NULL DEFAULT 'runbook',
  gym_id           uuid REFERENCES public.gyms(id) ON DELETE SET NULL,
  table_name       text NOT NULL,
  row_id           uuid,
  action           text NOT NULL CHECK (action IN ('delete', 'update', 'cancel', 'deactivate', 'insert')),
  reason           text NOT NULL,
  row_snapshot     jsonb,
  runbook_ref      text NOT NULL DEFAULT 'docs/DATA_REPAIR_RUNBOOK.md'
);

ALTER TABLE public.data_repair_log ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_data_repair_log_table_performed
  ON public.data_repair_log(table_name, performed_at DESC);

CREATE INDEX IF NOT EXISTS idx_data_repair_log_gym_performed
  ON public.data_repair_log(gym_id, performed_at DESC)
  WHERE gym_id IS NOT NULL;

COMMENT ON TABLE public.data_repair_log IS
  'DB-50: audit trail for data repairs. Every row a repair deletes, cancels, deactivates or rewrites is recorded here with a snapshot BEFORE the change. Service-role only.';
