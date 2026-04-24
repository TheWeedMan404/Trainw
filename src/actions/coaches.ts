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
      return Number.isNaN(parsed) ? null : parsed;
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
    const supabase = (await createServerSupabaseClient()) as any;
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
