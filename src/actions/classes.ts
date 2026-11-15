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
    }),
  coachId: z.string().uuid(),
  name: z.string().min(2),
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
    const supabase = (await createServerSupabaseClient()) as any;

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
      return { error: error.message };
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
    const supabase = (await createServerSupabaseClient()) as any;

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

      return { error: error.message };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to enroll the client.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/classes");

  return { success: "Client added to class successfully." };
}
