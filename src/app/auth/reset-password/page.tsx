import Link from "next/link";

import { ResetPasswordForm } from "@/components/auth/reset-password-form";
import { ConfigNotice } from "@/components/ui/config-notice";
import { Card } from "@/components/ui/card";
import { isSupabaseConfigured } from "@/lib/env";
import { createServerSupabaseClient } from "@/lib/supabase/server";

// NX-14: the reset-link landing page. Supabase redirects here with a
// `code` (PKCE); exchanging it signs the user in for this request, and
// the form then sets the new password via updateUser. Without a valid
// code the link is expired or already used — the user requests a new one.
export default async function ResetPasswordPage({
  searchParams,
}: {
  searchParams: Promise<{ code?: string }>;
}) {
  if (!isSupabaseConfigured()) {
    return (
      <main className="flex min-h-screen items-center justify-center px-4 py-12">
        <ConfigNotice />
      </main>
    );
  }

  const params = await searchParams;
  let codeValid = false;

  if (params.code) {
    const supabase = await createServerSupabaseClient();
    const { error } = await supabase.auth.exchangeCodeForSession(params.code);
    codeValid = !error;
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-12">
      <Card className="w-full max-w-md">
        <p className="text-sm font-medium uppercase tracking-[0.2em] text-brand-700">
          Trainw Gym OS
        </p>
        <h1 className="mt-3 text-2xl font-semibold text-slate-950">
          Choose a new password
        </h1>

        {codeValid ? (
          <>
            <p className="mt-2 text-sm text-slate-600">
              Your reset link is valid. Pick a new password below.
            </p>
            <div className="mt-6">
              <ResetPasswordForm />
            </div>
          </>
        ) : (
          <>
            <p className="mt-2 text-sm text-slate-600">
              This reset link is invalid or has expired. Reset links can only
              be used once.
            </p>
            <p className="mt-6 text-sm text-slate-600">
              <Link className="font-medium text-brand-700" href="/forgot-password">
                Request a new reset link
              </Link>
            </p>
          </>
        )}
      </Card>
    </main>
  );
}
