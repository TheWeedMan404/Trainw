// NX-01 (Phase 1b): in-memory sliding-window rate limiter for the Next.js
// app's unauthenticated entry points (login, signup, public client
// registration, gym search).
//
// This is deliberately small: one process, one Map. It stops casual
// credential-stuffing and registration spam against a single deployment,
// but it does NOT share state across instances — on a multi-instance
// deployment (Vercel with several regions) each instance enforces its own
// window. If the app ever scales past one instance, replace this with a
// shared store (Upstash Redis / Vercel KV) behind the same
// checkRateLimit() signature.

type Bucket = number[];

const buckets = new Map<string, Bucket>();

// Keeps the map bounded: once it grows past this, stale buckets are swept.
const MAX_BUCKETS = 1000;

function sweepStaleBuckets(now: number, windowMs: number) {
  if (buckets.size <= MAX_BUCKETS) return;
  for (const [key, hits] of buckets) {
    if (hits.every((hit) => now - hit >= windowMs)) {
      buckets.delete(key);
    }
  }
}

export function checkRateLimit(
  key: string,
  limit: number,
  windowMs: number,
): { allowed: boolean; retryAfterSeconds: number } {
  const now = Date.now();
  sweepStaleBuckets(now, windowMs);
  const hits = (buckets.get(key) ?? []).filter((hit) => now - hit < windowMs);

  if (hits.length >= limit) {
    const oldest = hits[0];
    return {
      allowed: false,
      retryAfterSeconds: Math.max(1, Math.ceil((oldest + windowMs - now) / 1000)),
    };
  }

  hits.push(now);
  buckets.set(key, hits);
  return { allowed: true, retryAfterSeconds: 0 };
}

// Best-effort client IP for rate-limit keys. Behind Vercel / a proxy the
// first x-forwarded-for entry is the client; fall back to x-real-ip.
export function getRequestIp(headers: Headers): string {
  const forwardedFor = headers.get("x-forwarded-for");
  if (forwardedFor) {
    const first = forwardedFor.split(",")[0].trim();
    if (first) return first.slice(0, 45);
  }
  const realIp = headers.get("x-real-ip");
  if (realIp) return realIp.trim().slice(0, 45);
  return "unknown";
}
