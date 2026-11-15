# Data Repair Runbook (DB-50)

> **Rule: a migration never performs destructive data repair.** Migrations do DDL
> (tables, columns, constraints, policies, functions) and constraint *validation*
> (DB-35). Data fixes — deleting orphans, cancelling conflicting sessions,
> deactivating bad rows — are a separate, reviewed, backed-up operation run
> through this runbook. Migrations 003 and 004 broke this rule; they are kept
> as-is for history and must not be copied as a pattern.

## When this runbook applies

- `scripts/data-repair-audit.sql` reports rows to repair (exit code non-zero).
- A constraint cannot be added/validated because existing rows violate it.
- An operator finds orphaned or contradictory rows in production data.

## Procedure (in order — do not skip steps)

### 1. Back up

```bash
# Full backup before any repair (see docs/DEPLOY_RUNBOOK.md for restore).
./scripts/backup-db.sh
```

Record the backup location and timestamp in the repair ticket. No backup,
no repair.

### 2. Dry-run

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/data-repair-audit.sql
```

The script is **read-only**: it reports, per rule, how many rows would be
affected. It exits `0` when nothing needs repair and non-zero otherwise.
Attach its full output to the repair ticket.

### 3. Review the rows

For each rule with a count above zero, pull the actual rows (not just the
count) and confirm they are genuinely orphaned/contradictory — not live data
the audit misread. Rules and their origin:

| Rule | Origin | What it touches |
| --- | --- | --- |
| FK orphan in any `public` table | 004 (orphan DELETEs, 20+ tables) | Rows whose foreign key points at a missing parent. Generic audit: every FK in `public` is checked. |
| Duplicate availability (`rn > 1`) | 003, `normalized_availability` | Same coach/gym/day/window listed twice — the later duplicate is deactivated. |
| Conflicting availability | 003, `conflicting_availability` | Same coach/gym/day with overlapping times and overlapping validity ranges — the later window is deactivated. |
| Conflicting sessions | 003, `conflicting_sessions` | Same coach or same client, same date, overlapping times, both `pending`/`confirmed` — the later session is cancelled (`migration_overlap_cleanup`). |
| `auth.users` row with no `public.users` row | DB-62 (signup trigger gap) | A signup whose profile creation failed. Repair is to *create* the missing profile, never to delete the auth row. |

**Never repair a row you cannot explain.** If a count is surprising (e.g. a
large share of a table), stop and investigate — it is usually a missing FK or
a bug, not bad data.

### 4. Write the repair as a logged script

The repair script must, for **every** affected row, in this order:

1. `INSERT INTO public.data_repair_log (gym_id, table_name, row_id, action, reason, row_snapshot)` — snapshot the row as `to_jsonb(row)` **before** changing it.
2. Then the `DELETE` / `UPDATE` / cancel.

Template (adapt the `WHERE` to the rule; keep the log insert first):

```sql
BEGIN;
-- 1. Log every row this repair will touch, with a snapshot.
INSERT INTO public.data_repair_log (gym_id, table_name, row_id, action, reason, row_snapshot)
SELECT gym_id, 'sessions', id, 'cancel', 'conflicting session: overlaps an earlier confirmed session (DB-50 runbook)', to_jsonb(s)
FROM public.sessions s
WHERE <the reviewed predicate>;

-- 2. Only now, apply the repair to exactly the logged rows.
UPDATE public.sessions s
SET status = 'cancelled',
    cancelled_at = COALESCE(s.cancelled_at, now()),
    cancellation_reason = COALESCE(NULLIF(s.cancellation_reason, ''), 'migration_overlap_cleanup'),
    updated_at = now()
FROM public.data_repair_log l
WHERE l.table_name = 'sessions'
  AND l.action = 'cancel'
  AND l.performed_at >= <the repair timestamp>
  AND s.id = l.row_id;
COMMIT;
```

Prefer joining the repair to the log rows just written (as above) over
repeating the predicate — then the repair provably touches exactly the rows
that were logged.

### 5. Run, verify, re-audit

1. Run the repair script in a transaction (`BEGIN`/`COMMIT`).
2. Re-run `scripts/data-repair-audit.sql` — it must exit `0`.
3. Spot-check `public.data_repair_log` for the run: row counts per table
   must match the dry-run counts.
4. If the repair touched sessions or payments, confirm with the affected gym
   that the cancellations/deletions are understood (a cancelled booking is a
   customer-facing event).

### 6. Record

Keep the ticket with: backup location, dry-run output, the repair script,
the re-audit output, and the `data_repair_log` row counts.

## What a migration may still do

- Add a constraint `NOT VALID`, then `VALIDATE CONSTRAINT` in the same
  migration (DB-35) — validation only *checks* data, it never changes it.
- Add a column with a default, backfill a *new* column from existing data
  (e.g. the DB-07 credential-hash backfill) — a backfill writes a derived
  value, it never deletes or cancels a business row.
- Anything that deletes, cancels, deactivates, or rewrites a business row to
  satisfy a constraint belongs in this runbook, not in a migration.

## Historical note

Migrations `20260408182000_trainw_003_booking_payments_reviews.sql`
(conflict repair, 3 rules) and
`20260408183000_trainw_004_integrity_security.sql` (orphan cleanup, 32
statements) performed their repairs inline at deploy time with no backup,
no dry-run, and no log. Any environment that already applied them cannot
un-apply the repair — the `data_repair_log` starts empty and only covers
repairs done after this migration. That is accepted and documented here;
the runbook exists so it never happens again.
