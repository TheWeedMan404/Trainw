import Link from "next/link";

import { SignupForm } from "@/components/auth/signup-form";
import { ConfigNotice } from "@/components/ui/config-notice";
import { Card } from "@/components/ui/card";
import { isSupabaseAdminConfigured } from "@/lib/env";

export default function SignupPage() {
  if (!isSupabaseAdminConfigured()) {
    return (
      <main className="flex min-h-screen items-center justify-center px-4 py-12">
        <ConfigNotice />
      </main>
    );
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-12">
      <Card className="w-full max-w-lg">
        <p className="text-sm font-medium uppercase tracking-[0.2em] text-brand-700">
          Trainw Gym OS
        </p>
        <h1 className="mt-3 text-2xl font-semibold text-slate-950">
          Create a gym workspace
        </h1>
        <p className="mt-2 text-sm text-slate-600">
          This creates the gym, default roles, and the first admin user in one flow.
        </p>

        <div className="mt-6">
          <SignupForm />
        </div>

        <p className="mt-6 text-sm text-slate-600">
          Already have an account?{" "}
          <Link className="font-medium text-brand-700" href="/login">
            Sign in
          </Link>
          .
        </p>
      </Card>
    </main>
  );
}
