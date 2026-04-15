# TRAINW V14 Database Audit

## Scope

Reviewed the legacy SQL files in the V14 root:

- `Main-Query.sql`
- `Booking-System.sql`
- `Booking-SLS.sql`
- `Demo-Data.sql`

Reviewed them against the frontend and Edge function usage in:

- `tw-client-acc.js`
- `tw-client-pilot.js`
- `tw-coach-acc.js`
- `tw-gym-acc.js`
- `tw-gym-acc-v14.js`
- `supabase/functions/gate-checkin/index.ts`

The new canonical production database stack is now:

- `supabase/migrations/20260408180000_trainw_001_foundation.sql`
- `supabase/migrations/20260408181000_trainw_002_profiles_operations.sql`
- `supabase/migrations/20260408182000_trainw_003_booking_payments_reviews.sql`
- `supabase/migrations/20260408183000_trainw_004_integrity_security.sql`
- `supabase/seeds/trainw_demo_seed.sql`

The root SQL files should be treated as legacy reference material only, not as deployable production migrations.

## Critical Legacy Findings

### 1. Three overlapping schema sources

`Main-Query.sql`, `Booking-System.sql`, and `Booking-SLS.sql` all redefine the same tables, RPCs, policies, grants, and constraints. Depending on execution order, the final database shape changes.

Impact:

- nondeterministic production deployments
- policy replacement collisions
- conflicting function bodies
- drift between environments

### 2. Non-idempotent migration behavior

The legacy scripts mix `CREATE IF NOT EXISTS` with direct policy creation, direct grants, duplicate indexes, and redefined functions without a single ordered migration strategy.

Impact:

- reruns can fail or silently diverge
- partial deploys are hard to recover from
- production roll-forward is unsafe

### 3. Booking integrity relied on optimistic checks

Legacy booking RPCs checked for overlaps, but the wider schema still allowed direct writes to `sessions` and `coach_availability` that could bypass concurrency protection.

Impact:

- race conditions under simultaneous booking load
- double-booked coaches or clients
- overlapping availability windows

### 4. Incomplete auditability

There was no durable, normalized lifecycle history for session state transitions or payment changes across the whole system.

Impact:

- weak operational debugging
- poor dispute handling
- difficult support investigations

### 5. Foreign-key and orphan risk

Several relationship-heavy tables depended on historical creation order rather than a guaranteed cleanup-and-tighten process.

Impact:

- orphan rows after manual edits or partial deploys
- inconsistent multi-tenant joins
- broken RLS assumptions

### 6. Payment model was underdeveloped

The legacy schema mentioned payments but did not provide a durable event trail, consistent status model, or clean session linking.

Impact:

- poor readiness for Stripe or manual reconciliation
- hard-to-audit payment state changes
- weak reporting foundations

### 7. RLS duplication and drift

Policies were defined in multiple files, sometimes with the same names and different logic.

Impact:

- whichever file ran last won
- security behavior could differ by environment
- debugging access issues became guesswork

### 8. Demo data was not production-safe

`Demo-Data.sql` was not structured as an idempotent seed aligned with the final schema.

Impact:

- local/demo setup drift
- seed failures after schema changes

## Production Refactor Summary

### Foundation

`001_foundation.sql` creates and normalizes the tenant core:

- `gyms`
- `users`
- base constraints
- duplicate email repair
- shared `updated_at` trigger

### Operational Domain

`002_profiles_operations.sql` covers the non-booking product surface:

- coach and client profiles
- specialties
- assignments
- messaging
- classes
- body metrics
- workout plans and logs
- check-ins
- gate access
- helper functions for RLS
- signup trigger integration

### Booking, Payments, Reviews

`003_booking_payments_reviews.sql` provides:

- `payments` and `payment_events`
- `sessions` and `session_enrollments`
- `coach_availability`
- `reviews`
- `session_status_history`
- deterministic overlap cleanup
- advisory-lock-backed validation triggers
- review aggregate maintenance
- payment event logging
- session lifecycle audit logging
- production RPCs:
  - `get_bookable_slots`
  - `book_coach_session`
  - `respond_to_session_booking`
  - `cancel_session_booking`
  - `complete_session_booking`
  - `mark_session_no_show`
  - `leave_session_review`

### Integrity and Security

`004_integrity_security.sql` provides:

- orphan cleanup before tightening rules
- uniqueness repair for reviews and enrollments
- missing foreign-key coverage
- full RLS reset
- one coherent policy model for all app-facing tables
- explicit RPC grants for authenticated users

### Seed

`supabase/seeds/trainw_demo_seed.sql` now gives a safe, idempotent demo dataset covering:

- one gym
- one manager
- one coach
- two clients
- availability
- classes
- assignments
- sessions
- payments
- reviews
- check-ins
- messages
- workout data

## Design Principles Applied

- Ordered migrations only
- Idempotent DDL wherever practical
- Data cleanup before constraint tightening
- Booking concurrency protection at the database layer
- Multi-tenant isolation by gym
- Session lifecycle timestamps with defensive status handling
- Event history for payments and session state changes
- Index coverage for real dashboard and booking access patterns
- Supabase-compatible RLS and RPC permissions

## Remaining Operational Notes

- The current app still hard-deletes some `users` and `sessions` rows from the dashboard. The new audit model preserves session history better than before, but long-term SaaS maturity would still benefit from replacing hard deletes with soft deletes plus archival admin tooling.
- Managed users created directly in `public.users` remain supported because the frontend already depends on that pattern.
- The new migration stack is the source of truth. Running the old root SQL files after these migrations would reintroduce drift.
