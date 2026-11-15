"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { type FormState, getErrorMessage } from "@/actions/shared";
import { getAbsoluteUrl, isSupabaseAdminConfigured } from "@/lib/env";
import { PERMISSIONS } from "@/lib/permissions";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import { requirePermission } from "@/lib/workspace";

const createStaffUserSchema = z.object({
  email: z.string().email(),
  fullName: z.string().min(2),
  roleId: z.string().uuid(),
});

// NX-09: the owner role has no stable code to check against — the
// migration chain's roles table has a `code` column, but database/schema.sql
// (which the Next.js app currently runs on) has only `name`. Until the
// P1-11 schema decision lands, the owner role is recognised by name, in
// both spellings the two schemas seed ('Gym Owner' in the migration chain,
// 'admin' in schema.sql's provision_new_gym). Replace this with a code
// check once the schema is unified.
const OWNER_ROLE_NAMES = new Set(["gym owner", "admin"]);

function isOwnerRoleName(name: string | null | undefined) {
  return OWNER_ROLE_NAMES.has(String(name ?? "").trim().toLowerCase());
}

export async function createStaffUserAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.rolesManage);
  const parsed = createStaffUserSchema.safeParse({
    email: formData.get("email"),
    fullName: formData.get("fullName"),
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
    .select("id, gym_id, name")
    .eq("id", parsed.data.roleId)
    .eq("gym_id", context.gymId)
    .maybeSingle();

  if (roleError || !role) {
    return { error: "The selected role does not belong to your workspace." };
  }

  // NX-09: only a gym owner may assign the gym owner role. The caller
  // reached this action through requirePermission(rolesManage), but a
  // non-owner role can hold that permission too — the owner-role grant is
  // a separate check.
  if (isOwnerRoleName(role.name) && !isOwnerRoleName(context.roleName)) {
    return { error: "Only a gym owner can assign the gym owner role." };
  }

  // NX-09: invite instead of creating with email_confirm: true + a
  // caller-chosen password. The invite email lets the staff member set
  // their own password; the account cannot sign in until they accept it.
  // NOTE: after accepting the invite the member must set a password —
  // there is no in-app set-password screen yet (password reset, NX-14,
  // is Phase 2). Until then an invited member who never sets a password
  // cannot sign in.
  const {
    data: invitedUser,
    error: authError,
  } = await admin.auth.admin.inviteUserByEmail(parsed.data.email, {
    data: {
      full_name: parsed.data.fullName,
    },
    redirectTo: getAbsoluteUrl("/auth/callback"),
  });

  if (authError || !invitedUser.user) {
    return { error: authError?.message || "Unable to invite the staff member." };
  }

  try {
    const { error: userError } = await admin.from("users").insert({
      email: parsed.data.email,
      full_name: parsed.data.fullName,
      gym_id: context.gymId,
      id: invitedUser.user.id,
      role_id: parsed.data.roleId,
    });

    if (userError) {
      await admin.auth.admin.deleteUser(invitedUser.user.id);
      return { error: userError.message };
    }
  } catch (error) {
    await admin.auth.admin.deleteUser(invitedUser.user.id);
    return { error: getErrorMessage(error, "Unable to create the staff member.") };
  }

  revalidatePath("/dashboard/roles");

  return { success: "Staff invitation sent. They will set their own password from the invite email." };
}
