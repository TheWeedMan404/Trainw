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
    const supabase = (await createServerSupabaseClient()) as any;
    const { error } = await supabase.from("attendance").insert({
      class_id: parsed.data.classId || null,
      client_id: parsed.data.clientId,
      gym_id: context.gymId,
      status: parsed.data.status,
    });

    if (error) {
      return { error: error.message };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to save attendance.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/attendance");

  return { success: "Attendance recorded successfully." };
}
