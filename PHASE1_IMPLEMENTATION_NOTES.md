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

## P1-11 (schema decision) — SKIPPED (awaiting the user's call)

Nothing archived or reconciled; `database/schema.sql` untouched.

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
