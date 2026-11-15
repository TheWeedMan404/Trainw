import type { NextConfig } from "next";

// NX-11 (round 6): the Next.js app shipped with no security headers at
// all — no CSP, no frame-ancestors, no HSTS, no nosniff. These mirror
// the headers the static frontend already gets from vercel.json, so the
// app is protected the same way whichever path serves it.
//
// Tradeoff (documented, not hidden): script-src keeps 'unsafe-inline'.
// Next.js inlines its bootstrap/runtime scripts, so a strict CSP without
// 'unsafe-inline' (or a nonce wired through middleware) breaks the app.
// The static frontend's vercel.json CSP omits it because the vanilla
// pages have no inline scripts. If the app later moves to nonce-based
// CSP via middleware, drop 'unsafe-inline' here.
const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Strict-Transport-Security",
    value: "max-age=31536000; includeSubDomains",
  },
  {
    key: "Permissions-Policy",
    value: "camera=(self), microphone=(), geolocation=()",
  },
  {
    key: "Content-Security-Policy",
    value:
      "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://unpkg.com https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: blob: https:; media-src 'self' blob:; connect-src 'self' https://*.supabase.co wss://*.supabase.co; frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
  },
];

const nextConfig: NextConfig = {
  reactStrictMode: true,
  async headers() {
    return [{ source: "/(.*)", headers: securityHeaders }];
  },
};

export default nextConfig;
