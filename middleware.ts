import { NextResponse, type NextRequest } from "next/server";

import { updateSession } from "@/lib/supabase/middleware";

const AUTH_PAGES = ["/login", "/signup"];
const PROTECTED_PREFIX = "/dashboard";

export async function middleware(request: NextRequest) {
  const response = await updateSession(request);
  const hasSession = request.cookies.getAll().some((cookie) =>
    cookie.name.startsWith("sb-") && cookie.name.endsWith("-auth-token"),
  );
  const pathname = request.nextUrl.pathname;

  if (pathname.startsWith(PROTECTED_PREFIX) && !hasSession) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("redirectTo", pathname);
    return NextResponse.redirect(url);
  }

  if (AUTH_PAGES.includes(pathname) && hasSession) {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    url.searchParams.delete("redirectTo");
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
