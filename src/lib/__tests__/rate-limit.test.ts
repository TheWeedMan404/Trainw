// NX-26 smoke tests for the in-memory sliding-window rate limiter
// (NX-01). No network, no database — the limiter is a pure Map.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { checkRateLimit, getRequestIp } from "@/lib/rate-limit";

describe("checkRateLimit", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-11-15T10:00:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("allows up to the limit, then blocks", () => {
    const key = `test-allow-${Date.now()}`;
    for (let i = 0; i < 5; i++) {
      expect(checkRateLimit(key, 5, 60_000).allowed).toBe(true);
    }
    const blocked = checkRateLimit(key, 5, 60_000);
    expect(blocked.allowed).toBe(false);
    expect(blocked.retryAfterSeconds).toBeGreaterThan(0);
  });

  it("tracks keys independently", () => {
    const a = `test-a-${Date.now()}`;
    const b = `test-b-${Date.now()}`;
    for (let i = 0; i < 3; i++) {
      expect(checkRateLimit(a, 3, 60_000).allowed).toBe(true);
    }
    expect(checkRateLimit(a, 3, 60_000).allowed).toBe(false);
    expect(checkRateLimit(b, 3, 60_000).allowed).toBe(true);
  });

  it("allows again once the window slides past", () => {
    const key = `test-window-${Date.now()}`;
    for (let i = 0; i < 2; i++) {
      expect(checkRateLimit(key, 2, 60_000).allowed).toBe(true);
    }
    expect(checkRateLimit(key, 2, 60_000).allowed).toBe(false);
    vi.advanceTimersByTime(61_000);
    expect(checkRateLimit(key, 2, 60_000).allowed).toBe(true);
  });
});

describe("getRequestIp", () => {
  it("takes the first x-forwarded-for entry", () => {
    const headers = new Headers({
      "x-forwarded-for": "203.0.113.10, 198.51.100.2",
    });
    expect(getRequestIp(headers)).toBe("203.0.113.10");
  });

  it("falls back to x-real-ip, then 'unknown'", () => {
    expect(getRequestIp(new Headers({ "x-real-ip": "198.51.100.3" }))).toBe(
      "198.51.100.3",
    );
    expect(getRequestIp(new Headers())).toBe("unknown");
  });
});
