// NX-26 smoke tests for CAPTCHA gating (NX-01/NX-05). In the test
// environment no CAPTCHA secret is configured, so the fail-open path
// is what runs — the tests pin that behaviour (and that the configured
// check reports false here).
import { describe, expect, it } from "vitest";

import { isCaptchaConfigured, verifyCaptcha } from "@/lib/captcha";

describe("captcha (unconfigured)", () => {
  it("reports unconfigured when no secret is set", () => {
    expect(isCaptchaConfigured()).toBe(false);
  });

  it("fails open (ok: true) while unconfigured", async () => {
    await expect(verifyCaptcha("any-token")).resolves.toEqual({ ok: true });
  });
});
