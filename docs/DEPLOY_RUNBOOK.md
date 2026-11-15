# Trainw deploy runbook (P2-7)

How a release goes from this repo to production, what must be set
before it works, and how to roll back. Live decisions that only the
user can make are listed at the end, separated from the procedure.

## 1. What deploys where

| Piece | Target | How |
| --- | --- | --- |
| Static frontend (`tw-*.html`, `trainw-core.js`, `gate-terminal.*`) | Vercel project `trainw` | Push to `main` (or the release branch) → Vercel builds with `node env-config.js` → output `dist/` |
| Next.js app (`src/`) | **Not deployed today** | P2-10 decision (whether the Next.js app is the ship target at all) — do not switch the Vercel build to it without the user's word |
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
- DB GUC `trainw.member_credential_pepper` — the pepper for the
  HMAC-SHA256 credential hashes (DB-07). Set it with
  `ALTER DATABASE postgres SET trainw.member_credential_pepper = '...'`.
  Without it, credential writes fail closed.
- `/tw-login.html` allowlisted in Authentication → URL Configuration →
  Redirect URLs (FE-25 password-reset flow), plus
  `/auth/reset-password` for the Next.js flow (NX-14) if that app ever
  ships.

**Supabase — edge function secrets:**
- `GATE_TERMINAL_PEPPER` — PIN hashing for `gate-terminal-auth`
- `APP_ORIGINS` — allowed origins for the `ai-proxy` (round 1);
  without it the proxy rejects every call

**Next.js app only (if P2-10 ever ships it):**
- `CAPTCHA_SECRET_KEY` + `NEXT_PUBLIC_HCAPTCHA_SITE_KEY` — CAPTCHA
  **fails open** without the secret; do not go live without it
- `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` (same
  values as the static app)

**Not a secret, but a setting:** the Supabase dashboard's CAPTCHA and
rate-limit settings for auth (FE-25), and the email templates' redirect
URLs.

## 4. Pre-launch checks

Run these on the staging/preview deployment before any pilot:

1. `npm run verify` (static app checks) — must pass.
2. `npm run typecheck && npm run lint && npm run test` in the
   Next.js app (if it is being shipped) — must pass.
3. Live-test the cross-tenant matrix (P1-13): a member of gym A
   cannot read or write gym B's members, payments, sessions, or
   messages; a coach sees only assigned clients; an outsider sees
   nothing.
4. End-to-end: signup → confirm email → create gym → invite a coach
   → member signup → payment settles → membership end date extends →
   gate QR grants access → freeze shifts the end date.
5. Check the deploy secrets in §3 are all set (a missing pepper or
   CAPTCHA secret fails open or fails closed — neither is acceptable
   to discover in front of a gym).

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
- **P2-10:** whether the Next.js app is the ship target at all.

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
