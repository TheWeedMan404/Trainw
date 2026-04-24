import Link from "next/link";
import {
  BookOpen,
  CalendarCheck,
  LayoutDashboard,
  LogOut,
  ShieldCheck,
  UserSquare2,
  Users,
} from "lucide-react";

import { logoutAction } from "@/actions/auth";
import { Button } from "@/components/ui/button";
import { hasPermission, PERMISSIONS } from "@/lib/permissions";
import type { WorkspaceContext } from "@/lib/workspace";

const NAV_ITEMS = [
  {
    href: "/dashboard",
    icon: LayoutDashboard,
    label: "Overview",
    permission: PERMISSIONS.dashboardView,
  },
  {
    href: "/dashboard/clients",
    icon: Users,
    label: "Clients",
    permission: PERMISSIONS.clientsManage,
  },
  {
    href: "/dashboard/coaches",
    icon: UserSquare2,
    label: "Coaches",
    permission: PERMISSIONS.coachesManage,
  },
  {
    href: "/dashboard/classes",
    icon: BookOpen,
    label: "Classes",
    permission: PERMISSIONS.classesManage,
  },
  {
    href: "/dashboard/attendance",
    icon: CalendarCheck,
    label: "Attendance",
    permission: PERMISSIONS.attendanceManage,
  },
  {
    href: "/dashboard/roles",
    icon: ShieldCheck,
    label: "Roles",
    permission: PERMISSIONS.rolesManage,
  },
];

export function AppShell({
  children,
  context,
}: {
  children: React.ReactNode;
  context: WorkspaceContext;
}) {
  const navigation = NAV_ITEMS.filter((item) =>
    hasPermission(context.permissions, item.permission),
  );

  return (
    <div className="min-h-screen bg-slate-100">
      <div className="mx-auto flex max-w-7xl flex-col gap-6 px-4 py-6 lg:flex-row">
        <aside className="rounded-3xl border border-slate-200 bg-white p-6 shadow-soft lg:w-80">
          <div>
            <p className="text-sm font-medium uppercase tracking-[0.2em] text-brand-700">
              Trainw Gym OS
            </p>
            <h1 className="mt-3 text-xl font-semibold text-slate-950">
              {context.gymName}
            </h1>
            <p className="mt-1 text-sm text-slate-600">
              Signed in as {context.fullName || context.email}
            </p>
            <div className="mt-4 inline-flex rounded-full bg-brand-100 px-3 py-1 text-xs font-medium text-brand-800">
              {context.roleName}
            </div>
          </div>

          <nav className="mt-8 space-y-2">
            {navigation.map((item) => {
              const Icon = item.icon;

              return (
                <Link
                  className="flex items-center gap-3 rounded-2xl px-4 py-3 text-sm font-medium text-slate-700 hover:bg-slate-50 hover:text-slate-950"
                  href={item.href}
                  key={item.href}
                >
                  <Icon className="h-4 w-4" />
                  {item.label}
                </Link>
              );
            })}
          </nav>

          <form action={logoutAction} className="mt-8">
            <Button className="w-full justify-center gap-2" variant="ghost">
              <LogOut className="h-4 w-4" />
              Sign out
            </Button>
          </form>
        </aside>

        <main className="min-w-0 flex-1">{children}</main>
      </div>
    </div>
  );
}
