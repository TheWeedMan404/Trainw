import { NextResponse } from "next/server";

import { isSupabaseConfigured } from "@/lib/env";

export function GET() {
  // NX-07: the health endpoint reports liveness only. It used to leak
  // whether the admin service-role key is configured (adminConfigured) —
  // that tells an attacker which backend capabilities are live, so it is
  // no longer returned. `configured` only says whether the app can talk
  // to Supabase at all.
  return NextResponse.json({
    configured: isSupabaseConfigured(),
    status: "ok",
    timestamp: new Date().toISOString(),
  });
}
