"use server";

import { redirect } from "next/navigation";
import { z } from "zod";

import { type FormState, getErrorMessage } from "@/actions/shared";
import { isSupabaseAdminConfigured } from "@/lib/env";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
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

  try {
    const supabase = await createServerSupabaseClient();
    const { error } = await supabase.auth.signInWithPassword({
      email: parsed.data.email,
      password: parsed.data.password,
    });

    if (error) {
      return { error: error.message };
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

  if (!isSupabaseAdminConfigured()) {
    return { error: "Supabase admin environment variables are not configured." };
  }

  const admin = createAdminSupabaseClient();

  const {
    data: createdUser,
    error: createUserError,
  } = await admin.auth.admin.createUser({
    email: parsed.data.email,
    email_confirm: true,
    password: parsed.data.password,
    user_metadata: {
      full_name: parsed.data.fullName,
      gym_name: parsed.data.gymName,
    },
  });

  if (createUserError || !createdUser.user) {
    return { error: createUserError?.message || "Unable to create the owner account." };
  }

  const { error: provisionError } = await admin.rpc("provision_new_gym", {
    p_email: parsed.data.email,
    p_full_name: parsed.data.fullName,
    p_gym_name: parsed.data.gymName,
    p_user_id: createdUser.user.id,
  });

  if (provisionError) {
    await admin.auth.admin.deleteUser(createdUser.user.id);
    return { error: provisionError.message };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: parsed.data.email,
      password: parsed.data.password,
    });

    if (signInError) {
      return {
        success:
          "Gym workspace created. Please sign in manually with your new credentials.",
      };
    }
  } catch (error) {
    return {
      error: getErrorMessage(
        error,
        "Gym created, but we could not sign you in automatically.",
      ),
    };
  }

  redirect("/dashboard");
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
