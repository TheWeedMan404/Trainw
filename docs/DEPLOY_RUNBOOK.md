# Trainw deploy runbook (P2-7)

How a release goes from this repo to production, what must be set
before it works, and how to roll back. Live decisions that only the
user can make are listed at the end, separated from the procedure.

## 1. What deploys where

| Piece | Target | How |
| --- | --- | --- |
| Static frontend (`tw-*.html`, `trainw-core.js`, `gate-terminal.*`) | Vercel project `trainw` | Push to `main` (or the release branch) → Vercel builds with `node env-config.js` → output `dist/` |
| Next.js app (`src/`) | **Deleted 2026-11-15 (P2-10)** | Ship vanilla only; the Next.js app no longer exists in this repo. |
| Supabase migrations (`supabase/migrations/`) | Supabase project `Trainw` (`caylegavnekidhytlswo`, eu-west-2) | Applied manually — see §2 |
| Edge functions (`supabase/functions/`) | Same Supabase project | `supabase functions deploy <name>` (needs the Supabase CLI + a login) |

## 2. Applying migrations

Rules (see also `docs/MIGRATION_CONVENTIONS.md` — never edit an
applied migration; one logical piece per file):

1. Apply in **lexicographic filename order** (DB-51 renamed the two
   out-of-order files so the order is the filename order).
2. The Supabase CLI applies each migration file inside **a single
   transaction** by default — a mid-file failure rolls the whole file
   back. Do **not** assume the dashboard SQL editor wraps a pasted
   script the same way: confirm it, or apply through the CLI.
3. Known by-design failure: `20261115050000_phase1b_directories.sql`
   (B5) fails on its own with a return-type error and is repaired by
   `20261115120000`. If anything else fails, stop — do not
   `-- pg-delta: transaction=false` your way past it.
4. After applying, re-run the checks in §4 before calling it done.
5. DB-51 caveat: if an environment already recorded
   `Trainw_001_foundation.sql` as applied, the rename must be paired
   with a migration-version repair on that environment before pushing.

## 3. Secrets checklist (deploy-time, never committed)

Set these before the first real pilot; the app fails loudly without
most of them.

**Vercel — project `trainw`, preview + production:**
- `NEXT_PUBLIC_SUPABASE_URL` — the new project URL
  (`https://caylegavnekidhytlswo.supabase.co`)
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` — the new project's anon key (the
  old project's key belongs to a deleted project; rotate, don't reuse)
- `TURNSTILES_ENABLED` — `false` until the user wants turnstiles back
  (the gate terminal shows a disabled screen while off)

**Supabase — SQL / dashboard:**
- Member-credential pepper (DB-07) — the pepper for the HMAC-SHA256
  credential hashes now lives in the `public.app_secrets` table, key
  `member_credential_pepper` (migration `20261116080000`; the old DB
  GUC `trainw.member_credential_pepper` cannot be set via the
  Management API and is no longer read). Set it once, via SQL, with a
  fresh random 32-byte hex value:
  `INSERT INTO public.app_secrets (key, value) VALUES
  ('member_credential_pepper', '<random 32-byte hex>') ON CONFLICT
  (key) DO UPDATE SET value = EXCLUDED.value;`
  Never commit the value anywhere. **Back it up:** the value lives
  only in the live database — a `pg_dump` (§5) includes the
  `app_secrets` table, so keep the dumps; if the database is lost
  without a dump, the pepper is lost and every enrolled credential
  must be re-enrolled (hashes cannot be recomputed). Rotating the
  pepper invalidates all stored hashes: every member must re-enrol.
- `/tw-login.html` allowlisted in Authentication → URL Configuration →
  Redirect URLs (FE-25 password-reset flow), plus
  `/auth/reset-password` (set live during P1-13 for the deleted
  Next.js flow; unused now, harmless to keep).

**Supabase — edge function secrets:**
- `GATE_TERMINAL_PEPPER` — PIN hashing for `gate-terminal-auth`
- `APP_ORIGINS` — allowed origins for the `ai-proxy` (round 1);
  without it the proxy rejects every call

**Next.js app — deleted (P2-10, 2026-11-15).** The hCaptcha keys
(`CAPTCHA_SECRET_KEY` + `NEXT_PUBLIC_HCAPTCHA_SITE_KEY`) are no
longer needed for launch: they only served the deleted app's public
registration flow. Do not set them up unless the app is ever rebuilt.

**Not a secret, but a setting:** the Supabase dashboard's CAPTCHA and
rate-limit settings for auth (FE-25), and the email templates' redirect
URLs.

## 4. Pre-launch checks

Run these on the staging/preview deployment before any pilot:

1. `npm run verify` (static app checks) — must pass.
2. Live-test the cross-tenant matrix (P1-13): a member of gym A
   cannot read or write gym B's members, payments, sessions, or
   messages; a coach sees only assigned clients; an outsider sees
   nothing.
3. End-to-end: signup → confirm email → create gym → invite a coach
   → member signup → payment settles → membership end date extends →
   gate QR grants access → freeze shifts the end date.
4. Check the deploy secrets in §3 are all set (a missing pepper
   fails closed — neither is acceptable to discover in front of a
   gym).

## 5. Backup and restore

- **Backup:** `scripts/backup-db.sh` — `pg_dump` of the Supabase
  database. The connection string comes from the environment
  (`DATABASE_URL`); never commit it. Run before every migration
  apply and weekly thereafter. Keep the dumps off the repo.
- **Restore drill:** restore a dump to a throwaway database and
  confirm the app reads it (PITR, below, is the real safety net for
  production — the drill proves the dump itself is good).
- **Uptime:** `scripts/uptime-check.sh` — curls the production URL
  and the Supabase REST endpoint; exits non-zero on failure. The
  REST check needs `SUPABASE_ANON_KEY` for a 200; without it, a 401
  still counts as reachable (the project answers). Wire it to
  whatever monitor is chosen (see §6).

## 6. Rollback

- **Frontend:** redeploy the previous Vercel deployment (Vercel keeps
  every deployment; a rollback is one click, no code change).
- **Edge functions:** `supabase functions deploy` the previous
  version from git.
- **Migrations:** there is no automatic down-migration. A bad
  migration is fixed forward with a new migration file (never edit the
  applied one). For data corruption, restore from the pre-apply dump
  (§5) — which is why the backup runs before every apply.
- **Secrets:** rotate (don't reuse) a leaked key; update Vercel and
  Supabase, then redeploy.

## 7. Live decisions (NOT made here — need the user)

- **Staging project:** create a second Supabase project for staging
  (or use a preview branch), so P1-13 live tests never run against
  the production database.
- **PITR (point-in-time recovery):** enable it on the production
  Supabase project in the dashboard (paid add-on on most plans).
  Until it is on, the pg_dump backups in §5 are the only safety net.
- **Error monitoring (Sentry or equivalent):** no account exists yet.
  Pick one, create the project, and add its DSN to the deploy env.
- **Uptime monitor:** `scripts/uptime-check.sh` is the probe; it
  still needs a scheduler (cron, UptimeRobot, Better Stack, …) to
  actually page someone.
- **P2-10:** decided 2026-11-15 — DELETE `src/`, ship vanilla only
  (deletion done in round 7).

## 8. Dashboard settings (FE-10 / FE-12 — set before the first pilot)

These are Supabase dashboard settings, not code. The code is written to
assume they are on; without them the protections below are weaker.

**Realtime Authorization (FE-10).** The three dashboards subscribe to
`postgres_changes` on `messages`, `sessions`, `check_ins`,
`workout_plans` and `weight_logs` with the signed-in user's JWT
(`tw-gym-acc.js`, `tw-client-acc.js`, `tw-coach-acc.js`). The channel
filters (`gym_id=eq.…`, `client_id=eq.…`) are chosen by the client, so
they are not a security boundary on their own. Enable **Realtime
Authorization** in the Supabase dashboard (Database → Replication, or
Settings → API → Realtime, depending on the dashboard version) so the
realtime stream enforces Row Level Security with the caller's JWT —
then a user can only receive rows their RLS policies already let them
read. Without it, any authenticated user could subscribe with any
filter and receive other gyms' rows. (The gate terminal does not use
`postgres_changes` for access results at all any more: gate-checkin
broadcasts only an opaque `access_refresh` signal and the terminal
fetches entries from the authenticated `gate-feed` function.)

**Refresh-token rotation + short JWT expiry (FE-12).** Sessions live in
`localStorage` (the static app has no backend-for-frontend to hold
HttpOnly cookies — that is a larger design item, not done here). The
mitigations that are in place: stored-XSS is closed (round 1, P1-5)
and the CSP is strict (round 1, P1-6), so a token can only be stolen
by a new XSS hole. Reduce the blast radius in the dashboard
(Authentication → Settings):
- Turn **refresh-token rotation ON** (and revoke the family on reuse
  detection if the dashboard offers it) — a stolen refresh token then
  stops working as soon as the legitimate client rotates it.
- Set the **JWT expiry short** (3600 seconds / 1 hour is the Supabase
  default; do not raise it). A stolen access token then dies within
  the hour instead of living for a day.

**Token hygiene (FE-12, verified in code).** No code in the repo logs a
token, secret, password, PIN, or key value: a grep over every `console.*`
call in `*.js` / `*.ts` / `*.tsx` / `*.mjs` finds only the names of
missing env vars (ai-proxy logs that `SUPABASE_URL` / `SUPABASE_ANON_KEY`
are not configured — the values are never printed) and the usual
`invalid_terminal_session` / `invalid_pin` / `server_error` reason
strings, which carry no credential material. Keep it that way: if a
future debug log needs a token, log a truncated hash or the first 4
characters, never the value.

## 9. P2-8 named checks (money and data hygiene, 2026-11-15)

One check per P2-8 item. Run the live SQL checks through the Management
API `POST /v1/projects/{ref}/database/query`; run the chain check on the
throwaway local Postgres cluster (see `docs/MIGRATION_CONVENTIONS.md`
§8). The Next.js items (NX-10/13/15/16) are SUPERSEDED — `src/` was
deleted in round 7 (P2-10) — so each has a vanilla-frontend equivalent
check below instead.

| Item | Named check | Where |
| --- | --- | --- |
| NX-10 (vanilla) | Owner dashboard has working edit/delete for clients, coaches, classes, custom roles, and a staff-revoke action (`revoke_gym_membership`); deleting a client/coach revokes the membership first. Verify by clicking each action in the owner portal on TEST Gym. | `tw-gym-acc.js` (`deleteClient`, `deleteCoach`, `deleteGymClass`, `deleteCustomRole`, `revokeMembership`) |
| NX-13 (vanilla) | Every submit handler disables its button while the request is in flight (`Trainw.ui.setBusy` / `setBtnBusy` / `setCoachBusy` / direct `disabled = true`) and re-enables it in `finally`. Grep: `setBusy\|disabled = true` across `tw-*.js` — no submit handler without one. | `tw-gym-acc.js`, `tw-client-acc.js`, `tw-coach-acc.js`, `tw-login.js` |
| NX-15 (vanilla) | No user-facing toast/inline error shows a raw Supabase/Postgres message. `Trainw.api.run` toasts `normalized.userMessage`; all display sites call `Trainw.api.userMessage(error, fallback)`. Grep: `showToast(.*\.message\|toast(.*\.message` must return nothing. Unit check: `~/workspace/.p28-scratch/test-sanitize.js` (raw RLS/FK/unique/schema-cache messages → generic; `cannot_delete_*:` guard messages and app-authored messages pass through). | `trainw-core.js` (`sanitizeUserErrorMessage`), `tw-gym-acc.js`, `tw-client-acc.js`, `tw-coach-acc.js`, `tw-role.js` |
| NX-16 (vanilla) | Names capped at 100 chars (`maxlength="100"` on every name input in `tw-*-acc.html` + `tw-login.html`); class/session capacity validated ≥ 1 client-side (`saveGymClass`, `submitNewSession`, `saveEditSession`); prices validated > 0 and ≤ 100000 (P2-2); `gym_classes_capacity_check` exists and is validated live. | `tw-gym-acc.html`, `tw-gym-acc.js`, migration `20261116150000` |
| DB-35 | `SELECT conname FROM pg_constraint WHERE NOT convalidated AND connamespace = 'public'::regnamespace;` returns 0 rows, live and on the fresh chain. `assert_no_unvalidated_constraints()` passes. | Live + fresh chain |
| DB-38 | Gym delete guard triggers `trg_prevent_gym_delete_with_data` and `trg_prevent_user_delete_with_payments` exist and are enabled live. Full soft-delete for gyms/users is NOT built — it needs a user decision (see §9 note below). | Migration `20261115240000` |
| DB-39 | All 7 `idx_phase1b_*` indexes exist live (`pg_indexes`, `indexname LIKE 'idx_phase1b_%'`). | Migration (round 2) |
| DB-41 | No public table carries the blanket `authenticated` grant; grants are per-table (`assert_all_tables_have_rls()` passes live). | Migration `20261115170000` |
| DB-50 | No migration after round 4 deletes user data without first logging to `data_repair_log` (see `docs/MIGRATION_CONVENTIONS.md` §4 for the two unlogged exceptions, `20261115230000` and `20261115400000`). | `docs/MIGRATION_CONVENTIONS.md` §4 |
| DB-51 | Foundation file is `20260408180000_trainw_001_foundation.sql` and the v18 file is `20260419000000_trainw_013_v18_additions.sql` (no duplicate "012"). Live `supabase migration list` cannot be checked from here — the chain is applied via the Management API, which does not populate the CLI version table; the substitute is the fresh-chain apply (67 OK + the 2 known by-design failures). | `supabase/migrations/` |
| DB-52 | No migration after `20260408183000` (004) drops policies in a loop; policy changes are per-table, additive. Grep: `DROP POLICY` appears only in 004/005. | `docs/MIGRATION_CONVENTIONS.md` §3 |
| DB-61 | `SELECT assert_rls_helpers_frozen();` passes live and on the fresh chain (resynced 2026-11-15, migration `20261116140000`). | Migration `20261116140000` |
| DB-62 | `handle_new_user` has no blanket `EXCEPTION WHEN OTHERS` handler — a failed profile creation fails the signup loudly. Verify: `prosrc` contains no `EXCEPTION WHEN OTHERS`. | Migration `20261115270000` |
| DB-32 | `users_role_check` includes `gym_admin` and `staff`: `CHECK ((role = ANY (ARRAY['client','coach','gym_owner','gym','admin','gym_admin','staff'])))`. | Live `pg_constraint` |
| DB-34 | `ensure_gym_default_roles` is insert-only: no `DELETE FROM` in its body; roles seeded `ON CONFLICT DO NOTHING`. | Migration `20261115080000` |
| Staging push | **DEFERRED to P2-7.** There is no staging project yet; a staging push cannot be run in this round. The substitute is the fresh-chain apply on the local Postgres cluster (67 OK + 2 by-design failures). | P2-7 |

**DB-38 note (needs the user).** Gym/user deletion is still hard: the
owner portal deletes a client/coach by revoking the membership, deleting
the profile, then deleting the `users` row — which cascades to that
user's messages (the other party's copy included). The audit's minimum
is live (gym delete is forbidden while tenant data exists; user delete
with payments fails with a clear error). True soft-delete
(`is_active`/archived flags + an admin purge) is not a small safe change:
it needs a product decision on what a deactivated gym/user can still do
(can they sign in? do they keep history? does re-signup reactivate them
— `membership_is_active_for_access` already honours `users.is_active`,
but `handle_new_user` would not reset it), plus nullable
`messages.sender_id`/`receiver_id` and chat UI for a deleted
counterpart. Do not build it without his call.
