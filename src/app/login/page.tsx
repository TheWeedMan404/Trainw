import Link from "next/link";
import { redirect } from "next/navigation";

import { LoginForm } from "@/components/auth/login-form";
import { ConfigNotice } from "@/components/ui/config-notice";
import { Card } from "@/components/ui/card";
import { isSupabaseConfigured } from "@/lib/env";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { getWorkspaceContext } from "@/lib/workspace";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ redirectTo?: string }>;
}) {
  if (!isSupabaseConfigured()) {
    return (
      <main className="flex min-h-screen items-center justify-center px-4 py-12">
        <ConfigNotice />
      </main>
    );
  }

  // NX-27: a signed-in user has no business on the sign-in form — send
  // them to the dashboard instead of showing the form again (and keep
  // the redirectTo parameter out of reach of already-signed-in users).
  // NX-28: but only when they actually HAVE a workspace — an orphaned
  // account (no users row) goes to /auth/recover instead, or /login ->
  // /dashboard -> /login would loop forever.
  const supabase = await createServerSupabaseClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) {
    redirect((await getWorkspaceContext()) ? "/dashboard" : "/auth/recover");
  }

  const params = await searchParams;

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-12">
      <Card className="w-full max-w-md">
        <p className="text-sm font-medium uppercase tracking-[0.2em] text-brand-700">
          Trainw Gym OS
        </p>
        <h1 className="mt-3 text-2xl font-semibold text-slate-950">Sign in</h1>
        <p className="mt-2 text-sm text-slate-600">
          Access your gym workspace and continue managing clients, classes, and staff.
        </p>

        <div className="mt-6">
          <LoginForm redirectTo={params.redirectTo} />
        </div>

        <p className="mt-6 text-sm text-slate-600">
          Forgot your password?{" "}
          <Link className="font-medium text-brand-700" href="/forgot-password">
            Reset it here
          </Link>
          .
        </p>

        <p className="mt-6 text-sm text-slate-600">
          Need a new gym workspace?{" "}
          <Link className="font-medium text-brand-700" href="/signup">
            Create one here
          </Link>
          .
        </p>
      </Card>
    </main>
  );
}
