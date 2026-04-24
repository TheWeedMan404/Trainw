"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { type FormState, getErrorMessage } from "@/actions/shared";
import { PERMISSIONS } from "@/lib/permissions";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/workspace";

const createClientSchema = z.object({
  name: z.string().min(2),
  type: z.enum(["gym", "individual"]),
});

export async function createWorkspaceClientAction(
  _previousState: FormState,
  formData: FormData,
): Promise<FormState> {
  const context = await requirePermission(PERMISSIONS.clientsManage);
  const parsed = createClientSchema.safeParse({
    name: formData.get("name"),
    type: formData.get("type"),
  });

  if (!parsed.success) {
    return { error: "Enter a client name and choose the client type." };
  }

  try {
    const supabase = (await createServerSupabaseClient()) as any;
    const { error } = await supabase.from("clients").insert({
      gym_id: context.gymId,
      name: parsed.data.name,
      type: parsed.data.type,
    });

    if (error) {
      return { error: error.message };
    }
  } catch (error) {
    return { error: getErrorMessage(error, "Unable to create the client.") };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/clients");
  revalidatePath("/dashboard/classes");

  return { success: "Client created successfully." };
}
