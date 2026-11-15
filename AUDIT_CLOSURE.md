# Trainw Audit Closure — 2026-11-15 (Round 6)

**Audit:** `~/workspace/goals/build-trainw/files/trainw-security-audit-2026-11-14.md` — 137 findings (7 CRITICAL, 39 HIGH, 54 MEDIUM, 37 LOW).
**Code state verified against:** local branch `phase1-security-fixes`, head `bd4c441` (rounds 1–6; remote tip `234cc893` + round-6 commits `78a63b6`, `b96c892`, `f3152ba`, `bd4c441` — not yet pushed).
**Method:** every finding checked against the CURRENT code, not the notes. Round 4 already caught false claims in the round-2 notes (NX-17, NX-27); round 6 caught more (NX-11 was open, NX-15 was only half-fixed, DB-14/DB-16/DB-54/DB-56 were partial, `invite_gym_member` was broken on every call, void-restore was wrong for NULL-end members). A finding counts as **FIXED+VERIFIED** only if a test or a code check proves it.

## Verification evidence used

- **Behavioural suite (round 6):** throwaway local Postgres 16 cluster, FULL migration chain applied end to end (60 files; 58 OK, 2 fail — exactly the two known by-design failures `20261115050000` B5 return-type and `20261115300000` DB-61 non-portable hash, both repaired by later migrations), **161/161 assertions pass** on a fresh DB, plus targeted probes for DB-42/43/44/47. Harness + suite: `~/workspace/.r6-scratch/` (`r6-harness.sh`, `r6-tests.sql`).
- **Next.js verification (round 6):** `npm install` + `tsc --noEmit` (clean) + `vitest run` (**33/33**, incl. a new NX-07 case) + `eslint` (clean) + `next build` (green, all routes) in a scratch copy on the overlay disk (`~/workspace/.r6-scratch/next-app`, deleted after — keep the notes, not the 400 MB).
- **Code checks (round 6):** grep audits for XSS sinks, PIN-in-URL, hardcoded secrets, SRI hashes, `as any` casts, direct `.message` returns, storage policies, edge-function error paths.

## Counts (honest)

| Status | Count |
|---|---|
| FIXED+VERIFIED | **115** |
| FIXED+NEEDS-LIVE-TEST | **19** |
| OPEN-DECISION-NEEDED | **2** |
| OPEN-LIVE-ONLY | **0** |
| NOT-APPLICABLE | **1** |
| **Total** | **137** |

By severity — CRITICAL 7: 6 VERIFIED, 1 NEEDS-LIVE (DB-08). HIGH 39: 27 VERIFIED, 11 NEEDS-LIVE, 1 DECISION (NX-03). MEDIUM 54: 46 VERIFIED, 6 NEEDS-LIVE, 1 DECISION (DB-66), 1 NOT-APPLICABLE (GT-04). LOW 37: 36 VERIFIED, 1 NEEDS-LIVE (NX-28). Detail is per-row below.

## Statuses

- **FIXED+VERIFIED** — a test or a code check proves the fix in the current code.
- **FIXED+NEEDS-LIVE-TEST** — code is in place; proof needs the live Supabase/Vercel environment (P1-13).
- **OPEN-DECISION-NEEDED** — the user's call; not decided by the agent.
- **OPEN-LIVE-ONLY** — can only be fixed/verified on the live project.
- **NOT-APPLICABLE** — does not apply to this codebase, with the reason stated.

---

## CRITICAL (7)

| ID | Description | Status | Evidence |
|---|---|---|---|
| DB-01 | Any client could UPDATE own `client_profiles` incl. `payment_status`/`price_paid`/dates and walk through the gate unpaid | FIXED+VERIFIED | Round-1 guard triggers (`20261114000000`); suite: self-update of `payment_status` rejected |
| DB-02 | Any coach could UPDATE own `coach_profiles` incl. `approval_status`/`rating` and self-approve | FIXED+VERIFIED | Round-1 guard triggers (`20261114000000`); suite: self-approve blocked |
| DB-03 | Unauthenticated SECURITY DEFINER `ensure_role_permission_codes` could wipe/rewrite any gym's roles | FIXED+VERIFIED | Round-1 REVOKEs (`20261114010000`); suite: unauthenticated call fails |
| DB-04 | Unauthenticated SECURITY DEFINER `ensure_gym_default_roles` could reset any gym's roles to defaults | FIXED+VERIFIED | Round-1 REVOKEs (`20261114010000`); suite: non-manager call fails |
| DB-07 | Fingerprint/face templates stored as plaintext, compared by plain equality | FIXED+VERIFIED | Round-2 HMAC-SHA256 + pepper (`20261115010000`); suite: hash-only storage, `validate_member_credential` verifies hashes |
| DB-08 | Seed hard-codes a real shared password for two real Gmail test accounts | FIXED+NEEDS-LIVE-TEST | Seed now takes the password from session GUC `trainw.seed_password`, raises if unset; grep: 0 password hits in repo. **Live step left:** rotate `coachtestv17@gmail.com` / `clienttestv17@gmail.com` in Supabase Auth |
| FE-01 | Stored XSS: client-controlled display name interpolated raw into the owner's client cards via `innerHTML`, incl. an inline `onclick` built from the name | FIXED+VERIFIED | Code check: `renderClients` escapes name/phone/goal via `Trainw.escapeHtml`; `onclick=` count in app JS is 1 and it is a comment; `setHtml` escapes by default |

## HIGH (39)

| ID | Description | Status | Evidence |
|---|---|---|---|
| DB-05 | Any user could UPDATE own `users` row incl. `role`/`gym_id` | FIXED+VERIFIED | Round-1 guard triggers; suite: role/gym_id self-edit rejected |
| DB-06 | `gyms_update` let any gym member rewrite the gym's name/settings | FIXED+VERIFIED | Round-1 `manages_gym` fix (`20261114020000`); suite: non-manager gym update rejected |
| DB-09 | Demo credentials `admin@lakeclub.tn` / `reception@lakeclub.tn` published in seed + deploy doc | FIXED+NEEDS-LIVE-TEST | Credentials removed from seed and doc; grep: 0 hits in repo. **Live step left:** rotate the demo accounts in Supabase Auth |
| DB-10 | Signup trigger trusted user-controlled `raw_user_meta_data` role/gym_id | FIXED+VERIFIED | Round-2 bootstrap rewrite (`20261115020000`); suite: metadata role/gym ignored |
| DB-11 | Bootstrap adopted an existing gym by email/name match for owner/admin claimants | FIXED+VERIFIED | Round-2; suite: adopts only a gym the caller already manages, else creates a new gym |
| DB-12 | `set_membership_role` had no check that the role belongs to the membership's gym | FIXED+VERIFIED | Round-2 role-gym check + round-6 owner-role guard (`20261115370000`); suite: foreign-role assignment rejected |
| DB-13 | `save_role_definition` could rewrite system roles (no `is_system` guard) | FIXED+VERIFIED | Round-2 system-role guard; suite: system role rewrite rejected |
| DB-14 | `gym_memberships` manage policy let a `manage_staff` holder INSERT an ACTIVE owner-role membership for someone else; invite path had no owner guard | FIXED+VERIFIED | **Round-6 fix** (`20261115360000`, `20261115370000`): policies + `set_membership_role` + `invite_gym_member` refuse `gym_owner` unless caller is the gym's manager; suite: 161/161 incl. owner-role insert attempts |
| DB-15 | `manage_staff` holder could self-grant any permission via `user_permissions` | FIXED+VERIFIED | Round-2; suite: self-grant/self-invite rejected |
| DB-16 | `manages_gym()` returned true for branding-only users, passing every admin policy (payments, credentials, devices, check-in deletes) | FIXED+VERIFIED | Round-1 removed `manage_branding` from `manages_gym()`; **round-6 fix** (`20261115380000`): payments/credentials/devices/check-in-delete policies also require the per-action permission (`manage_payments` / `manage_access_control` / `manage_checkins`). Suite proved the hole live (branding-only user inserted a payment) and proves it closed. **Behaviour change:** default `staff` role holds none of those three, so front-desk staff can no longer record payments or enrol gate credentials/devices; an owner can grant them from the roles UI |
| DB-17 | No payment idempotency key (`provider_reference`/`invoice_reference` not unique) | FIXED+VERIFIED | Round-2 idempotency indexes; suite: duplicate `provider_reference` rejected |
| DB-18 | `prepare_payment_write` did not verify a session-less payment's client belongs to the gym | FIXED+VERIFIED | Round-2; suite: cross-gym payment rejected |
| DB-19 | Managers could DELETE payment rows outright, cascading the audit trail | FIXED+VERIFIED | Round-2 no-DELETE + RESTRICT; suite: DELETE blocked (RLS 0 rows + FK RESTRICT), void via status only |
| DB-20 | Staff directory returned `invite_token` + `national_id` to any front-desk staff | FIXED+VERIFIED | Round-2 split (B5 + fix `20261115120000`); suite: `get_staff_directory` returns no `invite_token`/`national_id`; audited sensitive variant exists |
| DB-22 | `validate_member_credential` joined the membership without a gym filter (multi-gym clients) | FIXED+VERIFIED | Round-2; suite: credential valid only for the calling gym's profile |
| DB-31 | Audit/refresh triggers were SECURITY INVOKER writing to RLS tables with no INSERT policy | FIXED+VERIFIED | Round-2 SECURITY DEFINER triggers; suite: `log_payment_event` writes land |
| DB-32 | `users.role` CHECK vs 007 role codes mismatch; legacy mapping gaps | FIXED+VERIFIED | Round-2 role-check widening; suite: default roles seed with correct codes/permissions, `permission_codes_for_membership` resolves |
| DB-33 | Two conflicting schemas: `database/schema.sql` vs the migration chain | FIXED+VERIFIED | Round-3 P1-11: `database/schema.sql` + `seed.sql` archived under `database/archive/` with README; `database/` now holds only `archive/`; chain is authoritative. **Caveat (see NX-03):** the Next.js tables/RPC still have no migration |
| DB-34 | Role seeding DELETEs + re-inserts all permissions on every run | FIXED+VERIFIED | Round-4 insert-only redefinition (`20261115080000`, ON CONFLICT DO NOTHING); code check |
| DB-36 | No real money record: "paid" was a dropdown, revenue computed three ways, payments deletable | FIXED+VERIFIED | Round-3 append-only ledger + settlement + immutability guard + refund RPC; suite: settle/idempotency/void/refund all pass. **Round-6 fix** (`20261115390000`): void restores a NULL pre-settlement end date exactly (sentinel `0001-01-01`); previously left at the period start |
| DB-49 | Demo reset script picked its target gym with `SELECT ... LIMIT 1` (no ORDER BY), then DELETEs that gym's sessions, profiles and users | FIXED+VERIFIED | Round-2: the script requires an explicit gym id (`trainw.demo_gym_id` GUC), refuses to run without it and refuses multi-gym runs; code check |
| FE-02 | `innerHTML` sinks with unescaped user data (dashboard stats, schedule, session detail, coach carousel) | FIXED+VERIFIED | Code check: client-card renderer escapes name/phone/goal/initials; `membership_tier` interpolation is CHECK-constrained to 7 fixed values (`client_profiles_membership_tier_check`) |
| FE-03 | Inline `onclick` handlers built from user data | FIXED+VERIFIED | Code check: `onclick=` count across app JS is 1, a comment; handlers are `addEventListener`/delegation |
| FE-04 | Gate terminal PIN passed in the URL / blank PIN passed | FIXED+VERIFIED | Round-2: PIN verified server-side via `gate-terminal-auth`, SHA-256 token, no PIN-in-URL code (grep clean) |
| FE-06 | Client/coach data loads not gym-scoped (cross-gym reads) | FIXED+NEEDS-LIVE-TEST | Code: 48 `.eq('gym_id', currentGymId)` in `tw-gym-acc.js`, messages scoped, coach bootstrap gym-scoped. Runtime cross-tenant proof is P1-13 |
| FE-07 | Writes not gym-scoped (sessions, classes, clients, coaches, users delete) | FIXED+NEEDS-LIVE-TEST | Code: same 48 gym-scoped writes; DB suite proves RLS blocks cross-gym writes. Runtime proof is P1-13 |
| FE-08 | Coach search ran a bare `users` query (cross-gym names) | FIXED+NEEDS-LIVE-TEST | Code: no bare `users` select remains (remaining `from('users')` calls are id-scoped update/delete). Residual: embedded-users name filter still needs live verification |
| FE-09 | Weak QR token (`Math.random` in pilot code) + single-use enforcement questioned | FIXED+VERIFIED | Code check: 0 `Math.random` in gate paths; `randomGateToken()` uses `crypto.getRandomValues` (128-bit); handler enforces expiry + atomic single-use (`UPDATE ... WHERE used=false`). Live QR scan is a P1-13 check |
| FE-12 | Sessions in `localStorage` (supabase-js defaults, no auth options) | FIXED+NEEDS-LIVE-TEST | Code still uses defaults (no BFF/HttpOnly — deliberate design decision, L effort). Accepted mitigation is runbook §8 dashboard settings (refresh-token rotation ON, 1h JWT expiry) — **must be verified live**; if not applied, the finding is not mitigated |
| FE-14 | No Subresource Integrity on CDN scripts | FIXED+VERIFIED | Code check: 14 `integrity="sha384-…"` attributes across the HTML pages; real hashes for supabase-js 2.119.0, lucide, chart.js, html5-qrcode, qrcodejs |
| FE-19 | "Paid" was a dropdown anyone with edit access could flip; no ledger in the UI | FIXED+VERIFIED | Round-3: payments view rewired to the ledger; only `payment_status: 'pending'` seed write remains in `tw-gym-acc.js`; suite proves the ledger |
| FE-22 | `dist/` stale (6 referenced files missing) | FIXED+VERIFIED | Round-1 rebuilt `dist/`; `dist/` untracked (`git ls-files dist` empty) and rebuilt by Vercel per push — 4 preview deployments READY |
| GT-01 | AI proxy: no auth, wildcard CORS, no quota — anyone could spend the Anthropic key | FIXED+NEEDS-LIVE-TEST | Round-1: JWT auth + gym check + 50/day quota (`20261114030000`, `ai-proxy/index.ts:87-107`). Needs a live edge-function test (deploy + JWT) |
| GT-03 | No rate limiting/lockout on the gate endpoint (unlimited token guesses) | FIXED+NEEDS-LIVE-TEST | Code: gate rate limits 60/min IP, 30/min device (`20261114040000`); DB-48 lockout verified in suite (5 failures/15 min). Edge-function throttle itself needs a live test |
| NX-01 | Zero rate limiting/CAPTCHA/throttling in the Next.js app | FIXED+NEEDS-LIVE-TEST | Code: `src/lib/rate-limit.ts` wired into login/signup/search/public-registration; `src/lib/captcha.ts` (hCaptcha). **CAPTCHA fails open without `CAPTCHA_SECRET_KEY` — pre-launch deploy blocker.** Live behaviour unproven |
| NX-02 | Anyone unauthenticated could mint a full gym workspace + admin user (`email_confirm: true`) | FIXED+NEEDS-LIVE-TEST | Code: confirmed-email signup, invite flow (`src/actions/auth.ts:97-116`). Needs a live Auth test |
| NX-03 | Next.js data model (`clients`, `coaches`, `classes`, `provision_new_gym` RPC, RLS) has no migration | OPEN-DECISION-NEEDED | **P2-10 — the user's call.** P1-11 archived `database/schema.sql` without reconciling it into the chain, so NX-02/NX-04/NX-05 code fixes depend on a schema that does not exist in the chain DB. The callback's `provision_new_gym` call would fail against a chain-only DB |
| NX-04 | No server action verified a referenced UUID belongs to the caller's gym | FIXED+NEEDS-LIVE-TEST | Code: 33 `context.gymId` scoping uses across actions; role-belongs-to-gym checks. Cannot be exercised until P2-10 is decided (no chain tables) |
| NX-05 | Unauthenticated client registration: no login, CAPTCHA, rate limit, approval, or contact info | FIXED+NEEDS-LIVE-TEST | Code: pending-approval queue + CAPTCHA + rate limit + email/phone (`src/app/api/public/clients/route.ts`). Needs a live test (and the P2-10 tables) |

## MEDIUM (54)

| ID | Description | Status | Evidence |
|---|---|---|---|
| DB-21 | Member directory returned the full directory to any accepted member, incl. plain clients | FIXED+VERIFIED | Round-2 staff-only directory; suite: client caller gets 0 rows |
| DB-23 | Gate's "active" test disagreed with booking's (`trial`/`waived`, NULL start date) | FIXED+VERIFIED | Round-2 shared `membership_is_active_for_access` fn; suite: trial/waived/NULL-start cases agree |
| DB-24 | Duplicate guard only rejected 2-hour re-entry; later same-day check-in hit the unique index with a raw error | FIXED+VERIFIED | Round-2 graceful duplicates; suite: second same-day check-in returns a clean denial, no raw error. Note: one check-in/day remains the policy (see GT-08) |
| DB-25 | `gate_sessions` had no UPDATE policy and no SQL function validating a QR token | FIXED+VERIFIED | Round-2 service-role-only gate-session RPC; suite: authenticated callers get "permission denied for function" |
| DB-26 | `check_ins_insert` let any client insert a check-in for themselves with no membership/payment validation | FIXED+VERIFIED | Round-2; suite: check-in without an active paid membership rejected |
| DB-27 | `bookings_manage_v17` FOR ALL with no session/gym/status-transition checks | FIXED+VERIFIED | Round-4 booking/session write scoping; suite: cross-gym booking writes rejected |
| DB-28 | Coach branch could UPDATE any column on a session they coach | FIXED+VERIFIED | Round-4; suite: coach update outside assignment rejected |
| DB-29 | Every `gym_profiles` policy satisfied by `user_id = auth.uid()` alone, no gym check | FIXED+VERIFIED | Round-2; suite: profile writes outside the caller's gym rejected |
| DB-30 | Personal records / milestone photos: `gym_id` nullable, unconstrained — a client could tag any gym | FIXED+VERIFIED | Round-2; suite: record/photo insert with a foreign gym_id rejected |
| DB-35 | 25 CHECK/FK constraints added NOT VALID, never validated (audit said 25; actual count 24) | FIXED+VERIFIED | Round-4 validated all 24; suite on fresh DB: 0 unvalidated constraints, `assert_no_unvalidated_constraints()` passes |
| DB-37 | `gyms.timezone` never referenced; all date math used server time | FIXED+VERIFIED | Round-4 gym-timezone "today"; round-5 `get_bookable_slots` filters in the gym's zone (proven with a UTC+14 gym) |
| DB-38 | Deleting a gym cascaded to payments/sessions/memberships/media with no archive | FIXED+VERIFIED | Round-4; suite: deleting a gym that still holds tenant data is forbidden |
| DB-39 | Missing indexes that hurt at 5,000+ members per tenant | FIXED+VERIFIED | Round-2 seven indexes; SQL check on fresh DB: 7 `idx_phase1b_*` indexes present |
| DB-40 | Invite tokens never expired; re-inviting reset a member to pending with NULLed acceptance | FIXED+VERIFIED | Round-2 7-day expiry; **round-6 fix** (`20261115360000`): `invite_gym_member` raised "column reference invite_email is ambiguous" on EVERY call — the invite flow was completely broken; fixed + owner-role guard added. Suite: invite/accept/expiry pass |
| DB-41 | Blanket `GRANT ... ON ALL TABLES TO authenticated`, relying entirely on RLS | FIXED+VERIFIED | Round-4 per-table grants + `assert_all_tables_have_rls()`; suite: assert passes on fresh DB |
| DB-45 | Coach/client assignment sync had no confirmation step; reassigned profiles across gyms | FIXED+VERIFIED | Round-4: assignments pending until confirmed; suite caught the real cross-gym bug in `sync_client_profile_assignment` (fixed `20261115165000`); suite: cross-gym assignment rejected |
| DB-46 | Storage SELECT policy let any gym member read any member's profile files; `is_public` never consulted | FIXED+VERIFIED | Round-4 storage private-by-default + `media_assets.is_public`; suite: outsiders (no gym membership) cannot see private objects. **Design note:** a same-gym client holds `manage_media` by default, so they can see other members' private profile media — same-gym only; tightening needs a product decision |
| DB-47 | Credential-ref "truncation" returned the full value when ≤18 chars | FIXED+VERIFIED | Round-2 rewrite; live probe: 36-char input → `abcd...` (7 chars), ≤4-char input → `****` |
| DB-48 | No rate limiting/lockout in the gate validation RPC | FIXED+VERIFIED | Round-4 `record_gate_credential_failure` + lockout; suite end-to-end: 4 failures → no lock, 5th → `locked_until` set, locked credential denied with `credential_locked`, a different credential still works |
| DB-50 | Migrations performed destructive data repair on deploy with no log | FIXED+VERIFIED | Round-4 `data_repair_log` table (`20261115200000`) + `docs/DATA_REPAIR_RUNBOOK.md` + dry-run audit; code check |
| DB-51 | Foundation file had no timestamp prefix, so it sorted after all `202604...` files | FIXED+VERIFIED | Round-4 renamed to `20260408180000_trainw_001_foundation.sql` and the v18 file to `20260419000000_trainw_013_v18_additions.sql`; file check (60 migrations start with `2026...`). A live `supabase migration list` check remains for the deployed project |
| DB-65 | No policy/trigger stopped a manager changing `amount_total`/`amount_paid`/`status` after the fact | FIXED+VERIFIED | Round-3 immutability guard; suite: direct amount edits and paid→pending flips rejected |
| DB-66 | Completing/no-showing a session does not touch its payment (no refund/credit path) | OPEN-DECISION-NEEDED | **The user's call.** Refund RPC exists (`record_payment_refund`); the policy — refund vs credit vs forfeit on no-show — is undecided |
| FE-05 | Real Supabase URL + anon JWT hardcoded in committed `gate-terminal.html` | FIXED+VERIFIED | Code check: 0 `supabase.co` URLs in `gate-terminal.html`; config comes from `trainw-config.js` (build-time env injection) |
| FE-10 | Gate access results broadcast on a public Realtime channel (member names + entry outcomes) | FIXED+VERIFIED | Round-5: broadcast is now just an opaque `access_refresh` signal; new authenticated `gate-feed` edge function returns the 8 recent log rows (round-5 verified 5/5 by session token). Code check: `access_result` appears once, in a comment explaining the removal |
| FE-11 | Role/portal enforcement entirely client-side | FIXED+NEEDS-LIVE-TEST | Code part done (round-2 B2, `get_auth_context`); the real boundary is RLS, which the DB suite proves blocks cross-tenant access. Live test remains in P1-13 |
| FE-13 | No CSP headers on the static app (vercel.json) or the dev server | FIXED+VERIFIED | Round-1 strict CSP in `vercel.json` (+ dev-server headers); code check |
| FE-15 | Monthly revenue computed three different ways that disagree | FIXED+VERIFIED | Round-3: revenue derives from the ledger only (`loadLedgerRevenue`; code comment "never from a price_paid sum"); suite proves the ledger |
| FE-16 | Hardcoded price defaults (150/400/1400) in the frontend | FIXED+VERIFIED | Code check: grep for price/amount defaults returns nothing |
| FE-17 | `calcEndDate` used local `setMonth()` (Jan 31 + 1mo → Mar 2/3) and mixed local/UTC | FIXED+VERIFIED | Round-4 UTC + month-end clamping (`tw-gym-acc.js:3183-3188`); code check |
| FE-20 | `saveEditClient` swallowed errors / no error handling on writes | FIXED+VERIFIED | Round-2: writes go through `Trainw.api.run` (88 call sites in `tw-gym-acc.js`); code check |
| FE-21 | Uploads with no type/size validation | FIXED+VERIFIED | Round-2: PNG/JPEG/WebP, max 5 MB (`tw-gym-acc.js:1769`); code check |
| FE-23 | Scraping fallback that read the Supabase key out of a stale `dist` copy | FIXED+VERIFIED | Round-2 removed; code check: no scraping/fallback fetch remains |
| FE-27 | Dead code: `tw-client-pilot.js` (weak QR tokens), `wrap()` monkey-patching, dead renderers | FIXED+VERIFIED | Round-4 purge: `tw-client-pilot.js` deleted, `wrap()` gone (`window.TrainwGymHooks` registry + `runGymHooks()` instead); code check. (Round 5's notes wrongly listed FE-27(e) as skipped — it was done in round 4) |
| FE-28 | Hardcoded French strings outside the i18n dicts; gate admin modal not accessible | FIXED+VERIFIED | Round-4: 7 strings into the T dicts; `aria-label` attributes on gate result pills / modal controls; code check |
| FE-29 | Network failures shown as camera errors; no honest online indicator | FIXED+VERIFIED | Round-4: distinct `camera_error` / `network_error` strings, `isOnline` indicator (`gate-terminal.js:164`); code check |
| FE-30 | Auth context preferred a requested gym id without checking the user belongs to it | FIXED+VERIFIED | Round-4 `pickScopedActiveMembership` picks only from the user's real memberships (`trainw-core.js`); code check |
| FE-32 | Dev server served any file under the repo root, no allow-list | FIXED+VERIFIED | Round-2 allow-list (`dev-server.js`: allowed extensions + never-served trees); code check |
| GT-02 | Gate endpoint authenticated nothing except the public anon key; no per-device secret | FIXED+VERIFIED | Round-2 terminal tokens + round-5 device binding: same token from another device, or with no `device_id`, gets 401 (round-5 tested 4/4) |
| GT-04 | On network failure the terminal denies entry with a misleading `camera_error`; no offline queue/allow-list | NOT-APPLICABLE | No ESP32 gate firmware exists in this repo, so there is no offline path to build; and the user decided turnstiles are OFF (`TURNSTILES_ENABLED=false`) until further notice. If turnstiles are ever re-enabled, the offline allow-list must be designed then (firmware + cached list) |
| GT-05 | QR tokens predictable / not opaque | FIXED+VERIFIED | Round-4/5: tokens are opaque 128-bit random strings (`randomGateToken`, `crypto.getRandomValues`); same evidence as FE-09 |
| GT-08 | 2-hour duplicate guard denied legitimate same-day re-entry, then the unique index raised a raw error | FIXED+VERIFIED | Round-2/4 graceful duplicate handling: second same-day check-in returns a logged 409 `duplicate_checkin_today`, not a raw error. **Policy note:** one check-in per day is still the rule (unique index `uq_check_ins_gym_client_day`); allowing lunch-time re-entry is a product decision, not a bug fix |
| GT-09 | No `supabase/config.toml` — edge-function `verify_jwt` settings unverifiable from code | FIXED+NEEDS-LIVE-TEST | Round-2 `supabase/config.toml` exists (`gate-checkin`/`gate-terminal-auth`/`gate-feed` false by design, `ai-proxy` true). The file itself says to confirm in the dashboard after the first deploy |
| NX-06 | Unauthenticated gym directory: no auth, rate limit, or minimum query length; query interpolated into `.ilike` | FIXED+VERIFIED | Round-2 hardening: min length 2, max 64, rate limit 30/min (`src/app/api/gyms/search/route.ts:16-31`); code check |
| NX-07 | Login `redirectTo` passed straight to `redirect()` — open redirect | FIXED+VERIFIED | **Round-6 fix:** `loginSchema.redirectTo` refined to same-site relative paths only; callback `safeNext` also rejects `//` and backslash targets. Vitest: new case, 5 assertions, 33/33 pass |
| NX-08 | No Next.js middleware at all; `updateSession` defined but never invoked | FIXED+NEEDS-LIVE-TEST | Round-2 `src/middleware.ts` wires `updateSession`; needs a live test that protected routes actually redirect unauthenticated users |
| NX-09 | Staff creation checked only that the role belongs to the gym — no check the target role isn't more privileged than the caller | FIXED+NEEDS-LIVE-TEST | Round-2: owner-role grant requires the caller to be an owner (`isOwnerRoleName` check, `src/actions/roles.ts`); invites replace `email_confirm: true` + caller-chosen passwords. Needs a live test |
| NX-10 | No update/delete/deactivate actions at all (clients, coaches, classes, roles, staff logins) | FIXED+NEEDS-LIVE-TEST | Round-4 actions exist (`src/actions/roles.ts`, `clients.ts`); needs a live test against the P2-10 tables |
| NX-11 | Next.js app shipped with no security headers at all | FIXED+VERIFIED | **Round-6 fix:** `next.config.ts` now has `headers()` mirroring `vercel.json` (CSP, `X-Frame-Options: DENY`, HSTS, nosniff, Referrer-Policy, Permissions-Policy). Verified: tsc clean, `next build` green, headers present in `.next/routes-manifest.json`. **Tradeoff (documented in the file):** `script-src` keeps `'unsafe-inline'` — Next.js inlines its bootstrap scripts; a nonce-based CSP via middleware would be needed to drop it |
| NX-12 | Four of six list queries unbounded — whole member table rendered on every visit | FIXED+VERIFIED | Round-4 pagination: `Pagination` component + `parsePageParam` on all dashboard list pages (50/page); `pagination.test.ts` in the suite; code check |
| NX-13 | `SubmitButton` never set `disabled={pending}` — every server-action form could double-submit | FIXED+VERIFIED | Round-4 `SubmitButton` with pending state; used across all forms (`pendingLabel="Saving…"`) — code check + build green |
| NX-14 | No password-reset flow | FIXED+NEEDS-LIVE-TEST | Round-4: reset request + `/auth/recover` + `/auth/reset-password` (`src/actions/auth.ts:281`). Needs a live email test |
| NX-15 | Raw Supabase/Postgres error messages returned to the browser | FIXED+VERIFIED | **Round-6 fix:** `getErrorMessage` now returns only the caller-supplied generic fallback (raw error logged server-side). Round 6 found the fix was incomplete — 23 direct `.message` returns still existed across roles/clients/attendance/classes/coaches — all replaced. Grep proves zero direct returns remain in `src/`; tsc/vitest/build green |
| NX-16 | Server-side validation has no upper bounds (names, rating, capacity) | FIXED+VERIFIED | Rating clamped server-side already (`Math.max(0, Math.min(5, parsed))`). **Round-6 fix:** class capacity refined to a whole number ≥ 1 in both schemas (the DB CHECK exists only for sessions, not classes); create-name `max(100)` added to classes/clients/coaches + signup `fullName`/`gymName`. Verified by code check + tsc + build. Note: the capacity refine is not covered by a vitest case (the schemas are module-private and pull server imports); the NX-07 schema case is covered |

## LOW (37)

| ID | Description | Status | Evidence |
|---|---|---|---|
| DB-42 | SECURITY DEFINER `auth_user_email` returned any user's email, no REVOKE | FIXED+VERIFIED | Round-2 caller checks; **live probe (round 6):** as ownerA, `auth_user_email(ownerB)` raises "Not allowed to read this email.", `auth_user_email(self)` returns the own email |
| DB-43 | `permission_codes_for_membership` returned any membership's full permission set | FIXED+VERIFIED | Round-2 caller checks; **live probe (round 6):** own membership returns the full permission list, the other gym's membership returns an empty set |
| DB-44 | SECURITY DEFINER `sync_legacy_user_membership_projection` rewrote any user's `users` row, no auth check | FIXED+VERIFIED | Round-2 redefinition (`20261115050000` + fix `20261115120000`): self OR manager/`manage_staff` of the target's gym, else raise. **Live probe (round 6):** ownerA syncing ownerB raises "Not allowed to sync this user." |
| DB-52 | RLS reset dropped every policy on 24 tables in a loop before recreating them | FIXED+VERIFIED | Round-4 `docs/MIGRATION_CONVENTIONS.md` (no policy-drop loops; additive migrations only); code check |
| DB-53 | `messages_update` allowed the receiver — not the sender — to UPDATE a message | FIXED+VERIFIED | Round-2 policy fix; suite: message writes are sender-scoped; soft-delete is sender-only and idempotent (round 5) |
| DB-54 | Staff self-edit guard on `national_id`/`is_active`/`hire_date` never fired (gated on `manages_gym()`, true for all admin-portal staff) | FIXED+VERIFIED | **Round-6 fix** (`20261115410000`): `enforce_staff_profile_gym()` now gates on `has_permission('manage_staff', gym_id)`. Suite proved the hole (default-role staff self-edited `national_id`) and proves it closed |
| DB-55 | Managers had no read access to QR gate sessions (`gate_sessions_select` owner-only) | FIXED+VERIFIED | Round-2 `revoke_gate_session` + manager read; suite: manager can list/revoke sessions |
| DB-56 | No dedup on `personal_records` (same client/exercise/moment could repeat) | FIXED+VERIFIED | Round-2 added the `value > 0` CHECK + owner-only UPDATE policies, but the audit's dedup index was never created. **Round-6 fix** (`20261115400000`): unique index `uq_personal_records_client_exercise_achieved` on `(client_id, exercise_name, achieved_at)` with a defensive ROW_NUMBER dedup first. Suite: duplicate insert rejected |
| DB-57 | `specialty_tags`/`coach_specialties` had SELECT-only policies; no write path | FIXED+VERIFIED | Round-4 seed-only specialties; round-5 per-gym tags with manager-only RPC; suite: tag writes scoped to the gym |
| DB-58 | `approved_by` FK dropped in 006, never re-added | FIXED+VERIFIED | Round-4 FK re-added (`20261115080000`, ON DELETE SET NULL); code check |
| DB-59 | Session history SELECT policy hid rows after the session was deleted | FIXED+VERIFIED | Round-4 snapshot-readable history; suite: history survives session deletion via `session_status_history.session_snapshot` |
| DB-60 | `trainw-media` bucket allowed `image/svg+xml` (stored-XSS vector) | FIXED+VERIFIED | Round-4 SVG removed from the bucket MIME allow-list (`20261115080000`); chain applies clean on fresh DB |
| DB-61 | RLS helper functions redefined 3× with different semantics; no freeze | FIXED+VERIFIED | Round-4 freeze (30 helpers + `assert_rls_helpers_frozen()`); round-5 portable hash (`pg_get_function_arguments()`, stable across clusters); suite: assert passes on a fresh cluster. Note: the DB-61 hash migration itself fails by design on a fresh apply (`20261115300000`) and is repaired by the portable fix — live apply must continue past it |
| DB-62 | `handle_new_user` swallowed all errors, so failed profile creation never failed signup | FIXED+VERIFIED | Round-4 fail-loud migration (`20261115270000`); code check |
| DB-63 | Seed picked its gym with `ORDER BY created_at LIMIT 1` (oldest gym, no tenant parameter) | FIXED+VERIFIED | Round-2: live seeds require an explicit gym id (GUC); the `LIMIT 1` text survives only in `database/archive/seed.sql` (archived, not run). Code check |
| DB-64 | `specialty_tags.name` global, `coach_specialties.gym_id` nullable with no consistency check | FIXED+VERIFIED | Round-4/5 per-gym tags (`gym_id` on `specialty_tags`, partial uniques, coach specialties scoped to the coach's gym); suite: cross-gym tag use rejected |
| FE-18 | No double-submit guards (client cancel/review, coach savePlan, pilot updateCoachApproval, deletes) | FIXED+VERIFIED | Round-4 guards (`inFlightActions`/`setBtnBusy`, 10 hits in `tw-gym-acc.js`) + Next.js `SubmitButton` pending state; code check |
| FE-24 | Invite UI did not state the account-first prerequisite (invites failed silently) | FIXED+VERIFIED | Round-4 `inviteAccountFirst` strings in all three dicts (FR/EN/AR); code check |
| FE-25 | Password resets with no explicit `emailRedirectTo` | FIXED+VERIFIED | Round-4 explicit redirect (`tw-gym-acc.js:5321`, `/tw-login.html`); code check |
| FE-26 | Chat messages with no length cap | FIXED+VERIFIED | Round-4 2,000-char caps in all three send paths (gym/client/coach); code check |
| FE-31 | `setHtml` did not escape by default | FIXED+VERIFIED | Round-2: `setHtml` escapes by default (`trainw-core.js:342`), `setHtmlUnsafe` is the explicit raw variant (6 callers); code check |
| FE-33 | Hardcoded price defaults in the frontend (see FE-16) | FIXED+VERIFIED | Same evidence as FE-16: grep for price/amount defaults returns nothing |
| GT-06 | Both edge functions returned the raw `error.message` in 500 responses | FIXED+VERIFIED | Round-1/2: ai-proxy returns generic 'AI service failed'; gate-checkin returns `{ access: false, reason: 'server_error' }`. Grep: no raw `err.message` return in any of the four functions |
| GT-07 | Token marked `used=true` before the `check_ins` insert; on a non-23505 failure the token stayed consumed with no entry recorded | FIXED+VERIFIED | Round-2: on a non-23505 insert error the handler un-consumes the token (`used=false, used_at=null`) so the member can retry with the same QR (`handler.mjs`); code check |
| NX-17 | Permissions normalised with `Boolean(value)` — the string `"false"` counted as granted | FIXED+VERIFIED | Round-4 strict `value === true` (`src/lib/permissions.ts:30,44`); single shared `normalisePermissions` used by workspace/queries. Code check. (Round 2 wrongly claimed this was already clean) |
| NX-18 | Denied users redirected to `/dashboard`, which itself requires `dashboard.view` — redirect loop | FIXED+VERIFIED | Round-4 dedicated `/forbidden` page; `requirePermission` redirects there. Route present in the production build |
| NX-19 | "Attendance today" computed on the UTC day; timestamps rendered in server timezone | FIXED+VERIFIED | Round-4 Africa/Tunis rendering (`src/lib/utils.ts`, `timeZone: "Africa/Tunis"`); code check |
| NX-20 | Unauthenticated `/api/health` disclosed whether the service-role key is configured | FIXED+VERIFIED | Round-4: returns only `configured`/`status`/`timestamp` (`src/app/api/health/route.ts`); code check |
| NX-21 | Public registration accepted `gymId` with `type: "individual"` | FIXED+VERIFIED | Round-4 zod refine: `individual` must not carry a `gymId` (`src/app/api/public/clients/route.ts:45`); code check |
| NX-22 | `request.json()` awaited with no try/catch — malformed JSON threw before zod ran | FIXED+VERIFIED | Round-4 try/catch around the parse (`route.ts:72`); code check |
| NX-23 | Dead code: browser Supabase client, role templates, helpers, a whole page | FIXED+VERIFIED | Round-4 deleted (`src/lib/browser.ts` gone); code check + build green |
| NX-24 | App could not be built, type-checked, or run: `package.json` had zero dependencies | FIXED+VERIFIED | Round-4 pinned real deps (next 15.5.29, react 19.3.1, zod 3.25.76, typescript 5.9.3, vitest 3.2.7). **Round 6 re-verified properly:** `npm install` (418 packages) + `tsc --noEmit` clean + `vitest` 33/33 + `eslint` clean + `next build` green in a scratch copy |
| NX-25 | Five server actions cast the typed Supabase client to `any` | FIXED+VERIFIED | Round-4 removed the casts. **Round-6 grep:** 2 `as any` hits remain in `src/` — one in a test file, one in a comment. tsc clean |
| NX-26 | Only verification script checked the static app; nothing tested/type-checked the Next.js app | FIXED+VERIFIED | Round-4 CI (`.github/workflows/ci.yml`) + vitest suite (7 files, 33 tests, all passing in round 6) + `typecheck`/`lint` scripts |
| NX-27 | Login page never redirected an already-authenticated user | FIXED+VERIFIED | Round-4 redirect to `/dashboard` (or `/auth/recover`) in `src/app/login/page.tsx:35`; code check. (Round 2 wrongly claimed this was already clean) |
| NX-28 | Signup is a non-atomic multi-step sequence with partial compensation | FIXED+NEEDS-LIVE-TEST | Round-4 `/auth/recover` self-healing path exists in code; the orphan-account recovery flow itself needs a live test |
| NX-29 | Client codes are short, low-entropy, format-predictable, returned to anyone who registers | FIXED+VERIFIED | Round-4: codes are display-only by design — nothing authenticates with them (`src/actions/clients.ts:102` comment; codes shown in the dashboard, never checked). Code check. The codes stay low-entropy; that is acceptable only because they are never a credential |

## What round 6 fixed (new in this round)

1. **DB-14 (HIGH)** — owner-role privilege hole: a `manage_staff` holder could directly INSERT an ACTIVE `gym_owner` membership, and `invite_gym_member` / `set_membership_role` had no owner-role guard. Fixed by `20261115360000` + `20261115370000` (commit `78a63b6`).
2. **DB-16 (HIGH)** — branding-only admin-portal users could INSERT payments (and credentials/devices). Policies now also require the per-action permission. `20261115380000` (commit `78a63b6`). **Behaviour change:** default `staff` can no longer record payments or enrol gate credentials/devices.
3. **DB-40 (MEDIUM)** — `invite_gym_member` raised "column reference invite_email is ambiguous" on EVERY call: the invite flow was completely broken. Fixed by qualifying the column. `20261115360000` (commit `78a63b6`).
4. **DB-36/DB-65 (HIGH)** — voiding a payment for a member with a NULL pre-settlement end date left the end date at the period start instead of NULL. Fixed with a sentinel. `20261115390000` (commit `78a63b6`).
5. **DB-56 (LOW)** — the dedup unique index the audit asked for was never created. `20261115400000` (commit `78a63b6`).
6. **DB-54 (LOW)** — the sensitive self-edit guard never fired (gated on `manages_gym()`). Now gates on `manage_staff`. `20261115410000` (commit `78a63b6`).
7. **NX-11 (LOW)** — security headers added to `next.config.ts` (commit `b96c892`).
8. **NX-15 (MEDIUM)** — completed: `getErrorMessage` + all 23 direct `.message` returns replaced (commit `f3152ba`).
9. **NX-07 (MEDIUM)** — open redirect via `redirectTo` closed in the schema + callback hardening, with a new vitest case (commit `bd4c441`).
10. **NX-16 (MEDIUM)** — class capacity bounds + name max lengths (commit `bd4c441`).
11. **NX-24/NX-25 (LOW)** — properly verified with real tooling (npm install + tsc + vitest 33/33 + eslint + next build), not just by reading `package.json`.

## What round 6 deliberately did NOT do

- **DB-66 / NX-03 (P2-10)** — the user's call. Not decided.
- **Void-reason `window.prompt`** (`tw-gym-acc.js:1985`) — left as is. There is no confirm-modal helper in the app (the app's convention is native `window.confirm`, used in 8 places), so replacing the prompt means building a new modal with a text input in the payments flow — not quick-and-low-risk without a DOM test harness, and the native prompt works correctly today. The reason is mandatory and is stored (`void_reason`); nothing is broken.
- **FE-12 BFF/HttpOnly sessions** — deliberate design decision from round 4 (L effort); the accepted mitigation is dashboard settings, to be verified live.
- **GT-04 offline allow-list** — needs ESP32 firmware that does not exist in this repo; turnstiles are off by user decision.
- **Push to GitHub** — local only, per the task. Parent pushes (base = remote tip `234cc893`).

## Corrections to earlier rounds' notes (found by this pass)

- Round 5's notes wrongly listed NX-24, NX-25, NX-14, NX-28, DB-51 and FE-27(e) as skipped — round 4 had done all of them; NX-14/NX-28 were "not live-verified", the rest were simply wrong.
- Round 2's notes wrongly claimed NX-17 and NX-27 were already clean — both were false and were fixed in round 4.
- Round 2's notes described NX-11 as "all dashboard pages pass context.gymId" — that is NX-04, not NX-11 (security headers). NX-11 was genuinely open until round 6.
- Round 3's "reversal restores it exactly" was false for members whose pre-settlement end date was NULL (fixed in round 6, DB-36).
- Round 4's DB-35 count (24 constraints, not the audit's 25) confirmed.

## Residual notes (not findings, but worth knowing)

- **DB-46:** a same-gym client can see other members' private profile media (holds `manage_media` by default). Same-gym only; tightening needs a product decision.
- **FE-08:** the coach-search embedded-users name filter still needs live verification.
- **GT-08:** one check-in per day remains the policy; lunch-time re-entry needs a product decision.
- **DB-66:** no-show policy still undecided (refund vs credit vs forfeit).
- **P2-10:** Next.js ship target still undecided; until then NX-02/04/05/08/09/10/14/28 cannot be live-tested against the chain DB.

---

## Exact launch blockers (nothing else is blocking)

1. **Supabase live apply** — apply the full migration chain + Phase 1 migrations to project `caylegavnekidhytlswo` via the dashboard SQL editor (his login/2FA); check first whether the DB is empty. **Continue past the by-design failures in `20261115050000` (B5) and `20261115300000` (DB-61)** — both are repaired by later migrations. Round 6 adds 6 more files (through `20261115410000`).
2. **Deploy secrets** — `trainw.member_credential_pepper` (DB GUC), `GATE_TERMINAL_PEPPER`, `TURNSTILES_ENABLED=false`, `CAPTCHA_SECRET_KEY` + `NEXT_PUBLIC_HCAPTCHA_SITE_KEY` (**CAPTCHA fails open without the secret**), `APP_ORIGINS`, redirect allowlisting for `/tw-login.html` and `/auth/reset-password`.
3. **Credential rotation (live)** — the two test accounts (`coachtestv17@gmail.com`, `clienttestv17@gmail.com`) and demo accounts (`admin@lakeclub.tn`, `reception@lakeclub.tn`) still carry the published passwords until rotated in Supabase Auth (DB-08/DB-09).
4. **Edge-function deploy + dashboard settings** — deploy `gate-checkin`, `gate-terminal-auth`, `gate-feed`, `ai-proxy`; confirm `verify_jwt` per `supabase/config.toml` in the dashboard (GT-09); apply runbook §8 settings (Realtime Authorization, refresh-token rotation ON, 1h JWT expiry — the FE-12 mitigation).
5. **P1-13 live tests** — the cross-tenant matrix on the live project: FE-06/07/08/11 scoping, DB-31 trigger/RLS interaction, FE-09 live QR scan, FE-10 terminal flow flag ON/OFF, GT-01 ai-proxy JWT + quota, GT-02 cross-device token check, GT-03 edge rate limit, NX-01/02/05/08/09/10/14/28 flows.
6. **Two user decisions** — DB-66 (no-show auto-settlement policy) and P2-10 (Next.js ship target). P2-10 gates the live verification of 9 NX findings.
7. **Accountant check** — verify the TEIF e-invoice field list before the first real invoice.
8. **Production deploy** — only on his explicit word. Nothing in this round touches production, any live service, or any external message.

---

*Written 2026-11-15 ~05:50 Tunis, round 6. Head: `bd4c441`. 137 rows, 115 FIXED+VERIFIED, 19 FIXED+NEEDS-LIVE-TEST, 2 OPEN-DECISION-NEEDED, 0 OPEN-LIVE-ONLY, 1 NOT-APPLICABLE.*
