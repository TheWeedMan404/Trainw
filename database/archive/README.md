# Archived schema — DO NOT APPLY

Decision (P1-11, 2026-11-15): the **migration chain in
`supabase/migrations/` is the authoritative schema**. These two files are
kept here as non-deployable reference only. They were moved out of
`database/` so nothing can mistake them for the live schema again.

## Why they were archived

`schema.sql` is a second, incompatible schema for the same table names
(audit finding DB-33 / NX-03):

- Its `roles` table is `(gym_id, name, permissions jsonb)`; the migration
  chain's `roles` (007) is `(gym_id, code, portal, ...)`. Its `users`
  requires `role_id NOT NULL` and `gym_id NOT NULL`; the migrations use a
  `role text` column.
- It adds a parallel domain that does not exist in the migration chain:
  `coaches`, `clients`, `classes`, `class_clients`, `attendance`, plus its
  own RLS policies and triggers for those tables.
- Its `provision_new_gym` RPC inserts `(gym_id, name, permissions)` into
  `roles` and would fail against the chain's `roles` table.

Applying both stacks to one database yields a nondeterministic schema
(whichever `CREATE TABLE IF NOT EXISTS` runs first wins), duplicate and
conflicting policies on the same tables, and a broken provisioning
function. Nothing in `supabase/migrations/` loads these files, and the
Supabase CLI never looks in `database/`.

## What still depends on the archived schema (as of 2026-11-15)

The Next.js app in `src/` was written against this file and **does not
work against a migration-chain-only database** until its data model is
migrated (audit P2-10 — the Next.js app decision, still open):

- `src/app/auth/callback/route.ts` calls the `provision_new_gym` RPC
  after email confirmation; the RPC exists only here.
- `src/actions/clients.ts`, `src/actions/classes.ts`,
  `src/actions/attendance.ts`, `src/lib/queries.ts` and
  `src/app/api/public/clients/route.ts` query the `clients`,
  `class_clients` (and `coaches`/`classes`) tables, which exist only here.
- `src/types/database.ts` types `provision_new_gym` and `class_clients`
  from this schema.
- `src/actions/roles.ts` guards the gym-owner role by NAME
  ('Gym Owner' / 'admin') because this file's `roles` table has no `code`
  column; the migration chain's `roles` does.
- Migration `supabase/migrations/20261115090000_phase1b_public_clients_status.sql`
  is guarded: it no-ops when `public.clients` is absent, because that
  table lives only here.

Consequence: do not apply `schema.sql` to any database that already has
the migration chain, and do not apply the migration chain to a database
built from `schema.sql`, without first reconciling the two models. The
reconciliation (or the decision to drop the Next.js app in favour of the
vanilla frontend, which uses the migration chain) is a separate,
deliberately deferred decision.

`seed.sql` is the demo seed written against this archived schema. It is
kept for reference; the deployable demo seed is
`supabase/seeds/trainw_demo_seed.sql` (migration-chain tables).
