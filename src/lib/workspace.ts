import { cache } from "react";
import { redirect } from "next/navigation";

import {
  hasPermission,
  normalisePermissions,
  type PermissionKey,
  type PermissionMap,
} from "@/lib/permissions";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import type { Json } from "@/types/database";

type WorkspaceQueryRow = {
  email: string;
  full_name: string | null;
  gym_id: string;
  gyms: { id: string; name: string } | null;
  id: string;
  role_id: string;
  roles: { id: string; name: string; permissions: Json } | null;
};

export type WorkspaceContext = {
  email: string;
  fullName: string | null;
  gymId: string;
  gymName: string;
  permissions: PermissionMap;
  roleId: string;
  roleName: string;
  userId: string;
};

export const getWorkspaceContext = cache(async (): Promise<WorkspaceContext | null> => {
  const supabase = await createServerSupabaseClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return null;
  }

  const { data, error } = await supabase
    .from("users")
    .select(
      "id, email, full_name, gym_id, role_id, gyms(id, name), roles(id, name, permissions)",
    )
    .eq("id", user.id)
    .maybeSingle();

  if (error || !data) {
    return null;
  }

  const record = data as unknown as WorkspaceQueryRow;

  if (!record.gyms || !record.roles) {
    return null;
  }

  return {
    email: record.email,
    fullName: record.full_name,
    gymId: record.gym_id,
    gymName: record.gyms.name,
    permissions: normalisePermissions(record.roles.permissions),
    roleId: record.role_id,
    roleName: record.roles.name,
    userId: record.id,
  };
});

export async function requireWorkspaceContext() {
  const context = await getWorkspaceContext();

  if (!context) {
    redirect("/login");
  }

  return context;
}

export async function requirePermission(permission: PermissionKey) {
  const context = await requireWorkspaceContext();

  if (!hasPermission(context.permissions, permission)) {
    // NX-18: a dedicated page that requires no permission. The old
    // target (/dashboard?forbidden=1) was itself permission-gated, so a
    // role without dashboard.view looped until the browser gave up.
    redirect("/forbidden");
  }

  return context;
}
