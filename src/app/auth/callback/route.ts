import { NextRequest, NextResponse } from "next/server";

import { getAbsoluteUrl, isSupabaseAdminConfigured } from "@/lib/env";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import { createServerSupabaseClient } from "@/lib/supabase/server";

// NX-02: the auth callback. Supabase redirects here after the user clicks
// the confirmation link (signup) or the invite link (staff invite).
//
// The workspace is provisioned ONLY here, after the email is confirmed —
// the code exchange succeeds only for a confirmed email / valid invite
// link, so this is the proof the old signup flow skipped. The provision
// runs once: if the users row already exists (link clicked twice, or the
// user was created another way) it is skipped, because
// provision_new_gym always creates a NEW gym and must never run twice for
// the same user.
//
// Depends on database/schema.sql (provision_new_gym + the users table),
// which is P1-11 territory: the migration chain does not define them yet.
// Regenerate src/types/database.ts from the live DB at deploy time.
export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const next = request.nextUrl.searchParams.get("next") ?? "/dashboard";

  if (!code) {
    return NextResponse.redirect(getAbsoluteUrl("/login"));
  }

  const supabase = await createServerSupabaseClient();
  const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);

  if (exchangeError) {
    return NextResponse.redirect(getAbsoluteUrl("/login"));
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.redirect(getAbsoluteUrl("/login"));
  }

  const gymName =
    typeof user.user_metadata?.gym_name === "string"
      ? user.user_metadata.gym_name
      : null;
  const fullName =
    typeof user.user_metadata?.full_name === "string"
      ? user.user_metadata.full_name
      : null;

  if (gymName && isSupabaseAdminConfigured()) {
    const admin = createAdminSupabaseClient();
    const { data: existingUser } = await admin
      .from("users")
      .select("id")
      .eq("id", user.id)
      .maybeSingle();

    if (!existingUser) {
      const { error: provisionError } = await admin.rpc("provision_new_gym", {
        p_email: user.email ?? "",
        p_full_name: fullName,
        p_gym_name: gymName,
        p_user_id: user.id,
      });

      if (provisionError) {
        // The account exists but the workspace did not provision — do not
        // send them into a broken dashboard; login shows the generic
        // sign-in form and the owner can retry the link.
        return NextResponse.redirect(getAbsoluteUrl("/login"));
      }
    }
  }

  const safeNext = next.startsWith("/") ? next : "/dashboard";
  return NextResponse.redirect(getAbsoluteUrl(safeNext));
}
