import { redirect } from "next/navigation";

import { RecoverWorkspaceForm } from "@/components/auth/recover-workspace-form";
import { ConfigNotice } from "@/components/ui/config-notice";
import { Card } from "@/components/ui/card";
import { isSupabaseConfigured } from "@/lib/env";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { getWorkspaceContext } from "@/lib/workspace";

// NX-28: the orphan-recovery page. A signed-in user with no workspace
// row (signup died between auth-user creation and provisioning, or the
// /auth/callback RPC failed) used to be bounced to /login forever with
// no way out. This page detects that state and offers the two exits:
// re-run provisioning, or delete the account. Users who DO have a
// workspace never see it.
export default async function RecoverPage() {
  if (!isSupabaseConfigured()) {
    return (
      <main className="flex min-h-screen items-center justify-center px-4 py-12">
        <ConfigNotice />
      </main>
    );
  }

  const supabase = await createServerSupabaseClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  if (await getWorkspaceContext()) {
    redirect("/dashboard");
  }

  const gymName =
    typeof user.user_metadata?.gym_name === "string"
      ? user.user_metadata.gym_name
      : undefined;
  const fullName =
    typeof user.user_metadata?.full_name === "string"
      ? user.user_metadata.full_name
      : undefined;

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-12">
      <Card className="w-full max-w-md">
        <p className="text-sm font-medium uppercase tracking-[0.2em] text-brand-700">
          Trainw Gym OS
        </p>
        <h1 className="mt-3 text-2xl font-semibold text-slate-950">
          Finish setting up your workspace
        </h1>
        <p className="mt-2 text-sm text-slate-600">
          Your account was created, but your gym workspace wasn&apos;t — the
          setup stopped halfway. Enter your gym name below and we&apos;ll
          create it now.
        </p>

        <div className="mt-6">
          <RecoverWorkspaceForm
            defaultFullName={fullName}
            defaultGymName={gymName}
          />
        </div>
      </Card>
    </main>
  );
}
