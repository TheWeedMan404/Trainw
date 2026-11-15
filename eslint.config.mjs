// NX-26: flat ESLint config for the Next.js app only (the vanilla
// static files under the repo root are not linted — they predate this
// setup and have their own style). Scoped to src/ plus the TS configs.
//
// eslint-config-next 15 still ships legacy eslintrc configs
// (core-web-vitals.js / typescript.js use `extends:`), so the flat
// config loads them through FlatCompat — the documented Next 15 path.
// (The extensionless imports the Next docs show do not resolve here:
// the package ships no "exports" map, so Node's ESM loader needs the
// full path — but FlatCompat takes config names, not file paths, so no
// extension issue arises.)
import { FlatCompat } from "@eslint/eslintrc";
import { defineConfig, globalIgnores } from "eslint/config";
import path from "node:path";
import { fileURLToPath } from "node:url";

const compat = new FlatCompat({
  baseDirectory: path.dirname(fileURLToPath(import.meta.url)),
});

export default defineConfig([
  ...compat.extends("next/core-web-vitals", "next/typescript"),
  globalIgnores([
    ".next/",
    "dist/",
    "node_modules/",
    "supabase/functions/",
    "*.js",
    "*.mjs",
  ]),
]);
