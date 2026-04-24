import { AppShell } from "@/components/dashboard/app-shell";
import { ConfigNotice } from "@/components/ui/config-notice";
import { isSupabaseConfigured } from "@/lib/env";
import { requireWorkspaceContext } from "@/lib/workspace";

export const dynamic = "force-dynamic";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  if (!isSupabaseConfigured()) {
    return (
      <main className="flex min-h-screen items-center justify-center px-4 py-12">
        <ConfigNotice />
      </main>
    );
  }

  const context = await requireWorkspaceContext();

  return <AppShell context={context}>{children}</AppShell>;
}
