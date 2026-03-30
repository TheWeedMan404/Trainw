# TRAINW System Report

## Architecture Overview

TRAINW remains a static multi-page frontend built with:

- HTML pages per role and flow
- Existing CSS and branding preserved unchanged
- Plain JavaScript per page
- Supabase for Auth, database access, and edge functions

A lightweight shared runtime was added in `trainw-core.js` to centralize:

- Supabase client creation
- Safe async execution wrappers
- Auth/session/profile loading
- Role-based redirects
- Toast/error helpers
- Global error and unhandled rejection logging

This keeps the original file structure intact while giving all pages a consistent reliability layer.

## Data Flow

1. Browser loads the existing page HTML.
2. `trainw-core.js` initializes shared helpers and global error handling.
3. Page script loads and checks auth/session state.
4. The current user profile is loaded from `users`.
5. Role-specific page bootstrap loads feature data from Supabase.
6. User actions validate input before sending mutations.
7. API/database responses are validated before UI updates.
8. Errors surface through toasts or inline messages instead of failing silently.

## Fixes Applied

### Shared Reliability Layer

- Added centralized helper in `trainw-core.js`
- Wrapped Supabase operations in a reusable safe runner
- Added auth context loading with role validation
- Added edge-function helper with token forwarding
- Added shared toast/UI helpers
- Added global `error` and `unhandledrejection` handlers

### Login / Session Flow

- Added session restore routing for already-authenticated users
- Hardened forgot-password flow with explicit error handling
- Normalized role lookup through shared auth/profile helper
- Fixed admin routing to the gym dashboard instead of a missing `/dashboard`

### Client Dashboard

- Reworked bootstrap with auth + role validation
- Added centralized booking, settings, measurements, and messaging guards
- Wired missing buttons and navigation behavior
- Prevented empty/invalid submissions
- Added safer message history loading and read-state updates
- Fixed booking inserts to include `gym_id`
- Replaced direct edge-function use with shared helper

### Coach Dashboard

- Reworked bootstrap with auth + role validation
- Added safe loading for sessions, clients, and reviews
- Added graceful fallback when `reviews` table is missing
- Hardened profile save flow
- Replaced direct edge-function fetch with shared helper
- Preserved existing UI while removing silent failures during load/save

### Gym Dashboard

- Reworked bootstrap with auth + role validation
- Switched to shared Supabase/runtime helper
- Removed duplicate auto-message panel listeners
- Removed duplicate contact-search listeners
- Removed duplicate message input auto-resize listener
- Hardened coach creation flow and restored owner session after coach signup
- Hardened managed client creation flow with rollback on partial failure
- Hardened check-in loading and manual check-in creation
- Hardened conversation loading, send-message flow, and message escaping
- Scoped analytics revenue/renewal logic to current gym context
- Hardened settings, pricing, password reset, and automated inactivity messaging

## Database Contract Assumptions

The frontend was adapted to the existing Supabase contract inferred from the included SQL:

- `users`, `gyms`, `coach_profiles`, `client_profiles`, `sessions`, `messages`, `check_ins`, and `gym_classes` exist
- `coach_profiles` and `client_profiles` are linked to `users`
- `handle_new_user` trigger creates related profile rows for real auth signups
- `messages` and `sessions` logic expects `gym_id` for gym-scoped access and RLS behavior
- A standalone `reviews` table may not exist in the deployed schema, so coach review UI now degrades safely
- Managed gym-created clients may exist without real auth accounts

## Verification Performed

- Syntax checked:
  - `TW Login.js`
  - `TW Client Acc.js`
  - `TW Coach Acc.js`
  - `TW Gym Acc.js`
- Confirmed helper script is wired into the updated role/login pages
- Confirmed duplicate listener hotspots were removed from the gym dashboard

## Remaining Risks

- Live Supabase behavior could not be fully integration-tested from this sandbox because networked runtime verification was not available
- Coach creation still relies on client-side `auth.signUp` because no service-role/admin API access is available here
- Legacy implementations still exist in some files above the hardened overrides for backward compatibility; the active runtime now uses the newer guarded functions
- Final production readiness still depends on validating the real deployed RLS policies with real role accounts

## Recommended Demo Checklist

- Login as client, coach, and gym owner
- Confirm role redirects land on the correct account page
- Book a client session and verify it appears in coach/gym views
- Send messages between gym/client and client/coach where allowed by RLS
- Add a managed client and a coach from the gym dashboard
- Run a manual check-in and confirm analytics/check-in counts update
- Test password reset and session persistence
