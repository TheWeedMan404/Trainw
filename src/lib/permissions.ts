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
  return Boolean(permissions?.[permission]);
}
