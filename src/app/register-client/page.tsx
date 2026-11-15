import Link from "next/link";

import { ClientRegistrationForm } from "@/components/public/client-registration-form";
import { ConfigNotice } from "@/components/ui/config-notice";
import { Card } from "@/components/ui/card";
import { isSupabaseAdminConfigured } from "@/lib/env";

export default function RegisterClientPage() {
  if (!isSupabaseAdminConfigured()) {
    return (
      <main className="flex min-h-screen items-center justify-center px-4 py-12">
        <ConfigNotice />
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-slate-100 px-4 py-12">
      <div className="mx-auto grid max-w-6xl gap-8 lg:grid-cols-[0.95fr_1.05fr]">
        <Card>
          <p className="text-sm font-medium uppercase tracking-[0.2em] text-brand-700">
            Public client intake
          </p>
          <h1 className="mt-3 text-3xl font-semibold text-slate-950">
            Register a new client
          </h1>
          <p className="mt-4 text-sm leading-7 text-slate-600">
            Clients can register independently or under an existing gym workspace.
            Gym-linked registrations search gyms by name. Every registration
            goes into the gym&apos;s approval queue — your client code is issued
            once the gym approves it.
          </p>

          <div className="mt-8 rounded-2xl bg-slate-50 p-5">
            <h2 className="text-base font-semibold text-slate-900">How it works</h2>
            <ul className="mt-4 space-y-3 text-sm text-slate-600">
              <li>1. Choose whether the client is independent or linked to a gym.</li>
              <li>2. Search for the gym by name if the client should join a workspace.</li>
              <li>3. Submit once — the gym reviews the registration and issues the client code.</li>
            </ul>
          </div>

          <p className="mt-6 text-sm text-slate-600">
            Running a gym instead?{" "}
            <Link className="font-medium text-brand-700" href="/signup">
              Create a gym workspace
            </Link>
            .
          </p>
        </Card>

        <Card>
          <ClientRegistrationForm />
        </Card>
      </div>
    </main>
  );
}
