# Trainw V10 Checklist Report

Generated: 2026-03-30
Workspace: `C:\Users\aissa\OneDrive\Desktop\trainw_v9`

## Hotfix

- [x] Mojibake / encoding corruption was repaired across the affected JS translation files.
- [x] French, English, and Arabic dashboard/login text was revalidated locally after the repair.

## 1. Routing And Access

- [x] New URL-safe page files were created: `dashboard.html`, `coach.html`, `client.html`, `login.html`, and `role.html`.
- [x] Navigation no longer depends on Vercel rewrites to filenames with spaces.
- [x] `vercel.json` now contains only security headers and no route-mapping logic.
- [x] App redirects now point directly to the slug HTML pages.
- [x] HTML `href` links now point directly to the slug HTML pages.
- [ ] Live Vercel smoke test for direct deployed navigation was not runnable from this local workspace.

## 2. Duplicate Cleanup And Hardened Flows

- [x] Duplicate first-pass function definitions were removed from `TW Gym Acc.js`.
- [x] Duplicate first-pass function definitions were removed from `TW Client Acc.js`.
- [x] Duplicate first-pass function definitions were removed from `TW Coach Acc.js`.
- [x] Duplicate-function scans now return no repeated function names across all three dashboard JS files.
- [x] `submitNewCoach()` exists only once in `TW Gym Acc.js`.
- [x] The remaining `submitNewCoach()` is the hardened version that uses `Trainw.api.run()`.
- [x] Syntax validation passes for `TW Gym Acc.js`, `TW Client Acc.js`, `TW Coach Acc.js`, `TW Login.js`, `index.js`, and `trainw-core.js`.

## 3. Security And Database Patch Readiness

- [x] `trainw-core.js` now supports `window.__TRAINW_URL__` and `window.__TRAINW_KEY__`.
- [x] The hardcoded anon key remains as a fallback, matching the brief’s temporary-production guidance.
- [x] `SQL_FINAL_PATCH.sql` includes the `payments` and `reviews` RLS patch.
- [x] `SQL_MIGRATION_V5.sql` includes the same `payments` and `reviews` RLS patch.
- [ ] Supabase SQL execution was not possible from this workspace, so the RLS patch is prepared locally but not executed by me here.

## 4. UI Upgrade

### Desktop

- [x] `trainw-enhancements.css` was replaced with the requested enhancement layer and includes `--ease-snap`.
- [x] Landing page hero markup now contains the browser-window dashboard preview directly in `index.html`.
- [x] Landing page includes the proof bar directly in `index.html`.
- [x] Landing page stats row now uses the outcome-based numbers directly in `index.html`.
- [x] Landing page FAQ section now exists directly in `index.html`, between pricing and CTA.
- [x] Landing page still includes scroll reveal, animated counters, and floating WhatsApp CTA via `index.js`.
- [x] Dashboard nav icons now use Lucide placeholders directly in the dashboard HTML files.
- [x] Gym dashboard includes active-nav glow, stat-card accent line, page-load transition, unread message badge, and structured empty states.

### Mobile

- [x] Gym, coach, and client dashboards use a fixed bottom tab bar at `max-width: 768px`.
- [x] Each dashboard clears the tab bar with `80px` bottom padding on `.main-content`.
- [x] Sidebar logo/info/footer labels are hidden on mobile.
- [x] Gym mobile nav hides secondary tabs and keeps the requested primary set: Dashboard, Clients, Schedule, Messages, Settings.
- [x] Landing hero has responsive stacking rules in `index.css`.
- [x] FAQ grid collapses to one column on mobile.

## 5. Demo Readiness

- [x] Gym dashboard init loads clients, coaches, schedule, check-ins, analytics, and messages badge on startup.
- [x] Check-in UI is wired and preloads current data when the dashboard initializes.
- [x] Structured empty states are in place for the key gym-owner empty views called out in the brief.
- [x] Messages nav unread badge is implemented and refreshed after load/send/read flows.
- [x] Dummy/demo data already exists in the database according to the user.

## Validation Commands Run

- `node --check index.js`
- `node --check "TW Gym Acc.js"`
- `node --check "TW Coach Acc.js"`
- `node --check "TW Client Acc.js"`
- `node --check "TW Login.js"`
- `node --check trainw-core.js`
- PowerShell duplicate-function scan across all three dashboard JS files
- Route-string scan to confirm old spaced filename redirects were removed

## Deliverable

- Release package target: `Trainw-V10-TEXT-FIX.zip`
- Report file included in workspace: `TRAINW_V10_REPORT.md`
