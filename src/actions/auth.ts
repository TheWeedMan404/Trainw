"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";

import { type FormState, getErrorMessage } from "@/actions/shared";
import { getAbsoluteUrl } from "@/lib/env";
import { checkRateLimit, getRequestIp } from "@/lib/rate-limit";
import { createServerSupabaseClient } from "@/lib/supabase/server";

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  redirectTo: z.string().optional(),
});

const signupSchema = z.object({
  email: z.string().email(),
  fullName: z.string().min(2),
  gymName: z.string().min(2),
  password: z.string().min(8),
});

// NX-01: 5 attempts per 15 minutes, per IP and per email, for both login
// and signup. The limiter is in-memory (see src/lib/rate-limit.ts).
const AUTH_RATE_LIMIT = 5;
const AUTH_RATE_WINDOW_MS = 15 * 60 * 1000;

async function authRateLimited(scope: "login" | "signup", email: string) {
  const clientIp = getRequestIp(await headers());
  const ip = checkRateLimit(
    `${scope}:ip:${clientIp}`,
    AUTH_RATE_LIMIT,
    AUTH_RATE_WINDOW_MS,
  );
  const byEmail = checkRateLimit(
    `${scope}:email:${email.toLowerCase()}`,
    AUTH_RATE_LIMIT,
    AUTH_RATE_WINDOW_MS,
  );
  return !ip.allowed || !byEmail.allowed;
}

export async function loginAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const parsed = loginSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
    redirectTo: formData.get("redirectTo"),
  });

  if (!parsed.success) {
    return { error: "Please enter a valid email and password." };
  }

  if (await authRateLimited("login", parsed.data.email)) {
    return { error: "Too many sign-in attempts. Please try again in a few minutes." };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const { error } = await supabase.auth.signInWithPassword({
      email: parsed.data.email,
      password: parsed.data.password,
    });

    if (error) {
      // NX-06: never return Supabase's message (it distinguishes "invalid
      // credentials" from "email not confirmed" and leaks which accounts
      // exist). One generic message for every failure.
      return { error: "Invalid email or password." };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to sign in right now.") };
  }

  redirect(parsed.data.redirectTo || "/dashboard");
}

export async function signupGymOwnerAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const parsed = signupSchema.safeParse({
    email: formData.get("email"),
    fullName: formData.get("fullName"),
    gymName: formData.get("gymName"),
    password: formData.get("password"),
  });

  if (!parsed.success) {
    return { error: "Please complete every field with valid values." };
  }

  if (await authRateLimited("signup", parsed.data.email)) {
    return { error: "Too many signup attempts. Please try again in a few minutes." };
  }

  // NX-02: the old flow minted the user with email_confirm: true, ran
  // provision_new_gym immediately, and auto-signed the user in — a gym
  // workspace for an unconfirmed email, with no approval step. The new
  // flow is the normal signUp: Supabase sends the confirmation email, and
  // the workspace is provisioned only in /auth/callback, after the email
  // is confirmed (see src/app/auth/callback/route.ts).
  try {
    const supabase = await createServerSupabaseClient();
    const { error } = await supabase.auth.signUp({
      email: parsed.data.email,
      password: parsed.data.password,
      options: {
        data: {
          full_name: parsed.data.fullName,
          gym_name: parsed.data.gymName,
        },
        emailRedirectTo: getAbsoluteUrl("/auth/callback"),
      },
    });

    if (error) {
      // Generic on purpose: Supabase's message would confirm whether the
      // email is already registered (user enumeration).
      return { error: "Unable to create the account right now. Please try again." };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to create the account right now.") };
  }

  return {
    success:
      "Check your email to confirm your account — your gym workspace will be created once you confirm.",
  };
}

export async function logoutAction() {
  try {
    const supabase = await createServerSupabaseClient();
    await supabase.auth.signOut();
  } catch {
    // Ignore logout cleanup errors and still return to login.
  }

  redirect("/login");
}
