import { NextResponse } from "next/server";

import { isSupabaseAdminConfigured, isSupabaseConfigured } from "@/lib/env";

export function GET() {
  return NextResponse.json({
    adminConfigured: isSupabaseAdminConfigured(),
    configured: isSupabaseConfigured(),
    status: "ok",
    timestamp: new Date().toISOString(),
  });
}
