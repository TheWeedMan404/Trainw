// NX-01 / NX-05 (Phase 1b): CAPTCHA verification for the public client
// registration endpoint (hCaptcha-compatible server-side verify).
//
// Setup:
//   CAPTCHA_SECRET_KEY  — hCaptcha secret key (server-only, never public).
//   NEXT_PUBLIC_HCAPTCHA_SITE_KEY — hCaptcha site key (public, used by the
//     registration form widget).
//
// LAUNCH BLOCKER: if CAPTCHA_SECRET_KEY is not configured, verifyCaptcha
// logs a loud warning and returns ok (fail-open) so the public form keeps
// working during development. The public endpoint MUST NOT go live without
// the secret set — the fail-open is for local dev only, not production.

import { env } from "@/lib/env";

const VERIFY_URL = "https://hcaptcha.com/siteverify";

export function isCaptchaConfigured(): boolean {
  return Boolean(env.captchaSecretKey);
}

export async function verifyCaptcha(
  token: string | null | undefined,
  remoteIp?: string,
): Promise<{ ok: boolean; error?: string }> {
  if (!isCaptchaConfigured()) {
    console.warn(
      "[captcha] CAPTCHA_SECRET_KEY is not set — CAPTCHA verification is DISABLED (fail-open for local dev only). Set the secret before launch.",
    );
    return { ok: true };
  }

  if (!token) {
    return { ok: false, error: "captcha_required" };
  }

  try {
    const body = new URLSearchParams({
      secret: env.captchaSecretKey,
      response: token,
    });
    if (remoteIp && remoteIp !== "unknown") {
      body.set("remoteip", remoteIp);
    }

    const response = await fetch(VERIFY_URL, {
      body,
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      method: "POST",
    });
    const payload = (await response.json()) as { success?: boolean };
    if (payload.success === true) {
      return { ok: true };
    }
    return { ok: false, error: "captcha_failed" };
  } catch (error) {
    console.error("[captcha] verification request failed", error);
    return { ok: false, error: "captcha_unavailable" };
  }
}
