import { type NextRequest } from "next/server";

import { updateSession } from "@/lib/supabase/middleware";

// NX-08 (Phase 1b): session middleware — refreshes the Supabase auth
// session on every request so the cookies never go stale between
// navigations. Without this file, sessions expire mid-flow and users are
// bounced to sign-in. Static assets are excluded by the matcher.
export async function middleware(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
