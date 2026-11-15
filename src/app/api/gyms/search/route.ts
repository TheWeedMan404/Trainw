import { NextRequest, NextResponse } from "next/server";

import { isSupabaseAdminConfigured } from "@/lib/env";
import { checkRateLimit, getRequestIp } from "@/lib/rate-limit";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";

// NX-06 (Phase 1b): public gym search.
//   * At least 2 characters (NX-20: at most 64) — a 1-character query
//     matches nearly every gym and is a cheap enumeration vector.
//   * LIKE wildcards in the query are escaped, so "%" cannot dump the
//     table (PostgREST passes the pattern straight to Postgres ILIKE,
//     where backslash is the escape character).
//   * Rate limited (NX-01): 30/min per IP.
//   * Generic error, never Supabase's error text (NX-15).
export async function GET(request: NextRequest) {
  const query = request.nextUrl.searchParams.get("q")?.trim() ?? "";

  if (query.length < 2 || query.length > 64) {
    return NextResponse.json({ gyms: [] });
  }

  const rateLimit = checkRateLimit(
    `gyms-search:ip:${getRequestIp(request.headers)}`,
    30,
    60 * 1000,
  );
  if (!rateLimit.allowed) {
    return NextResponse.json(
      { error: "Too many searches. Please try again later.", gyms: [] },
      {
        headers: { "Retry-After": String(rateLimit.retryAfterSeconds) },
        status: 429,
      },
    );
  }

  if (!isSupabaseAdminConfigured()) {
    return NextResponse.json(
      { error: "Gym search is unavailable right now.", gyms: [] },
      { status: 503 },
    );
  }

  const admin = createAdminSupabaseClient();
  const escaped = query
    .replace(/\\/g, "\\\\")
    .replace(/%/g, "\\%")
    .replace(/_/g, "\\_");

  const { data, error } = await admin
    .from("gyms")
    .select("id, name")
    .ilike("name", `%${escaped}%`)
    .order("name", { ascending: true })
    .limit(8);

  if (error) {
    return NextResponse.json(
      { error: "Unable to search gyms right now.", gyms: [] },
      { status: 500 },
    );
  }

  return NextResponse.json({
    gyms: (data ?? []).map((gym) => ({ id: gym.id, name: gym.name })),
  });
}
