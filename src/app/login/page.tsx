import Link from "next/link";

import { LoginForm } from "@/components/auth/login-form";
import { ConfigNotice } from "@/components/ui/config-notice";
import { Card } from "@/components/ui/card";
import { isSupabaseConfigured } from "@/lib/env";

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
