// NX-26: smoke-test setup for the Next.js app. Node environment, no
// database, no network: the tests cover pure helpers, zod validation,
// and the API routes' validation/error paths only. Anything that needs
// Supabase stays a live-test item (P1-13).
import path from "node:path";
import { fileURLToPath } from "node:url";

import { defineConfig } from "vitest/config";

const root = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(root, "./src"),
    },
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
});
