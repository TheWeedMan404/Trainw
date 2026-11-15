import type { Json } from "@/types/database";

export const PERMISSIONS = {
  attendanceManage: "attendance.manage",
  classesManage: "classes.manage",
  clientsManage: "clients.manage",
  coachesManage: "coaches.manage",
  dashboardView: "dashboard.view",
  rolesManage: "roles.manage",
} as const;

export type PermissionKey = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];

export type PermissionMap = Partial<Record<PermissionKey, boolean>>;

// NX-23: DEFAULT_ROLE_TEMPLATES and the financeView permission were
// never imported or used anywhere (verified by grep) — the roles actually
// seeded live in the database, not in this file — so both are deleted.
// If a finance view is ever built, re-add its permission here and seed it
// through the roles table, not a hard-coded template.

export function hasPermission(
  permissions: PermissionMap | null | undefined,
  permission: PermissionKey,
) {
  // NX-17: strict true only. Boolean("false") is true — a role whose
  // permissions JSON was written with string values (manual DB edit,
  // bad migration, admin tool) would otherwise be granted a permission
  // the DB-side has_permission denies.
  return permissions?.[permission] === true;
}

// NX-17 / NX-26: the single normaliser for role permission JSON, used
// by workspace.ts and queries.ts. Strict true only (same reason as
// hasPermission). Exported for the smoke tests.
export function normalisePermissions(
  input: Json | null | undefined,
): PermissionMap {
  if (!input || Array.isArray(input) || typeof input !== "object") {
    return {};
  }

  return Object.fromEntries(
    Object.entries(input).map(([key, value]) => [key, value === true]),
  ) as PermissionMap;
}
