import { NextRequest, NextResponse } from "next/server";

import { isSupabaseAdminConfigured } from "@/lib/env";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";

export async function GET(request: NextRequest) {
  const query = request.nextUrl.searchParams.get("q")?.trim() ?? "";

  if (!query) {
    return NextResponse.json({ gyms: [] });
  }

  if (!isSupabaseAdminConfigured()) {
    return NextResponse.json(
      { error: "Supabase admin environment variables are not configured.", gyms: [] },
      { status: 503 },
    );
  }

  const admin = createAdminSupabaseClient();
  const { data, error } = await admin
    .from("gyms")
    .select("id, name")
    .ilike("name", `%${query}%`)
    .order("name", { ascending: true })
    .limit(8);

  if (error) {
    return NextResponse.json(
      { error: "Unable to search gyms right now.", gyms: [] },
      { status: 500 },
    );
  }

  return NextResponse.json({ gyms: data ?? [] });
}
