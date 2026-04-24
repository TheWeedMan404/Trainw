"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { type FormState, getErrorMessage } from "@/actions/shared";
import { isSupabaseAdminConfigured } from "@/lib/env";
import { PERMISSIONS } from "@/lib/permissions";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import { requirePermission } from "@/lib/workspace";

const createStaffUserSchema = z.object({
  email: z.string().email(),
  fullName: z.string().min(2),
  password: z.string().min(8),
  roleId: z.string().uuid(),
});

export async function createStaffUserAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.rolesManage);
  const parsed = createStaffUserSchema.safeParse({
    email: formData.get("email"),
    fullName: formData.get("fullName"),
    password: formData.get("password"),
    roleId: formData.get("roleId"),
  });

  if (!parsed.success) {
    return { error: "Enter a valid staff member profile and role." };
  }

  if (!isSupabaseAdminConfigured()) {
    return { error: "Supabase admin environment variables are not configured." };
  }

  const admin = createAdminSupabaseClient();

  const { data: role, error: roleError } = await admin
    .from("roles")
    .select("id, gym_id")
    .eq("id", parsed.data.roleId)
    .eq("gym_id", context.gymId)
    .maybeSingle();

  if (roleError || !role) {
    return { error: "The selected role does not belong to your workspace." };
  }

  const {
    data: createdUser,
    error: authError,
  } = await admin.auth.admin.createUser({
    email: parsed.data.email,
    email_confirm: true,
    password: parsed.data.password,
    user_metadata: {
      full_name: parsed.data.fullName,
    },
  });

  if (authError || !createdUser.user) {
    return { error: authError?.message || "Unable to create the staff login." };
  }

  try {
    const { error: userError } = await admin.from("users").insert({
      email: parsed.data.email,
      full_name: parsed.data.fullName,
      gym_id: context.gymId,
      id: createdUser.user.id,
      role_id: parsed.data.roleId,
    });

    if (userError) {
      await admin.auth.admin.deleteUser(createdUser.user.id);
      return { error: userError.message };
    }
  } catch (error) {
    await admin.auth.admin.deleteUser(createdUser.user.id);
    return { error: getErrorMessage(error, "Unable to create the staff member.") };
  }

  revalidatePath("/dashboard/roles");

  return { success: "Staff member created successfully." };
}
