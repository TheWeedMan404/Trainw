// NX-26 smoke tests for the health endpoint (NX-07): liveness only,
// no leak of whether the admin key is configured.
import { describe, expect, it } from "vitest";

import { GET } from "@/app/api/health/route";

describe("GET /api/health", () => {
  it("returns status ok with a parseable timestamp and no admin leak", async () => {
    const response = await GET();
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.status).toBe("ok");
    expect(typeof body.configured).toBe("boolean");
    expect(Number.isNaN(Date.parse(String(body.timestamp)))).toBe(false);
    // NX-07: the old adminConfigured field must never come back.
    expect("adminConfigured" in body).toBe(false);
  });
});
