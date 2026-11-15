import { isSupabaseAdminConfigured } from "@/lib/env";
import { PAGE_SIZE, parsePageParam, rangeForPage } from "@/lib/pagination";
import { normalisePermissions, type PermissionMap } from "@/lib/permissions";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import type {
  AttendanceStatus,
  ClassType,
  Database,
  Json,
} from "@/types/database";

type CountableTable = "classes" | "clients" | "coaches";
type ClientRow = Database["public"]["Tables"]["clients"]["Row"];
type CoachRow = Database["public"]["Tables"]["coaches"]["Row"];

type RoleRow = {
  created_at: string;
  id: string;
  name: string;
  permissions: Json;
};

type UserRow = {
  created_at: string;
  email: string;
  full_name: string | null;
  id: string;
  role_id: string;
};

export type DashboardMetrics = {
  attendanceToday: number;
  classes: number;
  clients: number;
  coaches: number;
  latestAttendance: Array<{
    className: string | null;
    clientCode: string;
    clientName: string;
    id: string;
    status: AttendanceStatus;
    timestamp: string;
  }>;
  recentClasses: Array<{
    capacity: number | null;
    coachName: string | null;
    createdAt: string;
    id: string;
    name: string;
    type: ClassType;
  }>;
};

type ClassPageData = {
  hasMore: boolean;
  page: number;
  classes: Array<{
    capacity: number | null;
    coachId: string;
    coachName: string;
    createdAt: string;
    enrollments: Array<{
      clientCode: string;
      clientId: string;
      clientName: string;
      id: string;
    }>;
    id: string;
    name: string;
    type: ClassType;
  }>;
  clients: Array<Pick<ClientRow, "client_code" | "id" | "name">>;
  coaches: Array<Pick<CoachRow, "id" | "name">>;
};

type AttendancePageData = {
  hasMore: boolean;
  page: number;
  attendance: Array<{
    className: string | null;
    clientCode: string;
    clientName: string;
    id: string;
    status: AttendanceStatus;
    timestamp: string;
  }>;
  classes: Array<{ id: string; name: string }>;
  clients: Array<Pick<ClientRow, "client_code" | "id" | "name">>;
};

type RolesPageData = {
  hasMore: boolean;
  page: number;
  roles: Array<{
    createdAt: string;
    id: string;
    name: string;
    permissions: PermissionMap;
  }>;
  users: Array<{
    banned: boolean;
    createdAt: string;
    email: string;
    fullName: string | null;
    id: string;
    roleName: string;
  }>;
};

async function countRows(table: CountableTable, gymId: string) {
  const supabase = await createServerSupabaseClient();
  const { count, error } = await supabase
    .from(table)
    .select("*", { count: "exact", head: true })
    .eq("gym_id", gymId);

  if (error) {
    throw error;
  }

  return count ?? 0;
}

export async function getDashboardMetrics(gymId: string): Promise<DashboardMetrics> {
  const supabase = await createServerSupabaseClient();
  const today = new Date().toISOString().slice(0, 10);

  const [
    clients,
    coaches,
    classes,
    attendanceToday,
    recentClassesResult,
    latestAttendanceResult,
  ] = await Promise.all([
    countRows("clients", gymId),
    countRows("coaches", gymId),
    countRows("classes", gymId),
    supabase
      .from("attendance")
      .select("*", { count: "exact", head: true })
      .eq("gym_id", gymId)
      .gte("timestamp", `${today}T00:00:00.000Z`),
    supabase
      .from("classes")
      .select("id, name, type, capacity, created_at, coach:coaches(name)")
      .eq("gym_id", gymId)
      .order("created_at", { ascending: false })
      .limit(5),
    supabase
      .from("attendance")
      .select("id, status, timestamp, client:clients(name, client_code), class:classes(name)")
      .eq("gym_id", gymId)
      .order("timestamp", { ascending: false })
      .limit(8),
  ]);

  if (attendanceToday.error) {
    throw attendanceToday.error;
  }

  if (recentClassesResult.error) {
    throw recentClassesResult.error;
  }

  if (latestAttendanceResult.error) {
    throw latestAttendanceResult.error;
  }

  return {
    attendanceToday: attendanceToday.count ?? 0,
    classes,
    clients,
    coaches,
    latestAttendance: (latestAttendanceResult.data ?? []).map((entry) => ({
      className: entry.class?.name ?? null,
      clientCode: entry.client?.client_code ?? "N/A",
      clientName: entry.client?.name ?? "Unknown client",
      id: entry.id,
      status: entry.status,
      timestamp: entry.timestamp,
    })),
    recentClasses: (recentClassesResult.data ?? []).map((entry) => ({
      capacity: entry.capacity,
      coachName: entry.coach?.name ?? null,
      createdAt: entry.created_at,
      id: entry.id,
      name: entry.name,
      type: entry.type,
    })),
  };
}

export async function getClientsPageData(
  gymId: string,
  page: number = 1,
): Promise<{ clients: ClientRow[]; hasMore: boolean; page: number }> {
  const supabase = await createServerSupabaseClient();
  const safePage = parsePageParam(page);
  const { from, to } = rangeForPage(safePage);
  const { data, error } = await supabase
    .from("clients")
    .select("id, name, client_code, type, status, email, phone, created_at, gym_id")
    .eq("gym_id", gymId)
    .order("created_at", { ascending: false })
    .range(from, to);

  if (error) {
    throw error;
  }

  // NX-12: one extra row was fetched; hasMore is true when it exists.
  const rows = (data ?? []) as ClientRow[];
  return { clients: rows.slice(0, PAGE_SIZE), hasMore: rows.length > PAGE_SIZE, page: safePage };
}

export async function getCoachesPageData(
  gymId: string,
  page: number = 1,
): Promise<{ coaches: CoachRow[]; hasMore: boolean; page: number }> {
  const supabase = await createServerSupabaseClient();
  const safePage = parsePageParam(page);
  const { from, to } = rangeForPage(safePage);
  const { data, error } = await supabase
    .from("coaches")
    .select("id, name, rating, created_at, gym_id")
    .eq("gym_id", gymId)
    .order("created_at", { ascending: false })
    .range(from, to);

  if (error) {
    throw error;
  }

  const rows = (data ?? []) as CoachRow[];
  return { coaches: rows.slice(0, PAGE_SIZE), hasMore: rows.length > PAGE_SIZE, page: safePage };
}

export async function getClassesPageData(gymId: string, page: number = 1): Promise<ClassPageData> {
  const supabase = await createServerSupabaseClient();
  const safePage = parsePageParam(page);
  const { from, to } = rangeForPage(safePage);

  const [classesResult, coachesResult, clientsResult] = await Promise.all([
    supabase
      .from("classes")
      .select("id, name, type, capacity, created_at, coach_id, coach:coaches(name)")
      .eq("gym_id", gymId)
      .order("created_at", { ascending: false })
      .range(from, to),
    supabase
      .from("coaches")
      .select("id, name")
      .eq("gym_id", gymId)
      .order("name", { ascending: true }),
    supabase
      .from("clients")
      .select("id, name, client_code")
      .eq("gym_id", gymId)
      .order("name", { ascending: true }),
  ]);

  if (classesResult.error) throw classesResult.error;
  if (coachesResult.error) throw coachesResult.error;
  if (clientsResult.error) throw clientsResult.error;

  const classIds = (classesResult.data ?? []).map((item) => item.id as string);
  const enrollmentsResult = classIds.length
    ? await supabase
        .from("class_clients")
        .select("id, class_id, client_id, client:clients(id, name, client_code)")
        .in("class_id", classIds)
    : { data: [], error: null };

  if (enrollmentsResult.error) throw enrollmentsResult.error;

  const enrollmentsByClass = new Map<
    string,
    Array<{ clientCode: string; clientId: string; clientName: string; id: string }>
  >();

  for (const enrollment of enrollmentsResult.data ?? []) {
    const list = enrollmentsByClass.get(enrollment.class_id) ?? [];
    list.push({
      clientCode: enrollment.client?.client_code ?? "N/A",
      clientId: enrollment.client_id,
      clientName: enrollment.client?.name ?? "Unknown client",
      id: enrollment.id,
    });
    enrollmentsByClass.set(enrollment.class_id, list);
  }

  // NX-12: the classes list is paged (one extra row fetched for
  // hasMore). The coaches/clients lookups below populate the create and
  // enrollment form selects, not a rendered list, so they stay
  // unbounded — PostgREST caps any single response at 1,000 rows.
  const classRows = classesResult.data ?? [];
  const hasMore = classRows.length > PAGE_SIZE;

  return {
    hasMore,
    page: safePage,
    classes:
      classRows.slice(0, PAGE_SIZE).map((item) => ({
        capacity: item.capacity,
        coachId: item.coach_id,
        coachName: item.coach?.name ?? "Unknown coach",
        createdAt: item.created_at,
        enrollments: enrollmentsByClass.get(item.id) ?? [],
        id: item.id,
        name: item.name,
        type: item.type,
      })),
    clients:
      (clientsResult.data ?? []).map((item) => ({
        client_code: item.client_code,
        id: item.id,
        name: item.name,
      })) ?? [],
    coaches:
      (coachesResult.data ?? []).map((item) => ({
        id: item.id,
        name: item.name,
      })) ?? [],
  };
}

export async function getAttendancePageData(gymId: string, page: number = 1): Promise<AttendancePageData> {
  const supabase = await createServerSupabaseClient();
  const safePage = parsePageParam(page);
  const { from, to } = rangeForPage(safePage);

  const [attendanceResult, classesResult, clientsResult] = await Promise.all([
    supabase
      .from("attendance")
      .select("id, status, timestamp, client:clients(name, client_code), class:classes(name)")
      .eq("gym_id", gymId)
      .order("timestamp", { ascending: false })
      .range(from, to),
    supabase
      .from("classes")
      .select("id, name")
      .eq("gym_id", gymId)
      .order("name", { ascending: true }),
    supabase
      .from("clients")
      .select("id, name, client_code")
      .eq("gym_id", gymId)
      .order("name", { ascending: true }),
  ]);

  if (attendanceResult.error) throw attendanceResult.error;
  if (classesResult.error) throw classesResult.error;
  if (clientsResult.error) throw clientsResult.error;

  // NX-12: the attendance list is paged (the old .limit(20) is now
  // 50/page). The classes/clients lookups populate the manual
  // check-in form selects, not a rendered list — see getClassesPageData.
  const attendanceRows = attendanceResult.data ?? [];
  const hasMore = attendanceRows.length > PAGE_SIZE;

  return {
    hasMore,
    page: safePage,
    attendance:
      attendanceRows.slice(0, PAGE_SIZE).map((entry) => ({
        className: entry.class?.name ?? null,
        clientCode: entry.client?.client_code ?? "N/A",
        clientName: entry.client?.name ?? "Unknown client",
        id: entry.id,
        status: entry.status,
        timestamp: entry.timestamp,
      })),
    classes:
      (classesResult.data ?? []).map((entry) => ({
        id: entry.id,
        name: entry.name,
      })) ?? [],
    clients:
      (clientsResult.data ?? []).map((entry) => ({
        client_code: entry.client_code,
        id: entry.id,
        name: entry.name,
      })) ?? [],
  };
}

export async function getRolesPageData(gymId: string, page: number = 1): Promise<RolesPageData> {
  const supabase = await createServerSupabaseClient();
  const safePage = parsePageParam(page);
  const { from, to } = rangeForPage(safePage);

  const [rolesResult, usersResult] = await Promise.all([
    supabase
      .from("roles")
      .select("id, name, permissions, created_at")
      .eq("gym_id", gymId)
      .order("name", { ascending: true }),
    supabase
      .from("users")
      .select("id, email, full_name, created_at, role_id")
      .eq("gym_id", gymId)
      .order("created_at", { ascending: false })
      .range(from, to),
  ]);

  if (rolesResult.error) throw rolesResult.error;
  if (usersResult.error) throw usersResult.error;

  const roles = (rolesResult.data as RoleRow[] | null)?.map((role) => ({
    createdAt: role.created_at,
    id: role.id,
    name: role.name,
    permissions: normalisePermissions(role.permissions),
  })) ?? [];

  // NX-10: whether each staff login is currently banned (deactivated).
  // The auth users list is only available through the admin client; when
  // the admin key is not configured every user reads as active and the
  // deactivate action itself reports the missing configuration.
  const bannedById = new Map<string, boolean>();
  if (isSupabaseAdminConfigured()) {
    try {
      const admin = createAdminSupabaseClient();
      const { data: authUsers } = await admin.auth.admin.listUsers();
      for (const authUser of authUsers?.users ?? []) {
        bannedById.set(authUser.id, Boolean(authUser.banned_until));
      }
    } catch {
      // A failed admin lookup must not break the roles page — the actions
      // re-check the target server-side.
    }
  }

  // NX-24: the role name is joined in JS, not embedded in the query —
  // the generated Database type has no users -> roles relation, because
  // the archived schema's FK is composite (role_id, gym_id) ->
  // roles (id, gym_id), which the type generator does not express as a
  // relation. Embedding `role:roles(id, name)` types as a
  // SelectQueryError and fails tsc. The roles list is already loaded
  // above, so the join costs nothing.
  const roleNameById = new Map(roles.map((role) => [role.id, role.name]));

  // NX-12: the staff users list is paged; the roles list is not (a gym
  // has a handful of roles). One extra user row was fetched for hasMore.
  const userRows = (usersResult.data as UserRow[] | null) ?? [];
  const hasMore = userRows.length > PAGE_SIZE;

  const users = userRows.slice(0, PAGE_SIZE).map((user) => ({
    banned: bannedById.get(user.id) ?? false,
    createdAt: user.created_at,
    email: user.email,
    fullName: user.full_name,
    id: user.id,
    roleName: roleNameById.get(user.role_id) ?? "Unassigned",
  }));

  return { hasMore, page: safePage, roles, users };
}

