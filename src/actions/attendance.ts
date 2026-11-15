"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { type FormState, getErrorMessage } from "@/actions/shared";
import { PERMISSIONS } from "@/lib/permissions";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/workspace";

const createAttendanceSchema = z.object({
  classId: z.union([z.string().length(0), z.string().uuid()]).optional(),
  clientId: z.string().uuid(),
  status: z.enum(["checked_in", "late", "missed", "excused"]),
});

export async function createAttendanceAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.attendanceManage);
  const parsed = createAttendanceSchema.safeParse({
    classId: formData.get("classId"),
    clientId: formData.get("clientId"),
    status: formData.get("status"),
  });

  if (!parsed.success) {
    return { error: "Choose a client and attendance status." };
  }

  try {
    const supabase = await createServerSupabaseClient();

    // NX-04: the client (and the class, when given) must belong to the
    // caller's gym. Individual-type clients have gym_id NULL, so they
    // cannot be recorded here — the attendance form only lists this gym's
    // clients.
    const { data: client, error: clientError } = await supabase
      .from("clients")
      .select("id")
      .eq("id", parsed.data.clientId)
      .eq("gym_id", context.gymId)
      .maybeSingle();

    if (clientError || !client) {
      return { error: "The selected client does not belong to your workspace." };
    }

    if (parsed.data.classId) {
      const { data: gymClass, error: classError } = await supabase
        .from("classes")
        .select("id")
        .eq("id", parsed.data.classId)
        .eq("gym_id", context.gymId)
        .maybeSingle();

      if (classError || !gymClass) {
        return { error: "The selected class does not belong to your workspace." };
      }
    }

    const { error } = await supabase.from("attendance").insert({
      class_id: parsed.data.classId || null,
      client_id: parsed.data.clientId,
      gym_id: context.gymId,
      status: parsed.data.status,
    });

    if (error) {
      return { error: getErrorMessage(error, "Unable to save attendance.") };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to save attendance.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/attendance");

  return { success: "Attendance recorded successfully." };
}

const updateAttendanceSchema = z.object({
  attendanceId: z.string().uuid(),
  classId: z.union([z.string().length(0), z.string().uuid()]).optional(),
  status: z.enum(["checked_in", "late", "missed", "excused"]),
});

// NX-10: correct an attendance record (status and optional class). The
// row must belong to the caller's gym, and the new class (when given)
// must too — the same NX-04 scoping as the create form.
export async function updateAttendanceAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.attendanceManage);
  const parsed = updateAttendanceSchema.safeParse({
    attendanceId: formData.get("attendanceId"),
    classId: formData.get("classId"),
    status: formData.get("status"),
  });

  if (!parsed.success) {
    return { error: "Choose an attendance status." };
  }

  try {
    const supabase = await createServerSupabaseClient();

    if (parsed.data.classId) {
      const { data: gymClass, error: classError } = await supabase
        .from("classes")
        .select("id")
        .eq("id", parsed.data.classId)
        .eq("gym_id", context.gymId)
        .maybeSingle();

      if (classError || !gymClass) {
        return { error: "The selected class does not belong to your workspace." };
      }
    }

    const { data, error } = await supabase
      .from("attendance")
      .update({
        class_id: parsed.data.classId || null,
        status: parsed.data.status,
      })
      .eq("id", parsed.data.attendanceId)
      .eq("gym_id", context.gymId)
      .select("id")
      .maybeSingle();

    if (error) {
      return { error: getErrorMessage(error, "Unable to update attendance.") };
    }
    if (!data) {
      return { error: "That attendance record no longer exists in your workspace." };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to update attendance.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/attendance");

  return { success: "Attendance updated." };
}

const deleteAttendanceSchema = z.object({
  attendanceId: z.string().uuid(),
});

// NX-10: delete an attendance record (e.g. a duplicate manual check-in —
// see NX-13, attendance has no unique constraint, so duplicates happen).
// Gym-scoped.
export async function deleteAttendanceAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.attendanceManage);
  const parsed = deleteAttendanceSchema.safeParse({
    attendanceId: formData.get("attendanceId"),
  });

  if (!parsed.success) {
    return { error: "No attendance record was selected." };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const { error } = await supabase
      .from("attendance")
      .delete()
      .eq("id", parsed.data.attendanceId)
      .eq("gym_id", context.gymId);

    if (error) {
      return { error: getErrorMessage(error, "Unable to delete attendance.") };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to delete attendance.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/attendance");

  return { success: "Attendance deleted." };
}
