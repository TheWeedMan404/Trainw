import Link from "next/link";

import { ForgotPasswordForm } from "@/components/auth/forgot-password-form";
import { ConfigNotice } from "@/components/ui/config-notice";
import { Card } from "@/components/ui/card";
import { isSupabaseConfigured } from "@/lib/env";

// NX-14: request a password-reset email.
export default async function ForgotPasswordPage() {
  if (!isSupabaseConfigured()) {
    return (
      <main className="flex min-h-screen items-center justify-center px-4 py-12">
        <ConfigNotice />
      </main>
    );
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-12">
      <Card className="w-full max-w-md">
        <p className="text-sm font-medium uppercase tracking-[0.2em] text-brand-700">
          Trainw Gym OS
        </p>
        <h1 className="mt-3 text-2xl font-semibold text-slate-950">
          Reset your password
        </h1>
        <p className="mt-2 text-sm text-slate-600">
          Enter the email you signed up with and we will send you a link to
          choose a new password.
        </p>

        <div className="mt-6">
          <ForgotPasswordForm />
        </div>

        <p className="mt-6 text-sm text-slate-600">
          Remembered it?{" "}
          <Link className="font-medium text-brand-700" href="/login">
            Back to sign in
          </Link>
          .
        </p>
      </Card>
    </main>
  );
}
