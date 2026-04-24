import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";

import { isSupabaseAdminConfigured } from "@/lib/env";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";

const registerClientSchema = z.object({
  gymId: z.string().uuid().nullable(),
  name: z.string().min(2),
  type: z.enum(["gym", "individual"]),
});

export async function POST(request: NextRequest) {
  if (!isSupabaseAdminConfigured()) {
    return NextResponse.json(
      { error: "Supabase admin environment variables are not configured." },
      { status: 503 },
    );
  }

  const payload = registerClientSchema.safeParse(await request.json());

  if (!payload.success) {
    return NextResponse.json(
      { error: "Please provide a valid client name and registration type." },
      { status: 400 },
    );
  }

  if (payload.data.type === "gym" && !payload.data.gymId) {
    return NextResponse.json(
      { error: "Gym-linked clients must select a gym." },
      { status: 400 },
    );
  }

  const admin = createAdminSupabaseClient();

  let gymName: string | null = null;

  if (payload.data.gymId) {
    const { data: gym, error: gymError } = await admin
      .from("gyms")
      .select("id, name")
      .eq("id", payload.data.gymId)
      .maybeSingle();

    if (gymError || !gym) {
      return NextResponse.json({ error: "Selected gym was not found." }, { status: 404 });
    }

    gymName = gym.name;
  }

  const { data, error } = await admin
    .from("clients")
    .insert({
      gym_id: payload.data.gymId,
      name: payload.data.name,
      type: payload.data.type,
    })
    .select("client_code")
    .single();

  if (error || !data) {
    return NextResponse.json(
      { error: error?.message || "Unable to create the client registration." },
      { status: 500 },
    );
  }

  return NextResponse.json({
    clientCode: data.client_code,
    gymName,
    message: "Client registered successfully.",
  });
}
