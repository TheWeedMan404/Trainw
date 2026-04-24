# TRAINW V17 Database Fix Log

## Audit Summary

The current V17 migration chain was re-audited and re-run transactionally against the linked Supabase project before the turnstile work was added. The fixes below are the concrete issues that were corrected to make the production migration set executable and idempotent on the legacy database.

| File | Line | What was wrong | What was changed |
| --- | --- | --- | --- |
| `supabase/migrations/20260408182000_trainw_003_booking_payments_reviews.sql` | 38 | `payments` backfill code referenced new production columns that do not exist on legacy `public.payments` rows created before the refactor. | Added compatibility `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` blocks and defaults before the normalization updates run. |
| `supabase/migrations/20260408182000_trainw_003_booking_payments_reviews.sql` | 86 | `payment_events` assumed new columns already existed on older linked databases. | Added idempotent compatibility columns and defaults before constraints/indexes. |
| `supabase/migrations/20260408182000_trainw_003_booking_payments_reviews.sql` | 193 | `reviews` backfill used `session_id`, `coach_id`, and `client_id` even when those columns were missing on legacy installs. | Added a legacy-upgrade block for `public.reviews` so the backfill and FK preparation can run safely. |
| `supabase/migrations/20260408182000_trainw_003_booking_payments_reviews.sql` | 244 | Legacy `sessions`, `payments`, and `reviews` rows could violate the new lifecycle and amount checks during migration. | Added defensive normalization for timestamps, capacities, amounts, ratings, and orphan foreign keys before constraints were added. |
| `supabase/migrations/20260408182000_trainw_003_booking_payments_reviews.sql` | 487 | New check constraints and foreign keys could fail immediately on dirty legacy production data. | Added them as `NOT VALID` so new writes are protected without crashing the migration on historical rows. |
| `supabase/migrations/20260408182000_trainw_003_booking_payments_reviews.sql` | 823 | The migration used `timerange(...)`, which is not a PostgreSQL/Supabase built-in and caused a hard parser error. | Replaced it with explicit half-open overlap logic using `start_a < end_b AND start_b < end_a`. |
| `supabase/migrations/20260408182000_trainw_003_booking_payments_reviews.sql` | 1208 | The coach availability trigger repeated the same invalid `timerange(...)` call. | Rewrote the trigger overlap predicate with native PostgreSQL comparisons. |
| `supabase/migrations/20260408182000_trainw_003_booking_payments_reviews.sql` | 1747 | `refresh_coach_review_stats(uuid)` already existed on the linked database with a different input parameter name, which blocks `CREATE OR REPLACE FUNCTION`. | Added `DROP FUNCTION IF EXISTS public.refresh_coach_review_stats(uuid)` and `DROP FUNCTION IF EXISTS public.handle_review_stats()` before recreating the current canonical function and trigger stack. |
| `supabase/migrations/20260408182000_trainw_003_booking_payments_reviews.sql` | 1888 | Legacy trigger names on `sessions`, `coach_availability`, and `reviews` conflicted with the new trigger set during rebuilds. | Added explicit `DROP TRIGGER IF EXISTS ...` cleanup before creating the current canonical triggers. |
| `supabase/migrations/20260408183000_trainw_004_integrity_security.sql` | 11 | The integrity migration referenced columns like `class_id`, `payment_id`, `created_by`, and `updated_by` that are missing on the linked legacy schema until later upgrades land. | Added a legacy compatibility section that creates those columns with `ADD COLUMN IF NOT EXISTS` before relationship cleanup runs. |
| `supabase/migrations/20260408183000_trainw_004_integrity_security.sql` | 193 | The session cleanup used unqualified `class_id` style predicates, which break when only the table alias is valid in the statement scope. | Qualified the predicates to `s.class_id`, `s.payment_id`, `s.created_by`, and `s.updated_by`. |
| `supabase/migrations/20260414090000_trainw_011_turnstiles.sql` | 1 | The turnstile feature required production-safe credential storage, gate audit logging, hardware validation, and check-in compatibility for new gate methods. | Added the new turnstile migration with idempotent enum creation, credential and access-log tables, hardware validation RPC, gate session device support, and expanded `check_ins` method enforcement. |

## Verification

- `001 + 002 + 003 + 004` now execute top-to-bottom in one transaction against the linked Supabase project with no SQL error.
- `001 + 002 + 003 + 004 + 011` also execute cleanly in one transaction.
- The new `validate_member_credential(...)` RPC was simulated transactionally with unknown, expired, granted, and duplicate scenarios and then rolled back cleanly.
