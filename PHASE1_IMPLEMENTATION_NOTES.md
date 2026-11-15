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

# Round 5 — remaining follow-ups from rounds 1–4, 2026-11-15

11 commits on `phase1-security-fixes` after the round-4 head `fcffd76`
(`e42697d` … `58069c7`). Local only — NOT pushed in this round. Rules
held throughout: never edit an applied migration (all SQL as NEW
files), one commit per logical piece, no history rewrites, no live
database, no production deploy, no DB-66 / P2-10 decisions.

Verification harness (same approach rounds 3–4 proved, rebuilt after
the VM reset wiped `/tmp` and the installed PostgreSQL): throwaway
local Postgres 16 cluster, harness at
`.r5-scratch/r5-harness.sh` (up/apply/test/psql/down/reset), cluster
`/tmp/r5-pgdata`, port 54399, DB `trainw`, stubs at
`.r5-scratch/supabase-stubs.sql` (auth schema + `auth.users` +
`auth.uid()`/`auth.role()`/`auth.jwt()` driven by `test.auth_uid` /
`test.auth_role` GUCs, storage buckets/objects +
`storage.foldername()`, roles anon/authenticated/service_role with
BYPASSRLS on service_role, RLS on storage.objects). Test files live in
`.r5-scratch/` during the round, NOT in the repo; the scratch dir is
deleted at the end of the round. The server must run as the `postgres`
OS user (initdb/pg_ctl refuse root) but psql runs as root; the harness
runs server commands via `su postgres`. The chain applies end to end:
**54 files** (stubs + 53 migrations), with only the two known
by-design failures (B5 `20261115050000`, DB-61 `20261115300000` — see
below), each repaired by a later migration. The harness tolerates
both by filename; the live apply must also continue past them.

Environment notes (round 5): apt was stuck on `apt-get update` (no
proxy config for apt; plain-HTTP proxy auth fails with 407). Fix:
write `/etc/apt/apt.conf.d/99proxy` from the live `$http_proxy` /
`$https_proxy` env vars **in the same exec call** as the apt command —
the proxy password rotates between exec calls (proved: apt sent a
stale password while the live env had a new one). Sources switched to
HTTPS; then `apt-get install postgresql postgresql-contrib`
succeeded (PostgreSQL 16). Harness gotcha: the harness `psql`
subcommand passes its arguments straight to psql, so a SQL string as
a positional argument is treated as a dbname and psql sits
interactive waiting on stdin — always use `-c` (or a file) with it.
`node --check` on every touched JS file; TS files got a transpile-only
esbuild check (cached esbuild in the npx cache); full `tsc --noEmit` +
`next build` remain deploy-time items (no node_modules in the repo).

## DB-61 hash gap for DEFAULTs (commit e42697d)

- **Files:** `supabase/migrations/20261115300000_phase1e_freeze_hash_defaults.sql`
  (built by `.r5-scratch/build-r5-db61.py`), `docs/MIGRATION_CONVENTIONS.md` §7.
- **What:** the round-4 freeze (migration `20261115210000`, assert
  re-created in DB-37 `20261115230000`) hashed signature, result,
  language, volatility, SECURITY DEFINER, proconfig, body — but NOT
  `proargdefaults`, so a default-only change slipped past. Seven
  frozen helpers carry defaults (`auth_user_email`,
  `client_membership_is_active`, `current_membership`,
  `get_my_permissions`, `has_permission`,
  `membership_is_active_for_access`, `user_has_membership`). The new
  migration adds `COALESCE(p.proargdefaults::text, '')` to the formula
  and recomputes all 30 hashes from the live chain.
- **Verification:** 4/4 (`r5-tests-db61.sql`) — assert passes; a
  default-only change to `has_permission` is detected; a body change
  to `can_view_user` is still detected; restoring both passes again.

## DB-61 portability defect (commit 2826ee3)

- **Files:** `supabase/migrations/20261115330000_phase1e_freeze_hash_portable.sql`
  (built by `.r5-scratch/build-r5-db61-portable.py`).
- **What:** the DB-61 formula hashed `proargdefaults::text`, whose
  node-tree text embeds the callee's OID (`FUNCEXPR :funcid 16401`
  for the `auth.uid()` defaults on `auth_user_email` and
  `user_has_membership`) — OIDs are assigned in creation order and
  differ between clusters, so the e42697d assert passed on the cluster
  it was built on and failed on any fresh cluster. Found by the
  rebuilt round-5 harness. The fix re-creates
  `assert_rls_helpers_frozen()` hashing
  `pg_get_function_arguments(p.oid)` instead — the signature WITH
  defaults deparsed as SQL text (e.g. `p_user_id uuid DEFAULT
  auth.uid()`), stable across clusters — and recomputes all 30 hashes.
  The old migration is untouched (same pattern as B5: its CREATE OR
  REPLACE still lands; this file supersedes it and re-validates).
- **Verification:** 4/4 (`r5-tests-db61p.sql`) — the assert passes on a
  fresh cluster whose hashes were computed on the previous cluster
  (genuinely portable); default-only and body changes still detected;
  restore passes again.
- **Live-apply note:** the live apply must continue past the
  by-design failure in `20261115300000`, exactly as it does for B5.

## DB-38: soft-delete for messages (commit c522ddc)

- **Files:** `supabase/migrations/20261115310000_phase1e_message_soft_delete.sql`,
  `tw-gym-acc.js`, `tw-client-acc.js`, `tw-coach-acc.js`,
  `trainw-enhancements.css` (shared `.msg-delete` style; all three
  pages load it).
- **What:** `deleted_at` / `deleted_by` columns on `messages`;
  `sender_id` / `receiver_id` nullable with FKs changed to ON DELETE
  SET NULL (constraint names `messages_sender_id_fkey`,
  `messages_receiver_id_fkey`); SELECT/UPDATE policies exclude
  soft-deleted rows; INSERT policy unchanged (still forces a real
  sender); `soft_delete_message(p_message_id)` RPC (SECURITY DEFINER,
  sender-only, idempotent — a second call returns the same id; REVOKE
  PUBLIC, GRANT authenticated); `forbid_message_field_updates()`
  trigger re-created as SECURITY DEFINER so the FK's SET NULL is
  allowed only when the old user row is genuinely gone (a caller
  cannot NULL out a live counterpart). UI: × button on own messages in
  the gym/client/coach conversation views, calling the RPC and
  re-rendering; `deleteMessage` i18n keys in all three T objects.
- **Verification:** 8/8 (`r5-tests-msgdel.sql`, re-run on a fresh
  cluster after the client/coach buttons landed) — both parties see a
  live message; sender soft-deletes, hidden for both, row survives;
  second soft-delete idempotent; receiver soft-delete forbidden;
  update on soft-deleted touches 0 rows; receiver cannot NULL a live
  sender; message survives sender deletion with `sender_id` NULL,
  still visible to receiver; insert policy still forces a real sender.
  `node --check` clean on all three JS files.
- **Test-writing lessons:** `can_message_user` requires
  `is_gym_manager()` (portal = 'admin') or `can_view_user(...)` —
  fixtures need an admin-portal membership role for the sender.
  `public.users.id` does NOT reference `auth.users` (plain uuid PK,
  linked only by the signup trigger's shared id) — MSGe deletes the
  `public.users` profile row, not the auth row, to fire the messages
  FK's ON DELETE SET NULL. `SET` is invalid inside a plpgsql DO block
  (use top-level SETs); psql does NOT interpolate `:'var'` inside a DO
  `$$` block (pass ids between statements via a temp table, with
  `GRANT ALL ... TO authenticated` since the superuser owns it).
- **Code quirk:** the client/coach files carry double-encoded French
  (mojibake `Ã©`, e.g. literal `Message envoyÃ©.`) — the i18n keys
  were added by a Python script (`.r5-scratch/r5-msgdel-i18n.py`)
  anchoring on ASCII `nameLabel` keys because the edit tool's
  proper-UTF-8 anchor failed. The gym file is proper UTF-8.

## FE-18 follow-up: server-side write idempotency (commit 9468eff)

- **Files:** `supabase/migrations/20261115320000_phase1e_write_idempotency.sql`
  (built by `.r5-scratch/build-r5-idempotency.py`, extract-and-patch
  from 003 + DB-37).
- **What:** `leave_session_review` returns the existing review id
  instead of raising conflict; `book_coach_session` returns the
  existing pending/confirmed session for the same client/slot (no
  duplicate session/payment) and raises `'conflict: this slot is
  already booked'` for a different client (the chain had no overlap
  guard at all); respond/cancel/complete/no_show return the id when
  already in the requested end state, still raise `invalid_state` on
  a mismatched end state; in respond the decision is validated BEFORE
  the idempotent return so a bogus decision still raises
  validation_error. Every function already locks its session row FOR
  UPDATE, so the check-then-act is race-safe.
- **Verification:** 9/9 (`r5-tests-idem.sql`) — first booking = 1
  session + 1 payment; same-client retry = same id, no duplicates;
  different client same slot = conflict; respond/cancel/complete/
  review/no-show each idempotent; mismatched decision still raises.
- **Fixture notes:** `get_my_role()` returns the role CODE, so the
  booking/review client needs a membership role with code `'client'`;
  complete/no_show refuse future sessions, so those tests move the
  session date to today via direct UPDATE as superuser (the write
  trigger allows the date move while confirmed).

## DB-57 follow-up: per-gym specialty tags (commit 6dd3320)

- **Files:** `supabase/migrations/20261115340000_phase1e_per_gym_tags.sql`,
  `tw-gym-acc.js`, `tw-gym-acc.html`, `trainw-enhancements.css`.
- **What:** `specialty_tags.gym_id` nullable (NULL = global; the
  seeded tags stay global). The global UNIQUE on name is replaced by
  two partial uniques: `UNIQUE (name) WHERE gym_id IS NULL` and
  `UNIQUE (gym_id, name) WHERE gym_id IS NOT NULL` (citext, so both
  are case-insensitive). SELECT shows globals + the caller's own gym
  tags (+ any gym they manage); INSERT/UPDATE/DELETE are gym managers,
  gym tags only — globals stay seed/service-role only and a tag cannot
  be moved into or out of the global list. New validated
  `create_gym_specialty_tag(p_gym_id, p_name)` RPC (trim, 1–60 chars,
  manager check, idempotent: an existing name in the gym returns its
  id). UI: tag suggestions in the gym dashboard coach-edit modal
  (global + this gym's tags as chips that fill the specialty field,
  with a dashed "+ save as tag" chip that calls the RPC; wired on
  modal open + on input, guarded against double-binding via
  `dataset.tagWatch`).
- **Verification:** 7/7 (`r5-tests-tags.sql`) — idempotent RPC create,
  validation + manager checks, per-gym case-insensitive uniqueness,
  cross-gym visibility, policy-gated direct writes, rename/delete
  allowed but no move to global, members cannot write.
- **Two real gotchas:** (a) `citext = text` resolves
  case-SENSITIVELY (citext is cast to text) — the RPC's fallback
  lookup casts the input (`name = v_name::citext`) or `'crossfit'`
  would miss `'CrossFit'`; (b) the chain only ever granted SELECT on
  the table, so the migration adds the INSERT/UPDATE/DELETE grants
  the policies need. Also: an RLS WITH CHECK failure raises an error,
  while a USING mismatch returns 0 rows (the move-to-global test
  expects the exception). The chain's own 002 seed insert
  (`ON CONFLICT (name)`) runs before the partial indexes exist, so it
  is unaffected.

## Searchable selects (commit 460010a)

- **Files:** new `src/components/ui/searchable-select.tsx`; wired
  into `src/components/forms/attendance-form.tsx` (client + class),
  `class-enrollment-form.tsx` (client), `class-form.tsx` (coach),
  `staff-user-form.tsx` (role).
- **What:** dependency-free combobox (filter-as-you-type, ArrowUp/Down
  + Enter + Escape, ARIA listbox, hidden input carries the selected id
  so server actions are unchanged; typing invalidates the previous
  selection so a stale id can never be submitted; blur closes via a
  timer cleared on re-focus; option pick uses onMouseDown +
  preventDefault so it lands before blur). Only the long lists got it;
  short lists (attendance status, class type, client type) stay native
  `<select>`s. The `'No class'` empty option is preserved via
  `defaultValue=""`.
- **Verification:** esbuild transpile-only check clean on all 14
  touched TSX files. Full `tsc --noEmit` + `next build` remain
  deploy-time items.

## NX-10 follow-up: Next.js edit forms (commit 98a57bd)

- **Files:** new `src/components/forms/client-edit-form.tsx`,
  `coach-edit-form.tsx`, `class-edit-form.tsx`; each `*RowActions`
  gained an Edit toggle; the three list pages (`clients`, `coaches`,
  `classes` under `src/app/(dashboard)/dashboard/`) restructured so
  the actions block sits under the info row.
- **What:** prefilled inline edit forms wired to the existing update
  server actions (client: name + type; coach: name + rating; class:
  name + type + capacity + coach via SearchableSelect; Cancel button;
  page revalidates on success). Pages now pass name/type/rating/
  capacity/coachId/coaches — `coachId` was already in
  `getClassesPageData`'s mapped rows.
- **Verification:** esbuild transpile-only check clean on all touched
  files. Full `tsc --noEmit` + `next build` remain deploy-time items.

## DB-37 follow-up: get_bookable_slots in the gym timezone (commit fb2da18)

- **Files:** `supabase/migrations/20261115350000_phase1e_bookable_slots_gym_tz.sql`
  (built by `.r5-scratch/build-r5-slots-tz.py`, extract-and-patch from
  DB-37 `20261115230000`).
- **What:** slots are generated as naive `p_session_date + start_time`
  (wall time in the gym's zone) but were filtered with
  `rs.slot_start_ts > now()` — now() is UTC on the server, so near
  midnight a slot could show bookable after it had already passed in
  the gym's zone (09:00 Tunis still listed at 08:30 UTC = 09:30
  Tunis). The function now carries `gym_tz`
  (`public.gym_timezone(COALESCE(ca.gym_id, cd.gym_id))`) through the
  windows/raw_slots CTEs and compares against the current wall time in
  the gym's zone (`now() AT TIME ZONE rs.gym_tz`). The overlap check
  is untouched (`session_time_range` is naive on both sides and
  internally consistent).
- **Verification:** 3/3 (`r5-tests-slottz.sql`) — with a
  Pacific/Kiritimati gym (UTC+14, no DST) the returned count matches
  the timezone-aware expectation (the old UTC filter would have
  returned all 23 slots), no returned slot has passed in the gym zone,
  and booking a slot still removes exactly that slot from the results.
- **Test note:** the Kiritimati wall time must stay a plain
  `timestamp`, not `timestamptz` — assigning
  `now() AT TIME ZONE '...'` to a timestamptz variable re-interprets
  the wall time in the session timezone.

## GT-02: terminal session tokens are device-bound (commit 3e3f1db)

- **Files:** `supabase/functions/gate-checkin/handler.mjs`.
- **What:** `verifyTerminalSession` only checked the token hash,
  expiry, and gym — never the session row's `device_id`, so a token
  lifted from one terminal could be replayed from any other device.
  It now also requires the request's `device_id` to match the
  session's `device_id` (a request that omits `device_id` fails too).
  Sessions with no `device_id` on record skip the check, but none
  exist — the column is NOT NULL and `gate-terminal-auth` binds
  `device_id` at issuance. The only gate-checkin caller is
  `gate-terminal.js`, which always sends `device_id` (verified by
  grep; the other `gate-checkin` reference in `tw-gym-acc.js` only
  builds a display URL).
- **Verification:** 4/4 with a Node harness + stub admin client
  against the real handler (`.r5-scratch/r5-test-gt02.mjs`) — same
  device passes verification (400 `missing_token`: no QR token
  supplied), wrong device 401, omitted device_id 401, wrong token 401.
  The handler is fully injectable (`createGateCheckinHandler(options)`
  uses only `crypto.subtle`, `Response`, `options.getEnv`,
  `options.createAdminClient`), which is what makes the local test
  possible.

## FE-10: gate access results off the public broadcast (commit 10aa327)

- **Files:** `supabase/functions/gate-checkin/handler.mjs`,
  new `supabase/functions/gate-feed/handler.mjs` +
  `supabase/functions/gate-feed/index.ts`,
  `supabase/config.toml`, `gate-terminal.js`.
- **What:** the `access_result` broadcast carried the member's name,
  days_left, denial reason and credential type on the public Realtime
  channel `gate-terminal:<gymId>` — anyone who guessed the gym id
  could subscribe and watch members walk in. `gate-checkin` now
  broadcasts only an opaque `access_refresh` signal (gym, device,
  timestamp); the three `emitAccessEvent` call sites pass only the
  minimal fields. The terminal fetches the actual entries from the new
  authenticated `gate-feed` edge function, which verifies the terminal
  session token (`x-terminal-token`, device-bound per GT-02, gym-bound
  to the requested gym — a wrong gym/device gets the same 401 either
  way) and returns the 8 most recent `gate_access_log` rows for that
  gym, enriched with client names and days_left (computed the same way
  gate-checkin does). The terminal refreshes the feed on each signal
  and once at startup / after PIN auth (in-flight guard + one pending
  re-run, so a burst of scans does not stack fetches); the result card
  shows this device's newest entry, with the old device filter and
  dedupe preserved; a 401 clears the session and re-prompts for the
  PIN, same as the QR-scan path. `config.toml` registers gate-feed
  with `verify_jwt = false` (same pattern as gate-checkin: the
  terminal authenticates with the session token, verified in code).
  `verifyTerminalSession` is duplicated in gate-feed's handler (the
  functions are separate Deno deployments and this repo has no
  `supabase/functions/_shared` module — the comment says to keep the
  two copies in sync). The terminal's own QR scans never depended on
  the broadcast (`handleQrScan` renders from the HTTP response
  directly); the broadcast only served external hardware pushes and
  other terminals.
- **Verification:** 5/5 with a Node harness + stub admin client
  against the real handler (`.r5-scratch/r5-test-gatefeed.mjs`) —
  200 with entries newest-first and names/days_left/reasons resolved,
  wrong device 401, wrong gym 401, no token 401, turnstiles off 503,
  with no entries leaked on any 401. GT-02 suite still 4/4 after the
  broadcast edit. `node --check` clean on both handlers and
  `gate-terminal.js`; no `access_result` broadcast remains (only the
  explanatory comment). `client_name` in the checkin handler now
  appears only in the direct HTTP response bodies (the terminal that
  performed the scan), never in a broadcast.
- **Live test still needed:** the full terminal flow with the flag ON
  (PIN → token → QR scan → feed populates from gate-feed; a second
  terminal shows its own newest entry on its own card), and the
  503 `turnstiles_disabled` path for gate-feed with the flag OFF.

## FE-12: session + realtime dashboard settings (commit 8f3a544)

- **Files:** `docs/DEPLOY_RUNBOOK.md` §8 (new).
- **What:** sessions live in localStorage (the static app has no
  backend-for-frontend to hold HttpOnly cookies — that stays a larger
  design item, not done here). The runbook now documents: enable
  **Realtime Authorization** so the dashboard `postgres_changes`
  subscriptions (`messages`, `sessions`, `check_ins`,
  `workout_plans`, `weight_logs` in `tw-gym-acc.js`,
  `tw-client-acc.js`, `tw-coach-acc.js`) enforce RLS with the caller's
  JWT — the channel filters are client-chosen and are not a boundary
  on their own; turn **refresh-token rotation ON**; keep the **JWT
  expiry short** (3600s / 1h default, do not raise it). Also records
  the token-hygiene grep audit: no code in the repo logs a token,
  secret, password, PIN, or key value — the only hit is ai-proxy
  logging the NAMES of missing env vars, never the values.
- **Verification:** grep audit over every `console.*` call in
  `*.js` / `*.ts` / `*.tsx` / `*.mjs`. These are dashboard settings,
  not code — they must be set by hand before the first pilot.

## Final sweep (commit 58069c7) — re-read the audit + skipped lists

Explicit list before starting, and the outcome for each:

- **DO — DB-35 (validate NOT VALID constraints):** already closed in
  round 4. Migration `20261115150000_phase1d_validate_constraints.sql`
  validates every unvalidated constraint dynamically; a fresh-cluster
  query proves it: 0 unvalidated constraints in `pg_constraint`
  (45 public tables, 350 constraints). The 25 `NOT VALID` grep hits
  are the original additions, not open work. Not re-done.
- **DO — DB-48 (RPC lockout):** closed by documenting + testing the
  edge-function throttle, the alternative the audit itself offers
  ("add per-credential/per-device failure counting ... or document
  and test the edge-function throttle"). Test 4/4
  (`r5-tests-ratelimit.sql`): device bucket allows 30, refuses the
  31st; refused calls do not inflate the counter; buckets are
  independent; IP bucket enforces the same way (exercised with limit
  5 for speed; production passes 60). Doc note in
  `docs/HARDWARE_INTEGRATION.md` (tune in `handler.mjs`
  `RATE_LIMITS`, not in the RPC).
- **DO — NX-29 (client codes):** closed with a doc note in
  `docs/HARDWARE_INTEGRATION.md`. Verified by grep: no code path in
  `gate-checkin`, `gate-terminal.js`, or the gym dashboard reads a
  client code as a credential; the gate accepts only single-use QR
  tokens and enrolled hardware credentials.
- **Already closed in round 4 (verified, not re-done):** DB-41
  (migration `20261115170000`: blanket grant replaced with per-table
  grants derived from the RLS policies + `assert_all_tables_have_rls()`);
  DB-46 (migration `20261115180000`: v18 storage policy — profiles/
  readable only by owner, `manage_staff`/`manage_media` holders, or
  when the asset row is `is_public` — plus `media_assets.is_public`
  added, default false); DB-50 (`docs/DATA_REPAIR_RUNBOOK.md` +
  `MIGRATION_CONVENTIONS.md` §4: no destructive data repair in a
  migration); NX-26 (`.github/workflows/ci.yml` exists: type-check,
  lint, smoke tests, production build); FE-27 (a) `tw-client-pilot.js`
  is gone from the repo, (b/c/d) `renderPersonalRecordsTable` /
  `renderProgram` / `renderWeight` each have exactly one definition
  now and there are zero `callEdge` / `legacyInitDisabled` references.
- **Deliberately skipped:** DB-51 (rename needs staging `supabase
  migration list`); DB-66, P2-10 (user's call); NX-14 (password
  reset/invite flow needs live email to verify); NX-28 (orphan
  recovery flow needs a live staging kill to verify); NX-24
  (dependency updates — needs npm install; not verifiable here);
  NX-25 (remove `as any` — cannot verify without tsc); FE-27(e)
  (`tw-gym-acc-v17.js` monkey-patching of `loadClients` /
  `loadAnalytics` / `loadCoaches` / `setLang` / `openCoachModal` —
  load-bearing rendering code with no DOM test harness; replacing it
  with explicit hooks needs staging verification); GT-04 (ESP32
  firmware, not in the repo); FE-11 live tests and the P1-13 live
  matrix (need staging/live); session-history retention and the
  consent checkbox (need user decisions); the void-reason
  `window.prompt` (`tw-gym-acc.js:1985` — P2 polish, low value vs
  UI risk in the minified file).

## Final verification (whole round, one cluster)

Fresh reset, then every round-5 suite in sequence (fixtures are
namespaced by distinct UUIDs/bucket keys; the mutating DB-61 suite
ran last): msgdel 8/8, idem 9/9, tags 7/7, slottz 3/3, ratelimit
4/4, db61p 4/4 — **35/35**. Node harnesses: GT-02 4/4, gate-feed
5/5. `node --check` clean on `tw-gym-acc.js`, `tw-client-acc.js`,
`tw-coach-acc.js`, `gate-terminal.js`, both edge handlers. esbuild
transpile-only clean on all 14 touched TSX files.

## Audit-vs-code mismatches found in round 5 (additions)

- DB-61: `proargdefaults::text` embeds callee OIDs, so a hash
  computed on one cluster is not reproducible on another — the
  round-4 freeze was cluster-specific until the portable fix.
- DB-57: `citext = text` resolves case-SENSITIVELY (citext is cast to
  text) — a case-insensitive lookup must cast the input to citext.
- DB-46 (round-4 note, confirmed in this sweep): the v18 policy is
  in place; nothing further was needed.
- FE-27: the audit's tripled renderers are already single
  definitions; the pilot file is already deleted.
- DB-35: the audit's 25 unvalidated constraints are already all
  validated by the round-4 migration — the count on a fresh cluster
  is 0.
- The gate-checkin QR path renders the terminal's own scan result
  from the HTTP response, not from the broadcast — so the FE-10
  change affects only external-hardware pushes and other terminals.

## What still needs live testing / access / a user decision (round 5)

- **Push:** round 5 is 11 local commits on `phase1-security-fixes`,
  NOT pushed. Push via the Git Data API script (fetch the remote tip
  first), then let the Vercel auto-build run. `dist/` was NOT rebuilt
  in this round — the gate-terminal.js and gym/client/coach JS
  changes ride in `dist/` only after a rebuild (round 1's P1-9 flow).
  The new `gate-feed` edge function must be deployed
  (`supabase functions deploy gate-feed`) alongside the updated
  `gate-checkin`.
- **Supabase live work (unchanged):** apply the migration chain +
  Phase 1 migrations to project `caylegavnekidhytlswo` via the
  dashboard SQL editor; check whether the DB is empty first; set the
  deploy secrets (runbook §3) + the §8 dashboard settings (Realtime
  Authorization, refresh-token rotation, 1h JWT expiry); point code
  config at the new project keys; rebuild dist. The live apply must
  continue past the by-design failures in `20261115050000` (B5) and
  `20261115300000` (DB-61 non-portable hashes) — both are repaired by
  later migrations. DB-51 rename caveat still applies.
- **P1-13 live tests** on the new project (cross-tenant matrix), plus
  the FE-10 terminal flow (flag ON: PIN → token → QR → feed from
  gate-feed; second terminal isolation; flag OFF: gate-feed 503),
  the GT-02 live check (a token from terminal A rejected on terminal
  B), the NX-28 recover flow, the FE-09 live end-to-end QR scan, and
  the FE-24/FE-25 live invite + reset-link flows.
- **Deploy secrets still unset:** DB GUC pepper,
  GATE_TERMINAL_PEPPER, TURNSTILES_ENABLED, CAPTCHA keys (fail-open
  without the secret), APP_ORIGINS, redirect-URL allowlisting for
  /tw-login.html and /auth/reset-password.
- **Decisions still open (unchanged):** P2-10 (Next.js ship target);
  DB-66 auto-settlement policy; session-history retention; the FE-08
  coach search embedded-users name filter (live verification).
- **Full type-check + `next build`:** the Next.js changes
  (SearchableSelect, edit forms) have only had a transpile-only
  esbuild check; `tsc --noEmit` + `next build` must run at deploy
  time (needs node_modules / network).

---

# Round 6 — audit closure pass (2026-11-15 ~04:04–06:00, head d206af9)

Task: reconcile all 137 audit findings against the CURRENT code (not the
notes), fix anything still open and code-doable, verify NX-24/NX-25
properly, deliver `AUDIT_CLOSURE.md`. Local only — no push, no live DB,
no history rewrites, no edits to existing migrations. Commits on top of
round 5's `e000c15`: `78a63b6` (6 migrations), `b96c892` (NX-11),
`f3152ba` (NX-15), `bd4c441` (NX-07/NX-15 residuals/NX-16), `60dce40`
(AUDIT_CLOSURE.md).

## Closure counts (verified programmatically against the audit report)

115 FIXED+VERIFIED, 19 FIXED+NEEDS-LIVE-TEST, 2 OPEN-DECISION-NEEDED
(DB-66, NX-03), 0 OPEN-LIVE-ONLY, 1 NOT-APPLICABLE (GT-04). All 7
CRITICAL are FIXED+VERIFIED. Every one of the 137 IDs appears exactly
once in AUDIT_CLOSURE.md (checked by script, no duplicates, none
missing); severities follow the audit report's findings table.

## Verification harness (round 6)

- Throwaway local Postgres 16 cluster, rebuilt from the round-5 data
  dir (`/tmp/r5-pgdata`, port 54399, socket /tmp). Harness + stubs +
  suite kept at `~/workspace/.r6-scratch/` (`r6-harness.sh`,
  `r6-tests.sql`, `supabase-stubs.sql`, `schema.txt`, `functions.txt`).
  The Next.js scratch copy (`~/workspace/.r6-scratch/next-app`) was
  deleted after verification.
- Fresh apply on a new DB `trainw_fresh`: **58 OK, 2 FAIL — exactly the
  two known by-design failures** (`20261115050000` B5 return-type;
  `20261115300000` DB-61 non-portable hash), both repaired by later
  migrations. All three asserts pass on the fresh DB
  (`assert_rls_helpers_frozen()`, `assert_all_tables_have_rls()`,
  `assert_no_unvalidated_constraints()`); 0 unvalidated constraints;
  45 tables.
- Behavioural suite `r6-tests.sql`: **161/161 assertions pass** (final
  run 9), plus targeted probes for DB-42/43/44/47 (all pass). Fixtures:
  gymA `...0a1` (ownerA `..001`), gymB `...0a2` (ownerB `..002`);
  pepper GUC set in-session.
- Next.js: `npm install` (418 packages) + `tsc --noEmit` clean +
  `vitest` **33/33** (incl. a new NX-07 case) + `eslint` clean +
  `next build` green, in a scratch copy on the overlay disk
  (NOT /tmp — 512M tmpfs, npm install fails there with ENOSPC).

## Test-writing conventions learned (hard-won, reuse next time)

- RLS tests use `SET ROLE authenticated` + `SET test.auth_uid`, then
  `RESET ROLE` + `RESET test.auth_uid` before superuser statements (a
  stale auth_uid makes self-update guards treat superuser writes as
  self-writes).
- INSERT denials raise `insufficient_privilege`; UPDATE/DELETE denials
  are silent 0 rows (use GET DIAGNOSTICS ROW_COUNT). Guard triggers
  raise, so tests must accept either a raise or 0 rows as PASS.
- Temp tables created by superuser need explicit
  `GRANT ALL ... TO authenticated, service_role, anon` or RLS blocks
  get "permission denied" on them.
- `r6_check` must be SECURITY DEFINER to log while role is
  authenticated. Assert functions return **void**, not boolean — wrap
  in DO blocks.
- `SELECT * INTO composite_var FROM fn_returning_composite` does not
  populate fields as expected — use PERFORM + direct table checks.
- Cross-gym reads as another user return NO ROW (not an error), so
  scalar subqueries yield NULL — verify cross-gym facts as superuser.
- Messages SELECT policy hides soft-deleted rows (`deleted_at IS
  NULL`), so verify soft-delete stamps as superuser.
- `SET ROLE` inside a DO block persists after the block — always RESET
  after. VALUES-list uuid literals need `::uuid` casts.
- `MIN(uuid)` does not exist in PG 16 — use ROW_NUMBER for dedup.

## Holes the closure pass found and fixed (all verified by the suite)

- **DB-14** — `gym_memberships_insert_v17b` let a `manage_staff` holder
  directly INSERT an ACTIVE owner-role membership; `invite_gym_member`
  and `set_membership_role` had no owner-role guard.
  (`20261115360000`, `20261115370000`)
- **DB-16** — a branding-only admin-portal user could INSERT a payment
  (proven live in the suite). Payments/credentials/devices/check-in
  deletes now also require the per-action permission.
  (`20261115380000`) **Behaviour change:** default `staff` can no
  longer record payments or enrol gate credentials/devices; owners can
  grant `manage_payments` / `manage_access_control` from the roles UI.
- **DB-40** — `invite_gym_member` raised "column reference
  invite_email is ambiguous" on EVERY call: the invite flow was
  completely broken. Fixed by qualifying the column.
  (`20261115360000`)
- **DB-36/DB-65** — voiding a payment for a member whose
  pre-settlement `membership_end_date` was NULL left the end date at
  the period start instead of NULL. Settle now stores sentinel
  `DATE '0001-01-01'` for NULL; reverse restores NULL.
  (`20261115390000`)
- **DB-56** — the dedup unique index was never created (round 2 did
  the CHECK + policies only). `uq_personal_records_client_exercise_achieved`
  on `(client_id, exercise_name, achieved_at)`, ROW_NUMBER dedup first.
  (`20261115400000`)
- **DB-54** — the sensitive self-edit guard never fired (gated on
  `manages_gym()`, true for all admin-portal staff). Now gates on
  `has_permission('manage_staff', gym_id)`. (`20261115410000`)
- **NX-11** — `next.config.ts` had no security headers at all. Added
  `headers()` mirroring vercel.json; `script-src` keeps
  `'unsafe-inline'` (Next.js inlines its bootstrap scripts; a nonce
  via middleware would be needed to drop it — documented in the file).
  Headers confirmed in `.next/routes-manifest.json`. (b96c892)
- **NX-15** — `getErrorMessage` alone did not close it: 23 direct
  `.message` returns still existed across roles/clients/attendance/
  classes/coaches. All replaced with `getErrorMessage(error, <generic>)`;
  grep proves zero direct returns remain in `src/`. (f3152ba, bd4c441)
- **NX-07** — login `redirectTo` was an unvalidated string (open
  redirect); callback `safeNext` accepted `//evil.com`. Schema now
  refines to same-site relative paths; callback rejects `//` and
  backslash targets. New vitest case (5 assertions). (bd4c441)
- **NX-16** — class capacity accepted 0, negatives, fractions (the DB
  CHECK exists only for sessions, not classes). Both class schemas now
  refine capacity to a whole number ≥ 1 (null = unlimited, unchanged);
  create-name `max(100)` added to classes/clients/coaches + signup
  `fullName`/`gymName`. Rating clamp was already server-side.
  (bd4c441) Note: the capacity refine is verified by code check + tsc
  + build, not by a vitest case (the schemas are module-private and
  pull server imports).

## What round 6 deliberately did NOT do

- DB-66 / NX-03 (P2-10) — the user's call.
- Void-reason `window.prompt` (`tw-gym-acc.js:1985`) — left as is. No
  confirm-modal helper exists in the app (the convention is native
  `window.confirm`, used in 8 places), so replacing it means building
  a new modal with a text input in the payments flow — not
  quick-and-low-risk without a DOM test harness, and the native prompt
  works correctly today (reason is mandatory, stored as `void_reason`).
- FE-12 BFF/HttpOnly sessions — deliberate design decision (L effort);
  mitigation is dashboard settings, to be verified live.
- GT-04 offline allow-list — needs ESP32 firmware that is not in this
  repo; turnstiles are off by user decision.
- No push (parent pushes, base = remote tip `234cc893`).

## Corrections to earlier rounds' notes (found by this pass)

- Round 5's notes wrongly listed NX-24, NX-25, NX-14, NX-28, DB-51
  and FE-27(e) as skipped — round 4 had done all of them; NX-14/NX-28
  were "not live-verified", the rest were simply wrong.
- Round 2's notes wrongly claimed NX-17 and NX-27 were already clean
  (fixed in round 4) and described NX-11 as "all dashboard pages pass
  context.gymId" — that is NX-04, not NX-11 (security headers); NX-11
  was genuinely open until round 6.
- Round 3's "reversal restores it exactly" was false for members whose
  pre-settlement end date was NULL (fixed in round 6, DB-36).

## Residual notes (not findings)

- DB-46: a same-gym client can see other members' private profile
  media (holds `manage_media` by default). Same-gym only; tightening
  needs a product decision.
- FE-08: the coach-search embedded-users name filter still needs live
  verification.
- GT-08: one check-in per day remains the policy; lunch-time re-entry
  needs a product decision.
- The `tier.toUpperCase()` interpolation in the client-card renderer is
  NOT an XSS hole: `membership_tier` is CHECK-constrained to 7 fixed
  values (`client_profiles_membership_tier_check`).

## What still needs live testing / access / a user decision (round 6, unchanged + additions)

- **Supabase live work (unchanged):** apply the migration chain +
  Phase 1 migrations to project `caylegavnekidhytlswo` via the
  dashboard SQL editor; check whether the DB is empty first; set the
  deploy secrets (runbook §3) + the §8 dashboard settings (Realtime
  Authorization, refresh-token rotation, 1h JWT expiry); point code
  config at the new project keys. The live apply must continue past
  the by-design failures in `20261115050000` (B5) and
  `20261115300000` (DB-61) — both are repaired by later migrations.
  Round 6 adds 6 more files (through `20261115410000`).
- **Credential rotation (live):** the two test accounts
  (`coachtestv17@gmail.com`, `clienttestv17@gmail.com`) and demo
  accounts (`admin@lakeclub.tn`, `reception@lakeclub.tn`) still carry
  the published passwords until rotated in Supabase Auth (DB-08/DB-09).
- **Edge-function deploy + dashboard settings:** deploy `gate-checkin`,
  `gate-terminal-auth`, `gate-feed`, `ai-proxy`; confirm `verify_jwt`
  per `supabase/config.toml` in the dashboard (GT-09); apply runbook
  §8 settings (the FE-12 mitigation).
- **P1-13 live tests** on the new project (cross-tenant matrix), plus
  the FE-10 terminal flow, the GT-02 live check, the NX-28 recover
  flow, the FE-09 live end-to-end QR scan, the FE-24/FE-25 live invite
  + reset-link flows, and the NX-01/02/05/08/09/10/14 flows.
- **Decisions still open (unchanged):** P2-10 (Next.js ship target —
  gates live verification of 9 NX findings); DB-66 auto-settlement
  policy; session-history retention; the FE-08 coach search
  embedded-users name filter (live verification).
- **Deploy secrets still unset:** DB GUC pepper,
  GATE_TERMINAL_PEPPER, TURNSTILES_ENABLED, CAPTCHA keys (fail-open
  without the secret), APP_ORIGINS, redirect-URL allowlisting for
  /tw-login.html and /auth/reset-password.
- **Accountant check:** verify the TEIF e-invoice field list before
  the first real invoice.
- **Full type-check + `next build`:** now DONE in round 6 (tsc clean,
  vitest 33/33, eslint clean, next build green, in a scratch copy).
  Re-run at deploy time after any further change.

---

## Live tests (P1-13) — 2026-11-15 ~08:00–08:50 Tunis

Run on the real Supabase project **Trainw (`caylegavnekidhytlswo`, eu-west-2)** with the
user's explicit approval (2026-11-15 07:53). Live DB was EMPTY and pre-launch; no
production data exists. Harness: `/tmp/live-matrix.py`, `/tmp/live-retest.py`,
`/tmp/live-retest2.py` (+ ad-hoc probes); reports `/tmp/live-matrix-report.json`,
`/tmp/live-retest-report.json`, `/tmp/live-retest2-report.json`.
Test users/gyms: two gyms `TEST — Gym A` (`28b82a5f-8e2d-4ce5-8a80-5a6428820f8c`)
and `TEST — Gym B` (`cc1b019a-1680-4414-a4ca-468aabe70f2b`), 10 users
`test-{a,b}-{owner,manager,staff,coach,client}@trainw.live` (fresh random
passwords in `/tmp/live-test-users.json`, chmod 600 — never commit/print),
plus invitees `test-invitee@`, `test-invitee2@trainw.live` and
`trainw-live-test-xyz123@gmail.com`. Test data LEFT IN PLACE for verification;
cleanup steps at the end of this section.

### Method notes (traps for the next live run)

- SQL route: Management API `POST /v1/projects/{ref}/database/query` via
  `sb-api.py` — one call = one transaction (rolls back on error); a file that
  fails mid-way must be split (B5's prefix was applied separately). `sb-api.py`
  takes `@file`, NOT `@-` (stdin) — it opens the argument as a filename.
- HTTP to the project host (`*.supabase.co`) MUST go through `curl`: Python
  `urllib` hits truncated chunked responses through this egress proxy
  (`RemoteDisconnected` / `IncompleteRead`). All harness HTTP was rewritten
  to curl with retries.
- Supabase CLI 3.1.0 cannot authenticate here (rejects the vault surrogate
  token format before any network call). Edge functions were deployed via the
  Management API multipart deploy endpoint (`/tmp/deploy-functions.py`).

### Migration apply — 60 files, 58 OK + 2 by-design failures

Identical to the local chain: `20261115050000` (B5 return-type) and
`20261115300000` (DB-61 non-portable hash) fail by design, both repaired by
later migrations. Live DB after apply: **47 tables, 355 functions, 127
policies, 7 extensions**; `assert_rls_helpers_frozen()`,
`assert_no_unvalidated_constraints()`, `assert_all_tables_have_rls()` all pass.
Plus repair migration `20261115190000` (Phase 1g, see below) — chain is now
61 files.

### Edge functions — all 4 ACTIVE

`gate-checkin`, `gate-terminal-auth`, `gate-feed` (`verify_jwt=false`),
`ai-proxy` (`verify_jwt=true`) — all ACTIVE, versions bumped to v4 after the
Phase 1g redeploy (SERVICE_ROLE_KEY fix). `verify_jwt` matches
`supabase/config.toml` (GT-09 verified live).

### Secrets / config set live

- Edge secrets set via Management API: `GATE_TERMINAL_PEPPER` (fresh random),
  `APP_ORIGINS` (`https://trainw.vercel.app`), `TURNSTILES_ENABLED` (see below),
  `SERVICE_ROLE_KEY` (alias of the platform-injected key — needed until the
  Phase 1g code fix shipped; kept as fallback).
- Auth config (GET/PATCH `/config/auth`): `jwt_exp = 3600` (1h, already the
  runbook §8 target), `refresh_token_rotation_enabled = true` (already ON),
  `mailer_autoconfirm = false`, `security_captcha_enabled = false`.
  Redirect allowlist set: `https://trainw.vercel.app/tw-login.html`,
  `https://trainw.vercel.app/auth/reset-password`.
- **No custom SMTP is configured** (`smtp_host` null) — the project uses
  Supabase's default mailer, whose rate limit blocked the password-reset
  retest (R8, 429). Recommend a custom SMTP before real users.
- **Realtime Authorization NOT flipped** (deliberate): `private_only` left
  null — setting it would break the dashboards and gate terminal, which
  subscribe to PUBLIC channels with no private-channel config and no
  `realtime.messages` RLS policies. `postgres_changes` already enforces
  source-table RLS server-side. Flipping needs a code change first.
- **Missing / blocked:** `ANTHROPIC_API_KEY` (ai-proxy fails closed without
  it — F3 proves it); the DB GUC `trainw.member_credential_pepper` CANNOT be
  set via the API (ALTER DATABASE / ALTER ROLE SET denied 42501; Management
  API config rejects custom GUC keys; ALTER SYSTEM impossible inside a
  transaction) — credential enrolment/validation fails closed live until the
  pepper moves to another source (Vault / edge secret) by a code change.
  CAPTCHA keys: **no longer needed for launch** (user decision 2026-11-15).

### Turnstile flag protocol (important)

`TURNSTILES_ENABLED=false` is the user's standing decision. For the gate
matrix it was temporarily set to `true` (edge secret), the full gate suite
run, then set back to `false` and verified: all three gate functions now
answer `turnstiles_disabled` again. Never leave it `true` after a test run.

### Matrix results

- **Run 2 (full matrix, 50 assertions): 38/50 PASS.** The 12 non-passes
  split into 2 real bugs, 1 blocked item, 2 superseded NX items, and 7 test
  artifacts (see below) — none of the artifacts is a product failure.
- **Retest-1 (22 assertions):** freeze + void re-tests after the Phase 1g
  fix; invite crashed on a reused email (fixed in retest-2).
- **Retest-2 (17 assertions): 13/17 PASS** (2 storage fails were a wrong
  test path — fixed in the final probe; 2 reset fails are the 429 rate limit).
- **Final probes:** storage with the correct `profiles/<gym>/<user>/` path
  (upload 200, cross-gym download 404, own download 200); FE-08 coach
  bare-`users` query returns only same-gym users, name filter for the other
  gym returns 0 rows; Vercel preview `trainw-cv9qwmo3q-...` answers **302**
  (healthy behind Vercel Authentication).

Proven live (mapped to closure rows): DB-01 (self-pay guard 400), DB-08/DB-09
(published demo accounts absent from `auth.users`), DB-14 (cross-gym role
change refused), DB-16 (cross-gym payment insert 403), DB-40 (invite flow
end-to-end incl. expiry message), DB-54 (self-grant 403), FE-06/FE-07/FE-08
(cross-gym reads/writes/names all blocked), FE-11 (RLS is the real boundary),
FE-12 (rotation ON + 1h JWT verified via API), FE-10 (gate-feed needs a valid
terminal token, 401 without), GT-01 (ai-proxy: 401 no JWT, 403 wrong gym,
reaches Anthropic step when authed), GT-02 (terminal token from another
device, or without device, → 401), GT-09 (verify_jwt matches config.toml),
ledger settle → gate admits → void → gate denies (after voiding ALL payments),
freeze → gate denies → cancel → gate admits, no-show keeps the money
(DB-66 CREDIT core), storage private-by-default with gym-scoped paths.

### REAL BUGS FOUND BY LIVE TESTING (all fixed, Phase 1g)

1. **`SERVICE_ROLE_KEY` is not injected by Supabase (gate functions 500).**
   `gate-checkin`, `gate-feed`, `gate-terminal-auth` all read
   `SERVICE_ROLE_KEY`, but the platform injects `SUPABASE_SERVICE_ROLE_KEY`
   — every gate call returned 500 `server_not_configured` until fixed.
   Fix: code now reads `SUPABASE_SERVICE_ROLE_KEY` first, `SERVICE_ROLE_KEY`
   as fallback (3 files); functions redeployed as v4. A `SERVICE_ROLE_KEY`
   edge secret (alias of the injected key) was also set so the pre-fix
   deployment worked during the run; it is now redundant but harmless.
2. **Freeze ignored at the gate (C15b).** `membership_is_active_for_access`
   used the RAW `p_reference_date` in its freeze clause while every other
   clause uses `COALESCE(p_reference_date, gym_today(...))`. The gate calls
   it without a date (DB-37), so `NULL BETWEEN ...` is NULL and frozen
   members were admitted. Local tests passed because they passed explicit
   dates (or used `client_membership_is_active`, which does). Fix:
   COALESCE in the freeze clause (source files `20261115110000`,
   `20261115210000`, `20261115230000` + repair migration). Verified live:
   function returns false during a freeze with no date arg; gate denies
   with `membership_inactive`.
3. **Invite flow broken live (D1, DB-40 again).** `invite_gym_member`
   calls unqualified `gen_random_bytes(18)`; on Supabase pgcrypto lives in
   the `extensions` schema and the function sets
   `search_path TO 'public','auth','pg_temp'` → 42883. Locally pgcrypto was
   in `public`, masking it. Fix: `extensions.gen_random_bytes` (source file
   `20261115360000` + repair migration). Same latent defect in
   `hash_member_credential` (`hmac()` → `extensions.hmac`, source file
   `20261115010000` + repair migration); verified it now raises the pepper
   error, not 42883. Repair migration: `20261115190000_phase1g_live_fixes.sql`
   (also applied live; chain is now 61 files).

### Test artifacts (not product failures — read before re-running)

- A3 (run 2): the profile was already `paid` from run 1's payment, so the
  self-pay PATCH was a no-op 200. Clean retest (R1, pending client-b) → 400
  guard, as in run 1.
- C14b/C14c (run 2): the client had TWO paid payments (run 1 + run 2);
  voiding one correctly leaves the other. Clean retest (R3, both voided) →
  profile `pending`, end date NULL, gate denies.
- R2b expectation was wrong (expected 2027-01-15, got 2026-12-15): run 2's
  void had already reverted the end date to the single remaining payment's
  end; the DIAG-freeze cancel rollback to 2026-12-15 is exactly correct.
- R3a-83d57cf7: re-voiding an already-voided payment → 400
  `payment_immutable` — the immutability guard working, not a failure.
- R6a (part 1): a FUTURE session cannot be marked no-show
  (`invalid_state`) — correct guard; retested with a today session (R6a pass).
- H1/H3 (run 2) + R5a/R5c (retest-2): wrong test inputs, not product bugs —
  `text/plain` is not an allowed bucket MIME (only png/jpeg/webp), and the
  upload path must be `profiles/<gym_id>/<user_id>/...` per the storage
  policies. Corrected probes pass.
- D3 (run 2) "passed" for the wrong reason (invite never issued); retested
  properly in R4f (exact message: "This invitation has expired.").
- E1/G1 400s in run 2 were the email rate limiter already engaging; R8
  retries return 429 for both `@trainw.live` and `@gmail.com` addresses.

### Decisions made during the run (user, 2026-11-15 08:12)

- **DB-66 = CREDIT.** No-show credits the member for rebooking; money stays
  in the gym. Verified what exists: marking a session no-show leaves all
  payments `paid` and the profile `paid` (R6b). A dedicated credit-balance
  mechanism does NOT exist in code (no `credit` concept in migrations or
  functions) — implementing it is a follow-up code task, not blocking.
- **P2-10 = DELETE src/.** Ship vanilla only. Consequence: the 9 NX findings
  (NX-02/04/05/08/09/10/14/28 + NX-03, plus NX-01 which is the same src/
  situation) can no longer be live-tested and are marked SUPERSEDED in
  `AUDIT_CLOSURE.md`. The `src/` deletion itself is a follow-up code task —
  NOT done in this run.
- **hCaptcha keys no longer needed for launch.**

### Still open after P1-13

- `ANTHROPIC_API_KEY` — needed from the user before ai-proxy works at all.
- Pepper GUC — needs a code change (different pepper source) or a dashboard
  attempt; credential enrolment stays fail-closed until then.
- DB-66 credit-balance mechanism — follow-up code task.
- `src/` deletion (P2-10) — follow-up code task.
- GT-03 gate throttle — deliberately NOT hammered live (would lock the test
  terminal); local suite proves the limiter. A live throttle test is still
  owed if wanted.
- Password-reset delivery — blocked by the default-mailer rate limit (429);
  retry after the window, and consider a custom SMTP before real users.
- Realtime `private_only` — needs a code change first (private channels +
  `realtime.messages` policies) before flipping.
- Production deploy — only on his word. Accountant check on TEIF fields.
- `AUDIT_CLOSURE.md` counts after this run: **124 FIXED+VERIFIED,
  1 FIXED+NEEDS-LIVE-TEST (GT-03), 2 DECISION MADE — CODE FOLLOW-UP
  (DB-66, NX-03), 9 SUPERSEDED (NX rows), 1 NOT-APPLICABLE (GT-04).**

### Test-data inventory + cleanup (do NOT run until verification is done)

Gyms: `TEST — Gym A` (28b82a5f…), `TEST — Gym B` (cc1b019a…).
Auth users (`@trainw.live`): `test-{a,b}-{owner,manager,staff,coach,client}`,
`test-invitee`, `test-invitee2`; plus `trainw-live-test-xyz123@gmail.com` and
`test-signup@trainw.live` (never confirmed — G1 signup failed at the rate
limiter; check whether the row exists before deleting).
Live rows created: gyms ×2, gym_memberships (10 + invitee ×1 active +
invitee2 pending-expired), client_profiles (auto, 10 + invitees),
coach_profiles ×2, payments ×3 (2 voided, 1 paid — client-a's current paid
payment `36aac56f-65e9-4e0c-a283-f71c668bf634`), sessions ×3 (1 no-show,
1 future, 1 today-no-show), messages ×2, gate_sessions (many, expired/used),
gate_terminal_sessions ×1–2, gate_access_log rows, check_ins rows,
membership_freezes (all cancelled), storage object
`trainw-media/profiles/<gym-B>/<client-B>/test-b.png`.
Cleanup (exact): delete the storage object; delete the two gyms
(`DELETE FROM public.gyms WHERE name LIKE 'TEST — %'` cascades memberships,
payments, sessions, messages, freezes, profiles where FKs cascade — verify
row counts after); delete the auth users via the Admin API
(`DELETE /auth/v1/admin/users/{id}` for each test address, which also removes
their `public.users` rows via the sync trigger — verify); delete
`test-signup@trainw.live` if present. Passwords for the test accounts are in
`/tmp/live-test-users.json` (0600, not committed).

---

## Round 7 — P1-13 follow-ups + the two launch decisions (2026-11-15)

Commits (local only, NOT pushed — parent pushes): `cd19191` (P2-10 src/ deletion),
`d5af77c` (DB-66 credits + table pepper), `f974126` (Phase 1h chain-order repair).
Docs: `AUDIT_CLOSURE.md` updated in the same round (see footer).

### 1. P2-10 — DELETE src/ (commit cd19191)

User decision 2026-11-15 08:12: ship vanilla only. Removed the whole Next.js app
(93 files: `src/` + Next-only `public/` favicons + `next.config.ts`,
`next-env.d.ts`, `tsconfig.json`, `tailwind.config.ts`, `postcss.config.js`,
`vitest.config.ts`, `eslint.config.mjs`, `package-lock.json`).
`package.json` trimmed to static-only scripts (build/dev/preview/verify, no
dependencies); CI keeps only the static-app job. Docs updated (runbook §1/§3/§4/§7,
CLIENT_CODES.md, README.md): CAPTCHA keys no longer needed for launch.
Verified: `node env-config.js` generates dist and `npm run verify` passes
("Trainw verify: all checks passed") — dummy values must be non-placeholder
(`https://dummy123.supabase.co`, `dummy-anon-key-xyz123`).
Consequence: all 29 NX findings are now SUPERSEDED (19 verified-in-code + NX-03
+ the 9 already superseded); they can no longer be live-tested.

### 2. DB-66 — CREDIT (migration 20261116090000, commit d5af77c)

Design (ledger-style, like the payments ledger):
- `member_credits` — gym, client, amount, amount_remaining, source session +
  source payment, status available/fully_applied/expired, created_by, timestamps.
  Partial unique index on source_session_id = double-credit guard. RLS SELECT-only
  for managers + owning client; NO write policies for app roles (only RPCs write).
- `member_credit_applications` — append-only audit (credit, payment, amount).
- `mark_session_no_show` extended: inserts the credit atomically in the same
  transaction. Credit = net collected = payment.amount_paid − amount_refunded,
  only when the session's payment is 'paid'. Unpaid pending sessions and free
  sessions credit nothing. Sessions marked no-show before this migration get no
  credit; no backfill.
- `apply_member_credit_to_session(p_session_id)` — applies available credits FIFO
  to the session's PENDING payment (amount_paid grows, status → 'paid' when fully
  covered; the ledger guard explicitly allows amount changes on pending rows;
  the settlement trigger ignores session payments).
- `get_member_credit_balance(p_client_id, p_gym_id)` — self or manager.
Frontend hook is a follow-up: after `book_coach_session`, call the apply RPC;
the balance helper drives the "you have X TND credit" display.

Local verification (throwaway cluster, see harness notes below): **33/33
assertions pass** — no-show credits 80; idempotent re-mark; unpaid + free
sessions credit nothing; balance self/manager/other-gym; full apply (80/80,
payment paid, credit fully_applied, application row); partial apply (50 of 80,
payment stays pending owed 30); cross-gym apply forbidden (client + manager);
apply with no credit → 0; direct INSERT denied by RLS; no forged credit;
coach marks own no-show → credits; end-to-end via `book_coach_session`.

Live verification (project caylegavnekidhytlswo, 2026-11-15, harness
`/tmp/live-r7.py`, report `/tmp/live-r7-report.json`): **14/14 PASS** —
fixtures (12 users, 2 gyms); pepper set; coachA 80/session + availability;
no-show call; credit 80 available; no double-credit on re-mark; apply pays
the rebooking in full (applied 80, owed 0); payment paid by credit; balance 0;
credential enrol (201) + hashed/cleared/ref-truncated; validate grants access
(days_left 30); cross-gym validate denied; balance RPC as the client.
Note: the live harness is resumable (reuses today's no-show + credit if a run
already created them) and uses 14:00 tomorrow for the rebooking — coachA
already holds a confirmed session tomorrow 10:00 from P1-13.

### 3. Pepper off the GUC (migration 20261116080000, commit d5af77c)

The pepper GUC `trainw.member_credential_pepper` CANNOT be set via the
Management API (ALTER DATABASE/ROLE denied 42501; the config endpoint rejects
custom GUCs), so credential enrolment/validation failed closed live.
- `public.app_secrets` — key PK, value, timestamps. RLS ON with NO policies:
  every app role denied; only owner postgres + SECURITY DEFINER functions read
  it; service_role bypasses RLS (operator path).
- `hash_member_credential` rewritten as SECURITY DEFINER reading the pepper
  from `app_secrets` (key `member_credential_pepper`), still fails closed when
  the row is missing; uses `extensions.hmac` (Supabase layout).
- `member_credential_pepper()` (GUC reader) DROPPED.
- The pepper VALUE was generated fresh (32 random bytes, hex) and set live via
  the API only — NEVER in any migration, file, or commit, never printed.
  Live verification: enrol + validate work (see §2 live results).
- Runbook §3 updated: the value lives ONLY in the live DB. Back it up —
  `pg_dump` includes `app_secrets`; if the DB is lost without a dump, every
  enrolled credential must be re-enrolled. Rotating the pepper invalidates
  all existing credential hashes.

### 4. Phase 1h — chain-order repair (commit f974126)

Found while building the round-7 local harness: the 1g commit (8873d82) broke
FRESH chain applies (the live DB never saw it — live applied before 1g, and
15190000 was applied as a patch afterwards):
- 1g added `public.gym_today()` calls to `20261115110000`, `20261115190000`,
  `20261115210000`, but `gym_today` is only created in `20261115230000`
  (SQL-language functions are validated at CREATE, so all three files failed).
  Fix: `gym_timezone`/`gym_today` are now also defined in `20261115110000`
  (verbatim copies of the canonical definitions; `gyms.timezone` exists since
  the foundation); `20261115230000` redefines them identically.
- 1g changed `membership_is_active_for_access`'s freeze clause (raw
  p_reference_date → COALESCE with gym_today) without updating the DB-61
  frozen hashes in `20261115210000` / `20261115230000` / `20261115330000`.
  Hashes recomputed empirically from the current bodies (same md5 formula as
  each file): 15210000 `080cc52b8697f1dd16d6ec97a70ca127`, 15230000
  `45fdc7f004152f175c06411c6c660a29`, 15330000 `3a70bd4a318b5ee8b55ce0473161e5a8`.
  `20261115300000` is UNTOUCHED: its formula is non-portable by design
  (proargdefaults::text embeds OIDs) and `20261115330000` is its repair.
Final definitions are unchanged; the live DB is unaffected (only the two new
migrations were applied live — the edited old files were NOT re-applied live,
which would have regressed intermediate definitions).
Fresh chain now applies **61 OK + the 2 known by-design failures**
(`20261115050000` B5 return-type, `20261115300000` DB-61 non-portable hash).

### 5. Password-reset retest — still 429

Retested 2026-11-15 ~08:00 via `/tmp/r7-reset-test.py` (anon key via sb-api.py,
never printed; one call, no hammering): still **429
`over_email_send_rate_limit`** — project-wide default-mailer limit, window not
cleared since P1-13. Custom SMTP is the user's decision; NOT set up.
The default mailer does not suffice for testing password reset.

### 6. ai-proxy / ANTHROPIC_API_KEY — blocker, no key sought

`supabase/functions/ai-proxy/index.ts`: needs edge secret **`ANTHROPIC_API_KEY`**
(line 177: `Deno.env.get('ANTHROPIC_API_KEY')`); model
**`claude-haiku-4-5-20251001`** (Claude Haiku 4.5, line 210), max_tokens 1024,
Messages API, `anthropic-version: 2023-06-01`. The user has no Anthropic API
access — AI features are blocked until he gets one.

### Local test harness (round 7) — environment notes for future rounds

This VM has NO Postgres installed and no usable apt cache at the time.
- `apt-get update` took 8m11s over the egress proxy (10.5 MB @ ~21 kB/s);
  the EDB binary tarball 403s. Source build was faster and is now the
  documented route: postgresql-16.4 tarball from ftp.postgresql.org,
  extract with `--no-same-owner` (uid-1107 ownership fails in this
  user-namespace container), `./configure --prefix=$HOME/workspace/.r7-scratch/pgsql
  --with-openssl --without-readline --without-icu --without-libxml
  --without-libxslt --without-ldap --without-pam`, `make -j4 && make install`,
  plus `make -C contrib/{pgcrypto,btree_gist,citext} install`.
- `--without-openssl` DOES NOT WORK: pgcrypto's Makefile compiles openssl.c
  unconditionally and references `EVP_cast5_cbc`; without libcrypto linked the
  .so fails to load (`undefined symbol`). Build WITH openssl (libssl-dev
  headers are present; libcrypto.so.3 exports the symbol). After changing the
  flag, `make clean` first — stale .o files cause duplicate-symbol link
  failures (fe-secure.o vs fe-secure-openssl.o).
- `initdb` refuses root: run the server as `nobody` (uid 65534;
  `setpriv`/`runuser` work, `chown` to nobody does NOT — create the datadir
  AS nobody). Datadir `/tmp/r7-pgdata` (tmpfs is fine — the cluster is small);
  socket in /tmp; port 54400; DB trainw_r7.
- The exec shell runs `umask 0007`, so a fresh `make install` leaves the
  install tree group-only: the nobody server then cannot read
  `share/timezone/*` (`pg_timezone_names` empty, "time zone Africa/Tunis not
  recognized"). Fix: `chmod -R o+rX` on the pgsql tree AFTER every install,
  then restart the server.
- Harness: `~/workspace/.r7-scratch/` — `r7-harness.sh` (port 54400),
  `r7-tests.sql` (33 assertions), `supabase-stubs.sql` (r6 stubs PLUS an
  `extensions` schema with pgcrypto installed there — mirrors Supabase, so
  `extensions.hmac`/`extensions.gen_random_bytes` resolve locally exactly as
  on live; the chain's `CREATE EXTENSION IF NOT EXISTS pgcrypto` then no-ops).
  Test bugs fixed this round (not product bugs): four assertions compared
  jsonb `->>` text `'80'`/`'50'`/`'0'` against numeric(10,2) values that
  render `'80.00'`/`'50.00'`/`'0.00'` — now compared as `::numeric`.

### Closure recount after round 7 (AUDIT_CLOSURE.md, head f974126)

**106 FIXED+VERIFIED, 1 NEEDS-LIVE-TEST (GT-03), 0 DECISION MADE,
29 SUPERSEDED, 1 NOT-APPLICABLE = 137.** By severity: CRITICAL 7 verified;
HIGH 33 verified, 1 needs-live, 5 superseded; MEDIUM 42 verified, 11
superseded, 1 N/A; LOW 24 verified, 13 superseded.
The drop 124 → 106 is NOT a regression — 19 NX findings verified in code are
now moot because the app was deleted. DB-66 → FIXED+VERIFIED (built + locally
tested + live-tested). All 29 NX findings SUPERSEDED.

### Live test-data inventory — round-7 additions (do NOT delete)

On top of the P1-13 inventory: coachA `price_per_session` = 80 + availability
all week 08:00–20:00; payments +2 (1 paid 80 session payment, 1 pending→paid
80 rebooking payment); sessions +2 (today 09:00 no-show, tomorrow 14:00
confirmed/pending→paid); member_credits ×1 (fully_applied, 80, source = the
no-show session); member_credit_applications ×1 (80); member_credentials ×1
(clientA RFID `R7LIVEBADGE001`, label "R7 live badge"); `app_secrets` ×1
(`member_credential_pepper` — the VALUE is live-only, never recorded here).
ClientA's check_ins + gate_access_log rows for today were deleted before the
credential validation test (P1-13 leftovers that would have masked the result
as duplicate_checkin_today).

### Still open after round 7

- `ANTHROPIC_API_KEY` (ai-proxy fails closed without it — he has no Anthropic
  API access; AI features blocked until he gets one).
- GT-03 gate throttle deliberately NOT hammered live (local suite proves the
  limiter; a live throttle test is still owed if wanted).
- Password-reset delivery blocked by the default-mailer rate limit (429) —
  retry after the window, consider custom SMTP before real users.
- Realtime `private_only` needs a code change first.
- Production deploy only on his word; accountant check on TEIF fields.
- Frontend hook for the credit flow (call `apply_member_credit_to_session`
  after `book_coach_session`; balance display) — not built yet.

## Round 8 — DB-66 credit frontend hook (2026-11-15)

Frontend only: no SQL changes, no new migrations, no live writes. RPC
signatures verified against migration `20261116090000` (not guessed):
`apply_member_credit_to_session(p_session_id uuid)` RETURNS jsonb
`{applied, remaining_owed, payment_status}`; `get_member_credit_balance(p_client_id, p_gym_id)`
RETURNS numeric(12,2). `book_coach_session` RETURNS uuid (the new session
id), so the apply call takes `r.data` directly.

Client view (`tw-client-acc.js`):
- `bookSelectedSession` now calls `applyCreditToBooking(r.data)` after a
  successful booking, before the reload. The helper calls the apply RPC
  with `{context:'apply member credit', fallback:null, toastOnError:false,
  silent:true}` and ends with exactly one toast: applied > 0 → the
  credit-applied toast (amount + remaining owed); applied 0 → the usual
  booking-saved toast; a real failure → the credit-failed toast (the
  booking is saved, settle at the gym).
- Two benign apply failures are treated as no-ops (booking-saved toast):
  free sessions have no payment row (`validation_error: session has no
  payment to apply credit to` — `book_coach_session` only creates a
  payment when price > 0), and a payment that is already settled has
  nothing left to owe (`invalid_state: ... pending payment`). Matched on
  the RPC exception text in `error.message`, the same pattern
  `isJoinGymInvalidError` already uses for invite errors.
- Balance display: `loadData` fetches `get_member_credit_balance` (self)
  into `memberCreditBalance` (silent fallback 0, never blocks the
  dashboard); `renderDashboardHero` appends ` · Crédit disponible : X DT`
  to the membership copy when the balance is > 0, and shows nothing extra
  at zero — same element/style as the membership display.
- New `creditBalance` / `creditApplied` / `creditApplyFailed` keys in the
  fr/en/ar `T` dicts.

Manager view (`tw-gym-acc.js` + `tw-gym-acc.html`, payments page):
- `refreshPayCreditBalance()` shows the selected member's available
  credit (`Crédit disponible : X DT`, via `Trainw.formatCurrencyDT`) in a
  `#pay-credit-balance` line under the record-payment form, empty at zero
  or on failure. Refreshed on `loadPayments`, on `pay-client-select`
  change, and in `openPaymentsFor`. A staff user without the manager role
  sees nothing — the RPC only returns a balance to the member or a gym
  manager, by design.

Encoding note: `tw-client-acc.js` is double-encoded UTF-8 (76
double-encoded é sequences; pre-existing, out of scope). The new French
strings are written as proper UTF-8 and will render correctly; the
neighbours' mojibake is unchanged. `tw-gym-acc.js`/`.html` are proper
UTF-8 already.

Verification: `node --check` clean on both touched JS files; `node
env-config.js` + `npm run verify` pass ("Trainw verify: all checks
passed", dummy Supabase values as in round 7); `dist/` contains the new
RPC calls and the balance element. Not live-tested in a browser (no
logged-in session in this VM) — the end-to-end click path (book →
credit applied → hero balance drops) is the one remaining check, and it
needs a real member login against the live project.

Open: nothing in code. The P1-13 live-test agent's results and the two
launch decisions (DB-66 CREDIT, P2-10 delete src/) are recorded in the
round-7 appendix; this round closes the "frontend hook" open item listed
there.

## Round 9 — Production signup: owner / client / coach onboarding + join flow (2026-11-15)

User authorised production readiness 2026-11-15 ~10:41 ("Make it production
ready, people can sign up and sign either as gym owners, clients or coaches..
each with their own dashboard and info. Data returns to db for future use.").
Commits (local, branch phase1-security-fixes): `3fcb81b` (signup + join flow),
`6e9cf8d` (anon revoke). The parent pushes; the squash-merge into `main` is
staged, not run — see "Production deploy (staged)" below.

### Step 1 — flow audit (verified against code AND the live DB)

Three stacked breaks, all in onboarding (dashboards themselves work once a
membership exists — client/coach/gym dashboards load their own data, and
P1-13 proved cross-gym isolation):

1. **Owner signup BROKEN.** `handle_new_user()` creates every signup as a
   bare client, and `bootstrap_authenticated_user()` gave the existing
   profile role precedence over the explicit `p_role` — a signup as
   gym_owner with a gym name stayed role='client' and no gym was ever
   created. The users upsert preserved the old role too. Confirmed live
   via `pg_get_functiondef`.
2. **Even with a gym, the owner had no workspace.** The round-2 rewrite
   dropped the 007 owner-membership insert AND the
   `ensure_gym_default_roles` call. `get_auth_context` reads memberships
   ONLY, so the owner would see "no workspaces" and the admin dashboard
   would bounce them to /role. No `provision_new_gym`/`create_gym` RPC
   exists in the vanilla chain — bootstrap is the only owner-creation path.
3. **No self-serve join path for clients/coaches.** Only owner invite
   existed; /role dead-ended with "No active workspace is linked to this
   account yet". A stranger signing up as client/coach could never reach
   a gym. No coach-approval UI existed either (invite-accepted coaches are
   auto-approved; bootstrap-created coach profiles are 'pending' with no
   way to approve them).
4. Email confirmation is the signup gate (`mailer_autoconfirm=false`).
   The default mailer 429'd in P1-13; see "Mailer observation" below.

### Step 2 — fixes

**Migration `20261116100000_phase1i_signup_owner_join.sql`** (601→624 lines):

- Bootstrap: a FRESH bare client (role='client', no gym, no memberships,
  manages no gym) may claim the explicit role — gym_owner (only with a
  gym name: a gym is created and the caller becomes its manager + active
  gym_owner member) or coach (pending gymless coach profile, as designed).
  Anyone else keeps their existing role (DB-10/DB-11 preserved). Adoption
  is unchanged: a gym is adopted ONLY when manager_id is the caller;
  metadata gym_id is still ignored outright. Restored the 007 owner
  membership insert (active, accepted, is_default, sets
  default_gym_id/default_membership_id) and the `ensure_gym_default_roles`
  call (guarded to gyms the caller manages). A fresh owner claim that ends
  gymless (e.g. name collision — see below) falls back to client instead
  of minting a gymless owner.
- New RPCs (SECURITY DEFINER, caller checks, REVOKE FROM PUBLIC+anon,
  GRANT TO authenticated): `list_public_gyms()` (id/name/address/location/
  logo only — no email/phone/owner/prices/tax/PIN); `request_gym_membership`
  (client/coach only, idempotent on existing pending/active);
  `approve_gym_membership` / `reject_gym_membership` (manage_staff only,
  join REQUESTS only — invite_token IS NULL, so an invite can never be
  approved past the invitee; on approval the profile is linked — a coach
  becomes approved — and the legacy projection syncs, as accept does).
- No RLS policy was touched.

Two real bugs caught by the local suite while building this (both fixed
before any live apply):
- `approve_gym_membership` used `ON CONFLICT (user_id)` on
  client/coach_profiles — neither table has a unique on user_id alone
  (uniques are partial `(user_id, gym_id) WHERE gym_id IS NOT NULL`), so
  every approval raised and rolled back. Replaced with the bootstrap
  pattern (UPDATE the existing row if there is one, else INSERT).
- Gym names are NOT unique: the creation block's `ON CONFLICT DO NOTHING`
  can never fire, so a same-name signup creates a second gym with that
  name, owned by the requester. Not an adoption (gym A keeps its manager;
  the requester gets no membership in gym A) and not a security issue —
  gyms are distinguished by id — so no constraint was added (product
  decision). Test T8 asserts the no-adoption property.

**Frontend:**
- `/role` (`tw-role.js` + `tw-role.css`): when the signed-in user has no
  usable workspace, a join directory lists public gyms with a client/coach
  toggle and a "Request to join" button per gym (`list_public_gyms` /
  `request_gym_membership` RPCs). Pending requests render as cards above
  (existing pattern); the directory stays until one is approved.
- Gym dashboard (`tw-gym-acc.js` + `.html`): the pending list now splits
  join requests from owner invites — requests are recognised by
  `invited_at IS NULL` (only owner invites set it; `get_staff_directory`
  returns no invite_token/invited_by) and render with Approve / Decline
  (`approve/reject_gym_membership`) instead of Resend / Cancel. Section
  title/subtitle updated (FR/EN; AR falls back to FR via `t()`).

### The anon-grant discovery (DB-03/DB-04 were still exploitable)

While verifying the new RPCs' grants live, every sampled function carried
an explicit `anon=X` grant — including `ensure_gym_default_roles` and
`ensure_role_permission_codes`, the DB-03/DB-04 role functions round 1
"revoked". Cause: Supabase's default privileges grant EXECUTE on a new
function explicitly to anon, authenticated AND service_role (plus
Postgres's own PUBLIC default). `REVOKE FROM PUBLIC` removes only the
PUBLIC pseudo-grant; the explicit anon grant survives on every function
the chain ever revoked.

**Proved live (TEST data only):** with the anon key alone and NO
Authorization header, `POST /rest/v1/rpc/ensure_gym_default_roles` on
'TEST R9 Anon Probe Gym' returned HTTP 204 and seeded 5 default roles
(0 → 5). The P1-4 internal check cannot stop this: it treats
`auth.uid() IS NULL` as trusted server/migration context, so the grant
was the only barrier — and it was never there. Any stranger holding the
publishable anon key could rewrite any gym's roles/permissions. The
P1-13 live matrix tested the authenticated non-admin case (which the
internal check does block) but never the anonymous case.

**Fix — migration `20261116110000_phase1i_revoke_anon_rpc.sql`:** revokes
EXECUTE from `anon` (and PUBLIC) on all 36 functions the chain ever
revoked from PUBLIC, including the 4 round-9 RPCs (each guarded by an
existence check). Authenticated grants untouched; internal SECURITY
DEFINER callers run as owner and are unaffected. The round-9 migration's
own REVOKE lines were also changed to `FROM anon, PUBLIC` so fresh
applies are correct. **Live verification:** all 36 ACLs now show only
`postgres/authenticated/service_role`; the same anonymous call now
returns **401 permission denied for function ensure_gym_default_roles**,
and the probe gym's role count is unchanged (5, from the proof call).
AUDIT_CLOSURE.md DB-03/DB-04 rows updated to record the correction and
the anonymous re-test; closure counts unchanged (they were counted
FIXED+VERIFIED, and now genuinely are).

Note for future rounds: any new RPC must revoke from `anon` explicitly,
not just PUBLIC — `REVOKE ALL ON FUNCTION f(...) FROM anon, PUBLIC;`
is now the chain convention. The local throwaway cluster does NOT
reproduce Supabase's default privileges, so this class of issue is only
visible live.

### ALLOWED_ORIGIN — the gate functions' CORS was broken

The gate edge functions (`gate-checkin`, `gate-feed`, `gate-terminal-auth`)
read `ALLOWED_ORIGIN` for `Access-Control-Allow-Origin`; the project only
had `APP_ORIGINS` set (which only `ai-proxy` reads). Live probe returned
`Access-Control-Allow-Origin: null` for the production origin — every
browser call to `gate-feed` (used by `gate-terminal.js` via fetch) would
be blocked by CORS. Set the `ALLOWED_ORIGIN` edge secret to
`https://trainw.vercel.app` via the Management API; re-probe returns
`Access-Control-Allow-Origin: https://trainw.vercel.app` (still 503
turnstiles_disabled, as expected while turnstiles are off). `APP_ORIGINS`
remains for ai-proxy.

### Local verification

Throwaway Postgres 16.4 cluster (round-9 scratch: `/tmp/r9-pgsql`,
datadir `/tmp/r9-pgdata` as `nobody`, port 54401 — the /home mount blocks
unmapped-uid exec, so the install tree had to be copied to /tmp; harness
`~/workspace/.r9-scratch/r9-harness.sh`, tests `r9-tests.sql`):
- Full chain applies: **63 OK, 2 FAIL** — the 2 are the known by-design
  failures (`20261115050000`, `20261115300000`), identical to rounds 6–8.
- **27/27 round-9 assertions pass** (T00–T20): trigger creates bare
  clients; owner signup creates gym + active owner membership + defaults
  and shows in `get_auth_context`; existing owner cannot be downgraded;
  owner claim without a gym name stays client; plain client/coach signups
  behave; same-name signup does not adopt the existing gym; a member
  cannot mint an owner gym; directory lists active gyms only; join
  requests pending + idempotent; gym_owner/unknown/inactive requests
  refused; owner approval activates + links profiles + syncs projection;
  outsider and other-gym owner cannot approve; an invite cannot be
  approved; reject + re-request works; coach approval approves the
  profile; multi-gym second membership keeps the first default; outsider
  sees only their own memberships.
- `node --check` clean on `tw-role.js`, `tw-gym-acc.js`.

### Live verification (live project caylegavnekidhytlswo)

Migration `...100000` applied via Management API (`[]`, success); the
revoke migration applied the same way. Live flow test
(`/tmp/r9-live-flow.py`, Admin-API-created pre-confirmed TEST users,
real PostgREST RPCs with per-user JWTs — passwords random per run, never
stored):
- Owner `r9-live-owner@trainw.live` → bootstrap gym_owner + 'TEST R9
  Live Gym' → role gym_owner, gym created, manager is the owner.
- Client + coach bootstraps → roles client / coach.
- Directory as client lists 4 gyms including TEST R9 Live Gym (the
  inactive probe gym is excluded).
- Client + coach join requests → pending, second identical request
  returns `already_requested: true`, no duplicate row.
- Outsider approve → 400 "You do not have permission..."; client
  gym_owner request → 400 "Join requests are only open for client and
  coach roles."
- Owner approves both → active. `get_auth_context` per role: exactly 1
  membership each — gym_owner / client / coach @ TEST R9 Live Gym.
- DB rows verified: gym manager is the owner; all 3 users correct role,
  in the gym, with default gym; 3 memberships active/accepted/is_default;
  client profile in gym (1); coach profile approved + in gym.

**Mailer observation (public signup, anon key only):** a signup with
`r9-live-signup-probe@trainw.live` was rejected at validation —
`400 email_address_invalid` (trainw.live has no MX; Supabase validates
the domain). No user row was created. A signup with a VALID deliverable
inbox could not be tested in this round without using the user's own
email — so confirmation-email deliverability on the default mailer
remains unverified live. P1-13's evidence stands: password-reset delivery
hit `over_email_send_rate_limit` (429) on the default mailer. Production
signup confirmation is therefore AT RISK until custom SMTP is configured
— still the user's decision; do NOT set it up unprompted.

### Production deploy (staged — parent runs it)

- `main` is still `e10932c` (verified via fetch). Local branch tip
  `6e9cf8d` (round 9). Diff `e10932c..HEAD`: 196 files, +20,648/−22,063
  (includes the P2-10 src/ deletion). Secret scan of the diff: no keys,
  tokens, or passwords — hits are audit-closure prose only.
- The squash-merge IS doable via the Git Data API with the existing
  helper — the parent runs:
  `python3 ~/workspace/custom-connectors/custom.github/bin/gh-push-branch.py ~/workspace/goals/build-trainw/phase1-fixes TheWeedMan404/Trainw main e10932c ~/workspace/goals/build-trainw/merge-message-main.txt`
  (one commit on main, parent = e10932c, tree = phase1 tip tree;
  fast-forward, no force-push, no history rewrite; masar untouched).
  Message file: `~/workspace/goals/build-trainw/merge-message-main.txt`.
- Vercel project `trainw` (prj_VIPLkqSbwcOp0IP8zTJaU1R8E76J):
  productionBranch `main`, framework null. **Production is already
  public:** `https://trainw.vercel.app` returns HTTP 200 and serves the
  real landing page (preview deployments are behind Vercel
  Authentication, 302 to SSO — production is not). No protection setting
  needs changing. After the merge, verify the production deployment for
  the new main tip is READY via the Vercel API.
- Supabase auth config re-verified: `mailer_autoconfirm=false`, no custom
  SMTP, redirect allowlist
  `https://trainw.vercel.app/tw-login.html,https://trainw.vercel.app/auth/reset-password`,
  JWT 3600s, refresh-token rotation ON. Edge secrets: `APP_ORIGINS` and
  the new `ALLOWED_ORIGIN` both cover `https://trainw.vercel.app`.

### Live test-data inventory — round-9 additions (do NOT delete)

- Gym: 'TEST R9 Anon Probe Gym' (`60000000-6000-6000-6000-6000000000b9`,
  manager test-a-owner) + its 5 default roles (seeded by the anonymous
  proof call — the evidence for the hole).
- Gym: 'TEST R9 Live Gym' (`e0d210d5-a4fd-4287-acd4-19c0a95270ad`,
  manager r9-live-owner) + 3 active memberships + client/coach profiles.
- Auth users: `r9-live-owner@`, `r9-live-client@`, `r9-live-coach@`,
  `r9-live-outsider@trainw.live` (ids in the flow-test output; passwords
  were random per run and are NOT recorded). The signup probe created no
  user. On top of the P1-13/round-7 inventory (2 TEST gyms, 13 test users,
  3 test payments — plus the round-7 additions).

### Still open (user-side) after round 9

1. **Production merge** — staged, parent runs the command above; then
   verify the production deployment is READY and re-run the Step-5 live
   check on production (test owner signup on the production URL).
2. **Custom SMTP decision** — default mailer 429'd in P1-13; confirmation
   deliverability for real inboxes unverified. Until decided, a stranger
   signing up may never receive the confirmation email.
3. **ANTHROPIC_API_KEY** — ai-proxy fails closed without it; AI features
   blocked (user has no Anthropic API access).
4. **GT-03 live throttle test** — still the one NEEDS-LIVE-TEST item.
5. **Accountant check** on TEIF e-invoice fields before the first real
   invoice.
6. **Test-data cleanup** on the live project — only after verification.
7. **Browser click path untested** — the join directory + approvals UI
   and the round-8 credit click path have not been exercised in a real
   browser (no live-browser access in this session). Needs a real member
   login against live/production in a browser.
8. Observations, not fixed: duplicate gym names allowed (see above);
   `accept_gym_invitation` inserts a second coach profile row when the
   invitee already has a pending gymless one from a coach signup
   (pre-existing; the approve path uses UPDATE-first instead); the /role
   join directory only shows when the user has no usable workspace
   (multi-gym joining from /role is a possible follow-up).

## Round 10 — production dashboard observations (2026-11-15)

Four observations from the production browser verification (2026-11-15
~11:53–11:55, https://trainw.vercel.app, all three TEST accounts signed in
fine — owner@test.com / coach@test.com / client@test.com, all active members
of TEST Gym `8a07bf89-ff6e-40f9-8feb-c384d6b47e5c`). User said "Fix them".
No RLS policy changes, no caller-check weakening, no new secrets, no SQL
migrations. 7 files changed, frontend only.

### Issue 1 — transient "Unexpected error. Please try again." toast on /admin load

**Root cause (proven, not guessed).** `tw-gym-acc.js:5287`, the last line of
`loadAnalytics()`:

```js
if (clientCountResult.error || coachCountResult.error || sessionsResult.error || paidThisMonth.error) toast(t('errorMsg'), 'err');
```

`clientCountResult` and `paidThisMonth` occur NOWHERE else in the codebase
(grep across all JS/HTML excluding dist: no other occurrences) — stale names
left from an earlier shape of the function. Node reproduces the exact
`ReferenceError: clientCountResult is not defined`. `loadAnalytics()` is
awaited in `initPage()`, which is called bare at the file's end, so the throw
is an unhandled rejection; the global `unhandledrejection` handler in
`trainw-core.js:1212` toasts exactly "Unexpected error. Please try again."
The dashboard stats still render because the throw happens after they are
set — matching the browser report (toast + otherwise fine dashboard).
`t('errorMsg')` is 'Une erreur est survenue.' / 'Something went wrong.' —
NOT the observed text, which rules out the other toast paths.

**Fix.** The line now checks the four results actually in scope in
`loadAnalytics()`:

```js
if (directoryResult.error || coachCountResult.error || sessionsResult.error || profileResult.error) toast(t('errorMsg'), 'err');
```

`directoryResult`/`coachCountResult`/`sessionsResult` are destructured from
the `Promise.all` at the top of the function; `profileResult` is declared
before the line as `{data: [], error: null}` when there are no client ids.
Preserves the author's intent (error toast if an analytics data call
failed). Verified by a node scope check over the extracted function:
all four names declared in `loadAnalytics`, stale names gone.

**Live check.** All ten admin load-path calls re-run as the owner with a
per-user JWT: `get_auth_context`, `list_gym_member_directory` (3 rows),
`get_staff_directory` (3), `list_role_matrix` (5), users coach count (1),
sessions select (0), `client_profiles` (1), payments ledger (0), messages
count (0), `gate_access_log` (0) — all HTTP 200. No other load failure
lurks behind the fixed ReferenceError. (Two runs died mid-flight on
`IncompleteRead` / `RemoteDisconnected` — the known VM↔Supabase transport
flakiness; `list_role_matrix` re-probed via curl returned HTTP 200, 2095
bytes, 5 roles. The failures were transport, not the RPC.)

### Issue 2 — sign-out delayed ("Déconnexion" needed two clicks)

**Root cause.** All three portals awaited `sb.auth.signOut({scope:
'global'})` (a server round-trip) and only navigated on success. On a
flaky network the call hangs or fails; the gym handler then threw into a
catch that toasted and never navigated, and the coach/client handlers had
no error handling at all, so a failure was an unhandled rejection with no
navigation. Matches the browser report exactly (two clicks, no navigation,
login page only on re-observation).

**Fix (all three portals).** Navigate immediately without waiting on the
server revocation; ignore double clicks with a `window.__trainwSigningOut`
guard; fire the global revocation in the background (`.catch` logs only);
then `await sb.auth.signOut({scope: 'local'})` — local-only, no network,
resolves at once — so the local session is certainly gone before the login
page loads. `tw-gym-acc.js:5603` (replaced the `Trainw.api.run` + throw +
catch handler), `tw-coach-acc.js:544`, `tw-client-acc.js:365` (both were
`await sb.auth.signOut({scope:'global'}); localStorage.removeItem(...);
window.location.href=LOGIN_HREF` with no error handling). Cleanup
(realtime unsubscribe, timers, `trainw_active_gym` removal) still runs
first in each handler.

Residual caveat: if the background global call reads the token lazily it
may find the session already cleared and skip server-side revocation.
Acceptable — the token only ever lived in this browser's cleared storage;
the UX (prompt sign-out) is what matters.

### Issue 3 — gym name missing in coach and client portals

Two separate causes, both fixed.

**Coach — the name was never loaded.** `renderCoachGymSwitcher()`
(`tw-coach-acc.js:106`) hides the switcher when there is ≤1 membership,
so with one gym it never showed. Worse, `loadCoachGymMemberships()`
(`tw-coach-acc.js:104`) queried
`gym_memberships … .eq('status','active').eq('portal','coach')` — but
`gym_memberships` has NO `portal` column (portal lives on `roles`, via
`role_id`); PostgREST rejects the query with 42703
("column gym_memberships.portal does not exist", proven live via curl),
so `coachGymMemberships` was always `[]` — the switcher could never show,
and the failing query also toasted (`Trainw.api.run` defaults
`toastOnError: true`) on every coach load.

**Coach fix.** `loadCoachGymMemberships(memberships)` now builds the list
from the auth context the bootstrap already loads (`ctx.memberships` —
normalized by `loadAuthContext`/`normalizeMembership`, which spreads the
record so `gym_name` survives; `portal`, `status`, `gym_id` included),
filtering to portal `coach` + status `accepted`/`active`, deduped by gym,
sorted by name. The broken query is gone; bootstrap calls it as
`loadCoachGymMemberships(ctx.memberships)`. `renderCoachGymSwitcher()`:
0 memberships → hidden (unchanged, freelance); exactly 1 → static label
("Salle active" / "Active gym" / "الصالة الحالية") + name, using the
membership matching `currentGymId` else the first; 2+ → existing select
(unchanged). New `.coach-gym-switcher-name` CSS rule in
`tw-coach-acc-v17.css` (Bebas Neue 20px `var(--ac)`, mirroring
`.coach-name`).

**Client — no gym element existed.** The sidebar (`.client-info`) had no
gym-name element, and bootstrap never retained the gym name even though
`get_auth_context` returns it (`memberships[].gym_name`, proven live:
`'TEST Gym'` for both coach and client; note the RPC's own
`active_membership` object does NOT carry `gym_name` — `getContext`
overwrites it with the pick from `memberships`, which does).

**Client fix.** Added `<div class="gym-name hidden" id="sidebar-gym-name">`
to `.client-info` in `tw-client-acc.html` (after `.client-label`); added
the `.gym-name` rule to `tw-client-acc.css` (same Bebas 20px accent rule
as the admin sidebar); `tw-client-acc.js` gains module-level
`currentGymName`, set in bootstrap from
`ctx.activeMembership?.gym_name`, rendered in `renderAll()` (hidden when
there is no gym name, i.e. solo mode).

**Verification.** Node simulation of the rewritten
`loadCoachGymMemberships` against the live coach membership payload
returns `[{gym_id: '8a07bf89-…', name: 'TEST Gym'}]`; mixed input
(coach+client, pending, duplicate, null name) filters/sorts/dedupes
correctly; empty/undefined → `[]`. Node DOM-stub simulation of
`renderCoachGymSwitcher`: 1 gym → `<span …>Salle active</span><span
…>TEST Gym</span>`; 2 gyms → the existing select; 0 gyms → hidden + empty.
Live: `gyms` row readable by both coach and client JWTs
(`[{"id":"8a07bf89-…","name":"TEST Gym"}]`), and the auth-context
`memberships[0].gym_name` is `'TEST Gym'` for both.

### Issue 4 — client "abonnement expiré" banner with no plan

**Root cause (proven).** The test client's `client_profiles` row (live DB):
`membership_end_date: null`, `membership_tier: basic`, `payment_status:
pending`. `membershipDaysRemaining()` (`tw-client-acc.js:37`) calls
`Trainw.dateOnly(clientProfile?.membership_end_date)`; `dateOnly`
(`trainw-core.js:200-207`) did `new Date(value)` with no null guard —
**`new Date(null)` is the epoch, so `dateOnly(null)` returned
`"1970-01-01"`** (proven in node; 20,772 days ago). `renderMembershipBanner`
already returns early when daysRemaining is null — it never got null. The
dashboard hero/stat-expiry paths already null-guard the raw value, which
is why they showed neutral '—' / 'No membership data available' while the
banner wrongly showed expired. Call-site audit: 28 `dateOnly` call sites;
all others pass `new Date()`, `now`, or `addDays(...)` results — only the
two client ones pass a nullable DB value.

**Fix (two parts).** (a) Core: `dateOnly` now returns `''` for
null/undefined/'' before `new Date(value)` — no caller depends on
`dateOnly(null) === '1970-01-01'`. (b) Belt-and-braces in
`membershipDaysRemaining()`: returns null early when
`!clientProfile?.membership_end_date`, so the banner logic is explicitly
correct and doesn't rely on `dateOnly`'s behaviour. Result: null end date
→ no banner, hero keeps its neutral copy; a genuinely expired plan (past
end date) still shows the expired banner. No subscription row invented for
the test client.

**Verification.** Node test of the actual fixed `dateOnly` (extracted from
`trainw-core.js`): null → `""`, undefined → `""`, `""` → `""`,
`"2026-12-31"` → `"2026-12-31"`, `new Date()` → `"2026-11-15"`.
Simulated `membershipDaysRemaining(null)` → null (no banner); past end
date → banner shows (expired).

### Round-10 verification summary

- `node --check` clean on all four touched JS files
  (`tw-gym-acc.js`, `tw-coach-acc.js`, `tw-client-acc.js`,
  `trainw-core.js`).
- Static build: `node env-config.js` + `npm run verify` — "all checks
  passed" (env vars fetched from the Supabase Management API into the
  build process env only, never printed; `dist/` rebuilt).
- Live (per-user JWTs, TEST accounts): the 10 admin load-path calls all
  200; auth-context `memberships[0].gym_name === 'TEST Gym'` for coach and
  client; `gyms` name readable by coach and client; the old coach
  `gym_memberships … portal` query proven to fail live (42703).
- Files changed: `tw-gym-acc.js` (issues 1, 2), `tw-coach-acc.js`
  (issues 2, 3), `tw-client-acc.js` (issues 2, 3, 4),
  `tw-client-acc.html` + `tw-client-acc.css` (issue 3),
  `tw-coach-acc-v17.css` (issue 3), `trainw-core.js` (issue 4).
- **Not verified in this session (no live-browser access):** the actual
  browser render of all four fixes — no more toast on /admin load,
  one-click sign-out landing on the login page, "TEST Gym" visible in the
  coach/client sidebars, no expired banner for the plan-less client.
  Browser re-check happens after the parent deploys. Also not re-tested
  in a browser: the coach multi-gym select path (code unchanged, only its
  data source changed) and the genuinely-expired banner path (logic
  unchanged, only the null path fixed).

## Round 11 — client membership card garbled dash (2026-11-15)

One-line fix, user-authorised under the standing grind instruction.
The round-10 browser re-check on production found the client portal
(/client, client@test.com) membership card rendering garbled characters
"Â€"" where a dash should be. Commit: local, branch
`phase1-security-fixes` (parent pushes).

### Root cause

`tw-client-acc.js` line 237, `renderDashboardHero()`:

```js
let membershipStatus='â€”',membershipCopy='No membership data available.';
```

The literal `'â€"'` is the classic double-encoding of the em-dash
`—` (U+2014). The em-dash's UTF-8 bytes (E2 80 94) were once decoded
as Windows-1252 — giving `â` (E2), `€` (80), `”` (94) — and those
three characters were then re-encoded as UTF-8, so the file on disk
holds the 9 bytes `C3 A2 E2 82 AC E2 80 9D`. The browser reads the file
as UTF-8 and displays exactly those three characters, `â€"`. The
value is the membership card's status: when the client has no
`membership_end_date`, `membershipDays` is null and the status stays
at this literal, which `Trainw.ui.setText('dashboard-membership-status',
membershipStatus)` writes straight into the card — no encoding step in
between, so the literal itself was the bug. The card's other dashes
("MEMBRE DEPUIS —", "FIN D'ABONNEMENT —") are proper em-dashes
elsewhere and render fine.

This is one of the file's pre-existing double-encoded sequences (round
8 counted 76). The same mojibake em-dash byte sequence occurs 10 times
in `tw-client-acc.js` (safeVal/date/weight/target/days-left/booking-date
fallbacks); only the `membershipStatus` instance is this bug. The other
9 were left untouched, per the minimal-fix scope — a bulk re-encode of
the file is a separate decision, not this round.

### Fix

One literal, one line (`tw-client-acc.js`, line 237):

```diff
-let membershipStatus='â€”'
+let membershipStatus='—'
```

No other file touched. No migration, no RLS change, no secret.

### Verification

- Hexdump: the literal's bytes are now `E2 80 94` (proper em-dash);
  the mojibake sequence count in the file dropped 10 → 9.
- Node eval of the extracted literal: char `—`, code point U+2014.
- `node --check tw-client-acc.js` clean.
- Static build: `node env-config.js` + `npm run verify` — "all checks
  passed" (env vars fetched from the Supabase Management API into the
  build process env only, never printed; `dist/` rebuilt and confirmed
  to contain the fixed literal).
- `git diff`: exactly 1 line changed in 1 file.
- **Not verified in this session (no live-browser access):** the actual
  browser render of the membership card on production. Browser re-check
  happens after the parent deploys.

## Phase 2 — P2-2: single revenue source (FE-15, FE-16) (2026-11-15)

Commit (local, branch phase1-security-fixes): `P2-2` (see `git log`). The
parent pushes; no merge, no deploy from this round.

### Step 1 — what was already done vs what was actually broken

Already done in round 3, verified again against the current code (not the
notes): revenue is computed once, from the ledger, in `loadLedgerRevenue`
(`tw-gym-acc.js:1892`) — the dashboard (`loadDashboardStats`), analytics
(`loadAnalytics`) and the prediction (`#pred-monthly`) all call that one
function, so the three views cannot disagree. The old v17 `revenueFor()`
list-price estimate is gone; `refreshRevenue()` in `tw-gym-acc-v17.js` is
a thin wrapper around `loadLedgerRevenue`. The ai-proxy edge function
computes no revenue. FE-15's "three ways" and the v17 override are closed
by the round-3 work, not by this round.

Genuinely broken, found by this round:

1. **No DB CHECK on any money column.** `prepare_payment_write`
   silently clamps negatives with `GREATEST(..., 0)` — so a −500 payment
   inserted through the API did NOT fail, it landed as a 0-amount PAID
   payment and the settlement trigger extended the membership for free.
   The audit step's "entering −500 as a price is rejected" could not
   pass against the DB.
2. **No upper cap anywhere.** `parseMoneyInput` accepted 999999999; the
   `numeric(12,2)` columns accept ~10 billion.
3. **Coach rates had NO validation at all.** `saveEditCoach` and
   `submitNewCoach` used bare `parseFloat()` and stored −500 verbatim
   (edit path) or into the invite metadata (add path).
4. **Revenue was GROSS, not net.** `loadLedgerRevenue` summed
   `amount_paid` and ignored `amount_refunded`, so a partially refunded
   payment still counted in full; `renderDayTotals` had the same flaw.

### Step 2 — fixes

**Migration `20261116120000_phase2_p22_price_validation.sql`** (9 CHECKs,
all validated — no NOT VALID dodge, so DB-35's
`assert_no_unvalidated_constraints` stays green):
- `payments`: `amount_total > 0 AND <= 100000`;
  `amount_paid >= 0 AND <= 100000 AND <= amount_total`;
  `status <> 'paid' OR amount_paid > 0`. The `paid ⇒ > 0` split is
  deliberate: a live PENDING 80/0 row exists (the DB-66 credit flow's
  pending rebooking payment) and `book_coach_session` legitimately
  inserts pending payments with `amount_paid = 0` — so 0 is allowed
  only for non-paid rows. `amount_paid <= amount_total` is safe because
  `apply_member_credit_to_session` only ever grows `amount_paid` up to
  `amount_total` (`v_take = LEAST(remaining, owed)`).
- `gyms`: `price_monthly/quarterly/annual > 0 AND <= 100000`.
- `coach_profiles`: `hourly_rate` / `price_per_session` NULL or
  `> 0 AND <= 100000`.
- `client_profiles`: `price_paid >= 0 AND <= 100000` (ledger-derived,
  bound for defence in depth).
- Cap is 100 000 DT everywhere — ~30x the most expensive Tunisian gym
  annual plan, so real prices never hit it and typos do. The
  `GREATEST(..., 0)` clamp in `prepare_payment_write` is left alone:
  with the CHECKs in place a negative now fails the CHECK instead of
  landing as 0.
- Live-data pre-checks (Management API, before writing): all 6 live
  payments satisfy the new CHECKs; all 5 gyms price 150/400/1400; coach
  rates are NULL or 80; no `price_paid < 0` or `> 100000`. None of the
  9 constraint names existed live before the apply.

**Frontend (`tw-gym-acc.js`, `tw-gym-acc.html`):**
- `parseMoneyInput` gains the shared cap `MAX_MONEY_DT = 100000`
  (anything above is invalid). Zero stays allowed in the parser because
  it means "none" in the new-client flow (a member added with no payment
  yet stays pending); entry points that take a real price reject ≤ 0
  themselves, and the DB CHECKs enforce the same bounds.
- `loadLedgerRevenue` now selects `amount_refunded` and sums
  `amount_paid − amount_refunded` (net collected); `renderDayTotals`
  nets the same way.
- `savePricing` rejects a 0 list price (empty still means "keep the
  current value" — a 0 DT price is not a price, per the audit step).
- `saveEditCoach` / `submitNewCoach` validate the rate through
  `parseMoneyInput` (empty = no rate; present must be > 0 and ≤ cap);
  the old `parseFloat` paths are gone.
- `max="100000"` on the 7 money inputs in `tw-gym-acc.html`
  (browser-level guard only; JS + DB CHECKs are the enforcement).
- Deliberately NOT changed: the coach self-profile rate input
  (`#coach-rate-input`, `tw-coach-acc.js`) is display-only —
  `saveCoachProfile` never sends it, so there is nothing to validate
  there; wiring it up is a separate product decision. `recordPayment`
  already rejected ≤ 0; it inherits the cap from `parseMoneyInput`.

### Local verification

Throwaway Postgres 16.4 cluster, built from source (round-7 recipe:
`configure --with-openssl --without-readline --without-icu
--without-libxml --without-libxslt --without-ldap --without-pam`,
`make -j4 && make install`, contrib `pgcrypto`/`btree_gist`/`citext`).
Why built: this VM has no system Postgres, `deb.debian.org` is throttled
to ~290 B/s, and the pip `pgserver` wheel ships no contrib (no
`pgcrypto`). `ftp.postgresql.org` is fast (14.8 MB/s). Server ran as
`nobody` (initdb refuses root); install tree `/var/tmp/p22-pgsql`
(`chmod -R o+rX` after install — umask 0007 leaves it group-only, same
trap as round 7); datadir `/tmp/p22-pgdata` — the /home mount denies ALL
access to uid 65534, so the datadir could NOT live under
`~/workspace/.p22-scratch` as first tried. Harness + suite:
`~/workspace/.p22-scratch/` (`p22-harness.sh` port 54402,
`p22-tests.sql`, `supabase-stubs.sql` copied from `.r9-scratch`).
- Full chain applies: **64 OK, 2 FAIL** — exactly the two known
  by-design failures (`20261115050000` B5, `20261115300000` DB-61).
- **P2-2 suite: 24/24 pass** — −500 / 0-total / 100001 payments
  rejected; pending 80/0 still inserts; paid 80/0 and paid 80/100
  rejected; paid 80/80 inserts and settles; partial refund 30 → ledger
  revenue nets to 50, not gross 80; gym prices −500/0/100001 rejected,
  200 saves; coach rates −500/0/100001 rejected, 45 saves; profile
  `price_paid` −1/100001 rejected; all 9 CHECKs present and validated.
- Round-6 suite as a regression check: **147/151** on a fresh chain —
  identical with and without this migration (diff of the two runs shows
  only random UUIDs), so the migration causes zero regressions. The 3
  named failures are all DB-48 (gate lockout), pre-existing drift: the
  r6 suite predates round 7 moving the pepper into `app_secrets`, so
  credential enrolment fails with "pepper is not configured" before the
  lockout logic runs. (An earlier 122/150 reading was a double-run
  artifact — the suite is not idempotent on one DB; ignore it.)
- `node --check` on every touched JS file; `node env-config.js` +
  `npm run verify` pass (env vars from the live project, transient).

### Live verification (Supabase "Trainw", caylegavnekidhytlswo)

Migration applied live via the Management API; all 9 CHECKs confirmed
present afterwards. Owner-JWT PostgREST tests (owner@test.com):
- **−500 payment insert → HTTP 400** `payments_amount_total_check`
  (the audit's −500 verify, now passing live).
- Valid 150 payment for client@test.com → HTTP 201
  (id `a8a1ef5f-f824-4775-a52d-825d82250ed9`).
- Gym price −500 PATCH → HTTP 400 `gyms_price_monthly_check`;
  coach rate −500 PATCH → HTTP 400
  `coach_profiles_price_per_session_check`.
- Partial refund 30 via `record_payment_refund` → HTTP 200.
- Final live state: TEST Gym holds 2 paid payments — the 150 above
  (30 refunded) plus a **10.00 payment I did not create**
  (`53cd3045-8cee-476b-b4c1-5c58fc223822`, paid 2026-11-15) — it
  appeared between my baseline query (0 payments) and the final check,
  so another agent/round was testing live concurrently. Net revenue
  this month for TEST Gym is **130 DT** (150 − 30 + 10); gross is 160.
  That 130 is the single number dashboard, analytics and prediction
  will all show (one function), once deployed. The −500 payment did not
  land; gym price is unchanged at 150; client@test.com settled to
  `paid` with end date 2027-01-15 (the later 10 payment extended it
  past my 150's month, per existing renewal semantics).

### What this round deliberately did NOT do

- **Push to GitHub / merge / deploy** — local only, per the task.
  The parent pushes and deploys; the frontend changes (net revenue,
  validation messages) only reach users after that deploy.
- **No data deletion** on the live project. The test payment + refund
  stay as test data, like the existing Gym A test payments.
- **No RLS change**; no new secrets in files (the JWT lived only in a
  shell variable for the live calls; the anon key was fetched via the
  Management API and never written down).

### Not verified in this session (no live-browser access)

- The actual browser render: dashboard `#stat-revenue`, the analytics
  page and `#pred-monthly` all showing 130 DT on production after
  deploy. The DOM equality check needs the parent's browser pass — the
  API-level proof (one shared function + one ledger number) is done,
  the pixels are not.
- The frontend validation messages in a real browser (typing −500 into
  the payment / pricing / coach-rate forms). The JS paths are covered by
  `node --check` + the shared `parseMoneyInput` logic, and the DB
  CHECKs were proven live, but no form was typed into.

## Phase 2 — P2-5: stop the enumeration and spam paths (FE-08 + NX-02/05/06/14, vanilla side) (2026-11-15)

Commit (local, branch phase1-security-fixes): `P2-5` (see `git log`). The
parent pushes; no merge, no deploy from this round.

### Step 1 — what was already done vs what was actually broken

Already done, verified again against the current code (not the notes):

- **Email confirmation gates workspace provisioning.** `doSignup`
  (`tw-login.js:506`) signs up, then — with no session — signs in; an
  `eEmailNotConfirmed` result stops the flow before `ensureProfile` /
  `bootstrap_authenticated_user` ever runs. `handle_new_user` (DB-10)
  ignores role/gym_id from metadata: every signup is a bare client,
  gym NULL, no gym created. Auth config live:
  `mailer_autoconfirm=false`, `rate_limit_email_sent=2`,
  `rate_limit_verify=30`.
- **Gate rate limits (P1-12 / GT-03).** `trainw_gate_rate_limit_consume`
  (60/min IP, 30/min device) + the gate-checkin handler, all 4 edge
  functions ACTIVE live.
- **Password-reset flow exists** (`tw-login.js:592` forgot + dashboard
  reset buttons in all three portals, `resetPasswordForEmail` with
  redirect to `/tw-login.html`). Its Phase 1 failure was the default
  mailer's rate limit, not broken code (see live verification below).
- **Invite flow.** `invite_gym_member` + `accept_gym_invitation`
  (7-day expiry, DB-40) + `sendInvitationEmail` via
  `signInWithOtp({shouldCreateUser: false})`. The invitee MUST already
  have a Trainw account (the UI says so; `accept` requires a signed-in
  user whose email matches the invite). No temporary password is ever
  issued, so there is nothing to force-change on first login — the
  "forced password change" item is moot by design, not missing.

Genuinely broken / missing, found by this round:

1. **Coach search had no minimum query length and no wildcard
   escaping.** Any 1-char term fired two queries, and `%`/`_` in the
   term acted as LIKE wildcards (live proof: `users.name ilike *%*`
   matched every coach name; `*\%*` matched none).
2. **The embedded-users name filter does not restrict rows.**
   PostgREST puts a filter on an embedded relation in the JOIN, not
   the WHERE: a non-matching `coach_profiles` row is still returned,
   with `users: null` (live proof: `ilike *ZZZZNoMatch*` returned TEST
   Gym's coach with `users: null`; `ilike *TEST A*` the same). The
   search still returns correct results today ONLY because the merge
   loop drops rows with no email. The stale FE-08 comment claimed the
   filter "needs live verification" and guessed the failure mode
   backwards (it said name search would return nothing — it returns
   everything, with null embeds). Related recall gap, left as a
   residual: the name query is capped at 20 rows by rating, so in a
   gym with >20 coaches a low-rated matching coach can be missed.
   Fixing that properly needs a server-side search RPC; out of scope
   for this round.
3. **The public directory + join requests had no rate limit.**
   `list_public_gyms` (authenticated-only, safe columns) and
   `request_gym_membership` (idempotent) could be hammered without
   limit. The directory has NO search input in the vanilla app, so the
   step's "minimum query length + wildcard escaping on search" is moot
   there — there is no query to constrain.
4. **No CAPTCHA on vanilla signup.** The Next.js hCaptcha (NX-01) died
   with src/. The vanilla controls are Auth email confirmation +
   `rate_limit_email_sent=2`/hour. Adding a CAPTCHA needs a provider +
   keys — a user decision, not taken here.

### Step 2 — fixes

**Frontend (`tw-gym-acc.js`):**
- `COACH_SEARCH_MIN_LENGTH = 2` — enforced in
  `scheduleExistingCoachSearch`, in `searchExistingCoaches` (it is
  also called directly after adding a coach), and in
  `renderCoachSearchResults` (new `coachSearchMinLength` hint, fr/en/
  ar). A 1-char term now shows the hint and fires no query.
- `escapeIlikeTerm(term)` — escapes `\` → `\\`, `%` → `\%`,
  `_` → `\_` (backslash first), applied to BOTH ilike patterns
  (name + specialty). Node-tested against the extracted function:
  10/10 cases pass. PostgREST passes the backslash escape through to
  SQL ILIKE (verified live: escaped `%` matches nothing).
- FE-08 comment rewritten with the verified PostgREST semantics
  (null embed = no match; merge loop's email check is what makes the
  result correct) instead of the stale "verify on staging" guess.

**Migration `20261116130000_phase2_p25_join_rate_limits.sql`** (mirror
of the proven gate limiter `20261114040000`, separate table so
join-flow buckets can never collide with gate buckets):
- `public.rpc_rate_limits` (bucket_key, window_start, hits) + RLS on,
  no policies. `trainw_rpc_rate_limit_consume(text, int)` — same
  fixed-calendar-minute window, counter only increments under the
  limit, stale windows for the key deleted on consume. Owner-only
  (REVOKE ALL FROM PUBLIC, no GRANT): it is called only from inside
  the SECURITY DEFINER RPCs, which run as the owner. Granting it to
  `authenticated` would let any user burn another user's bucket by
  naming it.
- `list_public_gyms()` rewritten SQL → plpgsql (same columns, order,
  grants): per-user 30/min (`dir:<uid>`), then the same SELECT.
- `request_gym_membership()` body carried verbatim from
  `20261116100000` except the limiter block + `v_limited` declaration:
  per-user 10/min (`join:<uid>`).
- Both fail OPEN on limiter error (logged via RAISE LOG) so a broken
  limiter can never block the join flow — same policy as the gate
  handler. The flag dance matters: raising inside the BEGIN block
  would be swallowed by its own EXCEPTION handler, so the consume
  result is stored in `v_limited` and raised after the block.

### Step 3 — local verification

- Full chain fresh-apply: **65 OK, 2 FAIL** — the 2 known by-design
  failures (`20261115050000` B5, `20261115300000` DB-61 non-portable
  hash, repaired by `20261115330000`).
- **P2-5 suite (`~/workspace/.p25-scratch/p25-tests.sql`): 13/13 pass**
  — consume limit 3 = T,T,T,F; separate keys independent; stale
  window purged (1 row, hits=1); invalid inputs false; anon cannot
  call consume (42501) or list gyms (42501); directory lists active
  gyms only, name-ordered; directory 30 OK / 31st `Too many requests`;
  second user unaffected by first user's exhaustion; join 10 OK /
  11th rejected, first two calls idempotent (pending, then
  already_requested); owner-role join still rejected; LIKE-escape
  semantics (escaped `%` literal, unescaped `%` wildcard);
  coach_profiles RLS scopes a gym-A coach to gym-A rows only.
  (One false alarm during the run: C07 first read 27/30 because C06
  had already spent 3 of the same user's directory hits that minute —
  correct behaviour; the test now uses a fresh user for the loop. C03
  first failed for the same class of reason — subselect evaluation
  order inside one expression is not guaranteed; rewritten as
  sequential statements.)
- `escapeIlikeTerm` node-tested 10/10 (extracted from the file).
- `node --check` on `tw-gym-acc.js` (+ `tw-role.js` untouched);
  `node env-config.js` + `npm run verify` pass (env vars from the
  live project, transient — keys never written down).

### Live verification (Supabase "Trainw", caylegavnekidhytlswo)

Probes in `~/workspace/.p25-scratch/p25-live-probe*.py` (keys fetched
via the Management API, kept in memory, never printed; VM↔Supabase
transport flakes retried — two sign-in calls returned HTTP 0
`RemoteDisconnected`/`IncompleteRead` before succeeding on retry):

- **Auth config re-verified:** `mailer_autoconfirm=false`,
  `rate_limit_email_sent=2`, `rate_limit_verify=30`,
  `security_captcha_enabled=false`. All 4 edge functions ACTIVE.
- **Unconfirmed email cannot provision a gym.** Admin-created test
  user `p25-unconfirmed@test.trainw.live` (`email_confirm=false`,
  hostile metadata `role=gym_owner`, `gym_name="P2-5 Fake Gym"`):
  sign-in → **HTTP 400 `email_not_confirmed`** ("Email not
  confirmed"). Its `users` row is `role=client, gym_id=NULL`, a
  `client_profiles` row exists with `gym_id=NULL`, and **0 gyms**
  have it as manager. DB-10 holds against hostile metadata.
  **Test user left on the live project for later cleanup** (same
  bucket as the existing TEST accounts).
- **50 fake registrations are blocked.** A single signup attempt
  with a fresh address → **HTTP 429 `over_email_send_rate_limit`**
  ("email rate limit exceeded") on the FIRST attempt. No account
  was created by the probe. The step's 50-in-a-minute hammer was
  deliberately not run; the limiter triggers at attempt 1, which is
  the proof.
- **Password-reset failure mode is the mailer limit, not code.**
  One `recover` call for the test user → **HTTP 429
  `over_email_send_rate_limit`** (same as P1-13/R8). The flow itself
  is intact in code; delivery needs the custom-SMTP user decision.
- **Gate limiter still live.** `trainw_gate_rate_limit_consume`
  with a probe bucket, limit 3: **T,T,T,F** — the 4th call refused.
  (One probe bucket row left in `gate_rate_limits`; it expires with
  its minute window.)
- **Coach search scoping re-verified.** As `coach@test.com`:
  unfiltered `coach_profiles` returns 1 row (TEST Gym's coach only);
  `users.name ilike *Client*` returns that row with `users: null`
  (no client is enumerable through it); ground truth via
  service_role is 4 coach rows, all coaches, no clients.
- **Directory:** `list_public_gyms` as `owner@test.com` returns 5
  rows with exactly the safe keys (`gym_id, name, address, location,
  logo_storage_bucket, logo_storage_path`).
- **P2-2's test rows untouched.** No live data was deleted or
  modified except the one test user above + the probe rate-limit
  bucket row. (The live check also re-confirmed the P2-2 note: TEST
  Gym holds the 150 payment with a 30 refund plus the 10.00 payment
  this round did not create.)

### What this round deliberately did NOT do

- **Push to GitHub / merge / deploy / apply the migration live** —
  local only, per the task. The parent pushes and deploys; the new
  migration needs the parent's live apply, and the frontend changes
  (min length, escaping, hint) only reach users after that deploy.
- **No data deletion** on the live project. The new test user stays
  for the user-decided cleanup, with the existing TEST accounts.
- **No 50-registration hammer** on the live project (see above).
- **No custom SMTP** — user decision, still open.
- **No CAPTCHA on vanilla signup** — needs a provider + keys, user
  decision.
- **No server-side coach-search RPC** — the >20-coaches recall gap
  stays a residual (see below).
- **No RLS weakening**; no new secrets in files.

### Not verified in this session (no live-browser access)

- The coach-search UI in a real browser after deploy: typing 1
  character shows the min-length hint and fires no query; typing `%`
  returns no coaches; typing a real coach name still finds them.
- The new rate limits firing through the real UI (31st directory
  load / 11th join request in a minute → toast). The DB behaviour is
  proven locally; the toast path is not.
- The unconfirmed-signup UX in a real browser (signup → "check your
  email" message, no workspace). The API-level proof (400
  `email_not_confirmed` + no gym) is done; the pixels are not.

### Residuals (not findings, but worth knowing)

- **Coach search recall in gyms with >20 coaches.** The name query
  is capped at 20 rows by rating and the embedded name filter does
  not restrict rows, so a low-rated matching coach past the cap is
  missed. A `search_coaches(p_gym_id, p_term)` RPC with server-side
  ILIKE would fix it; that is a small follow-up, not this round.
- **No CAPTCHA on vanilla signup.** Controls are email confirmation
  + Auth rate limits (`rate_limit_email_sent=2`/h). If the user
  wants a CAPTCHA, it needs a provider and keys.
- **GT-03 live throttle test** (60 rapid gate calls) is still owed
  by design — the limiter function itself is now proven live twice
  (gate probe above + P1-13 suite); hammering the edge function
  remains deliberately unrun.

## Phase 2 — P2-8: money and data hygiene (NX-10/13/15/16, DB-32/34/35/38/39/41/50/51/52/61/62) (2026-11-15)

### Step 1 — what was already done vs what was actually broken

Most of the step was already FIXED+VERIFIED in rounds 1–6; this round
re-verified every item against the live project and the chain, and found
three real gaps plus one process gap:

- **DB-61 — REAL GAP, live only.** `SELECT assert_rls_helpers_frozen()`
  on live raised "RLS helper definitions drifted …:
  membership_is_active_for_access(…)". The live function was
  byte-identical to the chain's final definition (prosrc diffed clean)
  and hashed (portable formula, computed live) to exactly the chain's
  expected value `3a70bd4a…` — but the live assert expected `c90ab575…`,
  a hash that appears in NO chain file. The other 29 expected hashes in
  the live assert are identical to the chain's `20261115330000`. The
  live assert was evidently patched by hand during the P1-13 live apply
  (when the function still had an intermediate body) and never re-synced.
- **NX-15 (vanilla) — REAL GAP.** The Next.js fix was superseded with
  `src/`, but the vanilla app had the same hole: `Trainw.api.run`
  toasted the raw `error.message`, and ~50 call sites displayed it
  (toasts, inline errors, `errEl.textContent`). A failed save could show
  `new row violates row-level security policy for table "client_profiles"`
  or a foreign-key constraint name to the user.
- **NX-16 (vanilla) — REAL GAP, class side only.** A class with capacity
  -5 sailed through: `gym_classes` has no DB CHECK (unlike sessions),
  and the JS `parseInt(...)||20` only guards NaN/0. Names had no
  max-length anywhere in the vanilla forms (only the message textareas
  had `maxlength="2000"`).
- **DB-50 — PROCESS GAP.** Two post-round-4 migrations deleted user
  data without logging: `20261115230000` (duplicate `check_ins` dedup)
  and `20261115400000` (duplicate `personal_records` dedup). Live
  `data_repair_log` holds 0 rows — the log was never used.

Everything else re-verified clean on live (see Step 3).

### Step 2 — fixes

- **DB-61:** migration `20261116140000_phase2_p28_freeze_hash_resync.sql`
  re-creates `assert_rls_helpers_frozen()` VERBATIM from
  `20261115330000` (same body, same 30 hashes — the only difference
  from the live version is the one stale hash) and runs the assert.
  No helper semantics change. On a fresh chain it is a no-op
  redefinition. Applied live via the Management API the same day; the
  assert now passes live.
- **NX-15:** `trainw-core.js` — `sanitizeUserErrorMessage()` +
  `Trainw.api.userMessage(error, fallback)`. `normalizeError` keeps
  `.message` verbatim (three call sites branch on it:
  `isInvitationAuthLookupError`, `isJoinGymInvalidError`, the
  `loadClientReviews` `session_id` fallback — plus the credit-apply
  branching on RPC messages) and attaches a sanitized `.userMessage`;
  `api.run` toasts the `userMessage`. Markers that trigger the generic
  fallback: violates / duplicate key / foreign key / row-level security
  / permission denied for / relation " / column " / does not exist /
  schema cache / pgrst / jwt / invalid input syntax / operator does not
  exist / could not find the. Deliberate `cannot_delete_gym:` /
  `cannot_delete_user:` guard messages (counts only) and app-authored
  messages pass through; the raw error is still `console.error`d.
  All 57 user-facing display sites switched to `userMessage`
  (`tw-gym-acc.js` 47, `tw-client-acc.js` 4, `tw-coach-acc.js` 4,
  `tw-role.js` 3); `tw-login.js` already mapped auth errors via
  `mapAuthError`. One behavioural note: `submitNewSession` used to
  `throw new Error(error.message)` — now `throw error`, so the
  normalized error (with `userMessage`) reaches the catch.
- **NX-16:** `maxlength="100"` on all 15 name inputs
  (`tw-gym-acc.html` 11, `tw-client-acc.html` 1, `tw-coach-acc.html` 1,
  `tw-login.html` 2 — signup name + gym name included); client-side
  capacity ≥ 1 validation in `saveGymClass`, `submitNewSession`,
  `saveEditSession`; migration `20261116150000_phase2_p28_class_capacity_check.sql`
  adds `gym_classes_capacity_check CHECK (capacity > 0)` — live data
  was clean (1 class, capacity 20; 0 bad rows), so it validated
  immediately. Prices were already bounded (P2-2).
- **DB-50:** `docs/MIGRATION_CONVENTIONS.md` §4 tightened — a migration
  that deletes user data must first INSERT one `data_repair_log` row
  per table (table, count, reason, filename); the two unlogged
  exceptions are named in the doc. §7 fixed a stale note (the portable
  hash uses `pg_get_function_arguments`, not `proargdefaults` — the
  latter was the by-design-failing `20261115300000` formula) and §8 now
  lists both known by-design fresh-apply failures.
- **Runbook:** `docs/DEPLOY_RUNBOOK.md` §9 adds the named check per
  P2-8 item (table, with the check and where it lives). Staging-push
  sub-check marked deferred to P2-7 (no staging project yet).
- **DB-38:** NOT built — needs the user (see below).

### Step 3 — local verification

- Fresh chain on the throwaway local Postgres 16.4 cluster
  (`~/workspace/.p22-scratch/p22-harness.sh`): **67 OK, 2 FAIL** — the
  same two known by-design failures (`20261115050000` B5,
  `20261115300000` non-portable hash), both repaired by later
  migrations. Both new migrations apply OK.
- On the fresh chain: all three asserts pass
  (`assert_rls_helpers_frozen`, `assert_no_unvalidated_constraints`,
  `assert_all_tables_have_rls`); 0 NOT VALID constraints; 7
  `idx_phase1b_*` indexes; gym delete guard triggers present; seeder
  has no DELETE; trigger has no blanket handler; `data_repair_log`
  exists; no table carries the blanket `authenticated=arwd` grant.
- P2-2 behavioural suite still passes 24/24 on the chain with both new
  migrations.
- Capacity CHECK proven on the fresh chain: inserting a class with
  capacity -5 raises `violates check constraint
  "gym_classes_capacity_check"`; capacity 20 saves.
- Sanitizer unit check (`~/workspace/.p28-scratch/test-sanitize.js`,
  functions extracted verbatim from the shipped `trainw-core.js`):
  17 cases — raw RLS/FK/unique/schema-cache/JWT messages → generic;
  `cannot_delete_*:` guard messages and app-authored messages pass
  through; `.message` preserved for logic, `.code` preserved,
  `.userMessage` generic. All pass.
- `node --check` on every touched JS file
  (`trainw-core.js`, `tw-gym-acc.js`, `tw-client-acc.js`,
  `tw-coach-acc.js`, `tw-role.js`); `node env-config.js` + `npm run verify`
  (see below).

### Live verification (Supabase "Trainw", caylegavnekidhytlswo)

Read-only checks first, then the two migration applies (Management API
`POST /v1/projects/{ref}/database/query`, one call = one transaction):

- DB-35: `pg_constraint WHERE NOT convalidated` → 0 rows.
- DB-39: all 7 `idx_phase1b_*` indexes present.
- DB-41: live ACLs are per-table (grants vary, e.g.
  `admin_audit_log` authenticated=r only); `assert_all_tables_have_rls()`
  passes.
- DB-61: drift reproduced (assert raised on
  `membership_is_active_for_access`), diagnosed (live hash =
  `3a70bd4a…` = chain value; live expected `c90ab575…`), fixed live by
  `20261116140000`; `assert_rls_helpers_frozen()` now passes live.
- DB-62: live `handle_new_user` prosrc has no `EXCEPTION WHEN OTHERS`
  (the word appears only in a comment explaining the ban).
- DB-32: live `users_role_check` includes `gym_admin` and `staff`.
- DB-34: live `ensure_gym_default_roles` body has no `DELETE FROM`.
- DB-38: both guard triggers exist and are enabled live.
- DB-50: `data_repair_log` exists, 0 rows (never used — the gap).
- NX-16: live `gym_classes` 1 row (capacity 20), `sessions` 6 rows
  (min capacity 1), 0 bad rows — then `20261116150000` applied live;
  `gym_classes_capacity_check` exists and is validated.
- No live data was deleted. No test rows were created or modified by
  this round (the only live writes are the two migration applies).

### What this round deliberately did NOT do

- **Push to GitHub / merge / deploy** — local commit only, per the task.
  The parent pushes and deploys; the frontend changes (generic errors,
  capacity checks, maxlengths) only reach users after that deploy.
- **Soft-delete for gyms/users (DB-38)** — needs the user. Deleting a
  user still hard-deletes the `users` row and cascades to the other
  party's messages; `users.is_active` / `gyms.is_active` exist but no
  deactivate flow uses them, and re-signup after a soft-delete would
  leave `is_active=false` (the gate already honours it) unless signup
  resets it. Needs a product decision on what a deactivated gym/user
  can still do, plus nullable message sender/receiver + chat UI for a
  deleted counterpart. The audit minimum (gym delete forbidden while
  tenant data exists; user delete with payments fails with a clear
  error) is live and verified.
- **Staging project** — P2-7. The staging-push sub-check is deferred
  there; the fresh-chain apply is the substitute used here.
- **No RLS weakening**; no new secrets in files; no data deletion.

### Not verified in this session (no live-browser access)

- The generic-error behaviour in a real browser after deploy: force a
  failing save (e.g. a payment with a bad amount, a duplicate RFID)
  and confirm the toast is the generic message, not a constraint name.
- The capacity ≥ 1 inline error and the 100-char name cap in the real
  forms (typing -5 capacity; pasting a 200-char name).
- The staff-revoke / delete-client / delete-coach / delete-class /
  delete-role actions clicked through in the owner portal on TEST Gym.
- The submit-button pending states under a slow connection
  (double-click a save and confirm only one request fires).

### Residuals (not findings, but worth knowing)

- **Live `supabase migration list` is not checkable from here.** The
  chain is applied via the Management API, which does not populate the
  CLI version table (`supabase_migrations.schema_migrations` is not
  visible to the query role). The fresh-chain apply is the working
  substitute; a CLI `migration list` needs the Supabase CLI + a login,
  which this VM cannot do.
- **`__probe_a` / `__probe_b` tables on live.** Two leftover probe
  tables from an earlier round's grant checks (both carry the
  per-table grant shape). Harmless, but they are not part of the app;
  removing them is a cleanup decision, not this round.
- **DB-61 live-vs-chain drift can recur** any time a hash is patched
  on live by hand. The conventions §7 note now says so explicitly;
  the guard is only as good as the discipline of re-deriving hashes
  from the chain.

## UI/UX — U1: client booking silently dead (2026-11-15)

Source: `~/workspace/goals/build-trainw/files/trainw-ui-ux-test-pass-2026-11-15.md`,
"Client — functional bugs" item 1. Highest-priority item of the pass.

### Symptom (production, main cff7df9a, real browser)

Client portal, Centre de réservation: Test Coach, date 2026-11-16, slot
10:00 (summary correctly showed COACH Test Coach, DATE 2026-11-16, START
TIME 10:00). Clicking "Confirmer la réservation" did NOTHING — no toast,
no error, no navigation, no booking. Clicked 4 times across two slots
(10:00 and 09:00), waited up to 10s each. Day stays "OPEN", "No booked
sessions for the selected date." remains, dashboard Quick booking still
"BOOKED THAT DAY 0", no new session in Upcoming sessions.

### Root cause (not the RPC, not the database)

`bookSelectedSession` in `tw-client-acc.js` gated the RPC behind a native
blocking dialog:

```js
if(!window.confirm(bookingConfirmCopy()))return;
```

An auto-dismissed `window.confirm` returns `false`, so the handler
returned silently BEFORE the RPC — exactly the observed behaviour (no
toast, no error, no booking, repeatable across clicks and slots).
Automated browsers auto-dismiss native dialogs unless the harness
installs a dialog handler, so the confirm never produced a visible
confirmation in the test browser. Every other exit in the handler is
loud: the selection guards toast, and `Trainw.api.run` toasts any RPC
error — so a failing RPC could not have produced this silence.

Proven by elimination at the API level (same parameters the UI sends,
same test client, live project): `book_coach_session` works. The
deployed production file is the same code (fetched
`https://trainw.vercel.app/tw-client-acc.js`, `bookSelectedSession`
with the confirm gate; main-branch source identical).

### Fix (frontend only, `tw-client-acc.js`, no SQL)

- Removed the `window.confirm(bookingConfirmCopy())` gate from
  `bookSelectedSession`; the click now goes straight to
  `book_coach_session`. The composer already renders the full
  confirmation summary (coach / date / start time / notes) directly
  above the button labelled "Confirmer la réservation", and the booking
  creates a `pending` session the client can cancel — the dialog added
  no safety. No other client mutating action uses a confirm (check-in,
  weight, goal, profile, free workout all book/save directly).
- Removed the now-unused `bookingConfirmCopy()` helper.
- The DB-66 round-8 hook is untouched: after a successful booking the
  handler still calls `applyCreditToBooking(r.data)` (the new session
  id) before the reload. Double-submit is still guarded: `setBtnBusy`
  disables the button synchronously before the RPC await.
- `cancelSession` still uses `window.confirm` — same silent-failure
  class, left alone as out of scope for U1 (cancel was deliberately
  untested in the pass). Flagged for a later round: replace native
  confirms with in-page confirmation wherever a core flow depends on
  one.

### Verification (API level, live project, TEST Gym)

Signed in as the test accounts via the Auth API (anon key from the
Management API; tokens in memory only) and called the exact RPCs the
UI calls. VM↔Supabase flakiness (RemoteDisconnected / IncompleteRead)
hit repeatedly; curl with retries was used.

- `get_bookable_slots` (Test Coach, 2026-11-16) returned 09:00 / 10:00 /
  11:00, 60 min, price 0 — the slots the tester saw.
- `book_coach_session` (Test Coach, 2026-11-16, 10:00, notes null)
  returned HTTP 200 and session `420c6a6a-7e38-476f-9846-968a8c638fde`
  (`pending`, visible to the client on re-read) — the exact parameters
  from the UI test. The RPC is not the bug.
- Test client credit balance: `get_member_credit_balance` = 0, and the
  project has zero `member_credits` rows at all — the "no credit
  balance display" note in the test pass is by design (round 8 shows
  the balance only when > 0).
- Credit-apply behaviour after booking, both reachable states:
  - Free session (price 0, no payment row — session `420c6a6a`):
    `apply_member_credit_to_session` returns
    `validation_error: session has no payment to apply credit to`
    (HTTP 400), which is one of the two benign strings the UI's
    `applyCreditToBooking` matches for the booking-saved toast.
  - Priced session with zero credit (see setup below): apply returned
    `{"applied": 0.00, "remaining_owed": 50.00, "payment_status":
    "pending"}` — the RPC runs and the UI ends with the booking-saved
    toast.
- Priced-booking setup (needed because Test Coach's rate was `null`):
  the owner set `coach_profiles.price_per_session` = 50 DT (pricing is
  manager-only — a coach self-update is refused by the profile guard:
  "pricing are manager-only"). Client then booked 2026-11-23 09:00 →
  session `9da61eac` with a pending payment of 50 DT; coach confirmed
  it via `respond_to_session_booking`; owner marked the payment paid
  (pending→paid, the transition the ledger guard explicitly allows;
  `paid_at` stamped by the trigger); client rebooked 2026-11-23 11:00
  → session `c4363df7` with a pending payment of 50 DT.

### NOT verified — positive credit-apply path is time-gated (blocked)

The full honest DB-66 chain (paid session → no-show → credit 50 →
rebook → apply → payment paid, balance 0) could NOT be completed
today, and no credit balance was fabricated to fake it:
`mark_session_no_show` is blocked for future sessions by the sessions
write trigger (`invalid_state: future sessions cannot be completed or
marked no-show` — session_date must be ≤ today), and Test Coach's
availability is Monday-only, so no bookable slot exists today
(Sunday 2026-11-15). The earliest honest completion is on/after
Mon 2026-11-23: mark session `9da61eac` (confirmed, payment paid
50 DT) no-show → credit 50 → book the still-free 2026-11-23 10:00
slot → `apply_member_credit_to_session` → expect applied 50,
remaining_owed 0, payment `paid`, balance 0, credit `fully_applied`.
That follow-up is owed after the U1 deploy; it is the first real
end-to-end exercise of the DB-66 click path (book → credit applies),
which the broken button had prevented until now.

### Test data left on live (TEST Gym, all "TEST", nothing deleted)

- Sessions for Test Client / Test Coach: `420c6a6a` (2026-11-16 10:00,
  pending, free — the exact UI-test parameters), `cb2f1e6b` (2026-11-16
  09:00, pending, free), `2d189383` (2026-11-16 11:00, pending, free),
  `9da61eac` (2026-11-23 09:00, confirmed, payment paid 50 DT),
  `c4363df7` (2026-11-23 11:00, pending, payment pending 50 DT).
- Payments: `dc74a52c` (session, 50 DT, paid — for `9da61eac`),
  `4d76311d` (session, 50 DT, pending — for `c4363df7`).
- Test Coach rate changed `null` → 50 DT (`coach_profiles`
  `0e9587ac`). The parent's browser test will now see "50 DT · 0 avis"
  on the coach card and a pending payment on each new booking.
- No `member_credits` rows exist anywhere on the project.

### Side observations (not fixed here, for later rounds)

- The coach profile form shows a rate input (`#coach-rate-input`) but
  `saveCoachProfile` never writes it — the rate is effectively
  unsettable from the coach portal (manager-only by design, but the
  input implies otherwise).
- No UI path marks a session's linked pending payment `paid`: the owner
  "record payment" form inserts a standalone paid row with no
  `session_id`, so a booked session's own payment can stay `pending`
  even after the client pays cash at the gym. The ledger guard does
  allow a manager to move a pending payment to `paid` (used above).

### Checks

`node --check tw-client-acc.js` clean; `node env-config.js` +
`npm run verify` pass ("Trainw verify: all checks passed", dummy
Supabase values as in round 7); `dist/` contains the fix (U1 comment
present, `bookingConfirmCopy` gone, `applyCreditToBooking(r.data)`
still wired). No RLS change, no SQL, no secrets in files, no data
deletion. Commit (local only, branch `phase1-security-fixes`):
`UI/UX U1: fix client booking ...` — parent pushes/deploys.
Browser click-path test still owed after deploy.

## Phase 2 — P2-6: close the remaining privilege paths (2026-11-15)

Step definition: findings DB-12, DB-13, DB-14, DB-20, DB-21, DB-27, DB-28,
DB-29, DB-30, DB-40, DB-54, DB-55, DB-42, DB-43, DB-44, DB-53, DB-56, DB-57,
DB-64, DB-46, DB-60. Verify: repeat the P1-13 live-test matrix for each; all
must fail. Plus the round-9 anon revocation re-verified live.

Method: same as P1-13 (curl, not urllib, against
`caylegavnekidhytlswo.supabase.co`; SQL via the Management API
`sb-api.py`). Harness `~/workspace/.p26-scratch/p26-matrix.py` (+
`p26-tail.py`, `p26-sweep.py`, `p26-retest.py`); reports
`p26-matrix-report.json`, `p26-matrix-report-tail.json`,
`p26-matrix-report-sweep.json`, `p26-matrix-report-retest.json` in the same
dir. Actors: anon (no JWT), `owner@test.com` / `coach@test.com` /
`client@test.com` (TEST Gym), plus Gym A/B actors
`test-a-owner/manager/staff/coach/client`, `test-b-client`,
`test-b-owner`, `test-invitee2` — the test-a/test-b passwords were lost with
`/tmp` (P1-13 kept them in `/tmp/live-test-users.json`), so they were reset
via the Auth Admin API; new values in
`~/workspace/.p26-scratch/p26-passwords.json` (chmod 600, scratch only,
never committed). Gyms: TEST Gym `8a07bf89`, Gym A `28b82a5f`, Gym B
`cc1b019a`.

### Matrix results (all attacks must FAIL)

Main matrix 46 checks + tail 5 + sweep 23 = 74 attack attempts. Every
P2-6 finding held except the two below (both fixed in this round):

- DB-12 role-gym mismatch: owner assigning a Gym-A Coach role to a TEST
  Gym client → 400 "Role does not belong to this gym." Anon → 401.
- DB-13 `is_system` guard: rewriting the system Client role → 400 "System
  roles cannot be edited." Anon → 401.
- DB-14 owner-role hole: Gym Admin direct INSERT of an ACTIVE `gym_owner`
  membership → 403 RLS; `invite_gym_member` with the owner role as a
  non-manager → 400 "Only the gym manager can assign the gym_owner role."
  Direct membership INSERT into another gym as a client → 403 RLS.
- DB-20 staff directory: as front-desk staff, `get_staff_directory` returns
  7 rows with NO `invite_token`/`national_id` keys; the sensitive variant
  as staff → 400; as manager → 200 with tokens (positive control).
- DB-21 directory restricted to staff: as a plain client,
  `get_staff_directory` and `list_gym_member_directory` → 200 `[]`. Anon →
  200 `[]` (pre-fix; now 401, see below).
- DB-27 booking writes: INSERT a booking into Gym B → 400
  "booking_gym_mismatch"; PATCH another gym's booking → 200 `[]`.
- DB-28 session writes: coach PATCHing a session coached by another coach,
  and client PATCHing a session → 200 `[]`.
- DB-29 `gym_profiles`: INSERT a row for Gym B → 403 RLS; GET Gym B
  profiles → `[]`.
- DB-30 records/photos: `personal_records` / `milestone_photos` tagged with
  a foreign gym → 403 RLS.
- DB-40 invite expiry: `accept_gym_invitation` with the Gym-A invite for
  `test-invitee2` (expired 2026-11-14) → 400 "This invitation has expired.
  Ask the gym to send a new one." Anon → 400 "You must be signed in…"
  (pre-fix; now 401).
- DB-42/43/44 info-leak RPCs: `auth_user_email(ownerB)` → 400 "Not
  allowed to read this email." (self → own email, positive control);
  `permission_codes_for_membership` (Gym-B owner membership) → 400 "Not
  allowed to read permissions for this membership." — see correction note
  below; `sync_legacy_user_membership_projection(ownerB)` → 400 "Not
  allowed to sync this user." Anon → 401 on all three (round-9 revocation
  holds; `ensure_gym_default_roles` anon → 401, same as round 9).
- DB-53 message update: receiver PATCHing `content` → 400 "Only is_read
  may be updated on a message."; sender PATCHing `content` → 200 `[]`;
  receiver PATCHing `is_read=true` → 200 (positive control; the test
  message is now marked read).
- DB-54 staff self-edit: staff self-PATCH of `national_id` → 400
  "national_id, is_active and hire_date are manager-only." (trigger holds
  live). BUT see the regression below — the same bug class lived in
  `upsert_staff_profile`.
- DB-55 gate sessions: manager GETs Gym-A gate sessions → 10 rows; plain
  client GETs the same gym → the same 10 rows, all their own (all 10 Gym-A
  gate sessions belong to test-a-client — verified by SQL); client
  `revoke_gate_session` → 400 "You do not manage this gym."; anon → 401
  (pre-fix; now 401).
- DB-56 dedup: duplicate `personal_records` insert (same
  client/exercise/moment) → 409 `uq_personal_records_client_exercise_achieved`.
- DB-57 tags: `create_gym_specialty_tag` as client → 400 "only a manager
  of this gym can create its tags"; as owner → 200 (tag `P26 Test Tag`
  created in Gym A).
- DB-64 coach specialties: INSERT with a Gym-B `gym_id` → 403 — note
  `authenticated` has NO INSERT grant on `coach_specialties` at all
  (seed/service-role only, by design), so the insert fails before the
  `validate_coach_specialty_write` trigger is reached; the trigger is
  defence in depth. No manager-only RPC for assigning specialties exists
  (product gap, not a security hole).
- DB-46 storage `is_public`: cross-gym GET of Gym-B member's profile file
  → 400 `NoSuchKey`; owner GET → 200; anon GET → 400 `Bucket not found`.
  PNG upload to the own profile path → 200.
- DB-60 SVG: upload `image/svg+xml` to `trainw-media` → 400
  `invalid_mime_type` ("mime type image/svg+xml is not supported"). Bucket
  allow-list confirmed png/jpeg/webp only.
- Post-state SQL verified nothing moved: staff `national_id` still NULL,
  message content unchanged, session/booking still `confirmed`, no owner
  or Gym-B memberships created for the attacking client, invite still
  `pending`, gate session not used.

### REAL REGRESSION — `upsert_staff_profile`: anonymous bypass (DB-54 family)

An unauthenticated `upsert_staff_profile(Gym A, test-a-client)` returned
HTTP 200 and a new row id — it CREATED `staff_profiles`
`6b213dc5-2194-4b94-8f17-3a116bc9c735` (Gym A, user test-a-client,
2026-11-15 16:12 UTC). Root cause: the guard was

    IF NOT (v_can_manage OR v_can_edit OR p_user_id = auth.uid()) THEN RAISE ...

For anon, `auth.uid()` is NULL, so `p_user_id = NULL` is NULL and
`NOT (false OR false OR NULL)` is NULL — the IF never fires. Classic
NULL-comparison fail-open. (The same file's UPDATE trigger was fixed for
the equivalent `manages_gym()` trap in round 6; the RPC was never fixed.)

Second hole in the same function: a self-caller could set `hire_date` on
the INSERT leg, where the BEFORE UPDATE trigger never fires (notes were
already manager-gated the same way).

### LOW — `user_role` / `user_gym_id`: unauthenticated oracle

Both are SECURITY DEFINER RLS helpers still granted to anon via the
PUBLIC default. Anon `user_role(<uuid>)` returned `"client"` and
`user_gym_id(<uuid>)` returned the gym UUID — an enumeration oracle for
anyone who already knows a user UUID. Low severity (UUIDs are not
enumerable, role/gym alone reveal little), but it is exactly the
"revoke PUBLIC EXECUTE on info-leak functions" item in the step.

### Corrections to earlier notes (not regressions)

- DB-43: the round-6 closure note ("other gym's membership returns an
  empty set") predates the `20261115210000` redefinition, which RAISES
  instead. The permission set is not disclosed either way; the live
  behaviour matches current code. Closure row updated.
- Sweep false positives: `bootstrap_authenticated_user` and
  `get_auth_context` as anon return HTTP 200 rows of all NULLs / empty
  lists — no data, no mutation (verified: no user/gym was created). The
  sweep's "RETURNED DATA" flag was too aggressive for null rows.
  Everything else anon returned is null / `[]` / `false` / `0`.

### Fix — migration `20261116160000_phase2_p26_privilege_paths.sql`

1. `upsert_staff_profile`: raise unless signed in, before the permission
   check (kills the NULL bypass); `hire_date` gated on
   `has_permission('manage_staff', gym_id)` on INSERT, and preserved for
   non-managers on UPDATE (same preserve-pattern as `notes`). The gate is
   deliberately `manage_staff`, NOT `manages_gym()`: the latter is true
   for every admin-portal staff member (Staff role portal is `admin`),
   which is exactly why the trigger tests `manage_staff` (round 6) —
   the first version of this migration used `manages_gym()` and the local
   probes caught it (self-upsert tripped the trigger).
2. `user_role` / `user_gym_id`: return NULL when `auth.uid()` IS NULL.
   Policy behaviour is unchanged (policies compare against
   `get_my_gym_id()`, already NULL for anon). Edge functions do not call
   them; the local suite does not call them directly.
3. Hardening (round-9 pattern): `REVOKE ALL ... FROM anon, PUBLIC` +
   `GRANT EXECUTE ... TO authenticated` on 17 app-facing RPCs
   (`upsert_staff_profile`, `get_staff_directory`,
   `get_staff_directory_sensitive`, `list_gym_member_directory`,
   `invite_gym_member`, `set_membership_role`, `save_role_definition`,
   `revoke_gate_session`, `accept_gym_invitation`,
   `decline_gym_invitation`, `apply_member_credit_to_session`,
   `get_member_credit_balance`, `revoke_gym_membership`,
   `revoke_gym_membership_by_user`, `set_active_gym`,
   `bootstrap_authenticated_user`, `list_role_matrix`). Policy machinery
   (`has_permission`, `manages_gym`, `can_*`, `get_my_*`,
   `get_auth_context`) is deliberately NOT revoked. A live grant audit
   found 62 SECURITY DEFINER functions still EXECUTE-able by anon — the
   rest are trigger/RLS helpers and context readers that return
   null/`[]`/`false`/`0` for anon (all probed).
4. DB-61 freeze resync: the assert re-created with the two new hashes
   (`user_gym_id 48660b5b…`, `user_role 37b47cd2…`), same as P2-8 did in
   `20261116140000`.

### Verification

- Local chain (throwaway Postgres 16.4, harness
  `~/workspace/.p26-scratch/p26-harness.sh`, cluster
  `/var/tmp/p26-pgdata`): full chain applies 68 OK + the 2 known
  by-design failures (`20261115050000` B5, `20261115300000` DB-61
  non-portable hash, repaired by later migrations). Round-9 suite 27/27
  pass on a fresh chain, identical with and without this migration.
  Targeted probes (`p26-probes.sql`) 14/14 pass: anon upsert blocked,
  manager upsert keeps `hire_date`, self upsert preserves the
  manager-set `hire_date` while updating `job_title`, anon oracle
  returns NULL, authed lookups still work, anon EXECUTE revoked on all
  17 RPCs (authenticated keeps it), freeze assert passes.
- Live apply via the Management API: one transaction, trailing
  `SELECT assert_rls_helpers_frozen()` returned clean.
- Live retest 24/24 PASS: anon upsert → 401 (was 200 + row); anon
  `user_role`/`user_gym_id` → 200 null; all 17 revoked RPCs → 401 as
  anon; manager upsert keeps `hire_date` (`2024-03-01`); self upsert
  updates `job_title` and preserves the manager `hire_date`; staff
  directory and credit-balance reads still work authenticated; no new
  staff row was created by the retest.
- `node --check` on touched JS: none touched (SQL-only round).
  `node env-config.js` + `npm run verify` pass ("Trainw verify: all
  checks passed").

### Test data created by this round (for the user-decided cleanup)

- `staff_profiles` row `6b213dc5-2194-4b94-8f17-3a116bc9c735` — created by
  the ANON attack itself (the proof of the hole). LEFT IN PLACE per the
  no-deletion rule; test-a-client now has a staff profile in Gym A.
- `staff_profiles` row for test-a-staff (Gym A, `national_id` NULL,
  `job_title` now "Front Desk", `hire_date` 2024-03-01) — created by the
  matrix setup, then legitimately upserted in the retest.
- `personal_records` 1 row ("P26 Test Lift", test-a-client, Gym A).
- `specialty_tags` 1 row ("P26 Test Tag", Gym A). `coach_specialties` 0
  (no INSERT grant — see DB-64 above).
- Storage object `profiles/<Gym A>/<test-a-client>/p26-matrix.png`
  (1×1 PNG). The SVG upload was rejected, nothing stored.
- Gym-A message `1738a7f2` is now `is_read=true` (positive control).
- Passwords reset for 7 test accounts (see method above); new values in
  `~/workspace/.p26-scratch/p26-passwords.json` (chmod 600).
- No live data deleted. No new test users created.

### Residual notes (not findings)

- The 62-function anon-EXECUTE audit: the remaining grants are trigger
  functions, RLS helpers, and context readers — all probed anon and all
  fail closed (null/`[]`/`false`/raise). Revoking anon on the policy
  machinery itself was deliberately NOT done: those functions are
  evaluated inside RLS policies, and the revoke could turn anon policy
  evaluation into errors instead of empty results.
- DB-46 same-gym note stands: a same-gym client holds `manage_media` by
  default and can see other members' private profile media (same-gym
  only; needs a product decision to tighten).
- `coach_specialties` has no app-facing write path at all (see DB-64);
  assigning a specialty currently needs seed/service-role.

## UI/UX — U2: "one 10 DT payment created TWO payments" — NOT A BUG (2026-11-15)

Commit (local, branch phase1-security-fixes): `UI/UX U2: ...` (see `git log`).
The parent pushes; no merge, no deploy from this round. **No code changed.**

### The report vs the ambiguity

Test pass item 2 (owner — functional bugs): recording ONE 10 DT cash
payment (Paiements > 10, Espèces, 1 mois, 15/11/2026, note "TEST Dummy
cash payment 10 DT") showed TWO rows in PAIEMENTS RÉCENTS — the 10 DT
plus an extra 150 DT (both Test Client, Espèces, 15 nov. 2026, 1 mois,
PAID); TOTAUX DU JOUR = 160 DT. The tester said the list was empty
("Aucun paiement enregistré.") before the single click. The P2-2 round
finished 16:31 CET and the test pass ran 16:23–16:44 CET — they
overlapped, and P2-2 itself created a valid 150 DT test payment (then a
30 DT partial refund) on TEST Gym. The 150 had to be checked against
P2-2's documented row before concluding anything.

### Row-by-row reconciliation (live, Supabase "Trainw", caylegavnekidhytlswo)

TEST Gym `8a07bf89-ff6e-40f9-8feb-c384d6b47e5c`; Test Client
`f7b9d45d-1f6a-4487-a7fd-4b61c2c2c649`; Test Owner
`50dcaddd-4b89-41ca-9ee8-5ad84c05ee8d`. Times below are CET (UTC+1).
The gym holds exactly **4 payments in total** (unfiltered query,
limit 100) — there is no second 150 anywhere in the gym, in any status.

1. **The 150 DT row — P2-2's test row, not a phantom.**
   `a8a1ef5f-f824-4775-a52d-825d82250ed9` — total 150.00, paid 150.00,
   refunded 30.00, method cash, status paid, type membership,
   period 1 month, session_id NULL, created_by Test Owner,
   notes NULL, paid_at 2026-11-15T00:00:00Z,
   created_at 2026-11-15T15:30:36.233704Z (**16:30:36 CET**).
   `payment_events`: created paid +150 at 15:30:36.23Z; updated +
   refunded −30 at 15:30:38.63Z. This is byte-for-byte P2-2's
   documented test payment (same id, same 150, same 30 refund — see
   the P2-2 appendix: "Valid 150 payment for client@test.com → HTTP
   201 (id a8a1ef5f-...)" and "Partial refund 30 via
   record_payment_refund → HTTP 200"). It carries NO tester note.
2. **The 10 DT row — the tester's single payment, exactly one row.**
   `53cd3045-8cee-476b-b4c1-5c58fc223822` — total 10.00, paid 10.00,
   refunded 0.00, method cash, status paid, type membership,
   period 1 month, session_id NULL, created_by Test Owner,
   notes **"TEST Dummy cash payment 10 DT"** (exact match),
   paid_at 2026-11-15T00:00:00Z,
   created_at 2026-11-15T15:30:37.297075Z (**16:30:37 CET**).
   `payment_events`: exactly ONE event — created paid +10.
   Same id P2-2 noted as "a 10.00 payment I did not create
   (53cd3045-..., paid 2026-11-15) — it appeared between my baseline
   query (0 payments) and the final check". One click → one row →
   one event. No duplicate was created by the payment flow.
3. **50 DT paid session payment — unrelated, later, booking flow.**
   `dc74a52c-2c13-4016-86ca-4dc210ce542a` — total 50.00, paid 50.00,
   refunded 0, method NULL, status paid, type session,
   session_id `9da61eac-d6ad-4f0a-a2e7-47f719e316b2`,
   created_by Test Client, notes NULL,
   created_at 2026-11-15T16:00:28.854405Z (**17:00:28 CET**),
   paid_at 16:00:32.13Z. Events: created pending, then
   status_changed pending→paid +50. Created by the client user via
   the booking flow (pending session payment → paid), ~30 min after
   the test pass ended — most likely the U1 booking-fix round's live
   verification. Not a duplicate of anything; not from the tester.
4. **50 DT pending session payment — unrelated, later, booking flow.**
   `4d76311d-75f7-46b4-b561-125b10e05a23` — total 50.00, paid 0.00,
   refunded 0, method NULL, status pending, type session,
   session_id `c4363df7-eeef-4e44-b2fc-02f0e0dbb368`,
   created_by Test Client, notes NULL,
   created_at 2026-11-15T16:00:34.722831Z (**17:00:34 CET**).
   Events: exactly one — created pending. Same booking-flow origin
   as row 3 (a second session booking's pending payment).

Note: the `payments` table has NO `collected_by` column (schema:
`created_by` only); nothing was omitted from the reconciliation —
the full column set above is `id, gym_id, client_id, session_id,
created_by, payment_type, status, provider, method, currency_code,
amount_total, amount_paid, amount_refunded, invoice_reference,
provider_reference, due_at, paid_at, cancelled_at, notes,
created_at, updated_at`.

### Timeline — how the tester saw an empty list and then two rows

- P2-2's baseline query: **0 payments** in TEST Gym.
- **16:30:36 CET** — P2-2 creates the 150 (owner JWT, PostgREST insert).
- **16:30:37 CET** — the tester records the 10 DT via the UI,
  **1.06 seconds later** (same owner JWT, same direct-insert path).
- **16:30:38 CET** — P2-2 refunds 30 on the 150.
- The tester opened the Paiements page before 16:30:36, when the
  list was genuinely empty (`loadPayments` loads ALL gym payments,
  limit 50 — "Aucun paiement enregistré." is only shown when the gym
  has no payments at all). After the single click, `recordPayment`
  re-ran `loadPayments()`, which re-fetched and now showed both
  rows: the tester's 10 and P2-2's 150, created one second apart.
- TOTAUX DU JOUR = 160 DT is also explained, not a second bug: the
  deployed build (main cff7df9a) still sums GROSS `amount_paid`
  (150 + 10 = 160); P2-2's net-of-refund frontend change
  (net would be 130) was not deployed yet. The 30 DT refund was
  correctly recorded on the 150 row.

### Sanity check on the payment flow (step 3, code-level; no live mutation)

- `recordPayment` (`tw-gym-acc.js:2019`) does exactly ONE
  `sb.from('payments').insert({...})` — no RPC, no second insert, no
  loop, no retry. `Trainw.api.run` (`trainw-core.js:157`) awaits the
  operation exactly once; there is no retry/re-fire path.
- Double-submit guard verified for this form specifically:
  `recordPayment` calls `Trainw.ui.setBusy(btn, true)` before the
  insert and `setBusy(btn, false)` after; `setBusy`
  (`trainw-core.js:405`) sets `element.disabled = Boolean(busy)`,
  so the button is disabled while the insert is pending.
- No live reproduction payment was recorded: the row evidence
  already proves one click → one row (single "created" event on
  `53cd3045`), and an extra live payment would only add test-data
  noise. The P2-2 round's own live 150 insert (one row, one event)
  is the same proof from the other side.
- Owner-JWT view re-checked live: the exact `loadPayments()` query
  returns the same 4 rows above, so what the tester saw in the
  browser matches the ledger.

### Verdict

**Not a bug. No fix made, nothing in the payment flow changed.**
The "phantom 150" is the P2-2 round's own documented test payment,
surfacing in the list because the two rounds ran concurrently and
their writes landed one second apart. The payment flow creates
exactly one row per click, with a working double-submit guard.

### What was NOT done (per the task)

- **No data deleted.** The 150 DT row `a8a1ef5f-f824-4775-a52d-825d82250ed9`
  (P2-2's test row, 30 DT refunded) and the 10 DT row
  `53cd3045-8cee-476b-b4c1-5c58fc223822` (tester's row) are both left
  in place, as are the two 17:00 CET 50 DT session rows. Cleanup
  needs the user's word — and note the 150/10 are P2-2's and the
  tester's rows respectively, not a duplicate pair to void.
- No push / merge / deploy. No RLS change; no new secrets in files
  (keys and JWTs lived only in script memory, never printed).
- Verification: `node --check` — no JS files touched, nothing to
  check. `node env-config.js` + `npm run verify` pass ("Trainw verify:
  all checks passed").

### Not verified in this session (no live-browser access)

- The browser render itself (the tester already saw it live; this
  round verified the underlying rows and the owner's API view, not
  the pixels).
- The two 17:00 CET 50 DT session rows were not traced to a specific
  round — attributed to the U1 booking-fix live verification by
  timing (17:00 CET, after the test pass) and shape (client-created
  pending session payments), but not confirmed with that round.

## UI/UX — U3: membership freeze flow completely broken (2026-11-15)

Test-pass item: Owner — functional bugs, #3. Paiements > GELS
D'ABONNEMENT > freeze Test Client 16–20 Nov 2026 → inline error +
toast `Could not find the function
public.request_membership_freeze(p_end_date, p_reason, p_start_date,
p_user_id) in the schema cache` (reproduced twice). Opening the
Paiements page also showed an unprompted red toast: `column
membership_freezes.freeze_start_date does not exist`. No freeze
existed, so no unfreeze control could be tested.

### Mismatch found (investigated live first — the DB was right, the UI was wrong on both counts)

Live DB (Supabase "Trainw", caylegavnekidhytlswo), queried via
Management API `POST /v1/projects/{ref}/database/query`:

- `request_membership_freeze(p_user_id uuid, p_gym_id uuid,
  p_start_date date, p_end_date date, p_reason text DEFAULT NULL)`
  EXISTS live, exactly as the chain defines it
  (`20261115110000_phase1c_membership_freezes.sql`).
- `cancel_membership_freeze(p_freeze_id uuid)` EXISTS live.
- `membership_freezes` has columns `start_date` / `end_date` — there
  are NO `freeze_start_date` / `freeze_end_date` columns, in the
  chain or live.
- `trg_freeze_shift_membership` trigger enabled; gate function
  `membership_is_active_for_access` contains the freeze clause;
  `assert_rls_helpers_frozen()` passes live (DB-61 hash still good).

UI (`tw-gym-acc.js`, before this round):

1. `requestFreeze` called the RPC with only 4 params — it omitted
   `p_gym_id`, which is required (no default). PostgREST therefore
   found no 4-arg overload → the "schema cache" error. The error
   message itself lists the 4 params the UI sent.
2. `loadFreezes` selected `freeze_start_date, freeze_end_date` and
   ordered by `freeze_start_date` — columns that never existed →
   the unprompted red toast on every Paiements page load.
   `renderFreezesList` read the same two wrong fields.
3. No migration was needed and none was applied live: the chain and
   the live DB already agree. A stale PostgREST schema cache was
   ruled out — the function and table are exactly as the chain
   defines them.

### Fix (UI only, `tw-gym-acc.js`)

- `loadFreezes`: select `start_date, end_date`, order by
  `start_date`. (Comment notes the U3 rename.)
- `renderFreezesList`: range now reads `f.start_date` /
  `f.end_date`.
- `requestFreeze`: RPC call now passes `p_gym_id: currentGymId`,
  plus a guard (`Aucune salle sélectionnée.`) when no gym is
  selected. `cancelFreeze` was already correct
  (`cancel_membership_freeze`, `p_freeze_id`) and is unchanged.
- No RLS change; no DB change; the gate's freeze check
  (`membership_is_active_for_access`) is untouched and consistent
  with the table as stored.

### Live verification (owner@test.com JWT, PostgREST — the exact call shapes the fixed UI now makes)

Baseline: Test Client (`f7b9d45d-1f6a-4487-a7fd-4b61c2c2c649`,
TEST Gym `8a07bf89-ff6e-40f9-8feb-c384d6b47e5c`), membership
2026-11-15 → 2027-01-15, paid, 0 prior freezes.

- Fixed `loadFreezes` query shape as owner: returns `[]`, no error
  (previously errored on the missing column).
- `request_membership_freeze` with
  `{p_user_id, p_gym_id, p_start_date: 2026-11-16, p_end_date:
  2026-11-20, p_reason: "TEST Dummy freeze - U3 round"}` → freeze
  `0e31776a-d795-4ec0-8f38-17a76bc66c65`, status `active`.
- End date shifted by the frozen days: 2027-01-15 → 2027-01-19
  (+4 days, the 16→20 Nov span) via the trigger.
- Gate: `membership_is_active_for_access` = false for 2026-11-17
  (inside the freeze), true for 2026-11-21 (after) and true for
  today 2026-11-15 (before the freeze starts). Frozen member is
  denied at the gate; P2-3 semantics hold.
- `cancel_membership_freeze` (`p_freeze_id`) → status `cancelled`,
  end date rolled back to 2027-01-15, gate true again for
  2026-11-17. Unfreeze verified — it exists and works.

### Test data left in place (no deletion)

- One freeze row `0e31776a-d795-4ec0-8f38-17a76bc66c65` (Test Client,
  2026-11-16 → 2026-11-20, reason "TEST Dummy freeze - U3 round"),
  status `cancelled`, created by the owner test account. Left as
  freeze history, per the no-deletion rule. The client's membership
  end date is back to its pre-test value (2027-01-15).

### Verification

- `node --check tw-gym-acc.js` clean; `node env-config.js` +
  `npm run verify` pass ("Trainw verify: all checks passed").
  (`.env.local` with the project URL/anon key was created for the
  build — gitignored, not committed.)
- No migration added, so no local chain re-test was needed.

### Not verified in this session (no live-browser access)

- The browser render itself (form → toast → "Aucun gel actif."
  replaced by the freeze row, and the "Annuler le gel" button) —
  needs the parent's browser check after deploy. The API-level
  round trip the UI calls is verified end to end.

## UI/UX — U4: direct "Ajouter un Client" fails RLS + example people prefilled (2026-11-15)

Test-pass item: Owner — functional bugs, #1, plus the cross-cutting
"all add/invite forms come prefilled with example people (Sana Ben Ali,
Ahmed Ben Ali) as real values, not placeholders". Clients > Ajouter un
Client > TEST Dummy A / dummy-a@test.com / +216 00 000 001 > Ajouter le
Client → inline error + toast: `new row violates row-level security
policy for table "client_profiles"` — no client created (list stays at
1). Reproduced twice by the tester.

### Root cause (ordering bug, not a missing policy)

`submitNewClient` in `tw-gym-acc.js` created the rows in this order:
`users` → `client_profiles` → `gym_memberships`. The
`client_profiles_insert` policy (004, unchanged since, verified live)
lets a manager insert only when
`is_gym_manager() AND is_same_gym_user(user_id)` — and
`is_same_gym_user` (latest form, `20261115210000`) requires an
`accepted`/`active` `gym_memberships` row for the target user in a gym
the caller belongs to. At profile-insert time no such row existed yet
for the brand-new user, so the check was always false for a direct add.
The `users` insert itself passes (manager branch of `users_insert`);
the `gym_memberships` insert would also have passed
(`gym_memberships_insert_v17b` needs only `manage_staff` + a role in
that gym) — it just never got reached.

Intended design, confirmed from the code: direct-add creates a profile
for a NON-existent user — a managed walk-in client (`is_managed:
true`, synthetic `@trainw.local` email derived from the name). It does
NOT expect the email to match an existing Trainw user. The invite flow
is the one that requires an existing account. Note the form's email
field (`new-client-email`) is currently read by nothing — the typed
address is silently discarded and the synthetic address is stored
instead. Left as is in U4 (changing it would need a product call: a
managed client has no login, so the address would be contact detail
only); flagged as a follow-up below.

### Fix (UI reorder + price validation moved earlier; no policy touched for the bug itself)

`tw-gym-acc.js` `submitNewClient`, new order:
`users` → `gym_memberships` → `client_profiles` → (`payments` if a
price was entered). Rollback is unchanged — deleting the `users` row
cascade-deletes the membership and profile rows
(`gym_memberships.user_id` and `client_profiles.user_id` are both
`ON DELETE CASCADE`, verified live; there is no DELETE policy on
`gym_memberships`, so no separate membership delete was added). The
price parse/validation also moved BEFORE the first insert: the old code
parsed it after the `users` insert, so an invalid amount orphaned a
managed `users` row (the early return deleted nothing).

### Second hole found during the investigation (policy, fixed by migration)

The `client_profiles_insert` WITH CHECK never constrained `NEW.gym_id`:
`user_id = auth.uid() OR (is_gym_manager() AND
is_same_gym_user(user_id))`. Proven live 2026-11-15: as the TEST Gym
owner, inserting a `client_profiles` row for Test Client (a same-gym
user) with `gym_id` = TEST — Gym B (a real gym the owner does not
manage) returned **201**. The probe row
(`8fb42fda-2ec3-4019-b781-8871f010d614`) was deleted immediately after
(204). Practical impact was cross-gym data pollution, not disclosure —
the stray row was not visible to Gym B's manager, because the SELECT
policy also needs `is_same_gym_user(user_id)`. Still a hole, so U4
closes it: new migration
`20261116170000_u4_client_profile_insert_gym_binding.sql` adds
`AND public.manages_gym(gym_id)` to the manager branch. The self-insert
branch (`user_id = auth.uid()`, signup bootstrap, `gym_id` NULL at that
point) is untouched. The only direct browser insert of
`client_profiles` is `submitNewClient`; every SQL-side insert runs in a
migration or a SECURITY DEFINER function and bypasses RLS. The
UPDATE/DELETE policies on this table share the unbound shape (they key
off the row's user, not its `gym_id`); they can only touch rows whose
user is in the manager's gym, and stray rows can no longer be created
via INSERT — tightening them is a follow-up, not U4.

### Prefill sweep (what was actually there)

Correction to the test-pass wording: no `value="Sana Ben Ali"`-style
prefill exists anywhere in source or `dist` — the example people were
already `placeholder="…"` attributes, never submitted values, and no JS
sets `.value` on these fields when a modal opens (only `.focus()` on
the invite name field). The tester read the realistic placeholders as
prefilled values, which is the real hazard, so U4 makes the hints
unmistakably generic instead of named people (placeholders stay
placeholders; values stay empty):

- `tw-gym-acc.html` — invite-member, new-coach, new-client forms:
  name `Sana Ben Ali` / `Ahmed Ben Ali` → `Prénom Nom`;
  email `sana@salle.tn` / `ahmed@salle.tn` → `exemple@email.com`;
  phone `+216 92 123 456` → `+216 XX XXX XXX` (also the edit-client
  phone placeholder). The `150` price and `28` age placeholders are
  bare numbers, not people — left alone.
- `tw-login.html` + `tw-login.js` — public signup name field, same
  class: `phName` `Ahmed Ben Ali` → `Prénom Nom` (fr),
  `First Last Name` (en), `الاسم الكامل` (ar).
- Verified after the change: no `Sana Ben Ali`, `Ahmed Ben Ali`,
  `sana@salle.tn`, `ahmed@salle.tn` or `92 123 456` string remains in
  source (JS/HTML, excluding generated `dist/`); `dist/` regenerated
  by the build carries the new hints.
- Edits were byte-level (Python, files read/written as bytes) so the
  double-encoded UTF-8 (mojibake) sequences in `tw-gym-acc.js` are
  untouched — the `tw-gym-acc.js` diff is confined to the
  `submitNewClient` region (3 hunks). `tw-coach-acc.js` /
  `tw-client-acc.js` were not edited in this round.

### Verification (API level, live project, TEST Gym)

Owner JWT (`owner@test.com`, TEST Gym
`8a07bf89-ff6e-40f9-8feb-c384d6b47e5c`), anon key via Management API,
tokens in memory only; repro scripts are throwaway in `/tmp`
(`u4-repro.py`, `u4-probe-c.py`, `u4-tests.sql`, `u4-edit.py`).

- Phase A — current UI order replayed: `users` insert 201, then
  `client_profiles` insert → **403, code 42501, `new row violates
  row-level security policy for table "client_profiles"`** — the exact
  tester error. The `users` row was rolled back exactly as the UI does
  (delete, 204).
- Phase B — fixed order replayed: `users` 201 → `gym_memberships` 201
  → `client_profiles` **201**. Created client **TEST Dummy U4**,
  user `9a1c45a3-3930-4191-8cfe-d2a71f4fbbff`, profile
  `4bce875d-241a-44a2-aefa-8baaec39997c`, membership
  `c07cd3f6-08f0-45f1-b8be-511f97f76bae`, monthly, pending, 2026-11-15 →
  2026-12-15, price 0 — read back OK. **Left in place as test data**
  (no payment attached). The cross-gym probe in this run used a random
  gym id and failed on the FK, not RLS — inconclusive as an RLS proof;
  the conclusive probe is Phase C below.
- Phase C — gym-binding probe (before the migration): same-gym user,
  foreign real gym id → **201** (hole confirmed); probe row deleted
  immediately (204).
- Local chain (throwaway Postgres 16, `p26-harness.sh`, stubs):
  full chain applies, **69 OK, 2 FAIL** — the same 2 failures as the
  pre-U4 baseline (68 OK, 2 FAIL), both pre-existing and unrelated
  (`20261115050000_phase1b_directories.sql`,
  `20261115300000_phase1e_freeze_hash_defaults.sql` — the latter is the
  `assert_rls_helpers_frozen` drift assertion). The U4 migration
  itself applies cleanly. Behavioural suite `/tmp/u4-tests.sql`,
  **6/6 pass**: owner is manager of Gym A not B; profile-before-
  membership → 42501; membership-first → insert ok (under the NEW
  policy); cross-gym insert → 42501; self-insert (signup path) still
  works; fixtures sane.
- `node --check` on `tw-gym-acc.js` + `tw-login.js`: OK.
  `node env-config.js` + `npm run verify`: "all checks passed".

### Still needs the parent

- **Browser check after deploy**: open Clients > Ajouter un Client as
  the owner, add a client end to end (the API-level sequence the UI now
  runs is verified; the click path itself was not — no live-browser
  access in this round), and confirm the add/invite forms render empty
  with the new neutral placeholders.
- **Live check of the policy migration after deploy**: the tightening
  is chain-tested locally only; confirm live that a cross-gym
  `client_profiles` insert is refused (42501) and that direct-add still
  succeeds.
- Follow-ups (not U4): the add-client email field is collected but
  discarded — drop the field or store the address (needs a product
  call); same unbound-`gym_id` shape in `client_profiles` UPDATE/DELETE
  policies and (by analogy) `coach_profiles_insert`; the 2 pre-existing
  chain failures above; test-data cleanup (TEST Dummy U4 from this
  round, plus the earlier TEST Dummy rows) needs the user's word.

## UI/UX — U5: rescheduling a session to a PM time fails with a range error (2026-11-15)

Test-pass item: Owner — functional bugs, #4. Planning > Modifier on the
class session, change to 19 Nov 2:00 PM > Enregistrer → red inline error
`range lower bound must be less than or equal to range upper bound`,
modal stays open, session unchanged. Reproduced twice by the tester. AM
changes worked (19 Nov 11:00 AM saved fine; no-change save works).

### Root cause (DB trigger, not the UI)

`saveEditSession` (`tw-gym-acc.js`) sends `session_date` + `start_time`
only — the UI has no end-time input (duration only). The edit input is
`type="time"` (`tw-gym-acc.html:898`), whose `.value` is always 24-hour,
so the PM save sends `start_time: "14:00:00"` — reproduced in node with
the exact tester values (19 Nov, 2:00 PM → `{session_date:
"2026-11-19", start_time: "14:00:00"}`); the payload itself is valid.
The failure is server-side, in the trigger chain on `sessions`:

1. `trg_sessions_10_prepare` → `prepare_session_write()` set
   `NEW.end_time := session_effective_end_time(start, end, duration)`,
   which returns a non-null stored `end_time` UNCHANGED.
2. The session was created 11:00 + 60 min, so it stored `end_time`
   12:00. The PM edit moved `start_time` to 14:00 but left `end_time`
   at 12:00.
3. `trg_sessions_20_validate` → `validate_session_write()` then built
   `v_range := session_time_range('2026-11-19', 14:00, 12:00, 60)` =
   `tsrange('2026-11-19 14:00', '2026-11-19 12:00')` → Postgres raises
   "range lower bound must be less than or equal to range upper bound".
   AM moves passed only because 11:00 stayed below the stale 12:00 end.

Reproduced exactly, pre-fix, twice over: on the local full chain
(insert 11:00/60 → end 12:00; UPDATE to 14:00 → the range error from
`validate_session_write()`) and live via PostgREST as the owner (PATCH
→ 400, code 22000, the tester's exact message).

The time-picker cross-cutting note (Tab across the hour/minute/AM-PM
spinbuttons corrupts segments to 0) is a native `type="time"` input
quirk: whatever the picker shows, `.value` is a valid 24-hour time or
empty, so it cannot produce this error and no UI change is needed for
U5. The create path (`submitNewSession`) never sends `end_time`
either, so fresh PM inserts always computed correctly — no bug there.

### Fix (DB only, migration `20261116180000_u5_session_reschedule_end_time.sql`)

In `prepare_session_write()` only — the one place that decides what
`end_time` gets stored. `end_time` is now always derived from
`start_time + duration_minutes` (clamped to 23:59 when the sum wraps
past midnight, the same pattern as the 003 data cleanup, so the
`end_time > start_time` CHECK stays satisfied; `NULL` start → `NULL`
end). The function body is otherwise byte-identical to the 003
definition (verified by diff — only the `NEW.end_time :=` line
changed). `session_effective_end_time()` itself is untouched: every
other caller passes NULL for `end_time`.

Why always derive, rather than keep a stored end that is still after
the new start: the keep-branch was tested first and is wrong in the
other direction — 11:00 → 14:00 (end recomputed 15:00) → 11:00 leaves
a 4-hour session (end 15:00) behind, a phantom block in every overlap
check that reads `end_time`. Always deriving is correct because no UI,
RPC or migration ever writes an explicit `sessions.end_time` (verified
by grep — this trigger is its only writer), and it self-heals rows
carrying a stale end from the old bug on their next write of any kind.
No RLS change; no data migration; no JS touched.

### Verification

- Local chain (throwaway Postgres 16, `p22-harness.sh`, stubs): full
  chain applies, **70 OK, 2 FAIL** — the same 2 failures as the pre-U5
  baseline (69 OK, 2 FAIL), both pre-existing and unrelated
  (`20261115050000_phase1b_directories.sql`,
  `20261115300000_phase1e_freeze_hash_defaults.sql`). The U5 migration
  itself applies cleanly. Behavioural suite `/tmp/u5-tests.sql`,
  **7/7 pass**: create 11:00/60 → end 12:00; PM move to 14:00 → end
  15:00 (was the range error); AM move back to 11:00 → end 12:00 (not
  the 15:00 the keep-branch left); explicitly supplied end_time is
  derived, not kept; 23:30 + 60 min → end 23:59 (no midnight wrap);
  fresh PM insert 14:00 → end 15:00; no-change save → end 12:00.
- Migration applied live via the Management API
  (`POST /v1/projects/caylegavnekidhytlswo/database/query`, `[]`);
  live `prepare_session_write` prosrc confirmed: U5 CASE present, old
  `session_effective_end_time(NEW.start_time, NEW.end_time, …)` line
  gone.
- Live API verification (owner@test.com JWT, PostgREST — the exact
  PATCH shape `saveEditSession` sends), TEST Gym
  `8a07bf89-ff6e-40f9-8feb-c384d6b47e5c`, session TEST Dummy Class
  `7fa5098e-42c3-41df-869f-55ed80103be0` (baseline 19 Nov 11:00→12:00,
  dur 60, confirmed): pre-fix PATCH to 14:00 → **400, code 22000,
  the tester's exact error**; post-fix PATCH to 14:00 → **200,
  stored 2026-11-19 14:00:00→15:00:00**; PATCH back to 11:00 →
  **200, stored 2026-11-19 11:00:00→12:00:00**. No session deleted.
  Final state equals the tester's last good state (19 Nov 11:00).
  Repro scripts are throwaway in `/tmp` (`u5-repro.sql`,
  `u5-tests.sql`, `u5-live.py`, `u5-apply.json`, `u5-check.json`).
- `node --check tw-gym-acc.js` clean (no JS changed in this round);
  `node env-config.js` + `npm run verify`: "all checks passed".

### Still needs the parent

- **Browser check after deploy**: open Planning > Modifier on the
  class session as the owner, move it to a PM time and save — the
  API-level round trip the UI calls is verified; the click path itself
  was not (no live-browser access in this round).
- **Live check of the migration after deploy**: the fix is applied
  live and verified via the API above, but confirm in the browser that
  the saved PM time renders correctly in Planning (and that no other
  session in TEST Gym shows a stale end — the 17 Nov coach session was
  untouched, 10:00→11:00).
- Follow-ups (not U5): changing `duration_minutes` alone in the edit
  modal now correctly recomputes `end_time` (a side benefit of always
  deriving); the native time-picker Tab-corruption quirk and the
  12:00 AM → "00:00" display remain as cross-cutting UI polish; the 2
  pre-existing chain failures above; test-data cleanup needs the
  user's word.

## UI/UX — U3b: "Annuler le gel" silently does nothing + full native confirm/prompt audit (2026-11-15)

Test-pass item: Owner — functional bugs, #3 follow-up. Freeze creation
works, but "Annuler le gel" does nothing — clicked 3x in a real
browser, no toast, no error, freeze stayed active. (Browser re-check
of batch 1, production main 5464264d.)

### The gate found

`cancelFreeze` (`tw-gym-acc.js`, was line ~2120) was gated behind a
bare native `confirm('Annuler ce gel ? …')`. An auto-dismissed
confirm returns `false`, so the handler returned before the RPC ever
fired — exactly the U1 booking bug, same silent-failure class. The
RPC itself was already proven fine: the parent called
`cancel_membership_freeze` as the owner via PostgREST (HTTP 200) and
the test freeze (`1b008f12`, "TEST re-check freeze", 16–20 Nov) is
now status `cancelled`, test client restored.

### Fix (UI only, no DB change)

- `cancelFreeze`: native confirm dropped; the click goes straight to
  `cancel_membership_freeze({p_freeze_id})` with a success/error
  toast. Cancelling a freeze is reversible (a new freeze can be
  created) and the button + toast are the confirmation. Comment
  notes the U3b reasoning at the call site.

### Full audit: every native confirm/prompt in the vanilla codebase

Searched all app JS (`tw-gym-acc.js`, `tw-client-acc.js`,
`tw-coach-acc.js`, `tw-role.js`, `tw-login.js`, `trainw-core.js`,
`tw-gym-pilot.js`, `index.js`, `gate-terminal.js`, `trainw-tenant-utils.js`,
`trainw-config.js`, `env-config.js`, `scripts/`) plus inline HTML
scripts, for `window.confirm`, bare `confirm(`, `window.prompt`,
bare `prompt(` and `alert(`. No `alert(` anywhere. 12 native-dialog
call sites total (11 confirm + 1 prompt), all in 3 files. There is
NO shared in-app confirm modal in the codebase — only per-feature
form modals (`.modal` + `.show`). The line-2060 comment claiming
"the app's confirm modal" was stale/aspirational; it was never built
and the comment is corrected in this round.

| # | Site | Action | Verdict |
|---|---|---|---|
| 1 | `tw-gym-acc.js` `cancelFreeze` | Cancel freeze (mutation, reversible) | **Fixed** — gate dropped, RPC + toast |
| 2 | `tw-client-acc.js` `cancelSession` | Client cancels a booking (mutation, re-bookable) | **Fixed** — gate dropped; dead `cancelConfirmCopy()` helper removed |
| 3 | `tw-coach-acc.js` `respondToBooking` | Coach confirms/declines a booking (routine workflow) | **Fixed** — gate dropped |
| 4 | `tw-coach-acc.js` `cancelCoachSession` | Coach cancels a session (routine workflow) | **Fixed** — gate dropped |
| 5 | `tw-coach-acc.js` `completeBooking` | Coach marks a session complete (routine workflow) | **Fixed** — gate dropped; dead `coachDecisionCopy()` helper removed |
| 6 | `tw-gym-acc.js` `triggerInactivityMessages` | Bulk in-app messages to N inactive clients | **Fixed** — gate dropped per the mutation rule. Flag: one click now sends to all inactive clients; the button + template + day threshold are the only guard. A future round may add an in-app confirm showing the count. |
| 7 | `tw-gym-acc.js` `deleteCustomRole` | Delete a role | **Kept** — destructive; no in-app confirm modal exists, native confirm is the only guard. Annotated `// U3b`. |
| 8 | `tw-gym-acc.js` `revokeMembership` | Revoke staff access | **Kept** — destructive; same reason. Annotated. |
| 9 | `tw-gym-acc.js` `deleteGymClass` | Delete (soft) a class | **Kept** — destructive; same reason. Annotated. |
| 10 | `tw-gym-acc.js` `deleteSession` | Delete a session, labelled irréversible | **Kept** — destructive; same reason. Annotated. |
| 11 | `tw-gym-acc.js` `deleteCoach` | Revoke + delete profile AND user row | **Kept** — destructive; same reason. Annotated. |
| 12 | `tw-gym-acc.js` `deleteClient` | Revoke + delete profile AND user row | **Kept** — destructive; same reason. Annotated. |
| 13 | `tw-gym-acc.js` `deleteMemberCredential` | Delete a gate badge | **Kept** — destructive (revokes a credential); same reason. Annotated. |
| 14 | `tw-gym-acc.js` `voidPayment` | `window.prompt` for the mandatory void reason | **Kept** — this is data entry, not a yes/no gate: the reason is mandatory ledger data and the prompt cannot just be dropped. No in-app input modal exists yet; a future round should replace it with one, not remove it. Stale comment fixed. |

No non-mutation confirm was found (nothing guards navigation away
from unsaved work), so no behaviour of that kind was changed.

After the fix, the only remaining native dialogs are the 8 kept
ones above (7 confirms on destructive actions + 1 prompt for a
mandatory reason), each annotated `// U3b` with its reason — proven
by grep (see Verification).

### Live verification (owner@test.com JWT, PostgREST — the exact call shape the fixed UI now makes)

Baseline: Test Client (`f7b9d45d-1f6a-4487-a7fd-4b61c2c2c649`, TEST
Gym `8a07bf89-ff6e-40f9-8feb-c384d6b47e5c`), membership end date
2027-01-15, paid, no active freeze; the parent's `1b008f12` freeze
confirmed `cancelled`; gate `membership_is_active_for_access` =
true for 2026-11-17.

- `request_membership_freeze` with `{p_user_id, p_gym_id,
  p_start_date: 2026-11-16, p_end_date: 2026-11-20, p_reason:
  "TEST U3b unfreeze re-check"}` → freeze
  `c16636e1-cc04-4628-ba5a-3fce0e63a3d0`, status `active`.
- End date shifted 2027-01-15 → 2027-01-19 (+4 days, trigger);
  gate false for 2026-11-17 while frozen.
- `cancel_membership_freeze({p_freeze_id: c16636e1-…})` → **200,
  status `cancelled`** — the exact call the fixed `cancelFreeze`
  makes, with no confirm in the path.
- End date rolled back to 2027-01-15; gate true again for
  2026-11-17. Unfreeze verified end to end at the API level.

First run of the verification script died on the known
VM↔Supabase flakiness (`IncompleteRead` on sign-in, both attempts);
re-run succeeded. Repro script is throwaway in `/tmp`
(`u3b-verify.py`, `u3b-check-avail.py`).

### Test data left in place (no deletion)

- One freeze row `c16636e1-cc04-4628-ba5a-3fce0e63a3d0` (Test
  Client, 2026-11-16 → 2026-11-20, reason "TEST U3b unfreeze
  re-check"), status `cancelled`, created by the owner test account.
  Left as freeze history, per the no-deletion rule. The client's
  membership end date is back to its pre-test value (2027-01-15).

### 18 Nov availability setup (for the parent's U1 browser re-test)

Test Coach (`b38df3c8-d7b3-49f6-a180-8d1c377b2f1f`, coach@test.com)
had only a Monday 09:00–12:00 active window. Published Wednesday
availability the same way the coach UI does
(`coach_availability` insert, `day_of_week: 3`,
`start_time: 09:00`, `end_time: 12:00`, `slot_minutes: 60`,
`is_active: true`, TEST Gym): row
`486cf170-c0ae-4a7e-a720-68493dbca55f`, created 2026-11-15
16:50:41 UTC. **Wednesday 18 Nov 2026 is now bookable 09:00–12:00
in four 60-minute slots** — the parent books in the browser; nothing
was booked by this round.

Quirk, reported honestly: the insert POST itself returned **400
`P0001 — conflict: availability overlaps an existing active window`**
even though no Wednesday window existed (the only prior row was
Monday 09:00–12:00). The row nevertheless exists — verified by two
independent reads after the insert (exactly one Wednesday row, no
duplicate). The 400 looks like the same VM↔Supabase connection
flakiness that killed the first sign-in attempt (the response was
likely garbled/replayed), not a real overlap: the stored row is
correct and no duplicate was created. The insert was NOT re-issued
(idempotency: the row already exists).

### Verification

- `node --check` clean on all three touched files
  (`tw-gym-acc.js`, `tw-client-acc.js`, `tw-coach-acc.js`).
- `node env-config.js` + `npm run verify`: "all checks passed".
- Grep after the fix: remaining `confirm(`/`prompt(` hits are only
  the 8 kept sites above (plus `// U3b` comment lines naming them);
  no native dialog gates any routine mutation.
- No RLS change; no DB change; no migration.

### Still needs the parent

- **Browser check after deploy**: freeze Test Client, then click
  "Annuler le gel" — confirm the freeze cancels, the toast appears,
  and the list returns to "Aucun gel actif." The API-level round
  trip is verified; the click path itself was not (no live-browser
  access in this round).
- **U1 booking + DB-66 credit click path**: book a slot on the new
  Wed 18 Nov 09:00–12:00 availability as the test client and confirm
  the booking + credit flow in the browser. The DB-66 credit click
  path is NOT verified by this round — only the parent's browser
  re-test can prove it.
- **Future round (not U3b)**: build one shared in-app confirm modal
  (the `.modal` + `.show` pattern already exists) and convert the 7
  kept destructive confirms + the `voidPayment` reason prompt to it;
  consider the same for the bulk inactivity-message send.


## UI/UX — U6: revenue figures disagree across views + Planning shows no reservations (2026-11-15)

Test-pass item: Owner — functional bugs, #12. Dashboard REVENU MENSUEL
showed "—", then 64, then 56 across reloads with no new payments, while
Analytiques showed "160 DT CE MOIS"; Planning said "Vue des réservations
— Aucune reservation a afficher." while the dashboard counted 2 confirmed
reservations.

### Live reconciliation (owner@test.com JWT, TEST Gym `8a07bf89-…`, 2026-11-15 ~17:52 CET)

Payments — all 4 rows in the gym (no other payments exist):

| row | paid | refunded | status | type | paid_at | net |
|---|---|---|---|---|---|---|
| `a8a1ef5f` | 150 | 30 | paid | membership, cash, 1 mo | 2026-11-15 | 120 |
| `53cd3045` | 10 | 0 | paid | membership, cash, 1 mo | 2026-11-15 | 10 |
| `dc74a52c` | 50 | 0 | paid | session | 2026-11-15 16:00:32 UTC | 50 |
| `4d76311d` | 0 | 0 | pending | session, total 50 | — | 0 (excluded) |

The "two 50 DT session payments created 17:00 CET" from the U2 note are
`dc74a52c` (paid 50, counts) and `4d76311d` (total 50, 0 paid, still
pending — correctly excluded by the `status='paid'` filter and by its
zero `amount_paid`).

- **November now: NET 180 DT, GROSS 210 DT. October: 0.**
- At test time (16:23–16:44 CET, before the two 17:00 CET rows):
  net 130, gross 160. Analytics' "160 DT CE MOIS" was exactly the
  deployed build's gross sum — consistent, not a second computation.
- **Single correct figure every view should show now (current branch,
  P2-2 netting): 180 DT net** — dashboard `#stat-revenue` "180 DT",
  analytics `#pred-monthly` "180 DT", delta +180 DT vs Oct (0).

Sessions — the pilot's exact query and `loadSchedule`'s query return
the **identical 7 rows**: confirmed 3 (17 Nov TEST Dummy Coach Session,
19 Nov TEST Dummy Class, 23 Nov Coach Session), upcoming 7, this week
(Sun 15–Sat 21 Nov) 5. At test time confirmed was 2 — the 23 Nov
confirmed session was created after the pass. The two views disagreed
on rendering, not on data.

### Variance cause 1 — revenue 64/56: overlapping `animateCounters()` runs (proven)

Not a data race and not a second formula. In the current branch all
three revenue displays already route through the single
`loadLedgerRevenue` (grep: `#stat-revenue` and `#pred-monthly` are
written nowhere else; the deployed main `cff7df9a` had the same single
function, gross version). The variance is the count-up animation:

- `loadLedgerRevenue` writes "160 DT" into `#stat-revenue`
  (`.stat-value`). `animateCounters()` parses it with `parseInt` → 160
  and counts 0→160 in steps of 8 (160/20), one tick per 40 ms.
- Every dashboard load calls `animateCounters()` at least twice while
  the first run is still mid-flight: `loadAnalytics()` ends with it,
  then `runGymHooks('afterLoadAnalytics')` → v17 `refreshRevenue()` →
  `loadLedgerRevenue()` (resets the text), then `initPage()` calls it
  again — plus the v17 `init` (window `load` + 120 ms) calls
  `refreshRevenue()` once more. The old code started a fresh interval
  per call with no guard, and each call parsed the **live mid-flight
  text** as its target.
- A second call landing mid-flight parses e.g. "56" or "64", starts an
  interval targeting that, and finishes **last** — freezing the card on
  the partial number. 56 and 64 are exact steps of the 160 count-up
  (7×8, 8×8); a data-driven value would not land on multiples of 8.
- Side effect of the same code: the interval wrote the bare number, so
  even a completed animation left "160" — the " DT" suffix was stripped.

Proven with a harness (`/tmp/u6-harness.js`, fake DOM, the real
function extracted from the file, second call 200 ms into the first):
**old code sampled "32" mid-flight and stuck at "32"; fixed code
settles on "160 DT".**

### Variance cause 2 — "—": a failed payments query read as zero revenue

`loadLedgerRevenue` ignored `result.error`: `Trainw.api.run` returns
the `[]` fallback on failure, `cur` computed as 0, and the card was
written "—" — indistinguishable from genuinely zero revenue. (`api.run`
does toast the error, but a toast is easy to miss on a reload.) Given
the known VM↔Supabase flakiness, a failed load on one reload is the
straightforward explanation for the "—" sighting.

### Cause 3 — Planning: stale pilot render, never refreshed after session mutations

The "Vue Réservations" card (`#schedule-booking-overview`) and the
dashboard "Bookings Overview" KPI (`#gym-bookings-overview`) are both
rendered by `tw-gym-pilot.js` `refresh()` from the **same** sessions
array — they cannot disagree within one refresh. They disagreed across
refreshes:

- The pilot only refreshes on script load, window `focus`, and nav
  clicks (+150 ms). `submitNewSession` / `saveEditSession` /
  `deleteSession` call `loadSchedule()` + `loadDashboardStats()` but
  never the pilot's `refresh()`. So after the tester created the two
  sessions on the Planning page, the session cards below updated while
  the "Vue Réservations" card above them kept its pre-creation empty
  state — and the dashboard KPI picked the sessions up on the next
  nav-click/focus refresh.
- Separately, a failed pilot refresh rendered the `[]` fallback as
  "Aucune reservation a afficher." with no distinction between "no
  sessions" and "query failed".

### Fix (UI only, no DB change, no RLS change)

`tw-gym-acc.js`:

- `animateCounters()`: the target is now the value the loaders wrote
  (`el.dataset.countTarget`), never the live mid-flight text; one
  interval per element (a still-running one is cleared first); the
  formatted final text (`dataset.countText`, e.g. "180 DT") is restored
  at completion. A second overlapping call now re-animates to the same
  true target instead of freezing on a partial sample.
- `loadLedgerRevenue()`: early return on `result.error` without touching
  the DOM (a failed load never clobbers a good value with "—", and an
  out-of-order failed run cannot overwrite a later successful one);
  records `countTarget`/`countText` on `#stat-revenue`.
- The `set()` helpers in `loadDashboardStats()` and `loadAnalytics()`,
  the expiring-stat write, `incrementCheckInStat()`, and
  `loadCheckIns()` all record `countTarget`/`countText` alongside the
  value they write, so every `.stat-value` animates to its loader's
  value. (`#pred-monthly` is a `.prediction-val`, not animated.)
- New `refreshPilotBookings()` helper (guarded `typeof` check +
  try/catch — a missing/failing pilot must never break the mutation
  flow), called after `loadSchedule()`/`loadDashboardStats()` in
  `submitNewSession`, `saveEditSession`, and `deleteSession`.

`tw-gym-pilot.js`:

- `refresh()` no longer renders on a failed query: the overviews render
  only when `!sessionsRes.error`, coach approvals only when
  `!coachesRes.error`. A failed load leaves the previous content (or
  "Chargement…" on first load); `api.run` already toasts the error.
- Exposes `window.TrainwPilotRefresh = refresh` for the hookup above.

No view computes revenue its own way any more than it already did —
all three displays were already routed through `loadLedgerRevenue`;
the fix is the animation race + the silent-failure rendering + the
stale pilot card.

Latent edge, noted not fixed (no live row hits it):
`loadLedgerRevenue` filters by `created_at >= prevStart` but buckets by
`paid_at || created_at` — a payment created in one month and paid in
another would be mis-bucketed or excluded. All live rows have
`paid_at` in the same month as `created_at`.

### Verification

- `node --check` clean on both touched files (`tw-gym-acc.js`,
  `tw-gym-pilot.js`); `node env-config.js` + `npm run verify`: "all
  checks passed".
- Harness `/tmp/u6-harness.js` (throwaway): **PASS** — old code sticks
  at "32", fixed code settles on "160 DT" under the same interleaving.
- Live API (owner@test.com JWT, PostgREST — the exact queries the UI
  makes): payments reconciled above (net 180 / gross 210 now; net 130 /
  gross 160 at test time); pilot sessions query and `loadSchedule`
  sessions query return the identical 7 rows (confirmed 3, upcoming 7).
- No data deleted, no payment voided (the 150 DT row untouched — cleanup
  still needs the user's word); no RLS change; no migration; no secrets
  in files. Repro scripts are throwaway in `/tmp` (`u6-recon.py`,
  `u6-recon2.py`, `u6-harness.js`, `u6-keys.json`, `u6-token.json`).
  `git diff --stat`: 2 files, +64/−13.

### Still needs the parent

- **Browser check after deploy**: reload the dashboard several times —
  REVENU MENSUEL must settle on "180 DT" (with the " DT" suffix) every
  time, Analytiques "Revenus ce Mois" 180 DT, delta +180 DT; the three
  views must agree with no reload-to-reload drift. Create a session on
  Planning and confirm the "Vue Réservations" card shows it immediately
  (no nav click / reload); edit and delete a session and confirm the
  card follows. The API-level round trips are verified; the click paths
  were not (no live-browser access in this round).
- The `created_at` vs `paid_at` month-bucketing edge above is a
  candidate for a small follow-up once the parent confirms the fix
  lands.

## UI/UX — U7: program created for a client never becomes the active plan + "Enregistrer comme modèle" creates no template (2026-11-15)

Test-pass items: Coach — functional bugs, #1 and #2. A program created
("TEST Dummy Program", General, 3/week, Test Client, Jour 1: TEST Dummy
Squat 3×10, 60s rest) toasted "SUCCÈS — Programme enregistré." and listed
under PLANS, yet the client profile drawer (coach and owner views), the Mes
Clients card and the client's own Booking center all said "Aucun programme
actif" / "Aucun programme." / "Votre coach n'a pas encore créé de
programme."; "Enregistrer comme modèle" toasted "Programme enregistré."
yet MODÈLES still showed "Aucun modele".

### Model found (traced, not guessed)

`workout_plans` (`20260408181000_trainw_002`, no `is_active`/status column
at all) has `client_id` (nullable) and `is_template` (default false).
"Active plan" is a convention, not a flag — the latest non-template plan
with `client_id = <client>`, `ORDER BY updated_at DESC LIMIT 1`. All four
read sites use exactly that query (none of them filtered `is_template`
before this round):

- client Booking center — `tw-client-acc.js` loadData: `.eq('client_id',
  currentUserId)` (no gym filter, no template filter);
- coach drawer — `tw-coach-acc.js` openClientPanel: same + gym scoping;
- coach Mes Clients card — `latestPlanForClient()`: `plans.find(p =>
  p.client_id === clientId)` over the coach's own `is_template=false` list;
- owner drawer — `tw-gym-acc-v17.js` fetchClientData (+ coach-followup
  query in renderCoachPanel): same + gym filter.

Live row for the test-pass program (`7ca81e2b-c328-491c-8197-1ac46eef0521`,
TEST Gym `8a07bf89-…`, via Management API SQL + the app's exact PostgREST
queries as coach/client JWTs):

| field | value |
|---|---|
| `title` / `goal` / `frequency_per_week` | TEST Dummy Program / general / 3 |
| `created_by` | coach `b38df3c8-…` |
| `client_id` | **null** |
| `is_template` | **true** |
| `created_at` / `updated_at` | 2026-11-15 15:37:45 / 15:38:02 UTC |

One exercise row exists (`8813dbf6-…`, Jour 1, TEST Dummy Squat 3×10,
60s). Only one plan row exists in the gym.

### Root cause

`savePlan(asTemplate)` in `tw-coach-acc.js` used the modal's hidden id for
BOTH buttons. "Enregistrer comme modèle" on an existing plan therefore
**UPDATE-d the plan row in place** to `is_template=true, client_id=null`
— it converted the client's plan into a template instead of creating one.
Timeline proves it: the row was created as a plan at 15:37:45 UTC and
converted 17 seconds later at 15:38:02 UTC, the tester's template save.
After that no row had `client_id = Test Client`, so every "active plan"
query legitimately returned empty — bug #1 is the direct consequence of
bug #2's write path, not a read bug. The create path itself was sound:
`assignedClients` entries carry `users.id`, so the plan-client select
writes a real user id, and the insert RLS (`workout_plans_insert`) allows
a coach to insert with `client_id` null or a client they manage.

Why MODÈLES showed "Aucun modele" in the browser despite the row
existing: the exact templates query the coach portal runs
(`created_by=coach, is_template=true, gym_id=TEST`) returns the row (200,
verified live) — so at the API level the template WAS listable. The
browser empty state was most plausibly stale rendering: `savePlan` shows
the success toast and closes the modal *before* `await bootstrap()`
re-renders, so a quick look at MODÈLES still shows the pre-save state
(the same stale-refresh class as the cross-cutting finding). Not
reproducible at the API level; the fix below removes the data-level
cause and the list refreshes via the existing `bootstrap()` call.

Two adjacent mislabels in the same flow: the plan/template card button
was labelled "Enregistrer" (`t('saveChanges')`) but only re-opens the
editor; the drawer Programme tab button was also "Enregistrer" but opens
a NEW plan modal — and worse, its handler set the client select value
*before* calling `openPlanModal()`, which rebuilds the select options via
`fillPlanClientSelect()`, silently wiping the preselection (a plan made
from the drawer opened with client "—").

### Fix (no migration — the model already supports it; no RLS change)

Creation with a client IS activation under the existing convention
(latest plan for the client wins), so no `is_active` flag was added.
`tw-coach-acc.js`:

- `savePlan(true)` now always INSERTs a new row (`writeId =
  (asTemplate && id) ? '' : id`): saving an existing plan as a template
  creates a **copy** (new id, `is_template=true`, `client_id=null`, the
  modal's exercise rows copied to the new plan id by the existing
  exercise-save code); the original plan keeps its client and stays the
  active plan. Plain plan saves still UPDATE the edited row; brand-new
  template saves still INSERT as before.
- Plan/template card button now reads "Modifier" / "Edit" / "تعديل" (new
  `editPlan` i18n key, fr/en/ar) — it opens the editor.
- Drawer Programme-tab button now reads "Nouveau programme"
  (`t('newProgram')`) and passes the client through
  `openPlanModal('', false, clientId)`; `openPlanModal` gained an
  optional `presetClientId` applied *after* `fillPlanClientSelect()`, and
  titles a new template "Nouveau modèle" instead of "Nouveau programme".
- Coach drawer active-plan query now has explicit
  `.eq('is_template', false)`.

`tw-client-acc.js`, `tw-gym-acc-v17.js`: the three other active-plan
reads (client Booking center, owner drawer `fetchClientData`, coach
followup card) gained the same explicit `.eq('is_template', false)` —
one token each, stating the "latest non-template plan for the client"
invariant instead of relying on templates always having `client_id`
null.

Known behaviour kept: "active" = latest updated plan for the client, so
editing an older plan re-activates it (its `updated_at` becomes newest).
No assign/activate button was added — creation for a client is the
activation, and the template copy no longer destroys it.

### Verification

- `node --check` clean on all three touched files; `node env-config.js`
  + `npm run verify`: "all checks passed". No migration, so no
  migration-chain test applies.
- Live API (PostgREST, exact app queries, coach/client/owner TEST JWTs;
  `~/workspace/.u7-scratch/verify-u7.py`, idempotent, 12/12 PASS):
  created plan `4989d6d9-507a-415b-a067-1025f634d7e8` ("TEST U7 Program",
  client Test Client, is_template=false, 1 exercise) via the exact
  `savePlan(false)` call sequence, then a template copy
  `1d90971d-18a3-48e5-82de-9960385e1517` via the exact fixed
  `savePlan(true)` call sequence (new row, client null, exercise copied).
  After both: client Booking center, coach drawer, owner drawer and the
  coach PLANS list all return the plan as Test Client's active plan; the
  coach MODÈLES list returns the template copy (2 rows there now — the
  copy plus the original TEST Dummy Program template row); the plan row
  still has `client_id = Test Client`. The original TEST Dummy Program
  row was left untouched (still a template, client null — its plan side
  is gone; it is test data, cleanup needs the user's word).
- Test data left in TEST Gym (documented, nothing deleted): plan
  `4989d6d9-…` "TEST U7 Program" (Test Client) + exercise "TEST U7
  Squat"; template copy `1d90971d-…` "TEST U7 Program" + copied exercise.

### Still needs the parent

- **Browser check after deploy**: as coach, create a program for Test
  Client and confirm the client drawer, Mes Clients card and the
  client's Booking center show it as the active plan immediately (no
  reload); open the plan and "Enregistrer comme modèle" and confirm the
  plan stays under PLANS *and* a copy appears under MODÈLES; check the
  plan-card button now reads "Modifier" and the drawer button reads
  "Nouveau programme" with the client preselected. The API-level round
  trips are verified; the click paths were not (no live-browser access
  in this round).
- The pre-existing TEST Dummy Program row (`7ca81e2b-…`) is a template
  with no plan behind it — if the team wants Test Client to have that
  program active again, a coach must recreate it (or the row can be
  flipped back to a plan with `client_id` set — a data decision, not
  taken here).

## UI/UX — U8: owner's message to the client is invisible to the client (2026-11-15)

Test-pass item: Client — functional bugs, #2. The client Messages page
listed only the Test Coach conversation; the owner's "TEST Dummy message
from owner - UI test" (16:35) never appeared, despite the page heading
"Discutez avec votre coach et votre gérant". The coach's message WAS
visible in the client's thread, and the client's reply to the coach worked.

### Root cause (traced, then proven live — not RLS on the message)

- The owner → client message row exists and the client's exact messages
  query returns it: `messages` SELECT policy is sender-or-receiver =
  caller, and a live run as client@test.com returned all 3 TEST Gym
  messages (owner 16:35, coach 16:39, client→coach 16:43).
- The thread list is NOT built from the messages. `tw-client-acc.js`
  builds `participants = [primaryCoachId, ownerInfo?.user_id]` and one
  thread per participant, filtering the loaded messages by participant id.
- `ownerInfo` comes from `list_gym_member_directory()` filtered for
  `portal === 'admin'` and `role_code` in `gym_owner`/`gym_admin`.
  DB-21 (phase1b/phase1c) gates that RPC to staff — the caller must manage
  the gym or hold `view_clients` — so a plain client gets ZERO rows,
  `ownerInfo` is null, and the owner thread is never built. The message
  was loaded and then dropped by the thread builder, not by RLS.
- The reply path needed no change: `can_message_user()` already lets a
  client message any active/accepted admin- or coach-portal member of the
  same gym, and the owner's `loadConversation()` queries both directions,
  so the owner sees the reply once the client can send it.

### Fix (minimal, no RLS weakening)

- New migration `20261116190000_u8_client_owner_contact.sql`: SECURITY
  DEFINER RPC `get_gym_owner_contact(p_gym_id)` returning ONLY the gym's
  owner/manager contact — `user_id`, display `name`, `role_code`,
  `portal` — to a caller holding an active, non-revoked membership in
  that gym. No email, no phone, no permissions, no other members.
  Grants follow the round-9 / P2-6 pattern: REVOKE ALL FROM anon, PUBLIC;
  GRANT EXECUTE TO authenticated. The in-function membership gate also
  rejects anon (auth.uid() NULL matches no membership row).
  `list_gym_member_directory` is untouched — the directory stays
  staff-only (DB-21).
- `tw-client-acc.js`: the owner lookup swaps one RPC name
  (`list_gym_member_directory` → `get_gym_owner_contact`). The
  `ownerInfo` `.find()` filter and the thread builder are unchanged, so
  the coach thread is unaffected. The owner thread now exists even before
  any message is exchanged (same as the coach thread).
- Out of scope, noted: the coach portal builds threads from assigned
  clients only (`tw-coach-acc.js`) — the coach has no owner/manager
  thread either. The test pass did not flag it and the coach heading does
  not promise it; left as-is.

### Verification

- Local chain (p26 harness, Postgres 16.2): full chain applies
  **71 OK, 2 FAIL** — the same 2 known by-design pre-existing failures
  as the pre-U8 baseline (phase1b directories, phase1e freeze-hash
  defaults); the U8 migration applies clean. U8 suite
  (`~/workspace/.u8-scratch/u8-tests.sql`): **10/10** — client sees
  exactly the owner row; no rows for another gym, for an outsider, for a
  revoked member, or for a caller with no auth uid; anon EXECUTE denied
  (permission denied); coach member sees the owner row too; output
  columns are exactly `p_gym_id, user_id, name, role_code, portal`; the
  old directory RPC still returns [] for the client (root-cause pin).
- Live (project Trainw, TEST Gym 8a07bf89; migration applied live via the
  Management API so the API-level checks could run — code NOT deployed,
  parent deploys): as client@test.com, `get_gym_owner_contact` returns
  `[{user_id: 50dcaddd-…, name: "Test Owner", role_code: "gym_owner",
  portal: "admin"}]`; replaying the client's exact UI queries through
  the UI thread-building logic gives TWO threads — coach (2 messages)
  and owner (1 message: "TEST Dummy message from owner - UI test").
  Negative controls live: other-gym call returns `[]`; anon call returns
  401 `permission denied for function get_gym_owner_contact`.
- Reply round-trip live: the client inserted "TEST Dummy reply from
  client to owner - U8 test" (row `98671c6d-99a4-4e71-8799-e7d55ece03b0`,
  HTTP 201, via the exact UI insert); the owner's exact
  `loadConversation` query then returns both messages — the original
  16:35 owner message and the client reply. Coach messages query
  unchanged (2 rows).
- `node --check` on `tw-client-acc.js`, `node env-config.js` +
  `npm run verify`: all pass.
- Test data left in place (no deletion): the U8 reply message above, in
  TEST Gym. Nothing else was written live.
- Still needs the parent: push / merge / Vercel deploy of the JS change,
  then a real-browser check that the owner thread renders in the client
  Messages page (API-level verification only here — no live-browser
  access in this round).

## UI/UX — U9: refresh / collapse / drawer / dead-button batch + stale toast after unfreeze (2026-11-15)

Test-pass items: Owner — functional bugs 6–11, Coach — functional bugs
3–6, Client — functional bugs 4, plus item 12 (stale "Abonnement gelé"
toast after "Annuler le gel", from the batch-2 browser re-check on
production main 3e58e41f). All 12 fixed; none needs a product decision,
none deferred. The refresh items follow the U6 pattern: re-render /
re-fetch after the mutation instead of trusting a stale render.

### 1. Client card collapses after filters/search (loses "Voir le profil", "Message", "Assigner un coach")

- Cause: the owner portal has two competing `#clients-grid` renderers —
  v2 `renderClients()` (`tw-gym-acc.js`) and v11 `renderClientsV11()`
  (`tw-gym-acc-v17.js`, rich cards with the profile/message/assign
  sections). The filter buttons and search input call v2
  `renderClients()`, which overwrote v17's v11 cards; v17 only re-rendered
  v11 on page load and after `loadClients()`.
- Fix: v17 now exports `renderClientsV11` on `window` and sets
  `window.TrainwV17ClientsReady = true` after its first `loadAssigns()`
  (init + the `afterLoadClients` hook); v2 `renderClients()` delegates
  to it when ready and falls through to v2 otherwise. Also aligned v17
  `filtClients` payment default to `'paid'` (was `''`, which dropped
  clients from "Payé"), added the `cc-btn-del` class to the v11 delete
  button, and call `syncPermissionVisibility()` at the end of
  `renderClientsV11()` for permission parity.
- Verification: code inspection + `node --check`. Needs the parent's
  real-browser check (click each filter, type in search, confirm the
  rich card survives).

### 2. Coach approval badge doesn't refresh until reload

- Cause: pilot `refresh()` (`tw-gym-pilot.js`) has no generation guard.
  A stale in-flight refresh (focus/nav-triggered, slow `getContext`)
  could finish after the post-toggle refresh and repaint pre-toggle data.
- Fix: `refreshSeq` counter — a superseded refresh returns before
  rendering. Plus `updateApprovalCardInPlace(profileId, status)` paints
  the pill text/class and swaps the button label /
  `data-approval-status` / classes immediately after the confirmed
  update; the refresh still runs afterwards as source of truth.
- Verification: node harness `~/workspace/.u9-scratch/u9-pilot-harness.js`
  (stubbed DOM + Supabase client, real pilot file in `vm`): PASS
  generation guard (stale refresh finishing last leaves the "Approuve"
  pill) and PASS in-place toggle (pill "en attente", button "Approuver",
  one update call `approval_status:"pending"`, toast "Mise a jour
  enregistree."). Negative control — the same harness against the HEAD
  pilot — FAILS both checks, so the harness discriminates. Live
  (owner@test.com, TEST Gym): approval toggle forth-and-back persisted —
  approved → pending (re-query confirms "pending") → approved with
  `approved_at` set (re-query confirms), net state unchanged. The
  in-place update assumes the update affected the row (PostgREST update
  without `.select()` returns no row count); the confirmation refresh
  corrects any miss.

### 3. Message threads don't refresh after sending (coach + client)

- Cause: coach `sendCoachMessage` and client `sendClientMessage` only
  queued a reload (`queueCoachReload(120)` / `queueClientReload(120)`),
  which rebuilds the thread *list*; the open conversation body is
  rendered only by `openThread()`.
- Fix (both files): after the insert, `.select('id, content, sender_id,
  receiver_id, created_at, is_read').maybeSingle()`, push the returned
  row onto the thread (fallback local stub with `crypto.randomUUID()`),
  then call `openThread(activeThreadId)`; the queued reload stays as
  confirmation. Mirrors the owner portal's `sendMessage`, which already
  did this correctly.
- Verification: code inspection + `node --check`. Needs the parent's
  real-browser check (send, message appears in the open thread at once).

### 4. Weight add from the client drawer fails silently (coach)

- Cause (proven by inspection): the drawer button handler
  (`tw-coach-acc.js:552`) calls `saveInlineWeight(clientPanel.id)`, but
  that function reads `[data-weight-input="..."]` — an input that exists
  only in the Suivi poids table — so the value was always 0 and the
  function toasted `t('weightKg')` ("INFO / Poids") and returned.
- Fix: `saveInlineWeight(clientId, valueOverride)` — the drawer call
  site passes the drawer input value; the Suivi call site passes nothing
  and keeps reading the table input. After success + `runCoachReload()`,
  if the drawer is still open for that client, it re-fetches the panel
  data via `openClientPanel(clientId)`, restores `clientPanel.tab`, and
  re-renders. The insert payload is byte-identical to the Suivi insert
  the tester already proved working.
- Verification: code inspection (selector mismatch + exact toast path)
  and call-site check (drawer passes the value, Suivi passes nothing);
  live read as coach@test.com confirms the test client has an 80.00 kg
  `weight_logs` row (2026-11-15T15:38:39Z), i.e. the insert path works.
  No new live row was inserted for this check (would be test-data
  pollution for a payload already proven). Needs the parent's
  real-browser check of the drawer click path.

### 5. Drawer weight chart scale wrong (0–1.0 kg) in both drawers

- Cause: empty-data default, not a scale formula — all four weight
  charts use the same Chart.js config with no explicit y-scale, and the
  Suivi page scales correctly because it has points. The coach drawer
  never fetched weights at all (it used the bootstrap snapshot in
  `openClientPanel`).
- Fix: `openClientPanel` now fetches `weight_logs` (weight_kg, logged_at,
  desc, limit 40, gym-scoped) and overrides `c.weights` when the fetch
  succeeds. Both drawer charts render the empty copy instead of a chart
  when there are no points (coach drawer weight tab conditionally renders
  the chart shell vs `<p class="empty-state">Aucune mesure
  enregistrée.</p>`; v17 `drawWeight` returns early and puts
  `t('noWeight')` into `.weight-chart-shell`).
- Verification: code inspection + live read (the 80 kg row above exists,
  so the drawer fetch has data to show). Needs the parent's real-browser
  check of both drawers.

### 6. "Ouvrir" on a session opens the client profile — misleading label

- Cause: label/action mismatch; both buttons open the client panel.
- Fix: relabel the coach `openClient` key — fr "Ouvrir" → "Voir le
  client", en "Open" → "View client", ar "فتح" → "عرض العميل" (applies to
  the session-card and Mes Clients grid buttons).
- Verification: code inspection + `node --check`.

### 7. "Complet" badge wrong at 0/20 (1/1 individual session legitimately full)

- Cause: `getStatusLabel` mapped `confirmed` → "Complet"/"Full"
  (`tw-gym-acc.js:2278`), regardless of attendance.
- Fix: `confirmed` now maps to Confirmé/Confirmed/مؤكد; new helpers
  `sessionIsFull(attended, capacity)` and `sessionFullLabel()`; the pill
  shows "Complet" only when `attended >= capacity > 0`, in both
  `renderSchedule` and `openSessionDetail` (a 1/1 individual session
  still correctly shows Complet).
- Verification: code inspection + `node --check`.

### 8. "Chercher un coach existant" finds nothing for "Test"

- Cause (confirmed by reading `searchExistingCoaches`): the search
  excludes all current gym members (`excludedUserIds` from
  `gym_memberships`), so Test Coach is dropped silently. Live check
  confirms the premise: Test Coach (b38df3c8-…) IS a `gym_memberships`
  member of TEST Gym and has a `coach_profiles` row
  (`approval_status: "approved"`).
- Fix (UI wording, per the brief — not a silent empty result): track
  `coachSearchExcludedCount` (matched-but-excluded user IDs; rows with no
  email are non-matches per the PostgREST embedded-relation quirk, not
  exclusions). The empty state now reads "Tous les coachs correspondants
  font déjà partie de votre salle." when the count is > 0, and the results
  count appends "N déjà dans votre salle." when applicable. Count resets
  on empty/short-term/error paths.
- Verification: premise confirmed live (see above); code inspection +
  `node --check`. The >20-coach recall gap (needs a `search_coaches` RPC,
  noted in P2-5) is untouched — out of scope for this round.

### 9. "?" Messages Auto button does nothing

- Cause: `#btn-show-auto-panel` had no listener. The panel
  (`#msg-auto-panel` with days/template and `#btn-trigger-auto-msg` →
  existing `triggerInactivityMessages`) exists in HTML and CSS
  (`.msg-auto-toggle.active` style exists).
- Fix: bind the click to toggle the panel `hidden` + the button `active`
  class. No new feature invented.
- Verification: code inspection + `node --check`. Needs the parent's
  real-browser check (click toggles the panel; the trigger button inside
  was already wired).

### 10. Branding colour cards dead (raw "var(--ac)" / "var(--s1)" / "var(--mt)")

- Cause: static HTML showing raw variable names; no colour storage
  existed (only `gyms.logo_url`) and no picker.
- Fix: new migration `20261116200000_u9_branding_colours.sql` adds
  nullable `accent_color`, `surface_color`, `muted_color` text columns to
  `gyms` with a hex CHECK (`^#[0-9a-fA-F]{6}$`, NULL = default). Shared
  helper `Trainw.applyGymBranding(colours)` + `GYM_BRANDING_DEFAULTS`
  in `trainw-core.js` (strict hex validation, sets `--ac/--s1/--mt` on
  `:root`, returns resolved values; exported on `window.TrainwCore`).
  Owner portal: the gym profile load fetches the 3 columns, applies
  them, and syncs the cards; cards now have `data-branding-colour`,
  hidden `<input type="color">`, and token spans showing the real hex +
  "· défaut" when unset; click/Enter/Space opens the picker, `change`
  persists via a `gyms` update (same `gyms_update` RLS =
  `manages_gym(id)`, no new policy) with revert-on-error + `savedOk`
  toast; no live `input` preview (picker cancel fires no event, a preview
  would stick). The colours section (`#settings-branding-colours`) is
  hidden in `syncPermissionVisibility()` without `manage_branding`.
  Coach + client portals apply gym branding at bootstrap (separate
  tolerant `gyms` select, `silent:true`). CSS: card `cursor:pointer`,
  `position:relative`, focus-visible outline, hidden input styling.
- Deploy-order hardening (found during verification): the colour columns
  were first folded into the owner portal's main gym-profile select, so
  a code deploy landing before the migration would have failed the whole
  profile load (name/prices/tier all blank). The colours now load via a
  separate tolerant select (`fallback:null, toastOnError:false,
  silent:true`); on error the theme stays at defaults and the profile
  load is unaffected. The save path still needs the migration (picker
  save errors and reverts until it is applied) — expected.
- Verification: full migration chain on a fresh local cluster (see
  Verification below) — migration applies clean; U9 tests pass (valid hex
  + NULL accepted; `var(--ac)`, `red`, `#12345`, `#12345678` rejected;
  row intact). Live: `gyms.accent_color` does NOT exist yet — the
  migration is NOT applied live; the parent applies it with the deploy.
  Needs the parent's real-browser check (picker opens, save persists,
  theme changes across portals).

### 11. "Aucune séance passée" clickable but dead (client)

- Cause: code inspection found no click handler and no `cursor:pointer`
  on `.empty-state` (the `#client-past-sessions-list` handler only
  handles review stars/submit; the `document.body` handler only handles
  `[data-open-page]`). No real action exists to wire it to.
- Fix (per the brief — make it non-clickable): the empty state is now
  rendered with class `empty-state-static` + CSS rule
  `#client-past-sessions-list.empty-state-static{cursor:default;
  pointer-events:none}` in `tw-client-acc.css`.
- Verification: code inspection + `node --check`.

### 12. Stale toast after unfreeze ("Abonnement gelé" surfacing after "Annuler le gel")

- Cause: `requestFreeze` / `cancelFreeze` toasted only AFTER
  `await loadFreezes(); await loadClients();` — slow reload cascades, so
  the freeze toast could fire after the unfreeze click (and the single
  legacy `#toast` element shows whichever fires last).
- Fix: toast immediately after the confirmed RPC success in both
  functions (`toast('Abonnement gelé')` / `toast('Gel annulé')`), before
  the reloads; reload failures still toast their own error via `api.run`.
  Same late-toast pattern observed in `voidPayment` (toast after 3
  loads) — deliberately NOT fixed here (out of the briefed
  freeze/unfreeze scope); flag for a later round.
- Verification: code inspection + `node --check`. Needs the parent's
  real-browser check of the freeze → unfreeze toast sequence (timing
  behaviour, not API-verifiable).

### Verification (round-level)

- `node --check` passes on all 6 touched JS files
  (`trainw-core.js`, `tw-gym-acc.js`, `tw-gym-acc-v17.js`,
  `tw-gym-pilot.js`, `tw-coach-acc.js`, `tw-client-acc.js`).
  (`node --check` "fails" on .html/.css are expected — wrong file type.)
- `node env-config.js` + `npm run verify`: all checks passed.
- Item 2 harness: see item 2 above (both PASS on fixed code, both FAIL
  on HEAD code). Harness at `~/workspace/.u9-scratch/u9-pilot-harness.js`.
- Migration chain on a fresh local Postgres 16.2 cluster (pgserver
  binaries; pgcrypto/btree_gist/citext .so + control files copied from
  the 16.4 source build at `~/workspace/.p22-scratch/build/` — pgserver's
  build ships without them; data dir on /tmp because `nobody` cannot
  traverse /home): **72 OK, 2 FAIL** — the same 2 known by-design
  pre-existing failures as the U8 baseline (phase1b directories,
  phase1e freeze-hash defaults). The U9 migration applies clean.
  U9 suite (`~/workspace/.u9-scratch/u9-tests.sql`): 3 columns exist,
  nullable text; CHECK `gyms_branding_colours_hex` exists; valid hex
  insert ok; NULL ok; `var(--ac)` / `red` / `#12345` / `#12345678` all
  rejected; row intact after the rejected writes.
- Live (project Trainw, TEST Gym 8a07bf89-ff6e-40f9-8feb-c384d6b47e5c;
  no data deleted; one forth-and-back toggle only, net state unchanged):
  sign-in as owner/coach/client OK; Test Coach is a gym member with an
  approved `coach_profiles` row (item 8 premise); test client has an
  80.00 kg `weight_logs` row (items 4/5 premise); approval toggle
  persisted both ways (item 2); `gyms.accent_color` does not exist live
  — migration NOT applied live (parent deploys).
- Double-encoded UTF-8 preserved: mojibake `Ã` counts unchanged after
  the edits (coach 44/44, client 93/93).
- Files changed (9 + 1 new migration, 265 insertions, 30 deletions):
  `trainw-core.js`, `tw-gym-acc.js`, `tw-gym-acc-v17.js`,
  `tw-gym-pilot.js`, `tw-coach-acc.js`, `tw-client-acc.js`,
  `tw-gym-acc.html`, `tw-gym-acc.css`, `tw-client-acc.css`, and new
  `supabase/migrations/20261116200000_u9_branding_colours.sql`.
- Still needs the parent: push / merge / Vercel deploy (code + the U9
  migration together — the branding save needs the migration; the
  profile load no longer does), then real-browser checks for items 1, 2,
  3, 4, 5, 9, 10 and the item-12 toast sequence. No live-browser access
  in this round, so all rendering/timing behaviour above is
  code-inspection + harness verified only.

## UI/UX — U10: cross-cutting issues (2026-11-15)

Source: `../files/trainw-ui-ux-test-pass-2026-11-15.md`, "Cross-cutting UI/UX
issues", items 1–9. Branch `phase1-security-fixes`. Files changed (12):
`trainw-core.js`, `tw-gym-acc.js`, `tw-gym-acc-v17.js`, `tw-gym-pilot.js`,
`tw-coach-acc.js`, `tw-client-acc.js`, `tw-gym-acc.html`, `tw-coach-acc.html`,
`tw-gym-acc.css`, `tw-coach-acc-v17.css`, `tw-gym-acc-v17.css`,
`trainw-enhancements.css` (307 insertions, 110 deletions).

### Item 1 — Stale/delayed refresh, remaining paths (fixed)
- Cause: the save handlers already called `runCoachReload()` /
  `runClientReload()` → full `bootstrap()` / `loadData()`, but the inflight
  guard dropped the post-mutation reload: `runCoachReload` /
  `runClientReload` did `if (inflight) return;` and the queue functions
  also returned early when inflight, so a reload that started just before
  the insert (e.g. triggered by the insert's own realtime event) rendered
  pre-insert data and no further reload was ever queued.
- Fix: (a) pending-flag loop in both reloaders — if inflight, set
  `coachReloadPending` / `clientReloadPending = true` and re-run after the
  current reload finishes; queue functions set pending instead of dropping.
  (b) Optimistic local updates + immediate targeted re-render before the
  reload, then the reload confirms: coach `saveAvailability` (insert with
  `.select('*')`, push row, `renderAvailabilityList()` +
  `renderProfileSummary()`), coach `saveInlineWeight` (unshift into the
  client's weights, `renderWeightRows()` + `drawClientWeight()`), coach
  `saveCoachProfile` (update `coachProfile`/`currentProfile` locals,
  `renderAll()` — fixes the "Coaching general" summary until re-render),
  client `saveWeight` (unshift into `weightLogs`, `renderWeight()` +
  `renderDashboardProgress()`), client `savePersonalRecord` (unshift,
  `renderPersonalRecordsTable()`), client `saveGoal` (`currentGoal =
  {...payload}`, `renderGoals()` + `renderDashboardProgress()`), client
  `saveFreeWorkoutLog` (`persistWorkoutLog` now returns the inserted log id
  instead of `true` — both callers only tested truthiness — then unshift
  the log + set `logSetsMap`, `renderProgram()` +
  `renderDashboardActivity()`). `savePlan` already awaits a full
  `bootstrap()`; not named, left alone.

### Item 2 — Date/time pickers awkward (fixed)
- Cause: no `datetime-local` anywhere; all time inputs were native
  `type="time"` (Chrome's segmented hour/minute/AM-PM spinbuttons; typing
  across segments zeroes values). Display: `localeForLang('en')` returns
  `'en-GB'`, so `formatTime` rendered midnight as `00:00` in English mode,
  and most displays used raw `.slice(0,5)`.
- Fix: new core helpers `Trainw.parseTimeOfDay(raw)` (accepts `9`, `9:00`,
  `09:00`, `9h30`, `2:00 PM`, `14:30`, `1430`, strips trailing `:SS`;
  returns `HH:MM` or null) and `Trainw.formatTimeOfDay(value, lang)` (en →
  `h:MM AM/PM`, so `00:00` → `12:00 AM`; fr/ar → `HH:MM`), exported from
  `trainw-core.js`; `formatTime` uses `hour12: lang==='en'` and its string
  branch delegates to `formatTimeOfDay`. The six named inputs are now
  plain text fields (`type="text"`, `data-time-input`, `inputmode="numeric"`,
  `placeholder="09:00"`, `autocomplete="off"`, `maxlength="8"`): session
  create `#sess-time`, session edit `#edit-sess-time`, class `#class-time`,
  gym class `#gym-class-time`, coach availability start/end. A delegated
  `change` listener in core normalizes valid input and sets
  `aria-invalid="true"` on unparseable input (red border via new CSS rule
  in `tw-gym-acc.css` + `trainw-enhancements.css`). Save handlers validate:
  `saveEditSession`, `submitNewSession` (empty vs invalid distinguished),
  `saveGymClass`, `saveClass` (v17, new `invalidTime` key), coach
  `saveAvailability` (normalizes before the start<end check). All
  time-display `.slice(0,5)` sites now use `formatTimeOfDay(..., currentLang)`
  (owner dashboard/schedule/detail, v17 class lists, coach hero/pulse/
  client-grid/session cards/availability cards, client feed/hero/upcoming/
  booking-day/past lists); coach `fmtDT` and client `fmtDateTime` gained
  `hour12: currentLang==='en'`. Input-value assignments (e.g. edit-session
  open, v17 class open) deliberately stay `slice(0,5)` "HH:MM" — the entry
  field is 24h, display surfaces are localized. Staff-schedule drawer
  inputs stay native `type="time"` (generated by JS, out of named scope).

### Item 3 — Mojibake (fixed by safe bulk re-encode)
- Cause: double/triple-encoded UTF-8 in `tw-coach-acc.js` and
  `tw-client-acc.js` (same class as the round-11 fix).
- Fix: bulk re-encode with `/tmp/u10-mojibake-fix.py` (dry-run first, full
  replacement log reviewed, then `--apply`). It re-decodes Latin-1/CP1252
  byte runs only when the decode succeeds, has no control characters, and
  matches plausible characters; single non-ASCII chars (e.g. legit `Â` in
  `Âge`) are never touched; up to 3 passes. Coach: 93 replacements, bytes
  86189 → 85589, `Ã` 44 → 0, `Â` 4 → 0, `â` 3 → 0 (programme-modal close
  `Ã—` → `×`, `Ã‰crivez Ã vos clients assignÃ©s.` → `Écrivez à vos clients
  assignés.`, placeholder → `Écrivez un message...`, Arabic day/status
  words back to real Arabic). Client: 131 replacements, bytes 100069 →
  99644, `Ã` 93 → 0, `Â` 19 → 0, `â` 17 → 0 (triple-encoded em dash
  `Ã¢â‚¬â€` → `—`, `â€”` → `—` in OBJECTIF/CIBLE/TEMPS RESTANT and
  Progression history). Owner HTML: 3 replacements (`SÃ©ances` →
  `Séances`, `ModÃ¨les de Cours` → `Modèles de Cours`, `regroupÃ©es` →
  `regroupées`); the 2 remaining `Â` are legit `Âge` labels. Owner Messages
  empty-state icon `??` → `💬` (the `??` was a lost emoji/icon,
  unrecoverable from the file).
- Deferred (not fixed): `tw-gym-acc-v17.js` Arabic table is literal `?`
  characters in the file bytes (855 `?` total — the +1 vs the earlier 854
  is my own new `parsedTime?...:...` ternary in `saveClass`, not data) —
  data loss from an earlier bad encoding round-trip, a different corruption
  class from mojibake, outside the named item-3 scope. Needs proper Arabic
  re-translation (needs-user). The v17 `t()` falls back fr → en, so the
  new `invalidTime` key was still added to the v17 ar block with real
  Arabic text.

### Item 4 — Missing French accents (fixed)
- All nine named strings fixed, plus unambiguous siblings in the same
  tables (longest-first replacements to avoid partial overwrites):
  pilot COPY.fr (`Confirmée`, `Terminée`, `Annulée`, `Approuvé`,
  `Prochaines réservations`, `Confirmées`, `Terminées`, `Annulées`, `Mise
  à jour enregistrée.`, `Aucune réservation à afficher.`); v17 I.fr
  (`Créez votre premier template...`, `Durée`, `Créneau`, `Capacité`,
  `Mettre à jour`, `Même niveau...`, `Aucune donnée...`, `Aucune mesure
  enregistrée.`, `Aucune séance prévue...`, `Template chargé...`,
  `Clients assignés`, `Aucun client assigné.`, `Série active`, `Séances par
  semaine`, `Téléphone`); coach `copy()` fr (~35 strings incl.
  `Disponibilités`, `À venir`, `Spécialité`, `Coaching général`, `À
  définir`, `Le résumé se met à jour...`, `Journée libre`, `confirmée`,
  `réservation`, `réservée`, `assigné`, `dès qu'ils seront reliés`,
  `défini`, `Téléphone`, `Non renseigné`, `données`, `récente`, `Créez un
  programme...`, `modèle réutilisable...`, `créneaux`, `coordonnée`,
  `l'espace Programmes.`); client inline `uiCopy` fr (`Unité`, `Aucun
  record enregistré...`, `Démarrer un entraînement libre`, `Photo ajoutée.`,
  `Aucune photo enregistrée pour le moment.`); owner (`Cours créé.`,
  `Cours mis à jour.`, `Aucun coach trouvé`, `Créez votre premier modèle...`,
  `-- Aucun modèle --`, `+ Créer une séance`, `Gérez vos cours et
  planifiez des séances à partir des modèles.`).
- Caution hit during verification: two replacements introduced raw
  apostrophes inside single-quoted JS strings (`qu'ils`, `l'espace`),
  which broke `tw-coach-acc.js` syntax; fixed by escaping (`\'`) and
  re-verified (see Verification).

### Item 5 — Settings layout (fixed)
- Button row: `ensureMobileSettingsShortcuts()` (tw-gym-acc.js:5799) injected
  the `.mobile-settings-shortcuts` div (Coaches / Analytics / Check-In)
  unconditionally on ALL viewports, and its CSS was just
  `display:flex; gap:12px; flex-wrap:wrap` with unstyled
  `.settings-shortcut` buttons (default white browser buttons). Fix:
  `display:none` by default, `display:flex` only inside
  `@media(max-width:768px)` (the mobile bottom-bar breakpoint), proper
  secondary-button styling on `.settings-shortcut`, `margin-bottom:20px`.
  (Exact overlap geometry vs the GENERAL heading could not be reproduced
  by inspection; the unconditional injection + unstyled buttons is the
  defect — parent to confirm visually.)
- Staff-profile drawer clipping: schedule row CSS was
  `grid-template-columns:110px 120px 1fr 1fr` — fixed columns plus native
  `type="time"` inputs' large intrinsic min-width overflowed the ~436px
  inner width. Fix: `grid-template-columns:96px minmax(0,1fr)` (2×2:
  day+toggle first row, start+end second row) +
  `.staff-schedule-row input[type="time"]{min-width:0;width:100%}`.
- Coach Mon Profil numbers jammed (`DISPONIBILITES1`): coach
  `.summary-chip strong` only set `color` (the grouped
  `.summary-line strong, .summary-chip strong, .mini-metric-card strong`
  rule). Fix: later `.summary-chip strong` rule in
  `tw-coach-acc-v17.css` with `display:block; margin-top:8px;
  font-family:'Bebas Neue'; font-size:28px; line-height:1` (mirrors the
  client file; `.summary-line strong` stays inline).
- Coach client-drawer stat cards wrap mid-word (`CHECK-` / `IN`): the
  wrapping label is `Dernier check-in` (`t('lastCheckin')`). Fix:
  non-breaking hyphen U+2011 in fr `Dernier check‑in` and en
  `Last check‑in`, plus `white-space:nowrap` on `.panel-stat-label`
  (tw-gym-acc-v17.css).
- Sidebar flips `Cours`/`Classes`: HTML defaults said `Classes` (nav-label,
  classes page title) but fr translations say `Cours`. Fix: HTML defaults
  now match fr (`Cours`, `Cours & Activités`, accented `classesSub`).
- English mode nav `Paiements` stays French: nav-label and page title were
  hardcoded with no `data-i18n`. Fix: `data-i18n="navPayments"` on both;
  new owner T key `navPayments` (fr `Paiements`, en `Payments`, ar
  `المدفوعات`). Also added `data-i18n` to the hardcoded `Bookings Overview`
  dashboard card title (key already existed in all three T blocks) and to
  the Planning `Vue Réservations` card title.

### Item 6 — Mislabelled / confusing controls (fixed)
- Coach drawer `Assigner un coach` inside `Assigner un client`: the button
  (v17:109) assigns the selected client to this coach but was labelled
  `t('assign')` = `Assigner un coach`. Fix: button → `t('assignClient')`.
  The client-card use of `t('assign')` (v17:91) is correct there (assigns a
  coach to the client) — left alone.
- Owner `Réserver` on a coach card opens session creation: label →
  `t('bookCoachSession')` (new T key: fr `Créer une séance`, en
  `Create a session`, ar `إنشاء جلسة`).
- `Vue des réservations` vs `Vue des séances` unexplained: the Planning
  page has a `Vue Réservations` card (next 8 upcoming sessions, pilot
  `renderScheduleOverview`) above the full session grid (`#schedule-list`,
  no heading), and the dashboard `Bookings Overview` card shows KPI counts
  + next 5 pending. Fix: subtitle under the reservations card (new key
  `reservationsCardSub`) and a new heading + subtitle above the sessions
  grid (`sessionsListTitle` = `Vue des séances`, `sessionsListSub`), with
  new `.card-sub` / `.schedule-list-head` CSS rules.
- Weekly staff schedule defaults to only Sunday ON: no code default — DB
  default is `'{}'` (migration `20260415000000_trainw_012_staff_profiles.sql:10`),
  `buildStaffScheduleGrid(member.work_schedule || {})` shows only stored
  shifts; live Test Coach row is Sunday-only from earlier saved data
  (verified via sb-api.py Management API: user
  `b38df3c8-d7b3-49f6-a180-8d1c377b2f1f`, `{"sun": ["10:00", "17:00"],
  "mon": null, ...}`). Per the task's either/or, explanation added, no
  behaviour change (changing the fresh-profile default is a product
  decision): `<p class="settings-section-copy" data-i18n="staffScheduleNote">`
  under the `Planning hebdomadaire` label (new T key; `.settings-section-copy`
  already exists in tw-gym-acc.css).
- Client QR raw code exposed: `renderGateQr` only renders the QR image,
  but qrcodejs 1.0.0 sets `this._el.title = token` (verified by fetching
  the CDN source) — raw token exposed as tooltip/DOM title. Fix:
  `c.removeAttribute('title')` right after `new QRCode(...)`; the token
  stays only in JS memory (`gateQrToken`, used as a truthiness check).
- Verified, no redo: U7 plan-card button is `t('editPlan')` = "Modifier";
  no `Enregistrer` left on plan cards. U4 prefilled example people gone —
  no `Sana Ben Ali` / `Ahmed Ben Ali` / `sana@salle` anywhere.
- Observed, not fixed (out of named scope): the edit-session modal's
  Delete button starts with a literal `?` (`? <span data-i18n="deleteSession">`)
  — likely another lost icon like the item-3 `??`; needs the intended icon
  choice. The dashboard `wow-card-icon` elements also contain literal `?`
  (tw-gym-acc.html:292–294).

### Item 7 — No Cancel affordance (fixed)
- Course/session edit modals: core Escape handler (`bindPanelControls`)
  only closed slide panels, never `.modal.show`; modals open/close via
  `classList.add/remove('show')`. Fix: Escape now also removes `show` from
  all `.modal.show` (same semantics as the X button; forms are re-populated
  on open). Explicit Cancel buttons (`btn-secondary modal-cancel`,
  `data-i18n="cancel"`, new owner T key `cancel`) added to four owner
  modals — edit-session (before Save), create-session (flex row with the
  submit), class-template, gym-class — with a `.modal-cancel` click binding
  next to the `.modal-close` binding in `bindUi`. Coach plan modal got a
  Cancel button (`#btn-cancel-plan`, coach T key `cancel` in fr/en/ar)
  bound next to the close binding.
- Team inline `Changer le rôle` editor: clicking set
  `activeStaffRoleEditMembershipId` and re-rendered; the row's select
  saves on `change`, so "cancel" means abandoning the open editor with the
  role unchanged. Fix: (a) an `Annuler` button (`data-staff-role-cancel`,
  `t('cancel')`) next to the select when editing; (b) handler clears the
  id + re-renders; (c) the `Changer le rôle` button now toggles off when
  already editing that member; (d) Escape cancels via a guarded `document`
  keydown listener in `bindUi` (`window.__trainwRoleEditEscBound`).

### Item 8 — Check-in confirm button sticks on "..." (fixed)
- Cause: `submitManualCheckIn` set `setBusy(btn,true)` + `textContent='...'`,
  then awaited `Promise.allSettled([loadCheckIns(), loadDashboardStats()])`
  BEFORE the `finally` restored the label/disabled state. The `finally`
  exists on main too, so the stick is the untimed post-save reloads:
  `Trainw.api.run` has NO timeout — a stalled request delays `finally`
  indefinitely.
- Fix: reset the button immediately after the successful insert + toast,
  before the reloads (`btn.textContent = t('confirmCheckIn')`;
  `Trainw.ui.setBusy(btn, false)`); `finally` stays as a safety net.
  Systemic note (not changed — out of named scope): many handlers share
  the `setBusy` + `...` + slow-await + `finally` shape, and `api.run` has
  no timeout; other buttons can stick the same way on a stalled request.

### Item 9 — Free-workout log repeats the exercise once per set (fixed)
- Cause: `renderProgram` rendered each log's sets as
  `Name 12x50` per set, joined with ` - `; same repetition in the
  in-workout summary (`renderWorkoutStep`).
- Fix: new `groupWorkoutLogSets(sets, joiner)` helper grouping consecutive
  same-`exercise_name` sets; identical sets render as
  `Name 12x50 ×3`, differing sets as `Name: 12x50, 12x50, 10x45`; used in
  both the log list (joiner ` - `) and the workout summary (joiner ` · `).

### Verification
- `node --check` passes on all six touched JS files (`trainw-core.js`,
  `tw-gym-acc.js`, `tw-gym-acc-v17.js`, `tw-gym-pilot.js`,
  `tw-coach-acc.js`, `tw-client-acc.js`). `node env-config.js` +
  `npm run verify`: "Trainw verify: all checks passed."
- Node harness for the new time helpers (`/tmp/u10-time-test.js`, 25
  cases): `formatTimeOfDay` — `00:00`→`12:00 AM` en / `00:00` fr,
  `12:00`→`12:00 PM`, `13:00`→`1:00 PM`, `09:30`→`9:30 AM`,
  `23:45`→`11:45 PM`, `12:30`→`12:30 PM`, `00:30`→`12:30 AM`;
  `parseTimeOfDay` — `9`/`9:00`/`09:00`→`09:00`, `9h30`→`09:30`,
  `2:00 PM`→`14:00`, `12:00 AM`→`00:00`, `12:00 PM`→`12:00`,
  `14:30`/`1430`/`930`→`14:30`/`09:30`, `9:00:00`→`09:00`, and
  `24:00`/`9:60`/`25:00`/`13:00 PM`/`abc`/empty → null. All passed.
- Mojibake re-check after the edits: coach `Ã` 0 / `Â` 0, client `Ã` 0 /
  `Â` 0. Remaining `Ã`/`Â` bytes elsewhere are legitimate: `Âge` labels
  (owner HTML ×2, owner JS `clientAge`), and the pre-existing core regex
  character class in `trainw-core.js` (`/[\xC3\x83\xC3\x82\xC3\x98\xC3\x99]/`).
  v17 literal `?` count 855 (was 854; +1 is the new ternary in `saveClass`).
- Full `git diff` reviewed hunk by hunk (incl. the minified coach/client/
  v17 lines). One real bug caught in review: the accent replacements had
  introduced unescaped apostrophes (`qu'ils`, `l'espace`) that broke
  `tw-coach-acc.js` syntax — fixed with `\'` and re-verified.
- All rendering/timing behaviour is code-inspection + harness verified
  only — no live-browser access in this round; parent browser-verifies
  after deploy.
- Still needs the parent: push / merge / Vercel deploy, then real-browser
  checks for items 1 (save → immediate re-render), 2 (type into the HH:MM
  fields; midnight shows 12:00 AM in English), 5 (settings row on desktop
  vs mobile; staff-drawer end-time inputs; coach summary numbers; drawer
  stat labels), 6 (drawer button label, coach-card button, reservations vs
  sessions subtitles, staff-schedule note, QR tooltip gone), 7 (Cancel
  buttons + Escape in modals and role editor), 8 (check-in button resets
  immediately), 9 (grouped sets display).

## Phase 2 — P2-4: gate hardening (FE-04, GT-02, GT-04, GT-05, GT-08, DB-22, DB-24, DB-47) (2026-11-15)

Step definition (audit §Phase 2, line 346): terminal PIN out of the URL
(server-checked short-lived terminal token, non-empty PIN required);
per-device secret; opaque QR tokens; fix the `validate_member_credential`
gym filter; graceful same-day duplicate handling; mask credential refs to
last 4 chars; shorten the re-entry window or make it configurable.
Verify: open the terminal URL without a PIN — admin modal must not open;
spoof a device id — rejected; re-enter after 30 min — admitted with a
clear state.

Method: code re-verification against the current tree (every P2-4 item
re-checked in code, not trusted from the round-2/5 notes) + bounded live
probes against the live project Trainw (`caylegavnekidhytlswo`):
harness `/tmp/p24-probes.py` (curl + Management API `sb-api.py`; 2 edge
calls, 4 limiter-RPC calls on a throwaway bucket, read-only SQL). No
burst, no hammering, no live data written except the throwaway
rate-limit bucket rows (auto-expire by window). 8/8 probes passed.
No code changed in this round — verification-only; no migration, no
edge-function change, nothing to deploy from P2-4 itself.

### Per-item verdicts

- FE-04 (PIN out of the URL, server-checked short-lived token,
  non-empty PIN) — DONE. `gate-terminal.js` reads only `gym_id`,
  `gym_name`, `device_id` from the query string; grep for PIN-in-URL
  is clean in source and in `dist/`. The PIN is entered on screen
  (admin modal doubles as the PIN prompt when no terminal session is
  stored) and verified server-side by `gate-terminal-auth`: `PIN_RE =
  /^\d{4,8}$/` rejects an empty PIN, HMAC-SHA256(PIN,
  `GATE_TERMINAL_PEPPER`) is compared constant-time, and a 256-bit
  random session token (8 h TTL, only the SHA-256 hash stored in
  `gate_terminal_sessions`) is issued. Empty PIN is also refused
  client-side (`Saisissez le PIN`, `gate-terminal.js:591-593`) before
  any request. Live: an empty-PIN `auth` call returns 503
  `turnstiles_disabled` — the flag check fires before the PIN check,
  which also proves the flag-first ordering (see GT-03).
- GT-02 (per-device secret) — DONE, as device-bound session tokens.
  `gate-terminal-auth` stores `device_id` at token issuance;
  `gate-checkin` `verifyTerminalSession` rejects a token presented
  from a different device or with `device_id` omitted (round 5 live
  4/4). Note: there is no separate per-device secret credential or
  `gate_terminal_devices` table — the session token bound to
  `device_id` at issuance IS the per-device secret. That is the
  implementation the closure already verified; no new device-secret
  scheme was built, because turnstiles are off and no hardware
  enrolment flow exists to hold one.
- GT-05 / FE-09 (opaque QR tokens) — DONE. `randomGateToken`
  (`tw-client-acc.js:346`) is 128-bit `crypto.getRandomValues`;
  `gate_sessions` tokens live 60 s, are consumed atomically
  (`UPDATE ... WHERE used=false`), and the legacy dotted
  `userId.gymId.timestamp.random` format is rejected outright in the
  handler. Live QR scan remains a post-deploy browser check (parent).
- DB-22 (`validate_member_credential` gym filter) — DONE, re-proven
  live this round: the live function body (`pg_proc.prosrc`, 9,430
  chars) contains both `mc.gym_id = p_gym_id` and
  `cp.gym_id = p_gym_id` (latest definition
  `20261115230000_phase1d_gym_timezone.sql`).
- DB-24 / GT-08 (graceful same-day duplicates) — DONE. Both paths
  (QR handler and `validate_member_credential`) return logged 409
  denials, never a raw unique-index error: within 15 min of the last
  check-in → `already_inside`; later the same day →
  `duplicate_checkin_today`; a `23505` race on the insert is mapped
  to the same `duplicate_checkin_today`.
- Re-entry window (shorten or make configurable) — DONE by
  shortening: the original 2-hour guard is now 15 minutes
  (`already_inside`), hardcoded identically in `handler.mjs` and in
  `validate_member_credential`. There is no per-gym setting for it;
  the step's "or" is satisfied by the shortening.
- DB-47 (mask credential refs) — DONE, with a wording variance.
  `turnstile_truncate_credential_ref` (SQL) and the handler's
  `truncateCredentialRef` return first-4 + `'...'` (7 chars) and
  `'****'` for ≤ 4 chars — never the full value. Live probe:
  36-char input → `ABCD...`, `ab` → `****`, `12345678` →
  `1234...`. The audit's own fix text accepts "a hash or a
  fixed-length masked form (e.g. last 4 chars only)", and first-4 +
  `'...'` is such a form, so the finding is satisfied — but the
  step's literal "last 4 chars" wording is NOT met (it shows the
  first 4, not the last 4). Deliberately not changed: identical
  masking strength, and switching would need a new migration + a
  handler edit + a live apply for zero security gain. If the user
  wants the literal last-4 form, that is a named follow-up, not a
  gap found by this round.
- GT-04 (offline queue / allow-list) — NOT-APPLICABLE, as already
  recorded in the closure: no ESP32 gate firmware exists in this
  repo, and turnstiles are off by user decision. If turnstiles are
  ever re-enabled, the offline allow-list must be designed then
  (firmware + cached list).

### GT-03 (gate throttle) — BLOCKED, not testable while turnstiles are off

Code is in place: `gate-checkin` enforces 60/min per IP + 30/min per
device (`handler.mjs`, `RATE_LIMITS`), checked BEFORE any token or
credential lookup, failing open if the limiter itself is down, with
429 + `Retry-After: 60`. The limiter RPC underneath it was re-proven
live in this round: throwaway bucket `p24-probe-d688a4a1`, limit 3,
returned `T, T, T, F` (4 calls, owner JWT).

But the edge-function throttle itself cannot be live-tested while
turnstiles are disabled, and this round proved why with one call to
each function instead of a burst: the 503 `turnstiles_disabled`
fires FIRST, before the rate-limit check, in both `gate-checkin`
(`handler.mjs`: turnstile check precedes `checkRateLimits`) and
`gate-terminal-auth` (`index.ts`: flag check precedes the PIN and
rate-limit logic). Live, both returned 503 on the first call, so a
burst would only ever return 503s and consume no rate-limit budget —
it would prove nothing about the throttle and was deliberately not
run. GT-03 stays NEEDS-LIVE-TEST / BLOCKED: it needs the user to
re-enable turnstiles for the test (a bounded burst of ~65 calls from
one IP, stopping on the first 429), or it waits until turnstiles are
re-enabled for real. Turnstiles were NOT enabled by this round, and
the flag was not touched.

### Verify-clause deviations (needs the user's call, not a code fix)

- "Re-enter after 30 min — admitted with a clear state" does NOT
  hold under the current policy, and cannot be made to hold by a
  code fix alone. A scan 30 minutes after entry returns 409
  `duplicate_checkin_today` — a clear state, but a denial, not an
  admission — because one check-in per gym per calendar day is the
  standing rule (unique index `uq_check_ins_gym_client_day`; see the
  GT-08 closure note). Admitting same-day re-entry is a product
  decision (lunch-time re-entry, multi-visit memberships), not a
  bug. If the user wants the audit's verify literally satisfied,
  the day rule must be relaxed first; this round did not change it.
- "Open the terminal URL without a PIN — admin modal must not
  open": as written this is ambiguous, because the admin modal IS
  the PIN prompt — opening the terminal URL with no stored session
  opens the modal asking for the PIN. What does not open without a
  PIN is the unlocked admin mode / scanner: the scanner starts only
  after the PIN is verified server-side (`handleAdminKey`). And
  while turnstiles are off, neither opens at all: the terminal page
  shows the disabled screen (`Trainw.TURNSTILES_ENABLED !== true`,
  `trainw-config.js` and `dist/trainw-config.js` both `false`) and
  stops before any PIN prompt. That disabled screen is expected,
  not a bug.

### Verification

- Live probes (`/tmp/p24-probes.py`): 8/8 pass — gate-checkin 503
  `turnstiles_disabled`; gate-terminal-auth empty PIN 503
  `turnstiles_disabled`; owner sign-in 200; limiter RPC T,T,T,F;
  live `validate_member_credential` gym filter present; live
  truncate function `ABCD...` / `****` / `1234...`; gate tables
  present; `gate_terminal_sessions` readable (2 rows — pre-existing
  test sessions, not created by this round).
- No JS/SQL/edge-function files touched, so no `node --check` or
  local-Postgres chain run was needed for P2-4 code; `node
  env-config.js` + `npm run verify` run for the notes-only change
  (see below).
- Still needs the parent: push / merge / deploy (nothing to deploy
  from this round — no code changed), then the post-deploy browser
  checks that only a live browser can do (terminal disabled screen
  on production, PIN prompt flow once turnstiles are re-enabled,
  live QR scan). GT-03 live throttle test is blocked until the user
  re-enables turnstiles.
