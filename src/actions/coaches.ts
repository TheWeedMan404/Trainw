"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { type FormState, getErrorMessage } from "@/actions/shared";
import { PERMISSIONS } from "@/lib/permissions";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/workspace";

const createCoachSchema = z.object({
  name: z.string().min(2),
  rating: z
    .union([z.string().length(0), z.string()])
    .optional()
    .transform((value) => {
      if (!value) return null;

      const parsed = Number(value);
      if (Number.isNaN(parsed)) return null;

      // NX-16: a coach rating is a 0–5 value by definition. Clamp
      // server-side so a crafted request cannot store an out-of-range
      // rating that the dashboard (or a future public display) renders.
      return Math.max(0, Math.min(5, parsed));
    }),
});

export async function createCoachAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.coachesManage);
  const parsed = createCoachSchema.safeParse({
    name: formData.get("name"),
    rating: formData.get("rating"),
  });

  if (!parsed.success) {
    return { error: "Enter a coach name. Rating is optional." };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const { error } = await supabase.from("coaches").insert({
      gym_id: context.gymId,
      name: parsed.data.name,
      rating: parsed.data.rating,
    });

    if (error) {
      return { error: error.message };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to create the coach.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/coaches");
  revalidatePath("/dashboard/classes");

  return { success: "Coach created successfully." };
}



const updateCoachSchema = z.object({
  coachId: z.string().uuid(),
  name: z.string().min(2).max(100),
  rating: z
    .union([z.string().length(0), z.string()])
    .optional()
    .transform((value) => {
      if (!value) return null;

      const parsed = Number(value);
      if (Number.isNaN(parsed)) return null;

      // NX-16: same 0–5 clamp as the create form.
      return Math.max(0, Math.min(5, parsed));
    }),
});

// NX-10: edit a coach (name and optional rating). Gym-scoped.
export async function updateCoachAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.coachesManage);
  const parsed = updateCoachSchema.safeParse({
    coachId: formData.get("coachId"),
    name: formData.get("name"),
    rating: formData.get("rating"),
  });

  if (!parsed.success) {
    return { error: "Enter a coach name. Rating is optional." };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const { data, error } = await supabase
      .from("coaches")
      .update({ name: parsed.data.name, rating: parsed.data.rating })
      .eq("id", parsed.data.coachId)
      .eq("gym_id", context.gymId)
      .select("id")
      .maybeSingle();

    if (error) {
      return { error: error.message };
    }
    if (!data) {
      return { error: "That coach no longer exists in your workspace." };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to update the coach.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/coaches");
  revalidatePath("/dashboard/classes");

  return { success: "Coach updated." };
}

const deleteCoachSchema = z.object({
  coachId: z.string().uuid(),
});

// NX-10: delete a coach. Gym-scoped. Classes reference their coach with
// ON DELETE RESTRICT, so a coach who still has classes cannot be deleted
// — the error says so instead of failing silently.
export async function deleteCoachAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.coachesManage);
  const parsed = deleteCoachSchema.safeParse({
    coachId: formData.get("coachId"),
  });

  if (!parsed.success) {
    return { error: "No coach was selected." };
  }

  try {
    const supabase = await createServerSupabaseClient();
    const { error } = await supabase
      .from("coaches")
      .delete()
      .eq("id", parsed.data.coachId)
      .eq("gym_id", context.gymId);

    if (error) {
      const message = error.message.toLowerCase();
      if (
        message.includes("violates foreign key") ||
        message.includes("restrict") ||
        message.includes("still referenced")
      ) {
        return {
          error:
            "This coach still has classes. Reassign or delete those classes first.",
        };
      }
      return { error: error.message };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to delete the coach.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/coaches");
  revalidatePath("/dashboard/classes");

  return { success: "Coach deleted." };
}
