import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import { createGateCheckinHandler } from './handler.mjs';

const handleGateCheckinRequest = createGateCheckinHandler({
  getEnv(name: string) {
    return Deno.env.get(name) ?? '';
  },
  createAdminClient(supabaseUrl: string, serviceRoleKey: string) {
    return createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });
  },
});

serve(handleGateCheckinRequest);
