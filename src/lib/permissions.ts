export const PERMISSIONS = {
  attendanceManage: "attendance.manage",
  classesManage: "classes.manage",
  clientsManage: "clients.manage",
  coachesManage: "coaches.manage",
  dashboardView: "dashboard.view",
  financeView: "finance.view",
  rolesManage: "roles.manage",
} as const;

export type PermissionKey = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];

export type PermissionMap = Partial<Record<PermissionKey, boolean>>;

export const DEFAULT_ROLE_TEMPLATES: Array<{
  description: string;
  name: "admin" | "manager" | "finance" | "frontdesk";
  permissions: PermissionMap;
}> = [
  {
    name: "admin",
    description: "Full workspace control across people, classes, attendance, and roles.",
    permissions: {
      [PERMISSIONS.dashboardView]: true,
      [PERMISSIONS.clientsManage]: true,
      [PERMISSIONS.coachesManage]: true,
      [PERMISSIONS.classesManage]: true,
      [PERMISSIONS.attendanceManage]: true,
      [PERMISSIONS.rolesManage]: true,
      [PERMISSIONS.financeView]: true,
    },
  },
  {
    name: "manager",
    description: "Daily operations access without role administration.",
    permissions: {
      [PERMISSIONS.dashboardView]: true,
      [PERMISSIONS.clientsManage]: true,
      [PERMISSIONS.coachesManage]: true,
      [PERMISSIONS.classesManage]: true,
      [PERMISSIONS.attendanceManage]: true,
      [PERMISSIONS.financeView]: true,
    },
  },
  {
    name: "finance",
    description: "Dashboard and finance visibility only.",
    permissions: {
      [PERMISSIONS.dashboardView]: true,
      [PERMISSIONS.financeView]: true,
    },
  },
  {
    name: "frontdesk",
    description: "Front-desk client operations and manual attendance.",
    permissions: {
      [PERMISSIONS.dashboardView]: true,
      [PERMISSIONS.clientsManage]: true,
      [PERMISSIONS.classesManage]: true,
      [PERMISSIONS.attendanceManage]: true,
    },
  },
];

export function hasPermission(
  permissions: PermissionMap | null | undefined,
  permission: PermissionKey,
) {
  return Boolean(permissions?.[permission]);
}
