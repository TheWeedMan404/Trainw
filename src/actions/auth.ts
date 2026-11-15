"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";

import { type FormState, getErrorMessage } from "@/actions/shared";
import { getAbsoluteUrl, isSupabaseAdminConfigured } from "@/lib/env";
import { checkRateLimit, getRequestIp } from "@/lib/rate-limit";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import {
  loginSchema,
  recoverWorkspaceSchema,
  resetRequestSchema,
  signupSchema,
  updatePasswordSchema,
} from "@/actions/auth-schemas";

// NX-01: 5 attempts per 15 minutes, per IP and per email, for both login
// and signup. The limiter is in-memory (see src/lib/rate-limit.ts).
const AUTH_RATE_LIMIT = 5;
const AUTH_RATE_WINDOW_MS = 15 * 60 * 1000;

async function authRateLimited(scope: "login" | "signup" | "reset", email: string) {
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
    consent: formData.get("consent") === "on",
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
          // P2-9: consent timestamp — handle_new_user() stores it on the
          // client profile (migration 20261115290000).
          consent_given_at: new Date().toISOString(),
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

// NX-28: self-healing for an orphaned account — a confirmed auth user
// with no public.users row (signup died between user creation and
// provisioning, or the /auth/callback RPC failed). Re-runs the same
// provision_new_gym RPC the callback uses, with the gym name from the
// form when the signup metadata does not carry one. Guarded: if the
// users row already exists there is nothing to recover.
export async function recoverWorkspaceAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const parsed = recoverWorkspaceSchema.safeParse({
    fullName: formData.get("fullName"),
    gymName: formData.get("gymName"),
  });

  if (!parsed.success) {
    return { error: "Enter your name and your gym name." };
  }

  if (!isSupabaseAdminConfigured()) {
    return {
      error:
        "Workspace recovery is not configured right now. Please contact support.",
    };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      return { error: "Sign in first, then try again." };
    }

    const admin = createAdminSupabaseClient();
    const { data: existingUser } = await admin
      .from("users")
      .select("id")
      .eq("id", user.id)
      .maybeSingle();

    if (existingUser) {
      redirect("/dashboard");
    }

    const { error: provisionError } = await admin.rpc("provision_new_gym", {
      p_email: user.email ?? "",
      p_full_name: parsed.data.fullName,
      p_gym_name: parsed.data.gymName,
      p_user_id: user.id,
    });

    if (provisionError) {
      return {
        error: "Could not create your workspace. Please try again or contact support.",
      };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Could not create your workspace.") };
  }

  redirect("/dashboard");
}

// NX-28: let an orphaned account delete itself instead of staying stuck
// forever. Refuses when a workspace row exists — deleting a user who
// owns a gym would orphan the gym; that is the owner's (or support's)
// decision, not a self-service one.
export async function deleteOwnAccountAction(): Promise<FormState> {
  if (!isSupabaseAdminConfigured()) {
    return {
      error:
        "Account deletion is not configured right now. Please contact support.",
    };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      return { error: "Sign in first, then try again." };
    }

    const admin = createAdminSupabaseClient();
    const { data: existingUser } = await admin
      .from("users")
      .select("id")
      .eq("id", user.id)
      .maybeSingle();

    if (existingUser) {
      return {
        error:
          "Your account has a gym workspace, so it cannot delete itself. Ask your gym owner or support for help.",
      };
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) {
      return { error: "Could not delete your account. Please contact support." };
    }

    await supabase.auth.signOut();
  } catch (error) {
    return { error: getErrorMessage(error, "Could not delete your account.") };
  }

  redirect("/login");
}
// the email belongs to an account or not — the reset link must never
// confirm that an address is registered (user enumeration). Supabase
// sends the link to /auth/reset-password; that path must be allowlisted
// in the Supabase dashboard (Authentication > URL Configuration >
// Redirect URLs), or the link lands on an error page.
export async function requestPasswordResetAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const parsed = resetRequestSchema.safeParse({
    email: formData.get("email"),
  });

  if (!parsed.success) {
    return { error: "Enter a valid email address." };
  }

  if (await authRateLimited("reset", parsed.data.email)) {
    return { error: "Too many reset requests. Please try again in a few minutes." };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const { error } = await supabase.auth.resetPasswordForEmail(
      parsed.data.email,
      { redirectTo: getAbsoluteUrl("/auth/reset-password") },
    );

    if (error) {
      return { error: "Unable to send the reset email right now. Please try again." };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to send the reset email right now.") };
  }

  return {
    success:
      "If an account exists for that email, a reset link is on its way. Check your inbox (and spam folder).",
  };
}

// NX-14: set a new password from the reset link. The reset page exchanges
// the link's code for a session first, so updateUser runs authenticated.
// Also the path an invited staff member uses to set their first password
// (the invite email has no password step — see roles.ts, NX-09).
export async function updatePasswordAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const parsed = updatePasswordSchema.safeParse({
    confirmPassword: formData.get("confirmPassword"),
    password: formData.get("password"),
  });

  if (!parsed.success) {
    return { error: "Enter a new password of at least 8 characters, twice." };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const { error } = await supabase.auth.updateUser({
      password: parsed.data.password,
    });

    if (error) {
      return { error: "Your reset link has expired. Request a new one." };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to update the password right now.") };
  }

  return { success: "Password updated. Sign in with your new password." };
}
