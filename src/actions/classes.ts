"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { type FormState, getErrorMessage } from "@/actions/shared";
import { PERMISSIONS } from "@/lib/permissions";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/workspace";

const createClassSchema = z.object({
  capacity: z
    .union([z.string().length(0), z.string()])
    .transform((value) => {
      if (!value) return null;

      const parsed = Number(value);
      return Number.isNaN(parsed) ? null : parsed;
    })
    // NX-16 (round 6): capacity must be a whole number >= 1 when given.
    // The old schema accepted 0, negatives and fractions and left the
    // rejection to a DB CHECK that exists only for sessions, not classes.
    .refine((value) => value === null || (Number.isInteger(value) && value >= 1), {
      message: "Capacity must be a whole number of at least 1.",
    }),
  coachId: z.string().uuid(),
  name: z.string().min(2).max(100),
  type: z.enum(["private", "group", "supervising"]),
});

const enrollSchema = z.object({
  classId: z.string().uuid(),
  clientId: z.string().uuid(),
});

export async function createClassAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.classesManage);
  const parsed = createClassSchema.safeParse({
    capacity: formData.get("capacity"),
    coachId: formData.get("coachId"),
    name: formData.get("name"),
    type: formData.get("type"),
  });

  if (!parsed.success) {
    return { error: "Enter the class name, coach, and type." };
  }

  try {
    const supabase = await createServerSupabaseClient();

    // NX-04: the coach must belong to the caller's gym — otherwise a
    // caller could attach another gym's coach to their class.
    const { data: coach, error: coachError } = await supabase
      .from("coaches")
      .select("id")
      .eq("id", parsed.data.coachId)
      .eq("gym_id", context.gymId)
      .maybeSingle();

    if (coachError || !coach) {
      return { error: "The selected coach does not belong to your workspace." };
    }

    const { error } = await supabase.from("classes").insert({
      capacity: parsed.data.capacity,
      coach_id: parsed.data.coachId,
      gym_id: context.gymId,
      name: parsed.data.name,
      type: parsed.data.type,
    });

    if (error) {
      return { error: getErrorMessage(error, "Unable to create the class.") };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to create the class.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/classes");

  return { success: "Class created successfully." };
}

export async function enrollClientInClassAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.classesManage);
  const parsed = enrollSchema.safeParse({
    classId: formData.get("classId"),
    clientId: formData.get("clientId"),
  });

  if (!parsed.success) {
    return { error: "Pick both a class and a client." };
  }

  try {
    const supabase = await createServerSupabaseClient();

    // NX-04: both the class and the client must belong to the caller's
    // gym. (Individual-type clients have gym_id NULL, so they cannot be
    // enrolled here — the class form only lists this gym's clients, and
    // an individual client must be added to the gym first.)
    const [classResult, clientResult] = await Promise.all([
      supabase
        .from("classes")
        .select("id")
        .eq("id", parsed.data.classId)
        .eq("gym_id", context.gymId)
        .maybeSingle(),
      supabase
        .from("clients")
        .select("id")
        .eq("id", parsed.data.clientId)
        .eq("gym_id", context.gymId)
        .maybeSingle(),
    ]);

    if (classResult.error || !classResult.data) {
      return { error: "The selected class does not belong to your workspace." };
    }
    if (clientResult.error || !clientResult.data) {
      return { error: "The selected client does not belong to your workspace." };
    }

    const { error } = await supabase.from("class_clients").insert({
      class_id: parsed.data.classId,
      client_id: parsed.data.clientId,
    });

    if (error) {
      if (error.message.toLowerCase().includes("capacity")) {
        return {
          error: "This class has reached its capacity. Increase the capacity or pick a different class.",
        };
      }

      return { error: getErrorMessage(error, "Unable to enroll the client.") };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to enroll the client.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/classes");

  return { success: "Client added to class successfully." };
}

const updateClassSchema = z.object({
  capacity: z
    .union([z.string().length(0), z.string()])
    .transform((value) => {
      if (!value) return null;

      const parsed = Number(value);
      return Number.isNaN(parsed) ? null : parsed;
    })
    // NX-16 (round 6): same bound as createClassSchema — whole number >= 1.
    .refine((value) => value === null || (Number.isInteger(value) && value >= 1), {
      message: "Capacity must be a whole number of at least 1.",
    }),
  classId: z.string().uuid(),
  coachId: z.string().uuid(),
  name: z.string().min(2).max(100),
  type: z.enum(["private", "group", "supervising"]),
});

// NX-10: edit a class (name, type, capacity, coach). Gym-scoped, with the
// NX-04 coach-belongs-to-gym check.
export async function updateClassAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.classesManage);
  const parsed = updateClassSchema.safeParse({
    capacity: formData.get("capacity"),
    classId: formData.get("classId"),
    coachId: formData.get("coachId"),
    name: formData.get("name"),
    type: formData.get("type"),
  });

  if (!parsed.success) {
    return { error: "Enter the class name, coach, and type." };
  }

  try {
    const supabase = await createServerSupabaseClient();

    const { data: coach, error: coachError } = await supabase
      .from("coaches")
      .select("id")
      .eq("id", parsed.data.coachId)
      .eq("gym_id", context.gymId)
      .maybeSingle();

    if (coachError || !coach) {
      return { error: "The selected coach does not belong to your workspace." };
    }

    const { data, error } = await supabase
      .from("classes")
      .update({
        capacity: parsed.data.capacity,
        coach_id: parsed.data.coachId,
        name: parsed.data.name,
        type: parsed.data.type,
      })
      .eq("id", parsed.data.classId)
      .eq("gym_id", context.gymId)
      .select("id")
      .maybeSingle();

    if (error) {
      return { error: getErrorMessage(error, "Unable to update the class.") };
    }
    if (!data) {
      return { error: "That class no longer exists in your workspace." };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to update the class.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/classes");

  return { success: "Class updated." };
}

const deleteClassSchema = z.object({
  classId: z.string().uuid(),
});

// NX-10: delete a class. Gym-scoped. Enrollments cascade (class_clients
// has ON DELETE CASCADE); attendance rows keep the class reference as
// NULL (attendance.class_id is ON DELETE SET NULL).
export async function deleteClassAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.classesManage);
  const parsed = deleteClassSchema.safeParse({
    classId: formData.get("classId"),
  });

  if (!parsed.success) {
    return { error: "No class was selected." };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const { error } = await supabase
      .from("classes")
      .delete()
      .eq("id", parsed.data.classId)
      .eq("gym_id", context.gymId);

    if (error) {
      return { error: getErrorMessage(error, "Unable to delete the class.") };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to delete the class.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/classes");

  return { success: "Class deleted." };
}

// NX-10: remove one client from a class. The class must belong to the
// caller's gym; the enrollment row is deleted (class_clients has no
// status column to soft-delete into).
export async function unenrollClientFromClassAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.classesManage);
  const parsed = enrollSchema.safeParse({
    classId: formData.get("classId"),
    clientId: formData.get("clientId"),
  });

  if (!parsed.success) {
    return { error: "Pick both a class and a client." };
  }

  try {
    const supabase = await createServerSupabaseClient();

    const { data: gymClass, error: classError } = await supabase
      .from("classes")
      .select("id")
      .eq("id", parsed.data.classId)
      .eq("gym_id", context.gymId)
      .maybeSingle();

    if (classError || !gymClass) {
      return { error: "The selected class does not belong to your workspace." };
    }

    const { error } = await supabase
      .from("class_clients")
      .delete()
      .eq("class_id", parsed.data.classId)
      .eq("client_id", parsed.data.clientId);

    if (error) {
      return { error: getErrorMessage(error, "Unable to remove the client.") };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to remove the client.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/classes");

  return { success: "Client removed from the class." };
}
