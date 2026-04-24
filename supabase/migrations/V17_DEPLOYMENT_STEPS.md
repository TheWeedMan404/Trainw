# Trainw V17 — Lake Club Demo Deployment Steps

Run these steps **in order** before the demo. All SQL runs in the Supabase SQL Editor.

---

## Step 1 — Run missing migrations (if not already done)

```sql
-- Paste contents of: supabase/migrations/20260414090000_trainw_011_turnstiles.sql
-- Paste contents of: supabase/migrations/20260415000000_trainw_012_staff_profiles.sql
```

Run each file separately. Both are idempotent (safe to re-run).

---

## Step 2 — Create demo auth accounts

In Supabase Dashboard → Authentication → Users → "Add user":

| Email | Password | Role metadata |
|---|---|---|
| `admin@lakeclub.tn` | `LakeClub2026!` | `{"role":"gym_admin","name":"Sami Admin"}` |
| `reception@lakeclub.tn` | `LakeClub2026!` | `{"role":"staff","name":"Rim Receptionist"}` |

After creating them, copy the generated UUIDs from the Users table.

---

## Step 3 — Bootstrap the accounts

Replace the placeholder UUIDs with the real ones from Step 2:

```sql
-- Replace UUIDs below with the actual ones from auth.users
UPDATE public.users
SET id = '<REAL_ADMIN_UUID>'
WHERE id = '22222222-2222-2222-2222-222222222001';

UPDATE public.users
SET id = '<REAL_STAFF_UUID>'
WHERE id = '22222222-2222-2222-2222-222222222002';

-- Then bootstrap auth links
SELECT public.bootstrap_authenticated_user('gym_admin', 'Sami Admin',       'admin@lakeclub.tn');
SELECT public.bootstrap_authenticated_user('staff',     'Rim Receptionist', 'reception@lakeclub.tn');
```

---

## Step 4 — Verify role access matrix

| Login | Expected nav tabs |
|---|---|
| `owner.demo@trainw.local` | All tabs visible |
| `admin@lakeclub.tn` | All tabs except Role Management |
| `reception@lakeclub.tn` | **Dashboard + Check-In only** |

---

## Step 5 — Deploy frontend

Push to Vercel or run locally. No build step required (vanilla JS).

---

## Risks accepted for demo (non-blocking)

- Anon key still in `env-config.js` — intentional, do not change before demo
- ZKTeco relay trigger is simulation-only — QR flow works, physical gate does not
- Staff landing page shows full shell for ~200ms before redirect — cosmetic only
