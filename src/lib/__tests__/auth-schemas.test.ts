// NX-26 smoke tests for the auth actions' input validation — the zod
// schemas from src/actions/auth-schemas.ts. These are the actions' first
// line of defence; they run with no database and no Supabase.
import { describe, expect, it } from "vitest";

import {
  loginSchema,
  recoverWorkspaceSchema,
  resetRequestSchema,
  signupSchema,
  updatePasswordSchema,
} from "@/actions/auth-schemas";

describe("loginSchema", () => {
  it("accepts a valid login", () => {
    expect(
      loginSchema.safeParse({ email: "owner@gym.tn", password: "s3cret-pass" })
        .success,
    ).toBe(true);
  });

  it("rejects a bad email and a short password", () => {
    expect(
      loginSchema.safeParse({ email: "not-an-email", password: "s3cret-pass" })
        .success,
    ).toBe(false);
    expect(
      loginSchema.safeParse({ email: "owner@gym.tn", password: "short" }).success,
    ).toBe(false);
  });

  // NX-07 (round 6): redirectTo must stay on-site. Absolute URLs and
  // protocol-relative targets are open redirects and must fail the parse.
  it("accepts a same-site redirect and rejects external targets", () => {
    const base = { email: "owner@gym.tn", password: "s3cret-pass" };
    expect(loginSchema.safeParse({ ...base, redirectTo: "/dashboard" }).success).toBe(true);
    expect(loginSchema.safeParse({ ...base, redirectTo: undefined }).success).toBe(true);
    expect(
      loginSchema.safeParse({ ...base, redirectTo: "https://evil.example" }).success,
    ).toBe(false);
    expect(loginSchema.safeParse({ ...base, redirectTo: "//evil.example" }).success).toBe(false);
    expect(
      loginSchema.safeParse({ ...base, redirectTo: "/\\evil.example" }).success,
    ).toBe(false);
  });
});

describe("signupSchema", () => {
  it("accepts a complete signup and rejects a missing gym name", () => {
    expect(
      signupSchema.safeParse({
        email: "owner@gym.tn",
        fullName: "Hamdi I.",
        gymName: "Arena Gym",
        consent: true,
        password: "s3cret-pass",
      }).success,
    ).toBe(true);
    expect(
      signupSchema.safeParse({
        email: "owner@gym.tn",
        fullName: "Hamdi I.",
        gymName: "",
        consent: true,
        password: "s3cret-pass",
      }).success,
    ).toBe(false);
  });

  it("rejects a signup without privacy consent", () => {
    expect(
      signupSchema.safeParse({
        email: "owner@gym.tn",
        fullName: "Hamdi I.",
        gymName: "Arena Gym",
        consent: false,
        password: "s3cret-pass",
      }).success,
    ).toBe(false);
  });
});

describe("resetRequestSchema", () => {
  it("accepts a valid email and rejects anything else", () => {
    expect(resetRequestSchema.safeParse({ email: "owner@gym.tn" }).success).toBe(
      true,
    );
    expect(resetRequestSchema.safeParse({ email: "nope" }).success).toBe(false);
  });
});

describe("updatePasswordSchema", () => {
  it("accepts matching passwords of 8+ characters", () => {
    expect(
      updatePasswordSchema.safeParse({
        confirmPassword: "new-secret-1",
        password: "new-secret-1",
      }).success,
    ).toBe(true);
  });

  it("rejects mismatched passwords and short ones", () => {
    expect(
      updatePasswordSchema.safeParse({
        confirmPassword: "different-1",
        password: "new-secret-1",
      }).success,
    ).toBe(false);
    expect(
      updatePasswordSchema.safeParse({
        confirmPassword: "short",
        password: "short",
      }).success,
    ).toBe(false);
  });
});

describe("recoverWorkspaceSchema", () => {
  it("accepts a name + gym name and rejects a 1-character gym name", () => {
    expect(
      recoverWorkspaceSchema.safeParse({ fullName: "Hamdi I.", gymName: "Arena" })
        .success,
    ).toBe(true);
    expect(
      recoverWorkspaceSchema.safeParse({ fullName: "Hamdi I.", gymName: "A" })
        .success,
    ).toBe(false);
  });
});
