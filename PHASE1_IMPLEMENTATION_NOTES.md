# Trainw — Phase 1 Security Fixes: Implementation Notes

Branch: `phase1-security-fixes` (local only, based on `main` @ e10932c).
Date: 2026-11-15. Audit report: `~/workspace/goals/build-trainw/files/trainw-security-audit-2026-11-14.md`.

Scope rules followed: local work only — nothing pushed to GitHub, nothing
applied to any live database, no external service contacted with credentials,
no git history rewritten. Existing migration files were never edited; all SQL
is in new timestamped migration files that sort after the latest existing
migration (`20260419000000`).

**What still needs live testing / access (P1-13, not done here):** every SQL
migration must be applied to a staging Supabase project and live-tested
against the cross-tenant matrix (self-pay attempt, role wipe, XSS payload,
ai-proxy without token / wrong gym / over quota, gate flood). The anon key
rotation, the `APP_ORIGINS` secret for ai-proxy, and the dashboard-side
Supabase Auth rate limits + CAPTCHA are pending (see P1-8 / P1-7 / P1-12).

---

## P1-1 (DB-01) — client_profiles self-update guard — DONE

Files changed:
- `supabase/migrations/20261114000000_phase1_self_update_guards.sql` (new)

What was done: BEFORE UPDATE trigger `trg_client_profiles_self_guard` +
function `trainw_guard_client_profile_self_update()`. When the row's owner
(`OLD.user_id = auth.uid()`) updates their own profile and is not a manager
of that gym (`NOT public.manages_gym(OLD.gym_id)`), any actual change
(`IS DISTINCT FROM`) to `payment_status`, `price_paid`,
`membership_start_date`, `membership_end_date` or `membership_tier` raises.
Managers editing via `manages_gym` are unaffected. Trigger functions stay
SECURITY INVOKER (default) so the `current_user IN ('postgres',
'service_role')` skip works for legitimate server-side updaters
(`bootstrap_authenticated_user`, `sync_legacy_user_membership_projection`).

Verification: careful review against the migration chain (no live DB
available). `node --check` N/A (SQL). The trigger compares OLD vs NEW, so
re-sending an unchanged value passes.
Still needs: live test in staging — client self-pay attempt must fail,
manager edit must succeed.

## P1-2 (DB-02) — coach_profiles self-update guard — DONE

Files changed:
- `supabase/migrations/20261114000000_phase1_self_update_guards.sql` (new)
- `tw-coach-acc.js` (coach's own save no longer sends pricing)
- `tw-coach-acc.html` (rate input disabled — pricing is manager-only)

What was done: BEFORE UPDATE trigger `trg_coach_profiles_self_guard`.
Self-update allow-list: `bio`, `specialty`, `specialties`,
`experience_years`, `certifications`, `instagram_url`, `whatsapp_number`.
Blocked on actual change: `user_id`, `gym_id`, `approval_status`, `rating`,
`total_reviews`, `sessions_completed`, `hourly_rate`, `price_per_session`,
`approved_at`, `approved_by`, `is_active`. The coach's own save
(`saveCoachProfile`) previously sent `price_per_session: rate`, which the new
trigger would reject — the field, the `rate` variable and its validation were
removed from the self-save payload, and the "Rate / session (DT)" input is
now `disabled` with the label "set by the gym". The users-row part of the
coach save (name/phone/language) is unchanged and allow-listed by P1-3.
Verified the client's own save (`tw-client-acc.js` `saveProfile`) only
updates `users` (name/phone/language) — no conflict with P1-1.

Verification: `node --check tw-coach-acc.js` — OK. Grep: no
`price_per_session` left in the coach save path.
Still needs: live test — coach changing their own rate must fail, manager
setting pricing must succeed.

## P1-3 (DB-05, DB-06) — users self-update guard + gyms_update policy — DONE

Files changed:
- `supabase/migrations/20261114000000_phase1_self_update_guards.sql` (new)

What was done: BEFORE UPDATE trigger `trg_users_self_guard`. Self-update
allow-list: `name`, `phone`, `avatar_url`, `language_preference`. Blocked on
actual change: `email`, `role`, `gym_id`, `is_active`, `is_managed`,
`default_gym_id`, `default_membership_id`, `last_seen_at`, `created_at`.
`gyms_update` policy restored to the 004 form
`USING/WITH CHECK (public.manages_gym(id))`.
Residual noted (out of scope, pre-existing): `bootstrap_authenticated_user`
re-activates a banned user on login (sets `is_active=true` as function
owner, so the guard does not stop it).

Verification: careful review (no live DB). `refresh_reviews_after_write`
(SECURITY INVOKER) updates coach_profiles as the reviewer, not the coach,
so the coach guard does not block it.
Still needs: live test — self role/gym change must fail, own name/phone
change must succeed.

## P1-4 (DB-03, DB-04) — lock down role-management functions — DONE

Files changed:
- `supabase/migrations/20261114010000_phase1_revoke_role_functions.sql` (new)

What was done: `REVOKE ALL ON FUNCTION ensure_role_permission_codes(uuid,
text[]) FROM PUBLIC` and `FROM authenticated`; removed the `authenticated`
grant on `ensure_gym_default_roles`. Both functions were replaced with
versions that add an authorisation check first: allowed when `auth.uid() IS
NULL` (migration/owner context), when the caller is the gym's manager, or
when the caller holds `manage_roles` for that gym. Bodies are otherwise
verbatim (007 for `ensure_role_permission_codes`, 012 for
`ensure_gym_default_roles` — the 012 body carries the expanded permission
sets incl. `view_staff_profiles`, `edit_staff_profiles`,
`manage_access_control`, `view_access_logs`).

Verification: careful review. Verified `save_role_definition` IS SECURITY
DEFINER, so the REVOKE does not break its internal call; verified
`ensure_gym_default_roles` is called by bootstrap only after the gym INSERT
sets `manager_id = auth.uid()`, so the manager branch of the check passes.
Still needs: live test — unauthenticated/authenticated direct call must
fail, manager-driven role creation must succeed.

## P1-5 (FE-01, FE-02, FE-03) — escape names/phones/goals, remove inline onclick — DONE

Files changed:
- `tw-gym-acc.js`
- `tw-coach-acc.js` + `tw-coach-acc.html` (coach save, see P1-2)

What was done: every raw `innerHTML` sink for client/coach/session data now
goes through `Trainw.escapeHtml()` — dashboard top-coach cards and recent
sessions (~1903, ~1909), `renderSchedule` (~1985), `openSessionDetail`
(~2350), coach carousel (~2660, incl. avatar initials), `renderClients`
(~2923). All inline `onclick="...('...')"` handlers in the file were
removed and replaced with `data-*` attributes (`data-coach-modal`,
`data-book-coach`, `data-session-detail`, `data-session-edit`,
`data-session-delete`, `data-client-msg`, `data-client-edit`,
`data-client-del`, `data-conversation`) plus ONE delegated document click
listener in `bindUi()` (guarded by `__trainwGymUiBound`). Handler checks
the most-specific action first; clicks inside `.sc-actions` that hit no
button do nothing (preserving the old inline `event.stopPropagation()`
behaviour); session-edit/delete close `#session-detail-modal` first (matching
old inline behaviour). `openBookSessionForCoach` simplified to one parameter
(`coachName` was unused); `openMessageModal` takes only `clientId`.
Extra sinks found by sweeping beyond the cited lines and fixed the same
way: three unescaped `<option>` builders (coach select ~2477, client selects
~3393/~3398) and the carousel avatar initials (~2666). `SESSION_CATEGORIES`
options (~738) left as-is — hardcoded constants, not user data.
`renderConversation` (chat) was already escaping message content and
initials. `tw-client-acc.js` render sites (`renderDashboardActivity`,
`renderProgram`) already escape at the render site; `gate-terminal.js`
uses `setText` (textContent). No inline onclick handlers exist in
`tw-client-acc.js`, `tw-coach-acc.js`, `gate-terminal.js` or `index.js`.

Verification: `node --check tw-gym-acc.js` — OK; `node --check
tw-coach-acc.js` — OK. Grep: zero `onclick=` attributes left in
`tw-gym-acc.js` (one remaining match is a code comment describing the
removal); zero unescaped `${c.name}` / `${...name}` sinks in `innerHTML`
templates across all four JS files (remaining matches are escaped at the
interpolation or at assignment, `textContent` uses, numbers, or UUIDs).
Mistake caught during the work: the delegated handler was first inserted
at the wrong `syncPermissionVisibility();` occurrence (inside a roles-render
function, would have added duplicate listeners on every render); removed
and re-inserted into `bindUi()` only.
Still needs: live test — stored-XSS payload in a display name must render
as inert text everywhere, and every card/button must still work via the
delegated listener.

## P1-6 (FE-13, FE-14) — CSP + HSTS, pinned CDN versions + SRI — DONE

Files changed:
- `vercel.json` (CSP, HSTS, Permissions-Policy headers)
- `dev-server.js` (same headers mirrored for local dev)
- `env-config.js` (generates `dist/trainw-config.js`; verification updated)
- `trainw-config.js` (new — placeholder-only committed copy)
- `gate-terminal.html`, `tw-gym-acc.html`, `tw-coach-acc.html`,
  `tw-client-acc.html`, `tw-login.html`, `tw-role.html` (pinned CDN
  scripts + SRI; inline config script replaced by `<script
  src="trainw-config.js">`)

What was done:
- **CSP (no `unsafe-inline`, no `unsafe-eval`):** `default-src 'self';
  script-src 'self' https://cdn.jsdelivr.net https://unpkg.com
  https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline'
  https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com;
  img-src 'self' data: blob: https:; media-src 'self' blob:; connect-src
  'self' https://*.supabase.co wss://*.supabase.co; frame-src 'none';
  object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors
  'none'`. `style-src` keeps `'unsafe-inline'` because the pages use inline
  `style="..."` attributes (66 in `tw-gym-acc.html`). HSTS:
  `max-age=31536000; includeSubDomains`. Permissions-Policy:
  `camera=(self), microphone=(), geolocation=()` — camera stays `(self)`
  because the gate terminal needs it for QR scanning.
- **Why the config moved out of the HTML:** every page carried an inline
  `<script>window.__TRAINW_URL__ / __TRAINW_KEY__ = ...</script>` block,
  which a strict CSP would block and break the whole app. The config now
  lives in external `trainw-config.js`: `env-config.js` writes it into
  `dist/` at build time (and verifies it exists with real values and that
  no page still carries an inline config script), `dev-server.js` serves it
  dynamically from the discovered config, and the committed root copy holds
  only `%%...%%` placeholders. The audit's FE-13 fix as written ("add a
  CSP header, no unsafe-inline") could not be applied without this move —
  a CSP with `'unsafe-inline'` retained would have left the XSS safety net
  toothless. Verified no `eval(`/`new Function`/string `setTimeout` exists
  in repo JS or in any pinned CDN bundle, and no dynamic script injection
  — so dropping `unsafe-eval` is safe. `html5-qrcode` uses no Web Worker.
- **Pinned versions + SRI (hashes computed from the exact bytes served by
  the exact pinned URL — never invented):**
  - `@supabase/supabase-js@2.119.0/dist/umd/supabase.min.js` —
    `sha384-gnyZit14c5lnGcarmA166QQjjJXpucw25ogZXuwH3HxxY904zHkBqmxVpelsPorb`
    (6 pages)
  - `lucide@1.73.0/dist/umd/lucide.min.js` —
    `sha384-DdDSdhkTpRzHOpRXj0iG8b2rBu5xPWN5SFqnCEZ0YKb/Yh1Ymmc9PVsYEZZOq40r`
    (3 pages)
  - `chart.js@4.6.1/dist/chart.umd.min.js` —
    `sha384-Emf5ZVIUiarAdhkgtqK+5/Z5qIvM6QoVrS+qAVtfyZVuD5lIHrac0me485+Antp0`
    (3 pages)
  - `html5-qrcode@2.3.8/html5-qrcode.min.js` —
    `sha384-c9d8RFSL+u3exBOJ4Yp3HUJXS4znl9f+z66d1y54ig+ea249SpqR+w1wyvXz/lk+`
    (gate-terminal)
  - `qrcodejs@1.0.0` (cdnjs, already pinned) —
    `sha384-3zSEDfvllQohrq0PHL1fOXJuC/jSOO34H46t6UQfobFOmxE5BpjjaIJY5F2/bMnU`
    (tw-client-acc)
  - All SRI tags carry `crossorigin="anonymous"`. Versions are the
    jsdelivr `latest` tags as of 2026-11-15. Gotcha found while pinning:
    jsdelivr's bare package URLs serve the *minified* default file, not
    `dist/...js` — the explicit minified paths were verified byte-identical
    to what the bare URLs serve today. Regenerate a hash with:
    `curl -sL -o f.js <pinned-url> && openssl dgst -sha384 -binary f.js |
    openssl base64 -A` (if a CDN ever changes served bytes, the script
    fails closed and the hash must be regenerated).
  - `index.html` has no CDN scripts and no config block — untouched.
  - Lucide was missing from the first CDN inventory grep (pattern quirk);
    found by a second grep: `unpkg.com/lucide@latest` on line 16 of the
    three account pages — pinned like the rest.

Verification: `node --check env-config.js`, `dev-server.js`,
`trainw-config.js` — all OK; `vercel.json` parses as valid JSON; CSP
string verified byte-identical between `vercel.json` and `dev-server.js`;
grep: zero unpinned CDN URLs, zero inline `<script>` blocks, zero
`unsafe-inline`/`unsafe-eval` in `script-src` across root HTML.
Still needs: live test — load every page in a browser and confirm no CSP
violations in the console (especially the gate terminal camera + QR scan,
charts, and the config bootstrap on all six pages).

## P1-7 (GT-01) — authenticate ai-proxy — DONE

Files changed:
- `supabase/functions/ai-proxy/index.ts` (rewritten)
- `supabase/migrations/20261114030000_phase1_ai_proxy_quota.sql` (new)

What was done: the function was callable by anyone, with wildcard CORS,
no quota and raw error messages. Now:
1. **Auth:** requires `Authorization: Bearer <user JWT>`; creates a
   Supabase client with the anon key + the caller's JWT and verifies it
   with `supabase.auth.getUser()` — 401 otherwise. The frontend
   (`trainw-core.js` `callEdge`) already sends the Bearer token when a
   session exists, so no frontend change is needed for auth.
2. **Gym membership:** `payload.gymId` is required (400 if missing/invalid
   UUID) and the caller must belong to that gym — via `users.gym_id` /
   `users.default_gym_id`, a `user_permissions` row, or `manages_gym(gymId)`
   — else 403. Note: **nothing in the repo currently calls `callEdge`**
   (no `session_notes`/`diet_plan` invocation exists), so the function has
   no live callers to break; the first caller must send `gymId` in the
   payload.
3. **Quota:** 50 calls/user/day, enforced atomically by the new SECURITY
   DEFINER function `trainw_ai_proxy_consume_quota(p_limit)` (derives the
   caller from `auth.uid()`, never from a caller-supplied id; counter only
   increments while under the limit; `ai_proxy_usage` table has RLS enabled
   with no policies, so only the function touches it). Over-quota returns
   429.
4. **CORS:** allowlist only. `APP_ORIGINS` env secret (comma-separated)
   plus `http://localhost:3000` / `http://127.0.0.1:3000` for local dev.
   Any other Origin gets no `Access-Control-Allow-Origin` (fail closed).
   **The production domain is not recorded anywhere in the repo, so
   `APP_ORIGINS` must be set at deploy time** (Supabase dashboard >
   Edge Functions > ai-proxy > Secrets), e.g. the Vercel URL — otherwise
   production browsers cannot read responses. `Vary: Origin` is set.
5. **Errors:** upstream Anthropic failures return a generic 502, all
   catch-alls return generic messages; real errors go to `console.error`
   only. Prompt inputs are capped in length (`asText`, max 120–2000 chars)
   and numeric fields are type-checked. Pinned imports: Deno std 0.168.0
   (unchanged), `@supabase/supabase-js@2.119.0` via esm.sh.

Verification: `tsc --noEmit --skipLibCheck` (via npx, no local Deno) —
zero syntax errors; the only errors are TS2307/TS2304 for the Deno URL
imports and the `Deno` global, which are expected outside Deno. Grep: no
`err.message` returned (one remaining match is a comment), no CORS `*`.
Still needs: apply the quota migration, deploy the function, set
`APP_ORIGINS` + confirm `ANTHROPIC_API_KEY` secrets, live test — no token
→ 401, wrong gym → 403, 51st call in a day → 429, wrong origin → no CORS
headers.

## P1-8 (DB-08, DB-09, FE-05) — remove hardcoded secrets from files — DONE (file edits only)

Files changed:
- `supabase/seeds/trainw_test_accounts.sql`
- `supabase/seeds/trainw_demo_seed.sql`
- `supabase/migrations/V17_DEPLOYMENT_STEPS.md`
- `gate-terminal.html` (hardcoded anon key removed as part of P1-6)

What was done: the seed's hardcoded password (`crypt('Hamdi2463', ...)`,
shared by the coach + client test accounts) is gone — the script now reads
the password from the session setting `trainw.seed_password` and raises a
clear error if it is not set (`SET trainw.seed_password = '<strong random
password>';`). The deployment doc's demo passwords (`LakeClub2026!` for
`admin@lakeclub.tn` and `reception@lakeclub.tn`) are replaced with
"set in Dashboard — strong, unique" placeholders; the same password in a
comment in `trainw_demo_seed.sql` was removed the same way. The hardcoded
anon key in `gate-terminal.html` was removed when its inline config block
was replaced by `trainw-config.js` (P1-6). The doc's stale risk line
("Anon key still in env-config.js — intentional") was corrected: the key is
injected at build time from the environment and must never appear in a
committed file.

Verification: grep — zero occurrences of `Hamdi2463` / `LakeClub2026!` and
zero occurrences of the anon JWT in any root file (excluding `dist/` and
`.git`). Note: the key/password strings still exist in git history — that
cannot be fixed without rewriting history, which is out of scope.
**Still needs (pending, needs Supabase access — NOT done): rotate the
exposed anon key and the two test-account passwords** (`coachtestv17@`,
`clienttestv17@`, `admin@lakeclub.tn`, `reception@lakeclub.tn`). Rotating
the anon key invalidates the old one everywhere it was copied; after
rotation, update the build/deploy secrets (Vercel env / `.env`) and
re-run the build. The exposed key is currently still the one injected by
the build (see P1-9).

## P1-9 (FE-22) — rebuild dist/, untrack it — DONE

Files changed:
- `dist/` rebuilt (now untracked; files remain on disk)

What was done: ran `node env-config.js` — build succeeded, sourcing the
config from the stale `dist/tw-coach-acc.html` fallback (no `.env` with
real values exists; `.env.example` is empty). Verified all 6 previously
missing files now exist in `dist/`: `trainw-tenant-utils.js`,
`trainw-v17.css`, `tw-gym-acc-v17.js`, `tw-gym-acc-v17.css`,
`tw-client-acc-v17.css`, `tw-coach-acc-v17.css`. Verified every local
asset referenced by the `dist/` HTML files exists in `dist/`. The build now
also generates `dist/trainw-config.js` (real values, no placeholders) and
all `dist/` HTML pages reference it — no inline config scripts and no
placeholders remain in `dist/`. The exposed anon key now appears in
`dist/` only inside `dist/trainw-config.js` (build output). `git rm
--cached -r dist` removed `dist/` from git tracking on this branch;
`.gitignore` already lists `dist`, confirmed via `git check-ignore`.

Verification: build exit 0, "generated dist with injected Supabase
configuration from tw-coach-acc.html"; file-existence checks above all
pass.
Still needs: deploy from a fresh build after the anon key rotation (P1-8);
confirm the Vercel build passes with the new `trainw-config.js` flow.

## P1-10 (DB-16, DB-15) — manages_gym + self-targeted permission writes — DONE

Files changed:
- `supabase/migrations/20261114020000_phase1_manages_gym_self_grant.sql` (new)

What was done: `manages_gym` recreated without `manage_branding` (now
admin portal OR `manage_staff` only); `user_permissions_manage_v17` policy
recreated with `user_id <> auth.uid()` in USING and WITH CHECK, forbidding
self-targeted `user_permissions` writes. Verified by grep that no app code
or RPC writes `user_permissions` rows for the caller themselves.

Verification: careful review (no live DB).
Still needs: live test — self-grant attempt must fail, manager granting a
role to someone else must succeed.

## P1-11 (schema decision) — DONE (2026-11-15, round 3; commit cf994d1)

Decision (per audit recommendation, under the standing grind instruction):
**the migration chain is the authoritative schema.** `database/schema.sql`
and `database/seed.sql` were moved (not deleted) to `database/archive/`
with a README explaining why (DB-33/NX-03 divergence) and what still
depends on it: the Next.js app in `src/` does not work against a
migration-chain-only DB until its data model is migrated (P2-10, open).
See `database/archive/README.md` for the full dependency list.

## P1-12 (GT-03, NX-01, FE-25 — code parts only) — DONE (code); dashboard parts pending

Files changed:
- `supabase/functions/gate-checkin/handler.mjs`
- `supabase/functions/gate-checkin/index.ts` (supabase-js import pinned to
  2.119.0 for consistency)
- `supabase/migrations/20261114040000_phase1_gate_rate_limits.sql` (new)

What was done: per-IP (60/min) + per-device (30/min) rate limiting,
enforced **before** any token/credential lookup so a flood cannot hammer
the database or probe token validity. Counters live in
`public.gate_rate_limits` and are consumed atomically by the new SECURITY
DEFINER function `trainw_gate_rate_limit_consume(p_bucket_key, p_limit)`
(fixed calendar-minute windows; counter only increments while under the
limit; RLS enabled with no policies; executable only by `service_role`).
Client IP comes from `x-forwarded-for` (first entry), `cf-connecting-ip`,
or `x-real-ip`, capped at 45 chars, falling back to the shared `unknown`
bucket. A limited request returns 429 `{ access: false, reason:
'rate_limited', limited_by: 'ip' | 'device' }` with `Retry-After: 60`,
and is deliberately NOT written to `gate_access_log` (that would let an
attacker flood the log table). If the limiter itself errors, the handler
fails OPEN with a `console.warn` — the gate must keep letting members in;
the token is 96-bit, single-use and short-lived, so the limiter is
defence-in-depth, not the sole brute-force control. The check applies to
both the QR path and the rfid/fingerprint/face path (it sits before the
branch split); OPTIONS preflights and non-POST methods are not limited.
Housekeeping: each bucket key keeps at most one row (stale windows for the
same key are deleted by the function); purge rows for dead keys
occasionally (`DELETE FROM public.gate_rate_limits WHERE window_start <
now() - interval '1 day'`).
**Pending (needs dashboard access — NOT done):** Supabase Auth dashboard
rate limits + CAPTCHA for the login/signup endpoints.

Verification: `node --check handler.mjs` — OK. A local smoke test of the
handler with a mocked admin client (`/tmp/gate-rate-limit-test.mjs`, not
committed) — 11/11 pass: allowed request reaches the credential check with
both buckets consumed (`ip:<ip>` @ 60, `device:<id>` @ 30); IP-exhausted →
429 `limited_by: ip` + `Retry-After: 60` with no credential RPC called;
device-exhausted → 429 `limited_by: device`; limiter error → fail open;
no `device_id` → only the IP bucket consumed; multi-value
`x-forwarded-for` uses the first IP. (One test initially failed because
the test's own mock was inverted, not the handler — fixed and re-run
green.)
Still needs: apply the migration, deploy the function, live test — flood
from one IP/device must 429 while a normal terminal keeps working.

## P1-13 (live tests) — SKIPPED (needs staging + Supabase access)

No live database was available. All SQL was verified by careful review
only, and every JS/TS file by syntax check. The live-test list per step is
recorded above under "Still needs".

---

## Audit-report mismatches (fix did not match the code as found)

1. **P1-6 / FE-13:** the audit's "add a CSP header (no unsafe-inline)"
   could not be applied as a header-only change — every page carries the
   Supabase config in an inline `<script>` block, which a strict CSP
   blocks. Fixed by moving the config to external `trainw-config.js`
   (build-generated + dev-server-served) instead of keeping
   `'unsafe-inline'`.
2. **P1-6 / FE-14:** the audit lists `lucide@latest` among the CDN pins,
   but the first CDN inventory grep missed it (pattern quirk) — it exists
   on line 16 of the three account pages and is now pinned to 1.73.0 with
   SRI like the rest.
3. **P1-7 / GT-01:** the audit assumes the ai-proxy has callers sending a
   gym in the payload. In fact nothing in the repo calls `callEdge` yet,
   so `gymId` is a new required contract for the first caller, not a
   check on existing traffic.
4. **P1-8:** the "both demo passwords" are one shared password
   (`Hamdi2463`) in the seed plus `LakeClub2026!` in the deployment doc
   and in a comment in `trainw_demo_seed.sql` (three spots, two distinct
   strings) — all removed. `V17_DEPLOYMENT_STEPS.md` lives in
   `supabase/migrations/`, not at the repo root as the report's path
   suggested.
5. **P1-9:** `node env-config.js` only succeeded via its fallback that
   scrapes the config from the stale `dist/tw-coach-acc.html` — there is
   no `.env` with real values and no env vars set in this environment.
   After the anon-key rotation the build will need the new key in the
   environment (or a fresh `dist/`), because the fallback source will be
   stale.
6. **P1-5 (extra):** beyond the six cited lines, the same stored-XSS
   class existed in three `<option>` builders (coach/client selects) and
   in the carousel avatar initials — fixed in the same pass.

---

# Round 2 — broadening (Phase 1b), 2026-11-15

User instruction 2026-11-15 00:24: "Broaden your targets... cover as many
issues to fix in phase 1 as you can." Same branch `phase1-security-fixes`,
same rules: local only, no push, no live DB, no credentialed external
calls, never edit existing migrations, one commit per finding group.
18 commits on top of 9d1cf21 (ba3799a … 84f3009). The payments ledger
(FE-19 / DB-36 core) stays OUT — approved as the next build after this
round lands. Also out: freeze + renewal (P2-3), Next.js app decision
(P2-10), privacy basics (P2-9), backups/monitoring/staging (P2-7), P1-11
schema decision, P1-13 live tests.

## Turnstile flag (user requirement, folded in 2026-11-15 00:28)

Turnstiles are NOT needed for now. All turnstile/gate structure stays in
the code, deactivated behind ONE flag, default OFF:

- **Flag name:** `TURNSTILES_ENABLED`
- **Files:** `trainw-config.js` (`window.__TRAINW_TURNSTILES_ENABLED__ =
  false;`) and `env-config.js` (reads the `TURNSTILES_ENABLED` env var —
  only the literal string `'true'` enables it — and writes it into
  `dist/trainw-config.js`). Runtime read: `Trainw.TURNSTILES_ENABLED`
  (`trainw-core.js`, from `window.__TRAINW_TURNSTILES_ENABLED__ === true`).
  Edge functions read it from their own env (`Deno.env.get("TURNSTILES_ENABLED")`).
- **Behaviour while off:** gate-checkin and gate-terminal-auth return 503
  `turnstiles_disabled` before doing anything (no check-in processed);
  `gate-terminal.html` shows a `#terminal-disabled` screen and never
  starts the scanner, realtime, or PIN prompt; the dashboard hides the
  credentials / journal / terminal check-in tabs and forces the tab to
  'live' (`renderCheckInTabs` / `setCheckInTab` in `tw-gym-acc.js`).
- **To re-enable later:** set `TURNSTILES_ENABLED=true` in the deploy
  environment (Vercel / Supabase edge secrets) AND in the build env so
  `env-config.js` writes `true` into `dist/trainw-config.js`, then
  redeploy both the static frontend and the edge functions. No code change
  needed. Verify afterwards: terminal PIN set → session token issued →
  QR check-in returns `checked_in`.
- Nothing turnstile-related was deleted: no tables, RPCs, migrations, or
  the gate-checkin function. The gate fixes in scope (DB-22, DB-25, FE-04)
  still apply — they live in the code behind the flag.

## B1 — ba3799a — member credential hashing + gate validation (DB-07, DB-22, DB-23, DB-24, DB-25, DB-47)

- File: `supabase/migrations/20261115010000_phase1b_member_credentials_hash.sql`
- DB-07: credentials are now stored as `hex(HMAC-SHA256(credential_data,
  pepper))` in new column `credential_hash`; pepper from DB GUC
  `trainw.member_credential_pepper`, set via `ALTER DATABASE postgres SET
  trainw.member_credential_pepper = '<random 32+ byte hex>'` (deploy-time
  secret, never committed — set it in the Supabase dashboard SQL editor or
  `ALTER DATABASE` at deploy). The hash function FAILS CLOSED (raises) when
  the pepper is unset. A BEFORE INSERT/UPDATE trigger hashes any plaintext
  in `credential_data` then clears it; `credential_data` is now nullable
  write-only intake. Added `credential_ref` (first 4 chars + '...') for
  display. Unique index moved from the raw value to `(gym_id, type,
  credential_hash)` partial (WHERE hash IS NOT NULL). Operator backfill fn
  `trainw_backfill_member_credential_hashes()` (SECURITY DEFINER, NOT
  granted to authenticated — run once as project owner after setting the
  pepper). Pepper rotation invalidates all hashes (re-enrolment required).
  Pre-existing unhashed rows fail closed at the gate until backfilled.
- DB-22: `validate_member_credential` rewritten — hash compare, profile
  join filtered `cp.gym_id = p_gym_id`, no profile for this gym →
  `membership_inactive`; old `payment_unpaid` reason retired (trial/waived
  are active under the shared rule); advisory-lock key uses the hash.
- DB-23: shared fn `membership_is_active_for_access(p_client_id,
  p_gym_id, p_reference_date)` — active when paid/trial/waived OR
  price_paid > 0 and not cancelled/refunded/overdue; **NULL
  membership_start_date = no lower bound** (behaviour change from the old
  gate code, which treated NULL start as inactive); end_date >= reference;
  `client_membership_is_active` now delegates (true when active in ANY
  gym, signature unchanged); `client_profiles.membership_start_date`
  default set to CURRENT_DATE.
- DB-24: 15-min anti-tailgating check first returning `already_inside`,
  then same-day check returning `duplicate_checkin_today` (graceful logged
  denial, not a raw unique-index error); last_used_at update matches by hash.
- DB-25: new service-role-only RPC `validate_gate_session(p_token)`
  (atomic check-and-consume). The gate-checkin handler KEEPS its inline QR
  flow for now (membership must be checked BEFORE consuming the token).
- DB-47: truncate now returns `'****'` for ≤4 chars, else first 4 + `'...'`.
- Verification: SQL review only (no live DB). Needs live: set the pepper,
  run the backfill, enrol a test credential, verify the gate accepts the
  hash and rejects a wrong-gym profile.

## B2 — daab4e7 — signup + bootstrap (DB-10, DB-11)

- File: `supabase/migrations/20261115020000_phase1b_signup_bootstrap.sql`
- DB-10: `handle_new_user` ignores metadata role/gym_id entirely — every
  signup is role='client', gym_id NULL, client profile only; no gym
  creation, no coach auto-creation. ON CONFLICT upsert preserves an
  existing role/gym. Exception handler kept as-is (loud failure is DB-62,
  M effort, deferred).
- DB-11: bootstrap ignores metadata gym_id; adopts ONLY a gym with
  `manager_id = auth.uid()`; post-insert fallback only by manager_id; **ON
  CONFLICT no longer forces `is_active = true`** (banned users stay
  banned); coach profiles created by bootstrap are always
  `approval_status='pending'`. Verified: the vanilla frontend calls
  bootstrap only via `trainw-core.js` `ensureProfile` (repair path when
  the profile is missing), passing `p_role` from the role-selection UI —
  owner onboarding (create NEW gym for a self-declared owner) still works;
  only ADOPTION of existing gyms is blocked.
- Verification: SQL review only. Needs live: sign up a fresh user, confirm
  role=client + gym NULL; attempt a metadata-injected owner signup,
  confirm it is ignored.

## B3 — bfd0415 — roles + memberships (DB-12, DB-13, DB-14, DB-40)

- File: `supabase/migrations/20261115030000_phase1b_roles_memberships.sql`
- DB-12: `set_membership_role` adds a role-belongs-to-gym check + a
  self-grant forbid (target = caller raises).
- DB-13: `save_role_definition` refuses edits where `is_system = true`.
- DB-14: `gym_memberships_manage_v17` FOR ALL replaced by split
  INSERT/UPDATE policies (manage_staff + role belongs to gym + target ≠
  caller + status allow-list) and **NO DELETE policy** (revoke RPC only);
  `invite_gym_member` forbids self-invite (invite email = caller's email
  raises). Only direct frontend write to gym_memberships in the whole app
  is submitNewClient's INSERT (verified by grep) — it passes all checks.
- DB-40: `gym_memberships.invite_expires_at` added (now()+7 days on
  invite/re-invite); accept enforces it (**NULL expiry on pre-existing rows
  is grandfathered**); re-invite of an ACTIVE member is a no-op returning
  the existing membership/token.
- Verification: SQL review only. Needs live: attempt a cross-gym role
  grant, a system-role edit, a self-grant, and an expired-invite accept —
  all must fail.

## B4 — 9c0547d — payments (DB-17, DB-18, DB-19)

- File: `supabase/migrations/20261115040000_phase1b_payments.sql`
- DB-17: partial unique indexes `(gym_id, provider, provider_reference)`
  and `(gym_id, invoice_reference)` WHERE ref IS NOT NULL. **Fails if
  duplicates already exist — staging dedupe needed first.**
- DB-18: `prepare_payment_write` always verifies the client via SECURITY
  DEFINER helper `payment_client_belongs_to_gym` (client required,
  role='client', belongs to the gym via a client_profiles row OR legacy
  `users.gym_id` — the users.gym_id leg keeps manager-created clients
  working before the backfill).
- DB-19: `payments_delete` policy dropped (no DELETE policy);
  `payment_events.payment_id` FK changed to ON DELETE RESTRICT (constraint
  name looked up dynamically).
- Verification: SQL review only. Needs live: dedupe check on staging
  first, then apply; attempt a payment delete (must fail) and a payment
  for a client of another gym (must fail).

## B5 — 69a4c5a — directories + RPC caller checks (DB-20, DB-21, DB-42, DB-43, DB-44, DB-55)

- File: `supabase/migrations/20261115050000_phase1b_directories.sql`
- Helpers `caller_manages_gym_direct(p_gym_id)` (gyms.manager_id OR
  admin-portal membership) and `caller_holds_permission_in_gym(code,
  gym_id)` (raw-table, deny-aware) — **these use ONLY raw-table lookups,
  never manages_gym/has_permission/get_my_permissions, because
  `current_membership()` calls `permission_codes_for_membership()` for the
  caller's own memberships, so a manages_gym call inside it would recurse
  infinitely.**
- DB-42/43/44: REVOKE PUBLIC + GRANT authenticated on `auth_user_email`,
  `permission_codes_for_membership`,
  `sync_legacy_user_membership_projection`, each with a caller check (own
  id, or manager/viewer of the target's gym). Two corrections applied
  during writing: the permission-codes tail kept verbatim from 007 (role
  UNION allow, minus deny — **a deny wins over both**); the sync body kept
  verbatim from 007 (`role = COALESCE(v_membership.role_code, role)` — raw
  role_code, NOT map_legacy_role_code; no early return on no membership).
  All `auth_user_email` callers pass `auth.uid()` (verified by grep).
- DB-20: `get_staff_directory` drops `invite_token` + `national_id` (both
  RETURNS TABLE and SELECT); new `get_staff_directory_sensitive(p_gym_id)`
  requires manage_staff and writes one row per call to the new
  `admin_audit_log` table (RLS, managers can SELECT their gym's rows); no
  frontend caller exists yet.
- DB-21: `list_gym_member_directory` gated to
  `caller_manages_gym_direct OR
  caller_holds_permission_in_gym('view_clients',...)` (staff/coach/admin
  hold view_clients; plain clients do not).
- DB-55: `gate_sessions_select` adds a `manages_gym(gym_id)` branch; new
  manager-only RPC `revoke_gate_session(p_session_id)` (used=true).
- Verification: SQL review only. Needs live: call get_staff_directory as a
  plain client (must fail / return no sensitive fields); call the sensitive
  variant and confirm an audit row lands.

## B6 — 42bbb91 — gate terminal DB side (FE-04)

- File: `supabase/migrations/20261115060000_phase1b_gate_terminal.sql`
- `gyms.gate_terminal_pin_hash` added (HMAC-SHA256 of the PIN under the
  `GATE_TERMINAL_PEPPER` edge secret, computed by the edge function, never
  the browser; NULL = no PIN = terminal disabled); `gate_terminal_sessions`
  table (id, gym_id, device_id, token_hash, expires_at, created_at,
  last_seen_at), RLS enabled with **NO policies** (service_role only).
  Verified: `gate_terminal_pin_hash` did not exist anywhere before (grep).
- Verification: SQL review only. Needs live: set a PIN via the edge
  function, confirm the hash lands and no plaintext PIN exists anywhere.

## B7 — 8e72725 — trigger functions SECURITY DEFINER (DB-31)

- File: `supabase/migrations/20261115070000_phase1b_trigger_definer.sql`
- The 5 trigger fns (`sync_session_enrollment_counts`,
  `sync_session_after_write`, `refresh_reviews_after_write`,
  `log_payment_event`, `log_session_status_event`) recreated SECURITY
  DEFINER + SET search_path = public, bodies verbatim from 003 (full
  `log_session_status_event` tail read: ROW comparison, v_event_type,
  final INSERT, RETURN NEW). `auth.uid()` inside them still returns the
  caller's id (JWT), so audit attribution is unchanged.
  `prepare_*`/`validate_*` only mutate NEW — unchanged.
- Verification: SQL review only. **Live confirmation still needed** (the
  audit marked this SUSPECTED): after applying, insert a session/payment
  as a low-privilege role and confirm the triggers fire without RLS errors.

## B8 — c46b425 — policies, indexes, constraints, backfill (DB-26, DB-29, DB-30, DB-32, DB-34, DB-39, DB-53, DB-54, DB-56, DB-58, DB-60)

- File: `supabase/migrations/20261115080000_phase1b_roles_seed_policies.sql`
- DB-32: `users_role_check` widened to include 'gym_admin' and 'staff'.
- DB-34: new `ensure_role_permission_codes_missing()` (INSERT-only, ON
  CONFLICT DO NOTHING; internal-only, revoked from PUBLIC + authenticated
  like its sibling); `ensure_gym_default_roles` now ON CONFLICT DO NOTHING
  for roles + uses the _missing variant; `ensure_role_permission_codes`
  unchanged (explicit admin replace for save_role_definition).
- DB-29: gym_profiles self branch now requires
  `user_has_membership(gym_id)` (NULL gym_id stays owner-editable).
- DB-30: messages BEFORE UPDATE trigger freezes everything except is_read.
- DB-53: messages BEFORE INSERT trigger `enforce_message_gym()` (SECURITY
  DEFINER) requires gym_id + sender AND receiver belong to that gym
  (active/accepted membership or manager).
- DB-54: staff_profiles trigger forbids gym_id/user_id changes; self-edits
  (non-manager) may not change national_id/is_active/hire_date.
- DB-56: personal_records value > 0 CHECK (NOT VALID — validate on
  staging) + owner-only UPDATE policies + gym-membership requirement on
  INSERT/UPDATE for both personal_records and milestone_photos.
- DB-58: `coach_profiles.approved_by` FK re-added ON DELETE SET NULL NOT
  VALID.
- DB-60: trainw-media bucket MIME list now only image/png, image/jpeg,
  image/webp (no SVG).
- DB-39: the 7 indexes (milestone_photos(client_id, created_at DESC),
  workout_plans(gym_id, updated_at DESC), workout_logs(gym_id,
  completed_at DESC), client_goals(gym_id, created_at DESC),
  staff_profiles(membership_id), sessions(client_id, session_date),
  users(default_gym_id)).
- DB-26: check_ins BEFORE INSERT trigger requires
  `membership_is_active_for_access` for non-service_role inserts
  (service_role gate functions bypass; owner data-repair must disable the
  trigger first).
- **Backfill in B8:** `UPDATE client_profiles SET gym_id = users.gym_id`
  where NULL and no profile row already exists for (user, gym) — the
  unique partial index `uq_client_profiles_user_gym` forbids a second row
  for the same pair, so conflicting rows are skipped. This backfill is what
  makes the FE-07 `.eq('gym_id', currentGymId)` on client_profiles
  updates/deletes safe.
- Verification: SQL review only. Needs live: the NOT VALID constraints
  must be validated on staging (`ALTER TABLE ... VALIDATE CONSTRAINT`)
  before they are enforced; cross-gym message insert must fail.

## B9 — ee4fc21 — demo/seed scripts (DB-49, DB-63)

- Files: `Gym Demo Reset & Seed (Coaches, Clients, Sessions).sql` (repo
  root), `database/seed.sql`
- Demo script now requires `trainw.demo_gym_id` set via `SELECT
  set_config('trainw.demo_gym_id', '<uuid>', false)` in the same SQL
  Editor session; refuses when the setting is missing, the gym doesn't
  exist, or >1 gym exists (the audit's literal rule — safety over
  convenience on a destructive reset script). All `(SELECT id FROM
  public.gyms LIMIT 1)` replaced with the setting. **Correction found
  during the rewrite: the script has 34 session rows, not 35** (verified by
  count); header/NOTICE corrected to 34. attendee_count removed from the
  sessions INSERT column list + all 34 value rows; real
  `session_enrollments` seeded instead (each session's own client first,
  group sessions up to LEAST(capacity, 15), ON CONFLICT DO NOTHING;
  trigger recomputes attendee_count). `database/seed.sql`: same pattern
  via `trainw.seed_gym_id`, falling back to the single gym only if exactly
  one exists, else raises.
- Verification: count check (34 rows) + review only. Needs live: run
  against a throwaway staging gym and confirm the refuse paths trigger.

## Edge functions — 1f5680d — gate-checkin rewrite + terminal auth (FE-04, DB-22, DB-24, DB-25, GT-06, GT-07, GT-08, GT-09, DB-47)

- Files: `supabase/functions/gate-checkin/handler.mjs`,
  `supabase/functions/gate-terminal-auth/index.ts` (new),
  `supabase/config.toml` (new)
- gate-checkin handler: flag check FIRST (TURNSTILES_ENABLED env must be
  exactly 'true', else 503 `turnstiles_disabled`, nothing processed);
  terminal session verified via `x-terminal-token` header against
  `gate_terminal_sessions.token_hash` (SHA-256; missing/invalid/expired/
  wrong-gym → 401 `invalid_terminal_session`); rate limiting unchanged
  (per-IP 60/min, per-device 30/min, fail open); QR membership now via
  `membership_is_active_for_access` RPC (profile lookup gym-filtered,
  days_left null when no end date; old `payment_unpaid` reason retired);
  duplicates: 15-min window → `already_inside`, same UTC day →
  `duplicate_checkin_today`, 23505 insert conflict →
  `duplicate_checkin_today` (GT-08/DB-24); GT-06 catch returns generic
  `server_error` + console.error (no raw message); GT-07 on non-23505
  insert failure the consumed gate session is reset (used=false/used_at=
  null) before throwing; DB-47 truncate = first 4 + '...' ('****' ≤4); CORS
  now allows `x-terminal-token`.
- New `supabase/functions/gate-terminal-auth/index.ts`: `set_pin` (manager
  JWT verified in code via anon-client getUser + gyms.manager_id check;
  PIN 4–8 digits; HMAC-SHA256 with `GATE_TERMINAL_PEPPER` secret;
  invalidates all terminal sessions for the gym) and `auth` (PIN check,
  constant-time compare, issues a 256-bit random token, SHA-256 stored, +8h
  expiry; rate-limited per-IP 10/min + per-gym 20/min via the existing RPC,
  **fail closed** on limiter error); flag check first (503
  turnstiles_disabled).
- `supabase/config.toml` (new, GT-09): gate-checkin verify_jwt=false,
  gate-terminal-auth verify_jwt=false, ai-proxy verify_jwt=true — **verify
  in the dashboard first, SUSPECTED, no live project access to confirm**.
- **Deploy secrets needed:** `GATE_TERMINAL_PEPPER` (edge secret, random
  32+ byte hex) and `TURNSTILES_ENABLED` (edge env). The DB pepper
  `trainw.member_credential_pepper` is separate (see B1).
- Verification: `node --check` passed on handler.mjs and
  gate-terminal-auth/index.ts (TS syntax via transpile check in the
  Next.js pass). Needs live: `deno check` / `supabase functions deploy`
  + a full PIN → token → QR check-in flow on staging.

## Frontend config/flag — c5b9b7c (flag, FE-23, FE-32, FE-31, FE-21 helper)

- Files: `trainw-config.js`, `env-config.js`, `dev-server.js`,
  `trainw-core.js`, `tw-gym-acc.js`
- `trainw-config.js` committed placeholder now has
  `window.__TRAINW_TURNSTILES_ENABLED__ = false;` + a re-enable comment.
  `env-config.js`: TURNSTILES_ENABLED read from env (only literal 'true'
  enables), written into dist/trainw-config.js; FE-23 HTML-scraping
  fallback REMOVED from `resolveSupabaseConfig` (the build now fails
  loudly without env vars — the round-1 notes record the build only
  succeeded via that fallback); the verify step checks the flag line
  exists. `dev-server.js`: flag served in /trainw-config.js; FE-23
  scraping fallback removed from `discoverSupabaseConfig`; FE-32
  allow-list in `safeResolve` (allowed extensions = mimeTypes keys +
  .map/.webmanifest/.woff/.woff2; dotfiles/dot-dirs blocked; `database/` +
  `supabase/` trees blocked; extension check applies to files, segment
  checks to files and dirs). `trainw-core.js`: `Trainw.TURNSTILES_ENABLED`
  from `window.__TRAINW_TURNSTILES_ENABLED__ === true`; FE-31 `setHtml`
  now escapes by default, raw variant renamed `setHtmlUnsafe` (only 4 call
  sites exist, all in tw-gym-acc.js:3214-3242, updated with comments);
  FE-21 `Trainw.media.validateImageFile` helper (PNG/JPEG/WebP, ≤5 MB).
- Verification: `node --check` passed on env-config.js, dev-server.js,
  trainw-core.js. **Build warning:** removing the FE-23 fallback means
  `node env-config.js` now requires real env vars — set them before the
  next build or it fails loudly by design.

## Frontend FE fixes — 1fe7bce (FE-04, FE-06, FE-07, FE-08, FE-16/FE-33, FE-20, FE-21, credential_ref display)

- Files: `tw-gym-acc.js` + `.html`, `gate-terminal.js` + `.html` + `.css`,
  `tw-gym-acc-v17.js`, `tw-gym-pilot.js`, `tw-client-acc.js`,
  `tw-coach-acc.js`
- FE-07: `.eq('gym_id', currentGymId)` added to sessions update/delete,
  gym_classes update/deleteGymClass, session_enrollments delete,
  saveEditClient client_profiles update (after the B8 backfill),
  deleteClient client_profiles delete, submitNewClient profile insert (now
  sets `gym_id: currentGymId`); users update/delete NOT scoped (shared
  rows; RLS is the backstop). v17 assignCoachToClient /
  unassignCoachFromClient / delClass and pilot updateCoachApproval scoped
  the same way.
- FE-20: saveEditClient routes both updates through Trainw.api.run and
  aborts on error.
- FE-08: bare users query dropped; coach search runs coach_profiles only
  (name via embedded `users.name` ilike filter — **flag for live
  verification** — + specialty); email masked in rendered cards (kept in
  the button's data attribute for the invite flow).
- FE-16/FE-33: strict money parse (`parseMoneyInput`, digits + optional 2
  decimals, no negatives; `parseFloat` "12abc"→12 rejected); savePricing
  fetches the current gyms row first, empty keeps current/NULL,
  invalid/negative errors + aborts; 150/400/1400 defaults removed from all
  three sites (913-915 and 5404-5406 now `?? ''`).
- FE-21: image validation at staff avatar (extension now derived from the
  validated MIME type, not the filename) and gym logo uploads.
- FE-06: gym side VERIFIED clean (loadConversation, updateMessageBadge,
  sendMessage, auto messages all filter/insert gym_id) — no change.
  Client: messages load guarded (empty when no gym, same pattern as
  check-ins) + gym eq on mark-read. Coach: `coachGymScopedQuery` 'all'
  mode no longer returns the query unfiltered when no gym (now matches
  nothing via the nil UUID); messages load + openClientPanel messages
  explicitly guarded; mark-read guarded + gym eq.
- Credential list: selects `credential_ref` instead of `credential_data`
  (3965, 4243, 4283 label); draft display uses ref; duplicate detection
  now ref-based (first 4 + '...') with DB 23505 as the real guard (already
  mapped to friendly messages in both insert sites).
- Terminal (FE-04): `buildGateTerminalUrl` drops the PIN param; new
  `saveTerminalPin()` calls gate-terminal-auth `set_pin` with the user's
  JWT; open/copy buttons disabled until a PIN is set (`terminalPinSet`
  from `gate_terminal_pin_hash` added to the gym profile load select at
  5381); PIN input now type=password; set-PIN button + status line added
  to the terminal card HTML. Turnstile UI flag-gated: `renderCheckInTabs`
  hides credentials/journal/terminal tabs while off and forces tab to
  'live'; `setCheckInTab` refuses turnstile tabs while off.
  `gate-terminal.js`: no PIN in URL; boot PIN prompt reuses the admin modal
  (server-checked via gate-terminal-auth `auth`); session token in
  sessionStorage (`trainw_terminal_session`); 401 invalid_terminal_session
  clears + re-prompts; `handleAdminKey` enter calls server auth (no local
  compare; no blank-PIN pass — empty buffer shows "Saisissez le PIN");
  `refreshAdminDisplay` masks by buffer length; REASON_LABELS added for
  duplicate_checkin_today, already_inside, turnstiles_disabled,
  invalid_terminal_session, server_error, rate_limited; `handleQrScan`
  sends `x-terminal-token`; flag off → `#terminal-disabled` screen (new
  HTML + CSS), never starts scanner/realtime, never prompts. Admin button
  after auth re-prompts for the PIN (re-auth refreshes the session; the old
  "open dashboard" behaviour is gone); `bindRealtime` unsubscribes any
  existing channel first.
- Verification: `node --check` passed on every touched JS file; grep
  confirms zero PIN-in-URL remnants and zero raw `setHtml` callers; the 2
  remaining `credential_data` hits in tw-gym-acc.js are the write-only
  intake inserts (correct). One fix during the work: a duplicated
  `function` keyword in tw-coach-acc.js (from a comment insertion) was
  caught by node --check and fixed before commit.

## Next.js group

Root `package.json` has zero dependencies (the static frontend's); no
node_modules, no deno binary — TS verification is review-only (see the
verification section at the end). `src/middleware.ts` did NOT exist yet
(NX-08 creates it; tsconfig already includes it).

### NX-01 + NX-02 — c80a49d — rate limiting, CAPTCHA, confirmed-email signup

- Files: `src/lib/rate-limit.ts` (new), `src/lib/captcha.ts` (new),
  `src/lib/env.ts`, `src/actions/auth.ts`, `src/app/auth/callback/route.ts`
  (new)
- `rate-limit.ts`: in-memory sliding window, 1000-bucket sweep,
  `checkRateLimit` + `getRequestIp`; documented single-instance limitation
  — a shared store (Upstash/Redis) is Phase 2.
- `captcha.ts`: hCaptcha siteverify; **if no secret is configured it logs
  a loud warning and returns ok — fail-open, documented as a
  pre-launch must-configure launch blocker.** `env.ts` adds
  `captchaSecretKey` + `hcaptchaSiteKey`.
- `auth.ts` rewritten: NX-01 login/signup rate limits (5 attempts/15 min
  per IP + per email, via `await headers()` — version-safe for Next
  14/15); NX-06 login returns generic "Invalid email or password."
  always; NX-02 signup now uses normal `supabase.auth.signUp` +
  `emailRedirectTo: getAbsoluteUrl('/auth/callback')` and returns "check
  your email" (no admin createUser, no immediate provision, no
  auto-sign-in; generic error on failure to avoid user enumeration).
- New `src/app/auth/callback/route.ts`: exchanges the code, then calls
  `provision_new_gym` (admin RPC) ONLY after email confirmation, skipping
  if the users row already exists (provision always creates a NEW gym,
  must never run twice); safe `next` redirect (must start with "/").
  Depends on database/schema.sql (provision_new_gym + users table) — P1-11
  territory. **Deploy env needed:** `CAPTCHA_SECRET_KEY` (+
  `NEXT_PUBLIC_HCAPTCHA_SITE_KEY` for the widget).
- `as any` casts kept (NX-25 skipped — can't verify without tsc).

### NX-04 — c6d1e13 — server-side gym ownership checks

- Files: `src/actions/classes.ts`, `src/actions/attendance.ts`
- `classes.ts`: createClass verifies the coach belongs to the gym; enroll
  verifies class AND client belong to the gym — individual-type clients
  with gym_id NULL are excluded by design (documented).
- `attendance.ts`: verifies the client, and the class if given, belong to
  the gym.
- Verified from the code (no changes needed): NX-11 — all dashboard pages
  pass `context.gymId` from requireWorkspaceContext to
  getCoachesPageData/classes/attendance/clients/metrics; NX-17 —
  `countRows` in queries.ts already returns real counts (count exact head),
  not 0; NX-18 — the dashboard page already renders the "Your role does
  not have permission to access that area." notice on `?forbidden=1`.

### NX-05 (+ NX-15, NX-20, NX-21, NX-22) — 8ce39b1 — pending-approval public client registration

- Files: `src/app/api/public/clients/route.ts` (rewritten),
  `src/actions/clients.ts`, `supabase/migrations/
  20261115090000_phase1b_public_clients_status.sql` (new),
  `src/types/database.ts`, `src/lib/queries.ts`,
  `src/app/(dashboard)/dashboard/clients/page.tsx`,
  `src/components/forms/client-row-actions.tsx` (new),
  `src/components/public/client-registration-form.tsx`,
  `src/app/register-client/page.tsx`
- Public route: 10/min per-IP rate limit + hCaptcha; email OR phone
  required (zod refine); gymId rejected for individual type (NX-21); safe
  JSON parse (NX-22); generic errors only, never Supabase error text
  (NX-15); inserts with `status='pending'` + contact, NO client_code in
  the response (code issued on approval).
- Guarded migration: adds `status`, `email`, `phone`, `contact_verified`
  to `clients` IF the table exists (it only exists in
  `database/schema.sql`, not the migration chain — do NOT touch schema.sql,
  P1-11 pending). `status` DEFAULT 'approved' so gym-created clients stay
  active and pre-migration rows backfill as approved; the contact CHECK
  only constrains pending rows (dashboard-created clients carry no
  email/phone). `src/types/database.ts` clients Row/Insert/Update updated
  by hand to match (regenerate from the live DB at deploy); new
  `ClientStatus` union type.
- Gym side: `approveWorkspaceClientAction` + `deleteWorkspaceClientAction`
  (clientsManage, gym-scoped); clients page shows a "Pending approval"
  badge + contact + Approve/Delete buttons. **Nuance:** the client_code is
  generated by the DB trigger at insert, so a pending row already HAS a
  code — approval only REVEALS it (dashboard list). A true "issue on
  approval" would need the trigger changed, which is schema.sql territory
  (P1-11).
- Registration form: email/phone fields + hCaptcha widget (plain JS API
  via `https://js.hcaptcha.com/1/api.js`, site key from
  NEXT_PUBLIC_HCAPTCHA_SITE_KEY; no @hcaptcha package installed — zero
  dependencies in the repo); sends `captchaToken` in the POST body; shows
  "pending approval" result instead of a client code. Register page copy
  updated to match.
- **Confirmation step:** a true email-confirmation token flow needs an
  email provider + a token table — Phase 2. The shipped step is the gym
  approval queue; `contact_verified` stays false until that flow lands.

### NX-06 + NX-07 + NX-08 (+ NX-20) — e049bca — public search, health leak, session middleware

- Files: `src/app/api/gyms/search/route.ts`, `src/app/api/health/route.ts`,
  `src/middleware.ts` (new)
- Gyms search: require ≥2 chars (cap 64, NX-20), escape `%`, `_`, `\`
  before ilike, rate-limit 30/min per IP, generic errors, limit 8 kept.
- Health: `adminConfigured` removed from the response (it leaked whether
  the service-role key is configured).
- New `src/middleware.ts` calling `updateSession` from
  `src/lib/supabase/middleware.ts` (standard Supabase matcher, static
  assets excluded).

### NX-09 — 138cc75 — staff invite + owner-role guard

- Files: `src/actions/roles.ts`, `src/components/forms/staff-user-form.tsx`
- Staff creation uses `admin.inviteUserByEmail` (confirmation email)
  instead of `createUser({email_confirm: true})` + a caller-chosen
  password; the password field is dropped from the form. **Gap:** invited
  staff must set a password via the invite link — there is no in-app
  set-password screen yet (password reset, NX-14, is Phase 2).
- Only a gym owner may assign the gym_owner role. The guard is
  NAME-based ('Gym Owner' / 'admin') because schema.sql's roles table has
  no `code` column — replace with a code check once the P1-11 schema
  decision lands.

### NX-13 + NX-16 + NX-19 + NX-23 — 84f3009 — misc hardening + dead code

- Files: `src/components/ui/submit-button.tsx`, `src/actions/coaches.ts`,
  `src/lib/utils.ts`, `src/lib/permissions.ts`,
  `src/lib/supabase/browser.ts` (deleted)
- NX-13: `SubmitButton` passes `disabled={pending}` (double-submit fix).
- NX-16: coach rating clamped 0–5 server-side in the zod transform.
- NX-19: `formatDateTime` pins `timeZone: 'Africa/Tunis'`.
- NX-23 dead code deleted (grep-verified zero usages): `formatDate`,
  `slugFromGymName`, `src/lib/supabase/browser.ts` (note: its staged
  deletion was swept into c80a49d, not this commit),
  `DEFAULT_ROLE_TEMPLATES`, and the `financeView` permission (only used
  inside the dead templates). `getAbsoluteUrl` kept (now used by the NX-02
  callback).
- NX-27 verified already clean: no hard-coded 'Gym Owner'/'Manager'
  role-name copy in src (the OWNER_ROLE_NAMES guard in roles.ts is the
  new provisional check documented under NX-09, not the old copy).
- NX-15: the three API routes are clean (no Supabase error text). The
  `error.message` returns that remain in src/actions/* are
  authenticated-dashboard form errors about the user's own workspace
  operations (the app's existing pattern) — left as-is.

## Round-2 verification (all local, no live DB, no build)

- `node --check` passed on every touched JS file (edge handler.mjs,
  gate-terminal-auth/index.ts, gate-terminal.js, trainw-core.js,
  env-config.js, dev-server.js, tw-*.js).
- TS: no `tsc --noEmit` possible (zero dependencies, no node_modules, so
  module resolution would fail regardless). Instead, TypeScript 5.9 was
  installed to /tmp and every touched TS/TSX file (22 files) was run
  through `transpileModule` (syntax-only, no type resolution): **all 22
  pass**. Full type-check + `next build` still required at deploy.
- Grep sweeps (branch-wide, post-round-2): `admin.createUser` 0 hits;
  `createBrowserSupabaseClient` 0 hits; `email_confirm` only in comments
  describing the old flow; `adminConfigured` only in a comment;
  `client_code` in the public clients route only in a comment;
  `DEFAULT_ROLE_TEMPLATES`/`financeView` only in a comment; no bare
  `formatDate(` usage; no password field left in the staff form; zero
  PIN-in-URL remnants; zero raw `setHtml` callers.
- Migration order: new files `20261115010000`–`20261115090000` sort after
  the round-1 files (`20261114000000`–`20261114040000`) and reference only
  objects that exist in the migration chain, except the guarded NX-05
  migration which no-ops when `public.clients` is absent (to_regclass
  guard). Pre-existing note: `Trainw_001_foundation.sql` carries no
  timestamp prefix — its load order under `supabase migration list`
  should be confirmed on staging (DB-51 territory, skipped).
- `git log 9d1cf21..HEAD`: 18 commits, working tree clean. Nothing
  pushed, nothing applied to any live DB.

## Deliberately skipped in round 2

- **Payments ledger (FE-19 / DB-36 core)** — Phase 2, approved as the next
  build after this round lands. (DB-65/DB-66 payment immutability/
  settlement are M effort and sit in the ledger's orbit — also Phase 2.)
- **P1-11 schema decision** — still the user's call (migration chain
  canonical + archive schema.sql vs reconcile). Blocks: NX-05's true
  "issue code on approval", the NX-09 code-based owner guard, DB-51.
- **P1-13 live tests** — needs staging + Supabase access.
- **Freeze + renewal (P2-3), Next.js app decision (P2-10), privacy basics
  (P2-9), backups/monitoring/staging (P2-7)** — Phase 2 per the brief.
- DB-51 (rename foundation file — S but SUSPECTED; renaming changes
  migration versioning, needs staging verification via `supabase migration
  list`); DB-35 (validate NOT VALID constraints — M); DB-41 (blanket grant
  — M); DB-45 (assignment pending — M); DB-46 (storage is_public — M);
  DB-48 (RPC lockout — M; edge rate limiting covers); DB-50 (repair
  runbook — M); DB-61 (freeze helpers — M); NX-10 (delete actions — M);
  NX-14 (password reset — M); NX-24 (deps — M); NX-25 (remove `as any` —
  can't verify without tsc/build); NX-26 (CI tests — M); NX-28 (orphan
  recovery — M); NX-29 (client codes doc note — schema.sql is P1-11
  territory).
- FE-27 dead-code purge (`tw-client-pilot.js` etc.) — M effort, out of
  scope for this round.

## Audit-vs-code mismatches found in round 2 (additions to the round-1 list)

7. `gym_profiles` policies DO have a manages_gym branch — only the self
   branch lacks a gym check.
8. FE-04's PIN is not stored anywhere (URL-only), so the fix needed a new
   PIN-hash column + edge function, not just "move it".
9. `permission_codes_for_membership` tail: a deny wins over both role and
   allow (first draft had it wrong — fixed).
10. `sync_legacy_user_membership_projection` stores the RAW role_code, not
    map_legacy_role_code (first draft had it wrong — fixed).
11. `coach_profiles.approved_by` column exists — only its FK was dropped.
12. FE-26's sendMessage is at tw-gym-acc.js:4548, not 4485 as the audit cites.
13. The demo script has 34 session rows, not 35.
14. NX-17's countRows already returns real counts; NX-18's forbidden
    notice already exists on the dashboard page; NX-11's gym scoping
    already holds in all dashboard pages.
15. schema.sql's `roles` table has NO `code` column (only `name`), and its
    `clients` table has no status/email/phone columns — both are why the
    NX-09 guard is name-based and the NX-05 migration is guarded. This is
    the P1-11 divergence in miniature.
16. The Next.js app has no `middleware.ts` and the root package.json has
    zero dependencies — there is no `next build` or `tsc` to run locally
    at all.

## What still needs live testing / access / a user decision (round 2)

- **Secrets to set at deploy (none committed):** DB GUC
  `trainw.member_credential_pepper` (random 32+ byte hex, via ALTER
  DATABASE); edge secret `GATE_TERMINAL_PEPPER` (random 32+ byte hex);
  `TURNSTILES_ENABLED` (edge env + build env, default false);
  `CAPTCHA_SECRET_KEY` + `NEXT_PUBLIC_HCAPTCHA_SITE_KEY` (hCaptcha). The
  CAPTCHA secret is a pre-launch must-configure — the endpoint fails open
  without it. The member-credential pepper must be set BEFORE the
  backfill runs, or the hash function raises.
- **Staging apply order:** migration chain first, then the round-1 files,
  then round-2 files 20261115010000–20261115090000. Dedupe payments
  (DB-17) before applying B4. Validate the NOT VALID constraints from B8
  after applying. Run the credential backfill as project owner after
  setting the pepper. Confirm `Trainw_001_foundation.sql` loads first
  under `supabase migration list`.
- **Live verification checklist (staging):** enrol + gate-check a
  credential (hash path); wrong-gym profile rejected at the gate;
  metadata-injected owner signup ignored; cross-gym role grant / system
  role edit / self-grant / expired invite all rejected; payment delete
  rejected; get_staff_directory returns no invite_token/national_id;
  triggers fire as a low-privilege role (DB-31); demo script refuse
  paths; full terminal flow PIN → token → QR check-in with the flag ON,
  and 503 `turnstiles_disabled` with it OFF; Next.js signup →
  confirmation email → callback provisions exactly one gym; public
  registration → pending queue → approve reveals the code; staff invite
  → set-password flow (needs NX-14); `next build` + `tsc --noEmit` clean.
- **User decisions still open:** P1-11 schema decision; the FE-08 coach
  search embedded-users name filter (live verification); whether the
  Next.js app is the ship target at all (P2-10).

---

## Round 3 — payments ledger (FE-19 / DB-36, DB-65) — 2026-11-15

Commits (all local, branch `phase1-security-fixes`, on top of be1044a):
- `cf994d1` P1-11: archive database/schema.sql + seed.sql (migration chain is canonical)
- `98fb52c` Ledger: append-only payments, settlement, immutability, refund RPC, TEIF fields
- `6112d1e` Freezes: membership_freezes table, gate check, end-date shift
- `ffdd175` Frontend: payment writes go through the ledger; revenue from the ledger
- `5b77717` Payments view: record/void/list, end-of-day totals, freezes UI

### P1-11 — DONE (commit cf994d1)
Files changed: `database/schema.sql` + `database/seed.sql` moved to
`database/archive/` (git mv), `database/archive/README.md` (new).
Decision: the migration chain is the authoritative schema. The README
documents the divergence (roles shape, parallel coaches/clients/classes/
class_clients/attendance tables, `provision_new_gym` RPC that fails against
the chain's roles) and what still depends on the archived file — the
Next.js app in `src/` does not work against a migration-chain-only DB
until its data model is migrated (P2-10, open): `src/app/auth/callback/
route.ts` calls `provision_new_gym`; `src/actions/clients.ts`,
`classes.ts`, `attendance.ts`, `src/lib/queries.ts`,
`src/app/api/public/clients/route.ts` query `clients`/`class_clients`;
`src/types/database.ts` types them; `src/actions/roles.ts` guards the owner
role by NAME because archived `roles` has no `code` column. Only comment
references to the old paths remain in code; nothing loads the files.
Verification: grep confirmed no code loads `database/schema.sql` or
`database/seed.sql`; `git log --follow` preserves history. Still needs:
the P2-10 Next.js decision (migrate its data model or drop it).

### Ledger migration — DONE (commit 98fb52c)
File: `supabase/migrations/20261115100000_phase1c_payments_ledger.sql`
(new, sorts after round-2 files 20261115010000–20261115090000).
Extends the EXISTING `payments` table (003 + B4 idempotency/verify/
no-DELETE — built on, not redone). Adds:
- `method` (cash/card/bank_transfer), `period_months`, `period_start`,
  `period_end`, `void_reason`, `voided_by`, `voided_at`, `settled_at`.
- TEIF e-invoice columns: `invoice_number`, `invoice_date`,
  `buyer_tax_id/name/address`, `seller_tax_id/name/address`,
  `service_description`, `amount_ht`, `vat_rate` (fraction 0..1),
  `vat_amount`, `amount_ttc`, `ttn_reference`, `e_invoice_status`
  (not_issued/pending/issued). Unique indexes on (gym_id, invoice_number)
  and (gym_id, ttn_reference) where not null. `gyms.tax_id` +
  `trade_register`, `client_profiles.tax_id` added for invoice identity.
- CHECKs: method values, amounts ≥ 0, amount_refunded ≤ amount_paid,
  period_months ≥ 0, vat_rate 0..1. Deploy note: the new CHECKs assume
  existing rows are sane — if the migration fails on a constraint, fix
  the offending rows on staging first.
- `prepare_payment_write` rewritten (B4 logic verbatim: idempotency-key
  dedupe, always-verify client, client/gym binding, no DELETE) plus
  'void' → 'voided' rename, voided_at/by, INSERT-only period defaults
  with Postgres month-clamping, e-invoice HT/VAT/TTC defaults, buyer/
  seller identity snapshots (best-effort under RLS). Trigger order
  follows 003 numbering (10_prepare → 15_settle → 20_audit → 80_guard
  → 90_upd).
- Settlement trigger `trg_payments_15_settle_membership` (BEFORE,
  SECURITY DEFINER): on a paid membership payment with `settled_at`
  NULL it settles — end date extends from
  GREATEST(old end, period_start, today) + period_months, start date
  defaulted, price_paid = amount_paid, payment_status = 'paid',
  settled_at = now(). Idempotent via settled_at (re-running is a no-op);
  backdated payments cannot shorten the end date. On paid → voided/
  cancelled with settled_at set it reverses — end date minus the period,
  floored at the start date; status/price recomputed from remaining paid
  payments; settled_at cleared.
- Immutability guard `trg_payments_80_guard_update` (BEFORE UPDATE,
  DB-65): only pending → paid/cancelled/voided and paid → voided/
  cancelled; void requires a reason; voided/cancelled rows are terminal;
  paid rows' money + identity fields are frozen; amount_refunded changes
  only via the refund RPC flag `trainw.allow_payment_refund`.
- Refund RPC `record_payment_refund(p_payment_id, p_amount, p_reason)`
  (SECURITY DEFINER, manager-only): partial refund keeps paid + fixes
  price_paid when it is the latest payment; full refund voids + reverses
  the settlement; writes a `payment_events` 'refunded' row.
- TEIF research (2026-11-15, browser search — KPMG Circulaire fiscale
  février 2026, challenges.tn 2026-01-25, bfc.com.tn, lapresse.tn
  2025-12-30, consistent): invoice number + date of operation; seller
  tax id (matricule fiscal) + identity/address (+ registre de commerce);
  buyer identity, address, tax id; service description + price HT; TVA
  rates and amounts; total TTC; unique TTN reference; electronic
  signature; QR code/electronic identifier. Art. 53 (Loi de Finances
  2026, loi n° 2025-17 du 12 décembre 2025) extended the obligation to
  services from 1 Jan 2026; Note Commune n° 2/2026 gives tolerance for
  providers who filed with TTN. An amendment to delay Art. 53 was
  approved in commission but NOT voted in plenary — Art. 53 applies as
  promulgated. **No VAT rate is hardcoded; `vat_rate` is NULL unless the
  gym sets it. The exact TEIF field list, the applicable TVA rate for
  gym services, and the Art. 53 delay-amendment status MUST be verified
  with an accountant before the first real invoice.**
- Two bugs caught and fixed while writing: the seller snapshot used
  `SELECT ... INTO` a `%ROWTYPE` variable (wrong column count — now
  three scalar vars); the refund flag read could be NULL (now COALESCE
  to '').
Verification: SQL reviewed by hand; no live DB yet (see Postgres note
below). Still needs: live apply + behavioral tests on staging (settle,
void, refund, freeze, guard — see "Round 3 live checklist" below).

### Freezes migration — DONE (commit 6112d1e)
File: `supabase/migrations/20261115110000_phase1c_membership_freezes.sql`
(new). `membership_freezes` table (gym_id, user_id, start/end dates,
reason, status active/cancelled, created_by; CHECK end ≥ start; RLS
managers + own rows; no DELETE policy). `membership_is_active_for_access`
rewritten verbatim from B1 plus a freeze clause (no active freeze covering
the reference date) — the gate + manual check-in inherit it, so a frozen
member is denied at the door. End-date shift trigger: extend on freeze
creation by end−start days, roll back on cancel, floored at the start
date, only when end ≥ today. RPCs `request_membership_freeze`
(manager-only, rejects overlapping active freezes) and
`cancel_membership_freeze` (manager-only). Model per audit P2-3: a freeze
pauses the membership.
Verification: SQL reviewed by hand; no live DB yet. Still needs: live
apply + freeze/gate tests on staging.

### Frontend — DONE (commits ffdd175, 5b77717)
Files changed: `tw-gym-acc.js`, `tw-gym-acc-v17.js`, `tw-gym-acc.html`.
- `saveEditClient` no longer writes `payment_status`/`price_paid`; the
  edit modal shows them read-only (ledger-derived) with a button that
  jumps to the Paiements page for that member. `submitNewClient` creates
  the profile as 'pending' / price_paid 0 and, when an initial amount is
  entered, inserts a paid `payments` row (method + period from the tier);
  the settlement trigger derives the profile. The amount is now parsed
  with the strict `parseMoneyInput` (FE-16). New-client modal takes a
  payment method instead of a payment status.
- `loadDashboardStats` + `loadAnalytics` use the new `loadLedgerRevenue()`
  (sum of `amount_paid` of paid payments by paid month) instead of
  `price_paid` sums; v17 `revenueFor`/`price`/`tier`/`monthActive`
  deleted — `refreshRevenue` now calls `loadLedgerRevenue`. The old v17
  estimate charged every paid member the tier list price read from the
  DOM inputs (a list-price estimate, not cash collected) and overwrote
  the dashboard's own figure.
- New Paiements page (nav item, hidden without `manage_payments`; the
  staff hard-redirect in `showPage` already applies): record a payment
  (member, strict-parsed amount, method, period 1/3/12/0, date, optional
  invoice number / buyer tax id / VAT rate / notes), recent payments
  list with void-with-reason, end-of-day cash/card/transfer totals,
  freeze form + active freezes with cancel. `recordPayment` inserts into
  the ledger only; void goes through the DB guard (reason mandatory).
- Verification: `node --check` clean on both JS files; grep confirms no
  UI path still writes `payment_status` directly — the only remaining
  `payment_status:` write is the new profile's `'pending'` seed with
  `price_paid: 0` in `submitNewClient`; remaining `payment_status` reads
  are display/filter badges only. All new HTML ids exist and are
  referenced in JS. Void uses `window.prompt` for the reason — P2 polish
  is a proper modal.

### Postgres local verification — DONE (2026-11-15, real PostgreSQL 16.15)
The `apt-get install postgresql` finished; a throwaway cluster was built
in /tmp (port 54399) with a minimal Supabase emulation (stub file
/tmp/supabase-stubs.sql — NOT in the repo: `auth` schema with
`auth.users` + `auth.uid()`/`auth.jwt()`/`auth.role()` driven by the
`test.auth_uid` / `test.auth_role` GUCs, `storage` schema with buckets /
objects / `foldername()`, roles anon/authenticated/service_role with the
schema grants Supabase gives them). The full chain (001 → 012_v18 →
round-1 → round-2 → 1c) applies cleanly EXCEPT B5 (see below), and a
50-assertion behavioral suite (/tmp/ledger-tests.sql, throwaway) passes
end to end: settle (profile paid, price_paid, end date, settled_at,
period_end, audit event, idempotent re-touch), duplicate
provider_reference rejected (23505), void with reason reverses
(status/price/end/settled_at), void without reason rejected, 3-month
settle + exact void restore, guard rejects direct amount edits,
paid→pending, tampering with settled_from_end_date, DELETE via FK
RESTRICT (superuser) and via RLS 0-rows (authenticated role, no DELETE
policy), partial refund (amount_refunded + price_paid fix + event),
full refund (void + reversal), refund guards (non-manager, voided
payment), freeze (+9 days, gate denies during freeze, active after,
overlap rejected, cancel rolls back), e-invoice defaults (TTC 150, HT
126.05, VAT 23.95 at 19%, invoice_date today, seller tax id snapshotted)
+ duplicate invoice_number rejected, backdated payment extends from
the current end date. Three defects found by this verification, all
fixed as NEW migrations (see below); the chain now applies end to end.

### Round 3 live checklist (staging, after the migration chain + round-1/2 files apply)
- Apply `20261115100000_phase1c_payments_ledger.sql` then
  `20261115110000_phase1c_membership_freezes.sql` on a THROWAWAY copy of
  the chain first (dedup payments before B4; the new CHECKs assume sane
  existing rows). Then: record a 1-month payment → profile flips paid,
  end date +1 month, price_paid set; record the same payment again with
  the same idempotency key → single row; void it with a reason → end
  date rolls back, profile recomputed; void without a reason → rejected;
  UPDATE a paid payment's amount directly → rejected; partial refund →
  amount_refunded + price_paid fixed; full refund → voided + end date
  reversed; freeze a member → gate denies, end date +frozen days;
  cancel the freeze → end date rolls back; dashboard + analytics revenue
  equals the ledger sum; a staff user cannot open the Paiements page.
- **User decisions still open (unchanged):** the FE-08 coach search
  embedded-users name filter (live verification); whether the Next.js app
  is the ship target at all (P2-10). **New:** DB-66 no-show/completion
  auto-settlement policy is undecided (refund-vs-credit-vs-forfeit) —
  the refund RPC exists but the policy call is his.

### Deliberately skipped in round 3
- DB-66 no-show/completion auto-settlement (policy undecided per audit
  Q10; the mechanism exists via the refund RPC).
- The Next.js app's payment handling (it uses the archived schema's
  tables — P2-10 territory).
- Online payment gateways (Konnect/Paymee — P3-3).
- `Trainw_001_foundation.sql` rename (DB-51, needs staging
  `supabase migration list`).
- The void-reason `window.prompt` is a P2 polish item, not a blocker.

### Verification fixes (new migrations, 2026-11-15 — all found by the local Postgres run)
- `20261115120000_phase1c_fix_get_staff_directory.sql` (commit 407d32b):
  B5 (round 2) FAILS on a fresh apply — `CREATE OR REPLACE` cannot
  change `get_staff_directory`'s return type (012 defined it WITH
  national_id + invite_token; B5 removes both per DB-20). With
  ON_ERROR_STOP the rest of B5 never applied (admin_audit_log,
  get_staff_directory_sensitive, list_gym_member_directory,
  revoke_gate_session). This file DROPs the old function, re-applies
  B5's definition verbatim, then applies the remainder of B5. B5 itself
  is untouched. The chain now applies end to end (B5 still fails on its
  own by design; the fix migration repairs it).
- `20261115130000_phase1c_payments_voided_status.sql` (commit 407d32b):
  the ledger's 'voided' status was NOT in the chain's
  payments_status_check (003) — every void failed the CHECK. Widens
  the constraint to include 'voided', then VALIDATEs it.
- `20261115140000_phase1c_settlement_exact_reversal.sql` (commit
  0d4a9c8): voiding reversed the end date by subtracting the period,
  but Postgres month arithmetic is not symmetric around month-ends
  (2026-11-30 + 3mo = 2027-02-28, minus 3mo = 2026-11-28) — a voided
  quarterly payment silently lost 2 days. New column
  settled_from_end_date records the pre-settlement end date; reversal
  restores it exactly (month-subtraction fallback for rows settled
  before this column existed). The guard freezes settled_from_end_date
  on paid/voided rows.
- Test-harness notes (not code defects): the chain auto-creates
  public.users + a bare gym-less client_profiles row per auth.users row
  (on_auth_user_created trigger) — test assertions must scope profiles
  by gym_id. RLS denies a DELETE silently (0 rows affected), it does
  NOT raise — the RLS delete test asserts the row count. The stub
  needed Supabase's schema grants (USAGE on auth/storage) for policies
  calling auth.uid() to evaluate as the authenticated role.

# Round 4 — remaining code-doable audit items, 2026-11-15

38 commits on `phase1-security-fixes` after the round-3 head `4e40313`
(`359e269` … `74bf6d7`). Local only — not pushed in this round. Rules
held throughout: never edit an applied migration (all SQL as NEW
files), one commit per logical piece, no history rewrites, no live
database, no production deploy, no P2-10 decision.

Verification harness (same approach round 3 proved): throwaway local
Postgres 16.15 cluster, `/tmp/r4-harness.sh` (up/apply/test/psql/down/
reset), cluster `/tmp/r4-pgdata`, port 54399, DB `trainw`, stubs in
`/tmp/supabase-stubs.sql` (auth + storage emulation). Quirk: the
server must run as the `postgres` OS user (initdb/pg_ctl refuse root)
but psql runs as root (userns permission quirk); the harness runs
server commands via `su postgres` and psql directly. Log path is
`/tmp/r4-apply.log` (root-owned). The harness's `service_role` now
gets BYPASSRLS (matching real Supabase) and the stub enables RLS on
`storage.objects` — both added in round 4. Test files live in `/tmp`,
NOT in the repo: `/tmp/r4-tests.sql` (82 PASS), `/tmp/r4-tests-db27.sql`
(20), `/tmp/r4-tests-db37.sql` (8), `/tmp/r4-tests-db38.sql` (5),
`/tmp/r4-tests-db57.sql` (5), `/tmp/r4-tests-db59.sql` (6),
`/tmp/r4-tests-db62.sql` (4), `/tmp/r4-tests-fe26.sql` (2),
`/tmp/r4-tests-p29.sql` (6) — **138 PASS total** (82+20+8+5+5+6+4+2+6).
Test-suite order/collision rules (learned the hard way): run each
suite on a FRESH cluster (`reset` first) — fixtures collide across
suites (DB-62's check and FE-26's gym UUID both broke when suites
shared a cluster). Never run the chain `apply` twice on one cluster
(5 files are not idempotent on re-application) and never run a test
suite twice on one cluster. Correct run order on a fresh cluster:
r4-tests.sql → DB-27 → DB-37 → DB-38 → DB-57 → DB-59 → DB-62, then
FE-26 and P2-9 each on their own fresh cluster. r4-tests.sql's
outsider is `55555555`, which the DB-27 file originally also used as
member 2 — DB-27's member 2 is now `56565656-5656-5656-5656-565656565656`.
r4-tests.sql's DB-61 tamper check is LAST and deliberately leaves
`can_view_user` redefined as `SELECT true`; the DB-37 file restores
the frozen definition before its freeze assert so it is
order-independent. Test-harness lessons: `validate_coach_availability_write`
requires legacy `users.gym_id` set for the coach AND `users.role =
'coach'`; the gyms row must be inserted before users reference it
(users_gym_id_fkey); a mutating function call and a state check must
not share one boolean expression (Postgres may evaluate the state
check first — split into two statements, learned on DB48h); RLS policy
tests use `SET ROLE authenticated;` + `SET test.auth_uid = '...';`
then `RESET ROLE;` — INSERT denials raise `insufficient_privilege`,
UPDATE/DELETE denials are silent (0 rows, use GET DIAGNOSTICS
ROW_COUNT). Deleting a gym cascades to sessions, but the
session-deletion trigger `log_session_status_event` inserts into
session_status_history with the about-to-be-deleted gym_id → FK
violation; test cleanup must delete sessions first, then the gym.

## DB-51 — 359e269 — rename foundation + v18 files so the chain sorts in order

- Files: `git mv Trainw_001_foundation.sql →
  20260408180000_trainw_001_foundation.sql`,
  `20260419000000_trainw_012_v18_additions.sql →
  20260419000000_trainw_013_v18_additions.sql` (the v18 file's own
  header already said "TRAINW 013 ADDITIONS";
  `docs/DATABASE_AUDIT_V17.md:21` already cited the timestamped
  foundation name, so no doc edits were needed).
- Before-state proof: applying
  `20260408181000_trainw_002_profiles_operations.sql` first fails with
  `relation "public.users" does not exist`. After: the full chain
  applies in pure lexicographic filename order — 33 files OK; the only
  failure is the pre-existing by-design B5 return-type failure
  (repaired by `20261115120000` as before). Round-3 ledger suite
  re-run on the renamed chain: 51 PASS.
- Live note: if any environment already recorded
  `Trainw_001_foundation.sql` as applied, the rename must be paired
  with a migration-version repair on that environment before pushing.

## DB-35 — 308780d — validate every NOT VALID constraint in the chain

- File: `supabase/migrations/20261115150000_phase1d_validate_constraints.sql`.
- Dynamic DO block validating every unvalidated CHECK/FK constraint in
  `public`. Authoritative count was **24**, not the audit's 25 — the 1c
  payments_status_check had already been validated. Plus persistent
  `assert_no_unvalidated_constraints()` tripwire function called at the
  end of the migration.
- Verified: unvalidated count 24 → **0**.
- Convention documented (also in the runbook, DB-50): never add a NOT
  VALID constraint without validating it in the same migration.

## DB-45 — 7207893 — coach/client assignments are pending until confirmed

- Files: `supabase/migrations/20261115160000_phase1d_coach_assignment_pending.sql`,
  `tw-gym-acc-v17.js`,
  `supabase/migrations/20261115165000_phase1d_fix_assignment_profile_sync.sql`.
- `coach_client_assignments` gains `status` ('pending'|'active'|
  'ended'); status is the source of truth, `is_active` is a derived
  mirror kept in sync by trigger `trg_coach_assignment_sync_status`
  (so `can_manage_client_data`/`can_message_user`, which read
  `is_active`, enforce the pending model with no edits); `is_active`
  default flipped to false; existing rows grandfathered (is_active=true
  → 'active'); `book_coach_session` rewritten (verbatim 003 definition
  with only the assignment block changed) to create a PENDING row only
  and never reactivate an ended one (a fresh pending row is created
  instead); new RPCs `confirm_coach_client_assignment` (assigned coach
  or gym manager, pending→active) and `end_coach_client_assignment`
  (coach, client, or manager, pending/active→ended), both SECURITY
  DEFINER, PUBLIC revoked, granted to authenticated; trigger honours
  legacy direct `is_active` writes (an explicit is_active change with
  unchanged status derives status from it; on INSERT, is_active=true +
  status='pending' → 'active') so cached frontend JS keeps working.
  Frontend: `tw-gym-acc-v17.js` `assignCoachToClient`/
  `unassignCoachFromClient`/`loadAssigns` now write/read `status`
  (`node --check` clean).
- **Verification exposed a REAL pre-existing bug** (found 2026-11-15
  ~00:55, fix written as `20261115165000`):
  `sync_client_profile_assignment` (migration 006, trigger
  `trg_sync_client_profile_assignment`) did `UPDATE client_profiles
  SET gym_id = src.gym_id, coach_id = ... WHERE cp.user_id =
  src.client_id` — it reassigned the profile row to a different gym
  and touched ALL of the user's rows. The chain auto-creates a bare
  NULL-gym `client_profiles` row per auth user, so the first time any
  assignment becomes active the trigger tried to set that bare row's
  gym_id to the gym, colliding with the user's real gym row →
  `duplicate key value violates unique constraint
  "uq_client_profiles_user_gym"`. Fix: scope the UPDATE to the
  assignment's gym (`cp.gym_id = src.gym_id`), never SET gym_id, and
  scope the NOT FOUND branch (coach_id=NULL) to that gym too.
- Verified with a 17-assertion suite (DB45a–p, incl. pending on
  booking, no data access while pending, member cannot confirm, coach
  confirm opens access, second booking adds no row, manager end closes
  access, re-booking creates a fresh pending row, legacy is_active
  write activates).
- History note: a first commit attempt bundled DB-35 and DB-45 files
  together plus an empty DB-45 commit; history was fixed with `git
  reset --soft HEAD~2` and clean re-commits (308780d, 7207893) —
  nothing pushed, so no history rule was broken.

## DB-41 — f513cba — replace the blanket authenticated grant with per-table grants

- File: `supabase/migrations/20261115170000_phase1d_replace_blanket_grant.sql`.
- Revokes the 004 blanket `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL
  TABLES IN SCHEMA public TO authenticated` and re-grants each public
  table exactly the operations its RLS policies allow for the
  authenticated role (ALL-policy counts for all four; service_role-only
  policies do not count), derived dynamically from pg_policy. Tables
  with no applicable policy (`ai_proxy_usage`, `gate_rate_limits`,
  `gate_terminal_sessions`) keep no grant. Adds
  `public.assert_all_tables_have_rls()` called at the end.
- **Audit-vs-code note:** `polroles` for a PUBLIC policy is `{0}` (an
  oidvector containing InvalidOid), not an empty array — the predicate
  is `polroles::oid[] = '{0}'::oid[] OR
  'authenticated'::regrole::oid = ANY(polroles::oid[])`. A `text[] ||
  'literal'` in plpgsql resolves to array-concat and fails to parse
  the literal — use `array_append`.
- Verified with 7 assertions (DB41a–g): payments has no DELETE grant,
  service_role-only tables have no grant, payment_events is
  SELECT-only, RLS assert runs clean, and behaviourally a manager
  payment insert as the authenticated role still settles while a
  client insert is still denied by RLS.

## DB-46 — fb1ad6c — profiles/ storage objects are private by default

- File: `supabase/migrations/20261115180000_phase1d_storage_profiles_private.sql`.
- Rewrites storage policy `trainw_media_select_v17` as v18:
  `profiles/` reads now need the object owner (foldername[3] =
  auth.uid()), `manage_staff` or `manage_media` on the gym, or the
  object being a public asset; `gyms/` (branding) branch unchanged.
- **Audit-vs-code mismatch:** `milestone_photos` HAS `is_public`, but
  `media_assets` does NOT — the migration adds
  `media_assets.is_public` (default false) plus an index on
  `milestone_photos(storage_bucket, storage_path)`. The publicity
  lookup is a SECURITY DEFINER helper
  `storage_object_is_public(bucket, path)` exposing exactly one bit —
  the inline EXISTS version could not see `milestone_photos` rows at
  all, because that table's own SELECT policy hides them from plain
  members (caught by the behavioral suite).
- Verified with 9 assertions (DB46a–i): owner reads own photo, member
  cannot read another member's private photo, member can read public
  media_assets and milestone_photos of another member, manager can
  read a private photo, gym logo readable by members but not outsiders,
  is_public defaults to false, v17 gone and v18 present.

## DB-48 — dbe5f08 — gate credential lockout, 5 failures / 15 minutes

- Files: `supabase/migrations/20261115190000_phase1d_gate_credential_lockout.sql`,
  `gate-terminal.js` (label only).
- New table `gate_credential_lockouts` scoped by (gym_id,
  credential_hash, device_id) — device_id is '' when the terminal
  sends none; RLS on with no policies (service-role only, no
  authenticated grant under the DB-41 model). Helper
  `record_gate_credential_failure(gym, hash, device)` returns the lock
  expiry when the failure just locked the credential, else NULL:
  reaching 5 sets locked_until = now() + 15 min and resets the counter
  to 0 (5 attempts per 15-minute window); an expired lock restarts the
  window at attempt 1. `validate_member_credential` rewritten verbatim
  from the round-2 version (extracted programmatically from
  `20261115010000`, 336 lines) plus 4 insertions: lockout check after
  the credential advisory lock returning `{access:false,
  reason:'credential_locked', locked_until}` (logged to
  gate_access_log; denial_reason is free text, no constraint change
  needed); failure recorded only on the invalid-credential branch (a
  valid credential denied for membership reasons never locks a
  legitimate member out); success clears the counter. The gate-checkin
  edge function passes the new reason through unchanged. Label added:
  `credential_locked: 'Badge verrouillé — réessayez dans 15 minutes'`.
- Verified with 11 assertions (DB48a–j): 4 failures →
  invalid_credential and counter 4; 5th → credential_locked with a
  15-minute lock; still locked on re-presentation; the legitimate
  member's own credential still grants access while another is locked
  and its pre-seeded failure row is cleared by the success; expiry
  restarts the window at 1 attempt; table has RLS with no authenticated
  grant; helper is not executable by authenticated.

## DB-50 — 068f135 — data repairs get a log, a runbook, and a dry-run audit

- Files: `supabase/migrations/20261115200000_phase1d_data_repair_log.sql`,
  `docs/DATA_REPAIR_RUNBOOK.md`, `scripts/data-repair-audit.sql`.
- Service-role-only `public.data_repair_log` table: performed_at/by,
  gym_id, table_name, row_id, action, reason, row_snapshot jsonb,
  runbook_ref. Runbook rule: a migration never performs destructive
  data repair; procedure backup → dry-run → review → logged repair →
  re-audit; template joins the repair to the log rows just written.
  The audit script is a read-only dry-run: generic FK orphan audit
  over every FK in `public` + the three 003 overlap rules + the DB-62
  signup-gap check; exits 0 when clean, non-zero with the full report
  otherwise.
- Verified on the throwaway cluster (`/tmp/r4-db50-test.sql`): clean DB
  audits exit 0; a seeded orphan + duplicate availability +
  conflicting session pair are reported as exactly 1 row each (plus
  conflicting_availability 1) with a non-zero exit; after cleanup the
  audit is clean again. Seeding the overlap rows needed triggers off
  (`SET session_replication_role = replica`) — the write validators now
  reject overlaps, so such rows can only arise from legacy data or
  direct SQL; seeding also needed `users.role = 'coach'` (the
  availability validator requires it) and a `coach_profiles` row.

## DB-61 — cd4e37a — freeze the RLS helper functions

- File: `supabase/migrations/20261115210000_phase1d_freeze_rls_helpers.sql` (753 lines).
- Re-creates 30 RLS helpers verbatim as they stand after the full
  chain, plus `public.assert_rls_helpers_frozen()`, which compares each
  helper's live definition against a frozen hash and raises on drift.
  The hash is over stored catalog values (signature, result type,
  language, volatility, SECURITY DEFINER, proconfig, body prosrc) —
  NOT over pg_get_functiondef output, whose rendering can differ
  between Postgres versions. Freeze set: every function the RLS
  policies call plus transitive dependencies (computed from pg_policy +
  pg_proc on the applied chain — this surfaced helpers the audit did
  not name, e.g. `get_my_portal`, `current_membership`,
  `permission_codes_for_membership`,
  `caller_holds_permission_in_gym`, `caller_manages_gym_direct`,
  `get_my_permissions`), plus the four access helpers the audit names
  or the gate relies on (`can_view_user`,
  `client_membership_is_active`, `membership_is_active_for_access`,
  `lock_booking_key`). Definitions are topologically ordered so a
  function is created after the functions it calls.
- Verified with 36 assertions (DB61a–aj): the freeze assert passes on
  the applied chain; a behavior matrix over manager/member/coach/
  outsider callers (`manages_gym`, `has_permission`, portals, roles,
  `can_view_user`, `can_manage_client_data`, `can_message_user`,
  `can_manage_sessions`, `auth_user_email`, workout-log access); and a
  tamper check — redefining `can_view_user` to always true is detected
  by the assert. (The coach matrix rows needed the DB-45 assignment
  ended first — DB-45 left it active — via
  `end_coach_client_assignment` called as the manager.)
- **Known freeze gap (follow-up):** the hash does not cover a
  function's DEFAULT expressions (`proargdefaults` is not in the
  formula) — a default-only change would slip past the tripwire. DB-37
  changed the membership helpers' defaults AND bodies, so the hashes
  did change there, but the gap stands.

## DB-27 + DB-28 — 51b0bef — close the direct booking/session write paths

- File: `supabase/migrations/20261115220000_phase1d_booking_session_write_scoping.sql` (183 lines).
- DB-27: `bookings_manage_v17` was FOR ALL for any row where
  client_id/coach_id = auth.uid(), with no session/gym/transition
  checks — replaced with three manager-only policies
  (`bookings_insert_v18` / `bookings_update_v18` /
  `bookings_delete_v18`, all `has_permission('manage_bookings',
  gym_id)`); read policy unchanged; safe because session RPCs and
  `sync_booking_from_session` are SECURITY DEFINER, and the frontend
  writes no bookings directly (verified by grep in JS and TS/edge
  code). New trigger `validate_booking_consistency` (BEFORE INSERT OR
  UPDATE on bookings, SECURITY DEFINER): linked session must exist and
  gym_id/client_id/coach_id must match it (null-safe `IS DISTINCT
  FROM`).
- DB-28: `sessions_update` coach branch could UPDATE any column — new
  trigger `validate_session_coach_update` (BEFORE UPDATE on sessions,
  SECURITY DEFINER): when the caller IS the session's own coach acting
  directly, gym_id/client_id/coach_id/payment_id are frozen and status
  may only move along the RPC transitions (pending→confirmed/cancelled,
  confirmed→completed/cancelled/no_show); managers keep full edit
  rights; a caller who is neither manager nor the session's coach never
  reaches the trigger directly (the policy blocks them first), so such
  updates can only be SECURITY DEFINER RPCs working on someone else's
  behalf — `book_coach_session` sets payment_id as the member — and the
  trigger lets those through (the first version raised for that case
  and broke booking; the test caught it). The assignment-check
  alternative was NOT implemented: legacy and manager-created sessions
  can exist with no assignment row, and the RPC path does not check
  assignment either.
- Verified: 20-assertion suite `/tmp/r4-tests-db27.sql` (DB27a–j,
  DB28a–j), all passing, incl. RPC flow end to end (book → respond →
  complete, booking kept in sync). The suite also documents that
  `validate_session_write` (003) already blocks future completion and
  cross-gym moves, so the DB-28 tests use a past date + a same-gym
  client swap to isolate the new trigger.

## DB-37 — 4815c57 — compute 'today' in the gym's timezone

- File: `supabase/migrations/20261115230000_phase1d_gym_timezone.sql` (1,265 lines).
- New helpers `gym_timezone(p_gym_id)` (gyms.timezone, Africa/Tunis
  fallback) and `gym_today(p_gym_id)` (`(now() AT TIME ZONE zone)::date`).
  Rewired: `membership_is_active_for_access` /
  `client_membership_is_active` (reference date now defaults to NULL =
  the gym's today; an explicit date is still honoured),
  `validate_member_credential` (gate's same-day duplicate day),
  `validate_session_write`, `book_coach_session` (past check now uses
  the gym's day AND clock), `complete_session_booking`,
  `get_bookable_slots` (date filter), `shift_membership_for_freeze`,
  and the manual check-in guard (drops the explicit CURRENT_DATE).
  `check_ins.checked_in_date` was a GENERATED column in UTC — a
  generated column cannot read another table, so it is now a plain
  column set by a BEFORE INSERT/UPDATE trigger in the row's gym
  timezone, with a backfill and a re-dedup for live data (two rows that
  were different UTC days can land on the same gym day). DB-61 freeze:
  the two membership helpers are frozen, so their hashes are updated
  in this migration (assert re-created with the new hashes, then run).
- Deliberately unchanged: ai-proxy quota day (per-user UTC day), the
  ledger's invoice/period dates (business dates, explicit dates
  passed), `client_profiles.membership_start_date` default (a column
  default cannot see the row's gym), and `get_bookable_slots`' naive
  slot timestamps compared to now() (date filter fixed; generating
  slots in the gym timezone is a follow-up).
- Verified: full chain applies end to end on a fresh throwaway cluster
  (only the known by-design B5 failure); 8-assertion DB-37 suite
  (`/tmp/r4-tests-db37.sql`, Kiritimati/Midway gyms so the timezone
  path is exercised — 23:30 UTC stamps 11-16 in Tunis and Kiritimati,
  11-15 in Midway; the membership 'gym yesterday' case notes when it
  discriminates from UTC at run time) plus the prior suites — 82 + 20
  + 8 = 110 PASS. Builder script: `/tmp/build-db37.py` (extracts
  verbatim definitions, applies surgical replacements, fails loudly on
  a missing pattern).

## DB-38 — 35f9b1b — forbid deleting a gym that still holds tenant data

- File: `supabase/migrations/20261115240000_phase1d_gym_delete_guard.sql`.
- BEFORE DELETE trigger on gyms raises when the gym still has payments,
  member profiles, sessions, check-ins, or coach profiles, naming the
  blocking category and count; an empty gym (only the owner's
  membership row) still deletes. RLS already denies gym DELETEs for
  authenticated users (no gyms DELETE policy), so the trigger is the
  backstop for service-role / direct-SQL deletes. A second BEFORE
  DELETE trigger on users replaces the opaque payments-client FK
  violation with a clear 'cannot_delete_user: user still has N
  payment(s)' error.
- **Deferred to the soft-delete work:** `messages.sender_id`/
  `receiver_id` are NOT NULL... ON DELETE CASCADE, so deleting a user
  still erases the other party's copy of the conversation — fixing
  that needs nullable columns plus chat UI handling for a deleted
  counterpart.
- Verified: 5-assertion suite (`/tmp/r4-tests-db38.sql`) + prior
  suites = 115 PASS.

## DB-52 — 939a063 — migration conventions doc (never copy the 004 RLS reset)

- File: `docs/MIGRATION_CONVENTIONS.md` (docs only).
- 004 drops every policy on 24 tables in a loop and only recreates
  them afterwards; a mid-file failure would leave RLS enabled with
  zero policies (deny-all, including managers). It cannot be fixed
  without editing 004, which is already applied everywhere. Mitigation
  documented: the Supabase CLI applies each migration file inside a
  single transaction by default (the `-- pg-delta: transaction=false`
  directive exists precisely to opt OUT of that wrapping — verified
  against Supabase docs via browser search 2026-11-15), so a mid-file
  failure rolls the whole file back. Rules for new work: never write a
  drop-all-then-recreate loop again (drop and recreate one table's
  policies together), do not assume the dashboard SQL editor wraps a
  script the same way (confirm it, or apply through the CLI), do not
  edit 004. The doc also consolidates the conventions rounds 1–4
  established (never edit an applied migration; one logical piece per
  migration; no destructive data repair in migrations per DB-50; NOT
  VALID constraints validated in the same migration per DB-35; RLS +
  policies + grants shipped together per DB-41; frozen-helper hash
  updates in the same migration as the change per DB-61, with the
  known gap that the hash does not cover DEFAULT expressions;
  throwaway-cluster verification before committing; gym-timezone
  'today' per DB-37).

## DB-57 + DB-64 — 5026f91 — specialties are seed-only; coach specialties scoped to the coach's gym

- File: `supabase/migrations/20261115250000_phase1d_specialty_scoping.sql`.
- DB-57 writer decision: **seed-only**. The audit offered 'add a policy
  plus a validated RPC, or document them as seed-only tables' —
  seed-only is right because nothing in the app reads or writes these
  tables: the frontend's specialty mechanism is the free-text
  `coach_profiles.specialty` column, and the only writer anywhere is
  `supabase/seeds/trainw_demo_seed.sql` (tags 'Strength &
  Conditioning', 'Mobility'). No INSERT/UPDATE/DELETE policy is added
  for either table, and under the DB-41 grant model authenticated holds
  no write grant on them either. `specialty_tags` stays a GLOBAL
  curated list (name citext UNIQUE, no gym_id); per-gym tags would need
  a gym_id column plus policies + RPC + frontend wiring, noted as
  future work.
- DB-64: a BEFORE INSERT OR UPDATE trigger
  `validate_coach_specialty_write` enforces
  `coach_specialties.gym_id` = the coach's gym (users.gym_id, falling
  back to coach_profiles.gym_id); NULL is filled in; a mismatch raises
  `specialty_gym_mismatch`; a gym-less coach keeps NULL. The demo seed
  is safe: its coach (Youssef Trabelsi) belongs to the gym its rows use.
- Verified: 5-assertion suite (`/tmp/r4-tests-db57.sql`) + prior
  suites = 120 PASS. **Test-harness note:** the throwaway cluster never
  granted service_role table access (real Supabase does), so the DB-57
  suite grants it in test setup to mirror production.

## DB-59 — ef50720 — session history stays readable by its participants after the session is deleted

- File: `supabase/migrations/20261115260000_phase1d_session_history_snapshot_policy.sql`.
- The SELECT policy on `session_status_history` (now `_v18`) keeps the
  manager branch and the live-session branch and adds a snapshot
  branch: `(session_snapshot->>'client_id')::uuid = auth.uid() OR
  (session_snapshot->>'coach_id')::uuid = auth.uid()`.
  `log_session_status_event` stores `to_jsonb(NEW)`/`to_jsonb(OLD)`,
  so the snapshot always carries the session's client/coach ids; the
  branch reveals a row only to the exact client/coach named in it, and
  rows with a null snapshot fall back to the live-session branch as
  before.
- Not decided here: a retention rule for orphaned history (rows whose
  session is long deleted accumulate forever) — needs a retention
  period decision.
- Verified: 6-assertion suite (`/tmp/r4-tests-db59.sql`, booking setup
  mirrors the DB-27 fixtures) + prior suites = 126 PASS.

## DB-62 — 37661c1 — let the signup trigger fail loudly

- File: `supabase/migrations/20261115270000_phase1d_signup_trigger_fail_loud.sql`.
- `handle_new_user()` swallowed every error (`EXCEPTION WHEN OTHERS
  THEN RAISE LOG...; RETURN NEW`), so a failed profile creation never
  failed the signup. The `users_insert` half of DB-62 was already done
  in round 2 (a self-insert may only create role='client' with gym_id
  NULL); this migration removes the blanket handler, so an unexpected
  error now fails the signup (the auth.users INSERT rolls back and the
  caller sees the error). The audit's alternative — alert on the log
  line — needs a monitoring setup that does not exist yet (P2-7).
  Removing the handler is safe for legitimate signups: the users write
  is an ON CONFLICT upsert, the profile write is guarded by IF NOT
  EXISTS, and the profile's NULL gym_id cannot unique-violate (NULLs
  are distinct in the (user_id, gym_id) unique index). The DB-50
  data-repair audit already detects any auth user with no public row.
- Verified: 4-assertion suite (`/tmp/r4-tests-db62.sql`: handler gone
  from the source, signup still provisions, gym_owner self-insert
  denied, gymless client self-insert allowed — the round-2 policy half
  behaviorally tested for the first time) + prior suites = 130 PASS.
- **Round-4 follow-on (P2-9):** the consent parse in this trigger was
  first written with a scoped `EXCEPTION WHEN OTHERS` block, which
  tripped the DB-62 source-text tripwire (any `WHEN OTHERS` in the
  function fails DB62a). It was rewritten to validate with
  `pg_input_is_valid()` before casting — no exception block at all —
  and DB-62 passes 4/4 again. Lesson: keep this trigger free of
  exception handlers entirely.

## NX-10 — ddcc274 — update/delete/deactivate actions for clients, coaches, classes, attendance, roles, staff users (16 files)

- Server actions follow the existing pattern (requirePermission → zod
  parse → gym-scoped query → revalidatePath). Clients: update (name/
  type); coaches: update (name/rating, NX-16 clamp) + delete (ON DELETE
  RESTRICT message when classes reference the coach); classes: update
  (incl. NX-04 coach check) + delete (enrollments cascade, attendance
  class_id SET NULL) + unenroll one client; attendance: update
  (status/class) + delete; roles: update (name + permissions JSON, flat
  object of real booleans only — NX-17 alignment; owner role editable
  only by an owner) + delete (refuses owner role, caller's own role,
  roles still held by staff); staff users: deactivate (auth ban ~100y
  via `ban_duration: "876000h"`), reactivate (`ban_duration: "none"`
  — confirm at deploy, GoTrue admin API), delete (admin deleteUser,
  cascades to public.users; refuses self and last gym owner). Six
  row-action components wired into coaches/classes (incl.
  per-enrollment ×)/attendance/roles pages following ClientRowActions;
  `getRolesPageData` now reports `banned` per user via admin listUsers
  (gated on `isSupabaseAdminConfigured()`, failures swallowed). Edit
  (update) actions exist as server actions only — prefilled inline edit
  forms are a UI follow-up (no edit-form pattern exists on any page yet).
- Verified: esbuild transpile-only syntax check on all 16 files.
- **Context (code as found):** the Next.js app runs on the archived
  `database/archive/schema.sql`. `clients` has no `status` column in
  that schema, yet the approve action, the public-clients route, and
  `getClientsPageData` all assume one — a pre-existing schema gap,
  P2-10 territory, not NX-10's to redesign.

## NX-14 — 9758462 — password-reset flow (7 files)

- `requestPasswordResetAction` (resetPasswordForEmail →
  /auth/reset-password, rate-limited like login/signup 5/15min,
  identical reply whether the email exists or not — no user
  enumeration); `updatePasswordAction` (min 8, max 128, must match, via
  updateUser on the session the reset page exchanges the link code
  for); `/forgot-password` page + form; `/auth/reset-password` page
  (exchanges the PKCE code, shows the form or an expired-link message);
  "Forgot your password?" link on the login page; roles.ts NX-09 note
  now points invited staff at the reset flow.
- Dashboard config still needed at deploy: /auth/reset-password must
  be allowlisted in Supabase (Authentication > URL Configuration >
  Redirect URLs).
- Verified: esbuild syntax check on all 7 files.

## NX-24 — c64c0a4 — real Next.js dependencies, pinned; tsc + next build pass (5 files + package-lock.json)

- package.json had zero dependencies. Pinned: next 15.5.29,
  react/react-dom 19.3.1, @supabase/ssr 0.12.7, @supabase/supabase-js
  2.119.0 (same as static frontend's CDN pin), zod 3.25.76,
  lucide-react 1.73.0 (same as static pin), clsx 2.1.1, tailwind-merge
  3.7.0; dev: typescript 5.9.3, @types/node 24.19.2, @types/react
  19.3.0, @types/react-dom 19.3.0, tailwindcss 3.4.19 (v3 — config +
  postcss are v3), postcss 8.5.33, autoprefixer 10.6.2. Deliberately
  NOT the newest majors: next 16 (latest 16.4.6), zod 4 (latest 4.6.7),
  typescript 7 (latest 7.0.2), tailwind 4 (latest 4.3.5) would need
  migration work. Scripts added: next:dev / next:build / next:start /
  typecheck. Existing build/dev scripts UNTOUCHED — they build the
  static frontend Vercel deploys today; switching the deploy to Next
  is the P2-10 decision. tsconfig: removed the stale root `middleware.ts`
  include entry (file lives at src/middleware.ts, already covered by
  src/**/*.ts). package-lock.json committed.
- **Two real bugs tsc found (first full type-check ever run on this
  app):** the users → roles embed does not type-check — the archived
  schema's FK is composite (role_id, gym_id) → roles (id, gym_id),
  which the generated Database type does not express as a relation, so
  `role:roles(id, name)` typed as SelectQueryError. Fixed by joining
  in JS from the already-loaded roles list (queries.ts) and by a
  separate role-name lookup (roles.ts getStaffUserInGym /
  countOwnersInGym).
- Verified in a scratch copy (not the repo): npm install clean (119
  packages), tsc --noEmit exit 0, next build exit 0 — all 16 routes
  compile, including /auth/reset-password and /forgot-password.
- **Cosmetic defect in this commit's message:** the backticked
  `` `role:roles(id, name)` `` fragment was eaten by shell quoting
  ("so typed as SelectQueryError"). Left as-is (no amends allowed).

## NX-17 — ae3d158 — strict boolean permission checks (value === true)

- **Round-2 notes claimed this was already clean — it was not:**
  `Boolean(value)` was still in workspace.ts:38, queries.ts:110, and
  the actual gate permissions.ts:24 `hasPermission` (`Boolean("false")`
  is true, so a role whose permissions JSON was ever written with
  string values would be granted a permission the DB-side
  `has_permission` denies). All three sites now use `value === true`.
  `normalisePermissions` in queries.ts exported for the NX-26 tests.
- **Commit attribution quirk:** the NX-18 `requirePermission`
  redirect change (to /forbidden) also landed in this commit because
  workspace.ts was staged with both edits — the code is correct, only
  the attribution is mixed; noted, not rewritten.

## NX-18 — 77f7600 — dedicated /forbidden page

- `requirePermission` sent denied users to /dashboard?forbidden=1, but
  the dashboard itself requires `dashboard.view`, so a role without it
  looped until the browser reported too many redirects. Denied users
  now go to /forbidden (plain page, no permission, no workspace data —
  gating it would recreate the loop); the dashboard's now-dead
  ?forbidden=1 banner removed.

## NX-27 — df65ee4 — login page redirects signed-in users to /dashboard

- Via getUser() — later refined by NX-28 (see below) to send orphans
  to /auth/recover instead.
- **Round-2 notes claimed NX-27 "verified already clean" — false;**
  the login page had no authenticated redirect until this session.

## NX-29 — d796676 — client codes are display-only, never proof of identity

- File: `docs/CLIENT_CODES.md`. Grep-verified: no flow accepts a bare
  client code — Next app only displays codes, gate terminal sends an
  opaque QR token, gate-checkin has no client_code reference at all.
- **Lengthening the generator is moot on the chain:** the generator
  (`generate_unique_client_code` + `set_client_code` trigger) lives
  only in the archived schema.sql; the migration chain has no
  client_code column, generator, or trigger (P2-10 schema gap).

## NX-28 — 64ae9b6 — self-healing path for orphaned accounts (4 files)

- A confirmed auth user whose provisioning died halfway (signup →
  callback RPC failure) could sign in but was bounced to /login
  forever — and NX-27's login redirect would have turned that into a
  /login ↔ /dashboard loop. Now: `/auth/recover` page (signed-in user
  with no workspace row; users WITH a workspace never see it) offering
  re-run provisioning (`recoverWorkspaceAction`, same
  `provision_new_gym` RPC the callback uses; gym name from the form
  when signup metadata lacks it; guarded to redirect /dashboard when
  the row already exists) or self-delete (`deleteOwnAccountAction`,
  orphan-only — refuses when a workspace row exists, so a gym can never
  be orphaned by a self-delete; needs the admin client). Login page: a
  signed-in user goes to /dashboard only when they HAVE a workspace;
  orphans go to /auth/recover.
- Verified: esbuild syntax check on all 4 files. Live test (kill a
  signup mid-provision, then recover) needs the deployed app +
  Supabase (P1-13 item).

## NX-25 — 07c3d97 — remove `as any` casts; generated types now carry real relationships (9 files)

- Every `as any` in src/ is gone (25 lint errors → 0). Root causes,
  both in the generated types: (1) `src/types/database.ts`
  `TableDefinition` defaulted Relationships to a bare `Relationship[]`,
  so the type listed NO relations at all and supabase-js typed every
  embedded select as SelectQueryError — which is why the queries were
  full of `(entry: any)` and `createServerSupabaseClient() as any`.
  TableDefinition now takes relations as a 4th type argument, and every
  table carries its real foreign keys from the archived schema
  (including the composite ones: `classes_coach_gym_fk`,
  `users_role_gym_fk`). The embeds now type-check. (2) The queries'
  `(entry: any)`/`(item: any)` annotations and the actions' client
  casts deleted; tsc passes with the real types. Also folded in: the
  duplicated `normalisePermissions` (workspace.ts + queries.ts) is now
  one exported function in permissions.ts; the two `{}` empty-object
  types in database.ts became `Record<string, never>`; unused
  NextResponse import removed from middleware.ts.
- Verified in a scratch copy: tsc exit 0, eslint exit 0, vitest 25/25,
  next build exit 0.

## NX-26 — 43a4531 — CI with type-check, lint, smoke tests, production build (13 files)

- vitest 3.2.7 + 25 smoke tests in 6 files, all passing with no
  database and no network: permission gate (NX-17 strict-true cases),
  rate limiter (allow/block/window-slide/IP parsing), auth zod schemas
  (login/signup/reset/update/recover), CAPTCHA fail-open, GET
  /api/health (no adminConfigured leak, NX-07), GET /api/gyms/search
  (validation paths, generic 503, 30/min rate limit). Auth schemas
  moved to `src/actions/auth-schemas.ts` so tests can import them
  without pulling in next/headers or Supabase clients. eslint 9.39.5 +
  eslint-config-next 15.5.29 + @eslint/eslintrc 3.3.7 (FlatCompat — the
  15.x configs are legacy eslintrc, not flat arrays; the extensionless
  imports the Next docs show do not resolve because the package ships
  no `exports` map). `.github/workflows/ci.yml`: two jobs — next-app
  (npm ci, typecheck, lint, test, next:build with dummy Supabase env)
  and static-app (npm run verify). package-lock.json updated.
- Verified in a scratch copy: npm ci clean, tsc exit 0, eslint exit 0,
  vitest 25/25, next build exit 0, npm run verify passes. Live
  Supabase paths (actions against a real DB, email delivery) stay
  P1-13 items.

## FE-27 — d9400e5 — dead-code purge (6 files)

- (a) `tw-client-pilot.js` deleted (loaded by no HTML — verified by
  grep; only the audit doc and the verify script listed it). It
  duplicated tw-client-acc.js with a weaker `Math.random()` gate token
  and a reset-password handler that toasted success without checking
  the result. Removed from scripts/verify-trainw.js and from dist/.
- (b) tw-client-acc.js: renderProgram/renderWeight/
  renderPersonalRecordsTable were defined 3×/3×/2× (the audit said 3×
  each — PRT is only twice). Kept the last definition of each (what
  always ran) and deleted the first copies (lines 241–245). Runtime
  behaviour unchanged by construction; the earlier copies were
  mojibake-corrupted variants.
- (c) trainw-core.js: `callEdge` (ai-proxy caller) deleted — exported
  as `Trainw.api.edge` but called nowhere; the api export drops the
  `edge` key.
- (d) tw-gym-acc.js: `legacyInitDisabled()` deleted (defined, never
  called).
- (e) tw-gym-acc-v17.js `wrap()` replaced with explicit hooks: a
  `window.TrainwGymHooks` registry + `runGymHooks()` in tw-gym-acc.js,
  with hook calls at the end of loadClients/loadAnalytics/loadCoaches
  (awaited) and setLang (fire-and-forget, as before); the v17 file only
  registers its extras (`registerV17Hooks()`). The one openCoachModal
  call site (tw-gym-acc.js:5434) now prefers `window.openCoachPanel`
  when present, falling back to the base modal. Behaviour note: hooks
  run at the end of the main body only, so a loader that bails early
  (no gym/element) now skips its extras — the old wrapper ran them
  anyway. Strictly more correct, no visible change.
- Verified: node --check on all 5 touched files, grep confirms no
  tw-client-pilot/callEdge/legacyInitDisabled/wrap() references remain
  (except the historical audit doc), each renderer defined exactly
  once, npm run verify passes. dist/ copies of the 4 edited JS files
  synced (dist is gitignored and rebuilt at deploy; **the rest of dist
  is stale since round 1** — pre-existing, fixed by the deploy-time
  rebuild; the tw-coach-acc.js root-vs-dist diff is 40 lines of
  round-2 code changes, no URL/key injection in JS files).

## FE-09 + GT-05 — 3e91643 — QR tokens are opaque 128-bit random strings (3 files)

- The gate QR token was `${userId}.${gymId}.${Date.now()}.${random}` in
  cleartext. Now the client generates a single opaque token (16
  crypto-random bytes, 32 hex chars, `randomGateToken()` in
  tw-client-acc.js; the member/gym live only on the `gate_sessions`
  row). The handler (`supabase/functions/gate-checkin/handler.mjs`)
  rejects the legacy dotted format outright, drops the
  `token.split('.')` parse and its cross-checks (the row's client_id
  and gym_id are authoritative), and logs only a `qr:` + 8-char prefix
  of the token instead of the full live bearer. The membership RPC call
  also drops its explicit `p_reference_date` (DB-37 follow-up: the RPC
  default is now the gym's today; the handler was passing the server's
  UTC date). The terminal forwards the scanned text verbatim and needed
  no change; the pilot file's Math.random token is already gone
  (FE-27). The unique index on `gate_sessions.token` already existed
  (`uq_gate_sessions_token`, 002:1248), so no migration was needed.
  `docs/HARDWARE_INTEGRATION.md` updated (token is a 32-hex-char
  opaque string; legacy dotted format rejected).
- Verified: node --check on both files; the generator run standalone
  produces 10,000 tokens, all 32 hex chars, no dots, no collisions;
  grep confirms no token.split/tokenParts/legacy-format references
  remain outside the historical audit doc. A live end-to-end scan still
  needs the deployed edge function (P1-13).

## FE-18 — 1a3075c — double-submit guards on the unguarded mutating actions (4 files)

- The audit named cancelSession/submitSessionReview (client), savePlan
  (coach), updateCoachApproval (pilot), and deleteSession/deleteClient/
  deleteCoach (gym) as having no busy guard. All now use the
  established `Trainw.ui.setBusy` pattern where a button exists, or a
  module-level in-flight Set keyed on action + row id where the buttons
  are rendered per row: client cancel/review (`cancel:<id>` /
  `review:<id>`), gym deletes (`delete-session/client/coach:<id>`),
  coach savePlan (both save buttons disabled for the whole save,
  re-enabled in finally), pilot approval (per-profile Set + the clicked
  button disabled). Every guard is released in a finally, so a failed
  request never leaves the UI stuck.
- **Repair during this piece:** the first coach edit nested a new
  `try{` around the original try without a handler — node --check
  caught it ("Missing catch or finally after try"); fixed by attaching
  the finally to the original try instead.
- Verified: node --check on all four files; `npm run verify` passes.
  Note: the guards are client-side only. Server-side idempotency for
  reviews (a unique index + upsert) is a separate hardening item, not
  built here.

## FE-17 — beae6c0 — clamp calcEndDate to the target month's last day, in UTC

- File: `tw-gym-acc.js:3142` (`calcEndDate`, used at :3593 edit client
  and :3734 new client submit to compute `membership_end_date`).
- `setMonth()` overflowed Jan 31 + 1 month to Mar 2/3, and the old code
  mixed local getters with toISOString() (UTC), shifting the date
  around midnight in Africa/Tunis. All math is now in UTC on the
  date-only value, and the day is clamped to the target month's last
  day (Jan 31 + 1 month = Feb 28, Feb 29 in a leap year; Feb 29 + 1
  year = Feb 28).
- Verified: node --check; the function run standalone over 9 cases
  (month-end, leap year, quarterly, annual, year rollover, basic tier
  returns null) — all pass.

## FE-30 — 926a59a — inferClientGymId only counts live gym ties

- File: `tw-client-acc.js:41`.
- The client gym was inferred from the newest assignment/session/
  check-in row with no status filter, so a pending or ended coach
  assignment — or a cancelled/completed session from a gym the member
  left — could pick the wrong gym. The assignment query now requires
  status='active' (the DB-45 pending model) and the sessions query only
  counts pending/confirmed sessions. Check-ins are left as-is: a
  check-in is evidence of access, and the server-side getContext check
  is what actually authorises the gym.
- Verified: node --check.

## FE-26 — b4bcef7 — cap chat messages at 2,000 characters

- Files: `tw-gym-acc.js`, `tw-client-acc.js`, `tw-coach-acc.js` (+
  their HTML textareas),
  `supabase/migrations/20261115280000_phase1d_message_length_cap.sql`.
- The three chat send paths (gym sendMessage, coach sendCoachMessage,
  client sendClientMessage) accepted unbounded text and inserted it
  into messages.content (text, no length CHECK). Now each path blocks
  an over-long message with a toast (never silently truncates), the
  three textareas carry maxlength=2000, and a new validating CHECK on
  messages (char_length(content) <= 2000) is the backstop for any other
  writer. The RPC-based conversation lookup was skipped per the
  audit's own 'if time permits' — the message insert already lands on
  a gym-scoped, policy-checked table.
- Verified: node --check on the three JS files; throwaway Postgres
  cluster, full chain applies (46 OK, only the known by-design B5
  failure), 2-assertion suite (`/tmp/r4-tests-fe26.sql`): a 2,000-char
  message is accepted, a 2,001-char one is rejected by the CHECK; the
  130 prior assertions still pass. Test-harness note: the message
  gym-consistency trigger (`enforce_message_gym`, DB-53) requires a
  `gym_memberships` row with status 'accepted'/'active' for both
  parties (or the sender being the gym manager) — the suite seeds
  those rows plus a roles row (gym_memberships.role_id is NOT NULL).

## FE-24 — d115a92 — say in the invite UI that the invitee needs a Trainw account first

- Files: `tw-gym-acc.js`, `tw-gym-acc.html`.
- Staff invites call signInWithOtp({shouldCreateUser:false}), so the
  invite only works when the person already has a Trainw account;
  otherwise it fails with a vague error (mapped by
  isInvitationAuthLookupError). The invite card now states the
  prerequisite under its subtitle (fr/en/ar), so a manager learns it
  before submitting instead of after a failed invite.
- Verified: node --check; the key exists in all three language blocks
  and the HTML carries the data-i18n binding.

## FE-25 — fde5414 — explicit emailRedirectTo on password resets, generic errors

- Files: `tw-login.js`, `tw-client-acc.js`, `tw-coach-acc.js`,
  `tw-gym-acc.js`.
- All four static-app resetPasswordForEmail calls (login
  forgot-password, client reset, coach reset, gym changePassword) now
  pass emailRedirectTo: origin + '/tw-login.html', so the recovery
  link lands on the page that handles the recovery session (getContext
  with recoveryRole) instead of whatever Supabase's dashboard default
  is. The gym changePassword flow also stopped surfacing the raw auth
  error message (which can name the account state) — it now shows the
  generic error toast; the login forgot-password already used the
  generic mapAuthError, and the client/coach buttons already swallowed
  errors silently. The Next.js reset flow (NX-14) already passed its
  redirect.
- Deploy note: /tw-login.html must be allowlisted in Supabase
  (Authentication > URL Configuration > Redirect URLs), same as the
  NX-14 /auth/reset-password entry.
- Verified: node --check on all four files; grep confirms no
  resetPasswordForEmail call outside dist/ lacks emailRedirectTo.

## FE-28 — 2e3ee4f — targeted i18n for the hardcoded strings + gate admin modal a11y

- Files: `tw-gym-acc.js`, `gate-terminal.js`, `gate-terminal.html`.
- Seven hardcoded French strings in tw-gym-acc.js now come from the T
  dicts (fr/en/ar): the expiring-members stat label and its '14
  prochains jours' delta, the schedule tab labels, the coach-search
  hint and 'Recherche en cours' status, and the two credential-list
  empty states. The gate admin modal is now a real dialog
  (role=dialog, aria-modal, labelledby), its ambiguous keypad keys
  carry aria-labels (Effacer/Valider), and openAdminModal traps Tab
  inside the modal, closes on Escape, syncs aria-hidden, and restores
  focus to the element that opened it.
- Note: the audit's fifth cited string (:4265) could not be located by
  its text — the strings found in the same functions were fixed
  instead; no hardcoded occurrence of any of the named strings remains
  outside the dicts.
- Verified: node --check on tw-gym-acc.js and gate-terminal.js; grep
  confirms no remaining hardcoded occurrence of the named strings
  outside the T dicts.

## FE-29 — 1e42a62 — gate terminal tells the truth about offline and dead modes

- File: `gate-terminal.js`.
- Three fixes: (1) a fetch/network failure in handleQrScan is no
  longer rendered as camera_error — safeReason now maps 'Failed to
  fetch' / NetworkError / 'Load failed' to a new network_error reason
  ('Réseau indisponible — vérifiez la connexion'); (2) the online
  indicator now reflects real connectivity (navigator.onLine) AND the
  Realtime subscribe state, with window online/offline listeners, so an
  offline terminal reads 'Hors ligne — pas de connexion' instead of
  claiming Realtime is connected; (3) the RFID/fingerprint/face mode
  buttons have no local handler — setMode only stopped the QR scanner
  for them — so they are disabled with a title saying an external
  reader is required, instead of implying they scan. GT-04's offline
  allow-list stays out (needs ESP32 firmware, not in the repo).
- Verified: node --check; the safeReason network patterns run
  standalone over 8 cases (Chrome/Firefox/Safari messages, known
  reasons, null) — all pass.

## NX-12 — 995f12f — paginate the dashboard lists (50/page)

- Files: `src/lib/pagination.ts` (new), `src/lib/__tests__/
  pagination.test.ts` (new), `src/lib/queries.ts`,
  `src/components/ui/pagination.tsx` (new), the five dashboard pages
  (clients, coaches, classes, attendance, roles).
- The five page-data queries fetched unbounded lists (a gym with
  hundreds of members rendered them all). Each now takes a page param
  (default 1, parsed and clamped by parsePageParam) and fetches one
  page with .range() plus one extra row, so hasMore is known without a
  count query. The five pages read ?page=N from searchParams (Next 15
  async pattern) and render a prev/next Pagination component under the
  list. The attendance page's old .limit(20) is now 50/page.
- The form-select lookups inside getClassesPageData (coaches/clients)
  and getAttendancePageData (classes/clients) stay unbounded on
  purpose: they populate selects, not rendered lists, and PostgREST
  already caps any single response at 1,000 rows. A searchable select
  is a P2 UI item. The roles list itself is not paged (a gym has a
  handful of roles); only the staff users list is.
- Verified in a scratch copy: npm install clean, tsc --noEmit exit 0,
  eslint exit 0, next build exit 0 (all five paged routes compile),
  vitest 31/31 (25 prior + 6 new pagination tests).

## P2-9 — 5f7deb5 — privacy basics: consent timestamp, data export, draft policies

- Files: `supabase/migrations/20261115290000_phase1d_privacy_basics.sql`,
  `tw-login.js`, `tw-login.html`, `src/actions/auth-schemas.ts`,
  `src/actions/auth.ts`, `src/components/auth/signup-form.tsx`,
  `src/lib/__tests__/auth-schemas.test.ts`,
  `docs/PRIVACY_POLICY.md`, `docs/TERMS_OF_SERVICE.md`.
- `client_profiles.consent_given_at` records when the user accepted
  the privacy terms at signup. Both signup surfaces (static tw-login
  and the Next.js gym-owner form) now require the checkbox and send
  `consent_given_at` in the signup metadata; `handle_new_user()`
  (rewritten verbatim from the DB-62 version, extracted
  programmatically by `/tmp/build-p2-9.py`) stores it, validating with
  `pg_input_is_valid()` before casting so no EXCEPTION block is needed
  — DB-62's no-blanket-handler tripwire still passes (see DB-62 note
  above). A future timestamp is clamped to now(). The column stays NULL
  for pre-existing accounts and gym-invited users (the gym attests
  their consent offline).
- `export_member_data(uuid)`: SECURITY DEFINER RPC returning the
  subject's Trainw data as one JSON document (profiles, memberships,
  payments + events, sessions, bookings, check-ins, messages, reviews,
  assignments, freezes, credential types). Self-export for anyone; a
  manager may export a member of one of their gyms only; outsiders and
  cross-gym managers are refused (`export_forbidden`). Biometric
  credential material is never exported — type/label/dates only, no
  `credential_data`. PUBLIC revoked, granted to authenticated.
- `docs/PRIVACY_POLICY.md` + `docs/TERMS_OF_SERVICE.md`: French +
  Arabic drafts, clearly marked BROUILLON / needs a lawyer before
  publishing (Loi n° 2004-63, INPDP). Deletion itself is already
  covered by the NX-10 delete actions.
- **Three real defects the behavioral suite caught** (all fixed in the
  migration before commit): (1) `membership_freezes` uses `user_id`,
  not `client_id`; (2) `payment_events` has no `client_id` — it joins
  through `payment_id` → payments; (3) the export's `client_profile`
  scalar subquery fails when the subject has two profile rows (the
  chain auto-creates a bare gym-less row per auth user) — the export
  now returns `client_profiles` as an array. A fourth near-miss: the
  P2-9 builder script regenerates the migration from scratch, so the
  first two fixes (applied to the output file only) were lost on a
  rebuild — they were moved into the builder before the final commit.
- Verified: throwaway Postgres cluster, full chain applies (47 OK,
  only the known by-design B5 failure), 6-assertion P2-9 suite
  (`/tmp/r4-tests-p29.sql`: consent stored, self-export contents,
  hash excluded, outsider refused, manager allowed, cross-gym refused)
  + DB-62 4/4 + FE-26 2/2 on fresh clusters; scratch-copy tsc +
  eslint + next build clean, vitest 32/32 (31 prior + 1 new consent
  case). Test-harness note: the P2-9 fixtures follow the r4 pattern —
  auth.users first (trigger auto-creates public.users), then gyms,
  then UPDATE the public rows (gyms.manager_id FK requires the user
  row to exist first).

## P2-7 — 74bf6d7 — deploy runbook, backup + uptime scripts (code only)

- Files: `docs/DEPLOY_RUNBOOK.md`, `scripts/backup-db.sh`,
  `scripts/uptime-check.sh`.
- Runbook: what deploys where (static frontend on Vercel, migrations
  + edge functions on Supabase), migration apply rules (lexicographic
  order, CLI single-transaction, the by-design B5 failure, the DB-51
  rename caveat), the full deploy secrets checklist (Vercel env,
  Supabase GUC pepper, edge secrets, CAPTCHA fail-open warning,
  redirect-URL allowlisting), pre-launch checks incl. the P1-13
  cross-tenant matrix, backup/restore and rollback procedures.
- backup-db.sh: pg_dump to a custom-format dump outside the repo;
  DATABASE_URL from the environment only, refuses to run without it.
- uptime-check.sh: probes the production URL and the Supabase REST
  endpoint; with SUPABASE_ANON_KEY it expects 200, without it a 401
  counts as reachable.
- Live decisions are separated in the runbook's §7 and NOT made here:
  staging project, PITR, Sentry, an uptime monitor scheduler, P2-10.
- Verified: bash -n on both scripts; uptime-check run live against
  caylegavnekidhytlswo.supabase.co exits 0 (401 = reachable — the
  first version wrongly assumed the REST endpoint answers 200 without
  auth; fixed); the backup script refuses without DATABASE_URL as
  designed.

## P2-3 renewal — verified complete, no code change

- Checked against the code (round-3 notes claimed it; verified this
  round): the settlement trigger (`20261115100000`) extends
  `membership_end_date` on a paid membership payment with renewal
  semantics `GREATEST(end_date, period_start, today) + period_months`
  — early renewal stacks on remaining time, lapsed renewal restarts
  from today; the void path restores the exact pre-settlement end date
  (`settled_from_end_date`). The freeze trigger shifts the end date.
  All three access paths read the shared function: the gate
  (`validate_member_credential` → `membership_is_active_for_access`,
  gym's today after DB-37, called by the gate-checkin handler), the
  manual check-in guard (`trg_check_ins_membership` →
  `enforce_check_in_membership()`), and booking (`book_coach_session`
  → `client_membership_is_active`). Nothing was missing; no commit.

## Round-4 audit triage (every audit ID grepped against these notes)

- IDs never mentioned in the notes before round 4: DB-36, FE-09/10/11/
  12/15/17/18/24/28/29/30, GT-02/04/05, NX-12. Of those: FE-09/GT-05,
  FE-17, FE-18, FE-24, FE-25, FE-26, FE-28, FE-29, FE-30, NX-12 are
  done above. **Assessed, NOT code-fixable this round:** FE-10
  (Realtime private channels — needs a Supabase JWT for the terminal,
  a design decision), FE-11 (client-side role enforcement — code part
  done via round-2 B2 trigger ignoring metadata; live tests remain in
  P1-13), FE-12 (sessions in localStorage — short-term mitigation done
  via XSS+CSP; BFF/HttpOnly cookies is L/design; refresh-token rotation
  is a dashboard setting), GT-02 (per-device secret — the round-2
  terminal session token substantially addresses it; verify against
  handler.mjs), GT-04 (offline allow-list — L + ESP32 firmware, not in
  repo), FE-15 (done in round 3 — single ledger revenue source).
  DB-36 (no renewal logic) is effectively done via the round-3
  settlement trigger + DB-37 + FE-17 (see P2-3 above).
- **Round-2 notes made false claims before (NX-17, NX-27) — verify
  claims against code, don't trust the notes.**

## Deliberately skipped in round 4

- DB-66 no-show/completion auto-settlement (policy undecided per audit
  Q10 — refund-vs-credit-vs-forfeit is the user's call; the refund RPC
  exists).
- P2-10 — whether the Next.js app is the ship target at all. NOT
  decided; flagged open throughout.
- FE-10, FE-12 (design), GT-02 (verify), GT-04 (firmware), FE-11 live
  tests — see triage above.
- Session-history retention rule (DB-59 follow-up): orphaned history
  rows accumulate; needs a retention period decision.
- Consent checkbox on the public register-client flow (P2-9
  follow-up): the archived schema's clients table has no consent
  column; the gym attests consent offline for now.
- `get_bookable_slots` generating slots in the gym timezone (DB-37
  follow-up); DB-61 hash hardening for DEFAULT expressions (see DB-61
  gap); soft-delete for messages on user deletion (DB-38 follow-up);
  server-side review idempotency (FE-18 follow-up); per-gym specialty
  tags (DB-57 follow-up); searchable selects for the NX-12 form
  lookups (P2 UI item).
- The Next.js edit forms (NX-10 follow-up): update actions exist as
  server actions only; no prefilled inline edit form pattern exists on
  any page yet.

## Audit-vs-code mismatches found in round 4 (additions to the round-1/2 lists)

- DB-35: the audit said 25 unvalidated constraints; the chain has 24
  (payments_status_check was already validated).
- DB-41: `polroles` for a PUBLIC policy is `{0}`, not an empty array.
- DB-45: `sync_client_profile_assignment` (006) reassigned profile
  rows across gyms and collided with the auto-created bare profile row
  — a real pre-existing bug the verification caught and fixed.
- DB-46: `media_assets` has no `is_public` column (the audit implied
  both tables had one); the inline EXISTS publicity check could not see
  `milestone_photos` rows at all because of that table's own SELECT
  policy.
- DB-61: the freeze set computed from pg_policy + pg_proc surfaced
  helpers the audit did not name (get_my_portal, current_membership,
  permission_codes_for_membership, caller_holds_permission_in_gym,
  caller_manages_gym_direct, get_my_permissions).
- FE-27: renderPersonalRecordsTable was defined twice, not three times.
- FE-28: the audit's fifth cited string (:4265) could not be located
  by its text.
- NX-17/NX-27: round-2 notes claimed both were already clean — both
  were false (see those sections).
- NX-29: the client_code generator lives only in the archived
  schema.sql; the migration chain has no client_code at all.
- P2-9: `membership_freezes` uses `user_id` (not `client_id`) and
  `payment_events` has no `client_id` (joins through payments).
- The `clients` table in the archived schema HAS status/email/phone/
  contact_verified (the type file shows them) even though round-2
  notes said schema.sql's clients table lacks them — the type file is
  hand-maintained and may diverge from the schema; regenerate from the
  live DB at deploy time (per the callback route comment).

## What still needs live testing / access / a user decision (round 4)

- **Push:** round 4 is 38 local code commits on `phase1-security-fixes`,
  NOT pushed. Push via the Git Data API script (fetch the remote tip
  first — the script was fixed for incremental pushes in round 3),
  then let the Vercel auto-build run.
- **Supabase live work (unchanged from round 3):** apply the migration
  chain + Phase 1 migrations to project `caylegavnekidhytlswo` via the
  dashboard SQL editor in the browser (his login/2FA); check whether
  the DB is empty first; set the deploy secrets (runbook §3); point
  code config at the new project keys; rebuild dist. Note the
  connector host-registration gap for
  `caylegavnekidhytlswo.supabase.co`. Note the DB-51 rename caveat:
  if any environment already recorded `Trainw_001_foundation.sql` as
  applied, pair the rename with a migration-version repair.
- **P1-13 live tests** on the new project (cross-tenant matrix), plus
  the NX-28 recover flow (kill a signup mid-provision, then recover),
  the FE-09 live end-to-end QR scan, and the FE-24/FE-25 live invite
  + reset-link flows.
- **Deploy secrets still unset:** DB GUC pepper, GATE_TERMINAL_PEPPER,
  TURNSTILES_ENABLED, CAPTCHA keys (fail-open without the secret),
  APP_ORIGINS, redirect-URL allowlisting for /tw-login.html and
  /auth/reset-password.
- **Decisions still open (unchanged):** P2-10 (Next.js ship target);
  DB-66 auto-settlement policy; session-history retention; the FE-08
  coach search embedded-users name filter (live verification).
- **Environment quirks (round 4 additions):** `/tmp` is a 512M tmpfs —
  a second `npm install` into a /tmp scratch copy failed with ENOSPC;
  scratch copies for npm work must live on the overlay disk (e.g.
  `~/workspace/.nx12-scratch`); both scratch copies were deleted after
  use. `tar` extraction fails on root-owned repo files ("Cannot change
  ownership to uid 0") in some destinations — use `cp -r` for scratch
  copies instead.
