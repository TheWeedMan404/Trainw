import type { PermissionMap } from "@/lib/permissions";
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
  role: {
    id: string;
    name: string;
  } | null;
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
  roles: Array<{
    createdAt: string;
    id: string;
    name: string;
    permissions: PermissionMap;
  }>;
  users: Array<{
    createdAt: string;
    email: string;
    fullName: string | null;
    id: string;
    roleName: string;
  }>;
};

function normalisePermissions(value: Json): PermissionMap {
  if (!value || Array.isArray(value) || typeof value !== "object") {
    return {};
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, enabled]) => [key, Boolean(enabled)]),
  ) as PermissionMap;
}

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
    latestAttendance: (latestAttendanceResult.data ?? []).map((entry: any) => ({
      className: entry.class?.name ?? null,
      clientCode: entry.client?.client_code ?? "N/A",
      clientName: entry.client?.name ?? "Unknown client",
      id: entry.id,
      status: entry.status,
      timestamp: entry.timestamp,
    })),
    recentClasses: (recentClassesResult.data ?? []).map((entry: any) => ({
      capacity: entry.capacity,
      coachName: entry.coach?.name ?? null,
      createdAt: entry.created_at,
      id: entry.id,
      name: entry.name,
      type: entry.type,
    })),
  };
}

export async function getClientsPageData(gymId: string): Promise<ClientRow[]> {
  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase
    .from("clients")
    .select("id, name, client_code, type, created_at, gym_id")
    .eq("gym_id", gymId)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return (data ?? []) as ClientRow[];
}

export async function getCoachesPageData(gymId: string): Promise<CoachRow[]> {
  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase
    .from("coaches")
    .select("id, name, rating, created_at, gym_id")
    .eq("gym_id", gymId)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return (data ?? []) as CoachRow[];
}

export async function getClassesPageData(gymId: string): Promise<ClassPageData> {
  const supabase = await createServerSupabaseClient();

  const [classesResult, coachesResult, clientsResult] = await Promise.all([
    supabase
      .from("classes")
      .select("id, name, type, capacity, created_at, coach_id, coach:coaches(name)")
      .eq("gym_id", gymId)
      .order("created_at", { ascending: false }),
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

  const classIds = (classesResult.data ?? []).map((item: any) => item.id as string);
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

  for (const enrollment of (enrollmentsResult.data ?? []) as any[]) {
    const list = enrollmentsByClass.get(enrollment.class_id) ?? [];
    list.push({
      clientCode: enrollment.client?.client_code ?? "N/A",
      clientId: enrollment.client_id,
      clientName: enrollment.client?.name ?? "Unknown client",
      id: enrollment.id,
    });
    enrollmentsByClass.set(enrollment.class_id, list);
  }

  return {
    classes:
      classesResult.data?.map((item: any) => ({
        capacity: item.capacity,
        coachId: item.coach_id,
        coachName: item.coach?.name ?? "Unknown coach",
        createdAt: item.created_at,
        enrollments: enrollmentsByClass.get(item.id) ?? [],
        id: item.id,
        name: item.name,
        type: item.type,
      })) ?? [],
    clients:
      (clientsResult.data ?? []).map((item: any) => ({
        client_code: item.client_code,
        id: item.id,
        name: item.name,
      })) ?? [],
    coaches:
      (coachesResult.data ?? []).map((item: any) => ({
        id: item.id,
        name: item.name,
      })) ?? [],
  };
}

export async function getAttendancePageData(gymId: string): Promise<AttendancePageData> {
  const supabase = await createServerSupabaseClient();

  const [attendanceResult, classesResult, clientsResult] = await Promise.all([
    supabase
      .from("attendance")
      .select("id, status, timestamp, client:clients(name, client_code), class:classes(name)")
      .eq("gym_id", gymId)
      .order("timestamp", { ascending: false })
      .limit(20),
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

  return {
    attendance:
      attendanceResult.data?.map((entry: any) => ({
        className: entry.class?.name ?? null,
        clientCode: entry.client?.client_code ?? "N/A",
        clientName: entry.client?.name ?? "Unknown client",
        id: entry.id,
        status: entry.status,
        timestamp: entry.timestamp,
      })) ?? [],
    classes:
      (classesResult.data ?? []).map((entry: any) => ({
        id: entry.id,
        name: entry.name,
      })) ?? [],
    clients:
      (clientsResult.data ?? []).map((entry: any) => ({
        client_code: entry.client_code,
        id: entry.id,
        name: entry.name,
      })) ?? [],
  };
}

export async function getRolesPageData(gymId: string): Promise<RolesPageData> {
  const supabase = await createServerSupabaseClient();

  const [rolesResult, usersResult] = await Promise.all([
    supabase
      .from("roles")
      .select("id, name, permissions, created_at")
      .eq("gym_id", gymId)
      .order("name", { ascending: true }),
    supabase
      .from("users")
      .select("id, email, full_name, created_at, role:roles(id, name)")
      .eq("gym_id", gymId)
      .order("created_at", { ascending: false }),
  ]);

  if (rolesResult.error) throw rolesResult.error;
  if (usersResult.error) throw usersResult.error;

  const roles = (rolesResult.data as RoleRow[] | null)?.map((role) => ({
    createdAt: role.created_at,
    id: role.id,
    name: role.name,
    permissions: normalisePermissions(role.permissions),
  })) ?? [];

  const users = (usersResult.data as UserRow[] | null)?.map((user) => ({
    createdAt: user.created_at,
    email: user.email,
    fullName: user.full_name,
    id: user.id,
    roleName: user.role?.name ?? "Unassigned",
  })) ?? [];

  return { roles, users };
}

