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
  **Live status (P2-7, 2026-11-15):** the live project is on the
  **free plan** (org `Trainw`, verified via the Management API) and
  **has no backups at all** — `GET
  /v1/projects/{ref}/database/backups` returns `pitr_enabled:
  false`, `walg_enabled: true`, `backups: []`. Until the user
  upgrades (see §7), the pg_dump backups in this section are the
  only safety net, and **no dump has ever been taken from here**:
  `pg_dump`/`psql` are not installed on this VM and the live DB
  password lives in the dashboard (user-held). Do not assume a
  backup exists until one has actually been run and its file listed.
- **Restore drill:** restore a dump to a throwaway database and
  confirm the app reads it (PITR, below, is the real safety net for
  production — the drill proves the dump itself is good).
  **Exact procedure (untested end to end — see blockers):**
  1. `DATABASE_URL='postgres://postgres:<live-db-password>@db.caylegavnekidhytlswo.supabase.co:5432/postgres' ./scripts/backup-db.sh` (needs `pg_dump` installed).
  2. Restore into staging: `pg_restore -d
     'postgres://postgres:<staging-db-password>@db.azstzaoujmtpnyjypggq.supabase.co:5432/postgres'
     ~/workspace/backups/trainw/trainw-<stamp>.dump`
     (staging DB password: `goals/build-trainw/hidden_files/staging-project-2026-11-15.md`,
     mode 0600, never committed).
  3. Log in on staging: sign in with the staging test user in that
     file (verified 2026-11-15) and confirm the dashboards load.
  **What was proven instead (P2-7):** a *schema* restore — the full
  74-file migration chain applied to the staging project via the
  Management API, then a login test (see §10). That proves staging
  can host the schema and auth works; it is **not** a data restore —
  no live data was copied, and the pg_dump → pg_restore path itself
  is still untested. Blockers: (a) PITR/backups need the paid
  decision in §7; (b) the live DB password is dashboard-held;
  (c) no `pg_dump`/`psql` on this VM.
  **Migration-chain caveat (learned on staging):** the Management
  API runs one call = one transaction, so a file that fails rolls
  back entirely. `20261115050000` (B5) fails by design (return-type
  error) and its rollback also takes down `20261115120000` (it needs
  `caller_manages_gym_direct` from B5). The working order is: apply
  B5 statement-by-statement, skipping only the failing
  `get_staff_directory` CREATE, then run `20261115120000` whole.
  The local-cluster apply does not hit this because psql continues
  past the error and keeps B5's earlier statements.
- **Uptime:** `scripts/uptime-check.sh` — curls the production URL
  and the Supabase REST endpoint; exits non-zero on failure. The
  REST check needs `SUPABASE_ANON_KEY` for a 200; without it, a 401
  still counts as reachable (the project answers). Wire it to
  whatever monitor is chosen (see §10 for the concrete proposal,
  including the edge-function probes).

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

- **Staging project:** DONE (P2-7, 2026-11-15) — project `Trainw
  Staging`, ref `azstzaoujmtpnyjypggq`, eu-west-2, free tier,
  ACTIVE_HEALTHY. Full migration chain applied, login verified
  (see §10). DB password + test login: `goals/build-trainw/
  hidden_files/staging-project-2026-11-15.md` (mode 0600).
- **PITR (point-in-time recovery):** NOT enabled — the live project
  is on the **free plan** and PITR is a paid add-on (Pro and up
  only). What it costs (Supabase pricing page as read Oct–Nov 2026
  by several independent pricing guides; the Management API does
  not expose prices, so confirm on the billing page before buying):
  **Pro $25/month per organization** (includes $10/month compute
  credit covering one Micro project, and daily backups with 7-day
  retention) **+ PITR $100/month per project for a 7-day retention
  window** ($200 for 14 days, $400 for 28 days), billed hourly and
  **not covered by the spend cap**. PITR also needs at least Small
  compute ($15/month vs the $10 Micro the credit covers), so the
  realistic total for one Pro project with 7-day PITR is **about
  $125–130/month**. The call is the user's: upgrade the org to Pro
  and switch PITR on (dashboard: Project Settings → Add-ons), or
  keep relying on pg_dump (§5) until the first paying gym.
- **Error monitoring (Sentry or equivalent):** no account exists yet
  — do NOT create one from here. Exact setup when the user decides
  (see §10): Sentry account + JavaScript project → DSN into Vercel
  env (`SENTRY_DSN`, preview + production) and into the Supabase
  edge-function secrets → wrap the 4 edge-function handlers (code
  change, not done) → alert rule on gate-function errors.
- **Uptime monitor:** `scripts/uptime-check.sh` is the probe; it
  still needs a scheduler (cron, UptimeRobot, Better Stack, …) to
  actually page someone. Concrete proposal (endpoints, cadence,
  alert rules): §10. No cron or monitor was created in P2-7 — the
  parent owns scheduling.
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
| Staging push | **DONE in P2-7 (2026-11-15).** Staging project `Trainw Staging` (`azstzaoujmtpnyjypggq`, eu-west-2, free) created via the Management API; full 74-file chain applied (71 whole-file OK + B5 statement-wise + `20261115120000` re-run; `20261115300000` failed by design, repaired by `20261115330000`); login verified (test user signs in, profile rows created, `list_public_gyms` `[]`). See §10 for the full result and the two discrepancies found vs live. | P2-7 |

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

---

## 10. P2-7 live status (2026-11-15) — backups, monitoring, staging

### What is live

- **Staging project:** `Trainw Staging`, ref
  `azstzaoujmtpnyjypggq`, region eu-west-2, free tier,
  `ACTIVE_HEALTHY` (created 2026-11-15T17:43:01Z via the Management
  API). API URL `https://azstzaoujmtpnyjypggq.supabase.co`, DB host
  `db.azstzaoujmtpnyjypggq.supabase.co`. DB password + staging test
  login: `goals/build-trainw/hidden_files/staging-project-2026-11-15.md`
  (mode 0600, never committed, never printed anywhere else).
- **Schema restore (the drill's feasible half):** the full 74-file
  migration chain applied to staging via the Management API
  `POST /v1/projects/{ref}/database/query` (harness
  `/tmp/p27-apply-chain.py`, log `/tmp/p27-chain-log.json`).
  First pass 71/74 OK; `20261115050000` (B5) failed by design
  (42P13 return-type) and its single-transaction rollback also
  took down `20261115120000` (missing `caller_manages_gym_direct`)
  — fixed by applying B5 statement-by-statement (24/25, only the
  `get_staff_directory` CREATE failed) and re-running
  `20261115120000` clean. `20261115300000` failed by design (DB-61
  drift guard), repaired by `20261115330000`. Final state: every
  file applied.
- **Staging verified:** 49 public tables;
  `assert_rls_helpers_frozen()` passes; 0 unvalidated constraints;
  all key functions present (`get_staff_directory`,
  `caller_manages_gym_direct`, `validate_member_credential`,
  `ensure_gym_default_roles`, `handle_new_user`,
  `prepare_session_write`, …); anon EXECUTE revoked on all
  sensitive RPCs (matches live — 306 anon grants on staging vs 307
  on live; the 1 difference is `rls_auto_enable`, which exists
  only on live). Ordering fix applied: 4 functions created after
  the round-9 revoke migration ran (`get_staff_directory`,
  `get_staff_directory_sensitive`, `revoke_gate_session`,
  `trainw_rpc_rate_limit_consume`) had anon EXECUTE from the
  Supabase default grant — revoked explicitly, then migration
  `20261116110000` re-run whole (guarded, idempotent).
- **Login verified on staging:** test user
  `staging-p27-test@example.com` created via the Auth Admin API
  (email pre-confirmed); password sign-in 200; `users` row
  `role=client, gym_id=NULL` and a `client_profiles` row exist
  (`handle_new_user` works); `list_public_gyms` returns `[]` (no
  gyms yet, as expected); anon calling
  `trainw_rpc_rate_limit_consume` gets 404 (not visible to anon —
  the owner-only design holds).
- **Staging gaps (not blockers for P2-7, needed before staging is
  really usable):** `app_secrets` is empty — set a **fresh**
  `member_credential_pepper` (different from live) before any
  gate-credential test on staging; no seed/test gyms exist yet;
  the app frontend is still pointed at live — to run the app
  against staging, build with the staging URL + anon key
  (`env-config.js` / Vercel preview env) and point a preview
  deployment at it.

### What is blocked on the user

- **PITR / backups:** live is free-plan, `pitr_enabled: false`,
  `backups: []`. Needs Pro ($25/mo/org) + PITR add-on ($100/mo per
  project, 7-day window; $200/14d, $400/28d) — realistic total
  about $125–130/mo (see §7). Until then pg_dump (§5) is the only
  safety net, and no dump has ever been taken.
- **True restore drill:** blocked on the PITR decision above, plus
  the live DB password (dashboard-held) and no `pg_dump`/`psql` on
  this VM. The pg_dump → pg_restore procedure is in §5; the
  schema-restore + login half is done (above).
- **Sentry:** no account exists. Setup when the user decides:
  1. User creates a Sentry account and a project (platform:
     JavaScript) at sentry.io and copies the DSN.
  2. DSN → Vercel env on project `trainw`, preview + production
     (`SENTRY_DSN`; browser-side reporting also needs it exposed
     as `NEXT_PUBLIC_SENTRY_DSN`), then redeploy.
  3. DSN → Supabase edge-function secret (`SENTRY_DSN`, via the
     dashboard or CLI) for the 4 functions.
  4. Code change (not done in P2-7): wrap the 4 edge-function
     handlers (`gate-checkin`, `gate-terminal-auth`, `gate-feed`,
     `ai-proxy`) with Sentry capture so a 5xx / uncaught exception
     becomes a Sentry issue with the request context.
  5. Alert rule in Sentry: new issue from any gate function →
     notify the user (email; Slack if he uses it). Until Sentry
     exists, gate errors surface only in the Supabase dashboard's
     Edge Function logs.

### Uptime check + gate-error alert — proposal (no monitor created)

No cron job or scheduled monitor was created in P2-7; the parent
owns scheduling. Proposed monitor (UptimeRobot / Better Stack /
cron — parent's choice), every **5 minutes**, running
`scripts/uptime-check.sh` extended with the edge-function probes:

| Probe | URL | Expected while turnstiles are OFF | Alert on |
| --- | --- | --- | --- |
| Production site | `https://trainw.vercel.app/` | 200 | anything else (000, timeout, 5xx) |
| Supabase REST | `https://caylegavnekidhytlswo.supabase.co/rest/v1/` | 401 without key (reachable) / 200 with anon key | 000, timeout, 5xx, or a 4xx other than 401 |
| `gate-checkin` | `POST …/functions/v1/gate-checkin` (no auth) | 503 `{"access":false,"reason":"turnstiles_disabled"}` | anything else — a 200/401 here means the flag check broke |
| `gate-terminal-auth` | `POST …/functions/v1/gate-terminal-auth` (no auth) | 503 `{"ok":false,"error":"turnstiles_disabled"}` | anything else |
| `gate-feed` | `POST …/functions/v1/gate-feed` (no auth) | 503 `{"entries":[],"error":"turnstiles_disabled"}` | anything else |
| `ai-proxy` | `POST …/functions/v1/ai-proxy` (no auth) | 401 `UNAUTHORIZED_NO_AUTH_HEADER` | anything else (000, 5xx) |

All six expected responses were observed live on 2026-11-15.
**When turnstiles are re-enabled, the expected gate responses
change** (unauthenticated calls should become 401, not 503) —
update the probe at the same time as the flag, or the monitor will
page on a healthy system. **Gate-error alert:** until Sentry
exists (§10 above), the alert is this probe plus a manual check of
the Supabase Edge Function logs for 5xx / `server_error`; with
Sentry, the alert rule is "new issue from a gate function". Note
the gate functions currently return 503 `turnstiles_disabled` for
every call, so a gate *error* today looks exactly like the healthy
disabled state — the probe can only catch the functions being down
or the flag logic breaking, not bad gate decisions. Real
gate-error alerting starts when turnstiles go back on.

### Two discrepancies found vs live (flagged, not fixed here)

- **P2-5 never landed on live.** Live has no `rpc_rate_limits`
  table and no `trainw_rpc_rate_limit_consume`; live's
  `list_public_gyms` / `request_gym_membership` are the
  pre-limiter versions (their bodies contain no reference to the
  limiter). Migration `20261116130000` was verified locally and on
  staging but has no live-apply record in the notes. The join-flow
  rate limiting is therefore not live. Applying it to live is a
  P2-5 follow-up for the parent, not part of P2-7.
- **Leftover probe tables on live:** `__probe_a`, `__probe_b`
  (from an earlier round's probes). Same bucket as the known
  test-data cleanup; remove with the rest of the test data, not
  ad hoc.
