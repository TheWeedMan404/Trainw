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
  // NOTE: an invited member sets their password through the reset flow
  // (NX-14, /forgot-password) — the invite link itself has no password
  // step, so point a newly invited member at "Forgot your password?" if
  // they never set one.
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

const updateRoleSchema = z.object({
  name: z.string().min(2).max(100),
  permissions: z.string(),
  roleId: z.string().uuid(),
});

// NX-17: permissions are read with `value === true` (see
// src/lib/workspace.ts), so a stored non-boolean would silently disagree
// with the app gate. The update accepts only a flat JSON object whose
// values are all real booleans.
function parsePermissionsJson(raw: string): Record<string, boolean> | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }

  const entries = Object.entries(parsed as Record<string, unknown>);
  if (entries.some(([, value]) => typeof value !== "boolean")) {
    return null;
  }

  return Object.fromEntries(entries) as Record<string, boolean>;
}

async function getStaffUserInGym(
  admin: ReturnType<typeof createAdminSupabaseClient>,
  userId: string,
  gymId: string,
) {
  const { data, error } = await admin
    .from("users")
    .select("id, role_id")
    .eq("id", userId)
    .eq("gym_id", gymId)
    .maybeSingle();

  if (error || !data) {
    return null;
  }

  // NX-24: the role name is looked up separately, not embedded in the
  // query — the generated Database type has no users -> roles relation
  // (the archived schema's FK is composite (role_id, gym_id) -> roles
  // (id, gym_id)), and PostgREST cannot reliably embed across it either.
  const { data: role } = await admin
    .from("roles")
    .select("id, name")
    .eq("id", (data as { role_id: string }).role_id)
    .eq("gym_id", gymId)
    .maybeSingle();

  const user = data as { id: string; role_id: string };
  return {
    id: user.id,
    role_id: user.role_id,
    roles: (role as { id: string; name: string } | null) ?? null,
  };
}

async function countOwnersInGym(
  admin: ReturnType<typeof createAdminSupabaseClient>,
  gymId: string,
) {
  // NX-24: owner roles are resolved by name, then users are counted by
  // role_id (same composite-FK reason as getStaffUserInGym — the users ->
  // roles embed does not work across it).
  const { data: roles } = await admin
    .from("roles")
    .select("id, name")
    .eq("gym_id", gymId);
  const ownerRoleIds = new Set(
    ((roles as Array<{ id: string; name: string }> | null) ?? [])
      .filter((role) => isOwnerRoleName(role.name))
      .map((role) => role.id),
  );
  if (ownerRoleIds.size === 0) {
    return 0;
  }

  const { data, error } = await admin
    .from("users")
    .select("id, role_id")
    .eq("gym_id", gymId);

  if (error || !data) {
    return 0;
  }

  return (data as Array<{ role_id: string }>).filter((row) =>
    ownerRoleIds.has(row.role_id),
  ).length;
}

// NX-10: edit a role (name and permission set). The owner role can only
// be edited by a gym owner, and a role cannot be renamed to the owner
// name by a non-owner (NX-09 symmetry).
export async function updateRoleAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.rolesManage);
  const parsed = updateRoleSchema.safeParse({
    name: formData.get("name"),
    permissions: formData.get("permissions"),
    roleId: formData.get("roleId"),
  });

  if (!parsed.success) {
    return { error: "Enter a role name and its permissions." };
  }

  const permissions = parsePermissionsJson(parsed.data.permissions);
  if (!permissions) {
    return { error: "Permissions must be a list of true/false values." };
  }

  if (!isSupabaseAdminConfigured()) {
    return { error: "Supabase admin environment variables are not configured." };
  }

  const admin = createAdminSupabaseClient();

  const { data: role, error: roleError } = await admin
    .from("roles")
    .select("id, name")
    .eq("id", parsed.data.roleId)
    .eq("gym_id", context.gymId)
    .maybeSingle();

  if (roleError || !role) {
    return { error: "That role does not belong to your workspace." };
  }

  if (
    (isOwnerRoleName(role.name) || isOwnerRoleName(parsed.data.name)) &&
    !isOwnerRoleName(context.roleName)
  ) {
    return { error: "Only a gym owner can edit the gym owner role." };
  }

  try {
    const { error } = await admin
      .from("roles")
      .update({ name: parsed.data.name, permissions })
      .eq("id", parsed.data.roleId)
      .eq("gym_id", context.gymId);

    if (error) {
      return { error: error.message };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to update the role.") };
  }

  revalidatePath("/dashboard/roles");

  return { success: "Role updated." };
}

const deleteRoleSchema = z.object({
  roleId: z.string().uuid(),
});

// NX-10: delete a role. Refused when the role is the owner role, when it
// is the caller's own role, or while any staff user still holds it —
// deleting a role out from under its users would orphan their logins.
export async function deleteRoleAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.rolesManage);
  const parsed = deleteRoleSchema.safeParse({
    roleId: formData.get("roleId"),
  });

  if (!parsed.success) {
    return { error: "No role was selected." };
  }

  if (!isSupabaseAdminConfigured()) {
    return { error: "Supabase admin environment variables are not configured." };
  }

  const admin = createAdminSupabaseClient();

  const { data: role, error: roleError } = await admin
    .from("roles")
    .select("id, name")
    .eq("id", parsed.data.roleId)
    .eq("gym_id", context.gymId)
    .maybeSingle();

  if (roleError || !role) {
    return { error: "That role does not belong to your workspace." };
  }

  if (isOwnerRoleName(role.name)) {
    return { error: "The gym owner role cannot be deleted." };
  }
  if (parsed.data.roleId === context.roleId) {
    return { error: "You cannot delete your own role." };
  }

  const { count, error: countError } = await admin
    .from("users")
    .select("id", { count: "exact", head: true })
    .eq("role_id", parsed.data.roleId)
    .eq("gym_id", context.gymId);

  if (countError) {
    return { error: countError.message };
  }
  if ((count ?? 0) > 0) {
    return {
      error: `${count} staff member${count === 1 ? "" : "s"} still hold${count === 1 ? "s" : ""} this role. Reassign them first.`,
    };
  }

  try {
    const { error } = await admin
      .from("roles")
      .delete()
      .eq("id", parsed.data.roleId)
      .eq("gym_id", context.gymId);

    if (error) {
      return { error: error.message };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to delete the role.") };
  }

  revalidatePath("/dashboard/roles");

  return { success: "Role deleted." };
}

const staffUserSchema = z.object({
  userId: z.string().uuid(),
});

// NX-10: deactivate a staff login (revoke access without deleting the
// record). The auth user is banned for 100 years — effectively permanent
// until reactivated — so the login stops working immediately while the
// users row and history stay intact. Never your own login, and never the
// last gym owner.
export async function deactivateStaffUserAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.rolesManage);
  const parsed = staffUserSchema.safeParse({
    userId: formData.get("userId"),
  });

  if (!parsed.success) {
    return { error: "No staff member was selected." };
  }

  if (parsed.data.userId === context.userId) {
    return { error: "You cannot deactivate your own login." };
  }

  if (!isSupabaseAdminConfigured()) {
    return { error: "Supabase admin environment variables are not configured." };
  }

  const admin = createAdminSupabaseClient();
  const target = await getStaffUserInGym(admin, parsed.data.userId, context.gymId);

  if (!target) {
    return { error: "That staff member does not belong to your workspace." };
  }

  if (isOwnerRoleName(target.roles?.name)) {
    const owners = await countOwnersInGym(admin, context.gymId);
    if (owners <= 1) {
      return { error: "You cannot deactivate the last gym owner." };
    }
  }

  const { error } = await admin.auth.admin.updateUserById(parsed.data.userId, {
    ban_duration: "876000h",
  });

  if (error) {
    return { error: error.message };
  }

  revalidatePath("/dashboard/roles");

  return { success: "Staff login deactivated." };
}

// NX-10: reactivate a deactivated staff login (lifts the ban).
export async function reactivateStaffUserAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.rolesManage);
  const parsed = staffUserSchema.safeParse({
    userId: formData.get("userId"),
  });

  if (!parsed.success) {
    return { error: "No staff member was selected." };
  }

  if (!isSupabaseAdminConfigured()) {
    return { error: "Supabase admin environment variables are not configured." };
  }

  const admin = createAdminSupabaseClient();
  const target = await getStaffUserInGym(admin, parsed.data.userId, context.gymId);

  if (!target) {
    return { error: "That staff member does not belong to your workspace." };
  }

  const { error } = await admin.auth.admin.updateUserById(parsed.data.userId, {
    ban_duration: "none",
  });

  if (error) {
    return { error: error.message };
  }

  revalidatePath("/dashboard/roles");

  return { success: "Staff login reactivated." };
}

// NX-10: delete a staff user entirely. The auth account is deleted, which
// cascades to the public.users row (FK ON DELETE CASCADE). Never your own
// login, and never the last gym owner.
export async function deleteStaffUserAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.rolesManage);
  const parsed = staffUserSchema.safeParse({
    userId: formData.get("userId"),
  });

  if (!parsed.success) {
    return { error: "No staff member was selected." };
  }

  if (parsed.data.userId === context.userId) {
    return { error: "You cannot delete your own login." };
  }

  if (!isSupabaseAdminConfigured()) {
    return { error: "Supabase admin environment variables are not configured." };
  }

  const admin = createAdminSupabaseClient();
  const target = await getStaffUserInGym(admin, parsed.data.userId, context.gymId);

  if (!target) {
    return { error: "That staff member does not belong to your workspace." };
  }

  if (isOwnerRoleName(target.roles?.name)) {
    const owners = await countOwnersInGym(admin, context.gymId);
    if (owners <= 1) {
      return { error: "You cannot delete the last gym owner." };
    }
  }

  const { error } = await admin.auth.admin.deleteUser(parsed.data.userId);

  if (error) {
    return { error: error.message };
  }

  revalidatePath("/dashboard/roles");

  return { success: "Staff user deleted." };
}
