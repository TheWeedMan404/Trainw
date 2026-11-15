import Link from "next/link";

import { Card } from "@/components/ui/card";

// NX-18: the access-denied page. It deliberately requires no permission
// and loads no workspace data — requirePermission sends denied users
// here, so gating this page would recreate the redirect loop it exists
// to fix. A signed-in user who lands here has a role without the
// permission for the area they tried to open; the gym owner can change
// their role in the dashboard.
export default function ForbiddenPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-12">
      <Card className="w-full max-w-md">
        <p className="text-sm font-medium uppercase tracking-[0.2em] text-brand-700">
          Trainw Gym OS
        </p>
        <h1 className="mt-3 text-2xl font-semibold text-slate-950">
          You don&apos;t have access to that area
        </h1>
        <p className="mt-2 text-sm text-slate-600">
          Your role doesn&apos;t include the permission for the page you tried
          to open. Ask your gym owner to update your role, or sign in with a
          different account.
        </p>

        <p className="mt-6 text-sm text-slate-600">
          <Link className="font-medium text-brand-700" href="/login">
            Back to sign in
          </Link>
        </p>
      </Card>
    </main>
  );
}
