# Migration Conventions (DB-52 and the rules rounds 1–4 established)

Rules for every future change to `supabase/migrations/`. They exist because
the audit found the failure modes in the original chain — read them before
writing a migration, not after it breaks staging.

## 1. Never edit an applied migration (DB-51)

All SQL changes ship as NEW files with a timestamp prefix. A file that has
run anywhere is history: fix it with a forward migration, never by editing
it. The foundation file was renamed once (DB-51) because its unprefixed
name sorted after the files that depend on it; that rename is the only
exception, and any environment that recorded the old name needs a
migration-version repair before the rename is pushed.

## 2. One migration, one logical piece

One file does one thing (one finding, one feature). Small files are easy to
review, easy to roll forward past, and easy to bisect when staging breaks.
Commit one file (or one coherent set) per commit, with the finding ID in
the message.

## 3. The 004 RLS reset must never be copied (DB-52)

Migration `20260408183000_trainw_004_integrity_security.sql:540-568` drops
every policy on 24 tables in a loop and only recreates them afterwards. If
that file failed midway, the tables would be left with RLS enabled and
zero policies — deny-all for every user, including managers — until someone
re-ran it.

Why it did not bite: the Supabase CLI applies each migration file inside a
single transaction by default (a file whose statements cannot run in a
transaction must start with the `-- pg-delta: transaction=false` directive,
which `db push` / `migration up` / `db reset` honour by running without
the wrapping transaction — the directive's existence is the evidence that
wrapping is the default). A mid-file failure therefore rolls the whole
file back, drops included. Two rules follow for new work:

- **Never write a drop-all-then-recreate loop again.** When policies
  change, drop and recreate one table's policies together, in the same
  statement block, before moving to the next table. A failure then leaves
  at most one table's policies half-changed, and the transaction still
  rolls that back.
- **Do not assume the dashboard SQL editor wraps a script the same way.**
  Before applying any migration through the dashboard (rather than the
  CLI), confirm the editor's transaction behaviour for that run; if it
  cannot be confirmed, apply through the CLI instead. Either way, the
  per-table pattern above is what makes a failure survivable.
- **Do not edit 004.** It is already applied everywhere; its pattern is
  documented here as a known-bad example, not a template.

## 4. No destructive data repair in a migration (DB-50)

Migrations do DDL (tables, columns, constraints, policies, functions) and
constraint *validation* (DB-35). Deleting orphans, cancelling conflicting
sessions, deactivating bad rows — that is a separate, reviewed, backed-up
operation run through `docs/DATA_REPAIR_RUNBOOK.md`. Migrations 003 and
004 broke this rule; they are kept as-is for history and must not be
copied as a pattern. `scripts/data-repair-audit.sql` is the read-only
dry-run; `public.data_repair_log` is where every repair is recorded.

## 5. NOT VALID constraints are validated in the same migration (DB-35)

Never add a `NOT VALID` constraint without validating it in the same file.
`public.assert_no_unvalidated_constraints()` (migration
`20261115150000`) is the tripwire — it fails the migration if any
unvalidated CHECK/FK constraint is left behind.

## 6. A new table ships with RLS, policies, and grants together (DB-41)

Every table in `public` has RLS enabled and grants that match its policies
exactly (no blanket grant — the 004 `GRANT ... ON ALL TABLES` is revoked).
`public.assert_all_tables_have_rls()` (migration `20261115170000`) fails
the migration if a table is missing RLS. Service-role-only tables get no
`authenticated` grant at all.

## 7. Frozen RLS helpers: change deliberately, update the hash (DB-61)

The 30 helpers in migration `20261115210000` are frozen:
`public.assert_rls_helpers_frozen()` compares each live definition against
a recorded hash and raises on drift. To change a helper on purpose,
re-create it in a new migration AND update its hash in the re-created
assert function in the same migration, then run the assert at the end of
that migration (see DB-37, migration `20261115230000`, for the worked
example). Never update a hash to silence the check without reviewing the
definition diff.

Known gap: the hash does not cover a function's DEFAULT expressions
(`proargdefaults` is not in the formula), so a default-only change slips
past the tripwire. Hardening the hash to include defaults is a follow-up.

## 8. Verify on the throwaway cluster before committing

Every DB change is verified by applying the FULL chain end to end on a
throwaway local Postgres cluster and running a behavioural assertion
suite for the change (`/tmp/r4-harness.sh`, `/tmp/r4-tests*.sql`).
`node --check` (or a transpile-only check) on every touched JS/TS file.
The only apply failure ever seen is the by-design B5 return-type failure
in `20261115050000` (repaired by `20261115120000`). A migration that has
not been applied to the throwaway cluster has not been verified.

## 9. Time is the gym's time (DB-37)

"Today" in any membership / gate / check-in / booking cut-off is
`public.gym_today(gym_id)` — `(now() AT TIME ZONE gyms.timezone)::date`,
Africa/Tunis when the gym row is missing. Never use `CURRENT_DATE` /
`LOCALTIME` for an access cut-off. The ai-proxy quota day (per-user UTC)
and the ledger's business dates are the documented exceptions.
