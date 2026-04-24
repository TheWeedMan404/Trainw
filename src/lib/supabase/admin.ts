import { createClient } from "@supabase/supabase-js";

import { env, isSupabaseAdminConfigured } from "@/lib/env";
import type { Database } from "@/types/database";

export function createAdminSupabaseClient() {
  if (!isSupabaseAdminConfigured()) {
    throw new Error("Supabase admin environment variables are not configured.");
  }

  return createClient<Database>(env.supabaseUrl, env.supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
