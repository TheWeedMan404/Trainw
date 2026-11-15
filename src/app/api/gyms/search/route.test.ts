// NX-26 smoke tests for the public gym search (NX-06). The validation
// paths run before any database call, so they are testable with no
// Supabase: too-short/too-long queries return an empty list, and a
// valid query with no admin key configured returns a generic 503.
// The handler only reads request.nextUrl + request.headers, so a plain
// stub stands in for NextRequest.
import { describe, expect, it } from "vitest";

import { GET } from "@/app/api/gyms/search/route";

function requestFor(query: string, ip = "203.0.113.10") {
  return {
    headers: new Headers({ "x-forwarded-for": ip }),
    nextUrl: new URL(`http://localhost/api/gyms/search?q=${query}`),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any;
}

describe("GET /api/gyms/search", () => {
  it("returns an empty list for a missing or 1-character query", async () => {
    for (const q of ["", "a"]) {
      const response = await GET(requestFor(q));
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ gyms: [] });
    }
  });

  it("returns an empty list for a query over 64 characters", async () => {
    const response = await GET(requestFor("x".repeat(65)));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ gyms: [] });
  });

  it("returns a generic 503 (not a Supabase error) when search is unconfigured", async () => {
    const response = await GET(requestFor("arena"));
    expect(response.status).toBe(503);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.gyms).toEqual([]);
    expect(typeof body.error).toBe("string");
  });

  it("rate-limits after 30 searches per minute from one IP", async () => {
    const ip = `198.51.100.${Math.floor(Math.random() * 200) + 1}`;
    for (let i = 0; i < 30; i++) {
      const response = await GET(requestFor("arena", ip));
      expect([200, 503]).toContain(response.status);
    }
    const limited = await GET(requestFor("arena", ip));
    expect(limited.status).toBe(429);
    expect(limited.headers.get("Retry-After")).toBeTruthy();
  });
});
