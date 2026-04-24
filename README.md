# Trainw V17

Trainw V17 is the original Trainw static product bundle: landing page, role chooser, login/signup, gym dashboard, coach dashboard, client dashboard, and gate terminal.

The active app is the static Trainw frontend in the repository root. The experimental Next.js rewrite is not part of the deploy path.

## Run locally

```bash
npm run dev
```

That starts `dev-server.js`, which:

- serves the root static files
- rewrites friendly routes like `/role`, `/login`, `/admin`, `/coach`, `/client`, `/dashboard/*`, and `/gate`
- injects Supabase config placeholders at runtime when available

## Build for deployment

```bash
npm run build
```

That runs `env-config.js`, which:

- copies the real Trainw app into `dist/`
- injects `%%SUPABASE_URL%%` and `%%SUPABASE_ANON_KEY%%`
- verifies the required HTML files were generated correctly

## Verify

```bash
npm run verify
```

The verifier checks:

- JS syntax on the core Trainw files
- required route rewrites through the local dev server
- local asset references in the key HTML pages
- absence of legacy `V14` / `V16` naming inside the active app files

## Deploy on Vercel

The repository is configured to deploy the static Trainw app, not the rewrite.

- `buildCommand`: `node env-config.js`
- `outputDirectory`: `dist`
- rewrites mirror the working local dev server route map

Required env vars:

```env
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
```

If those are not set, `env-config.js` can still fall back to an already-generated `dist/` config during local recovery work, but production deploys should always set them explicitly.

