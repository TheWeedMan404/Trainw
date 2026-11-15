import { StaffUserForm } from "@/components/forms/staff-user-form";
import { RoleRowActions } from "@/components/forms/role-row-actions";
import { StaffUserRowActions } from "@/components/forms/staff-user-row-actions";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeader } from "@/components/ui/page-header";
import { Pagination } from "@/components/ui/pagination";
import { StatusBadge } from "@/components/ui/status-badge";
import { PERMISSIONS } from "@/lib/permissions";
import { getRolesPageData } from "@/lib/queries";
import { parsePageParam } from "@/lib/pagination";
import { formatDateTime } from "@/lib/utils";
import { requirePermission } from "@/lib/workspace";

export default async function RolesPage({ searchParams }: { searchParams: Promise<{ page?: string }> }) {
  const context = await requirePermission(PERMISSIONS.rolesManage);
  const params = await searchParams;
  const page = parsePageParam(params.page);
  const { hasMore, roles, users } = await getRolesPageData(context.gymId, page);

  return (
    <div className="space-y-6">
      <PageHeader
        description="Manage predefined role permissions and create staff logins for this gym."
        title="Roles and staff"
      />

      <div className="grid gap-6 xl:grid-cols-[0.85fr_1.15fr]">
        <Card>
          <h2 className="text-lg font-semibold text-slate-950">Create staff user</h2>
          <p className="mt-2 text-sm text-slate-600">
            Each staff member gets a Supabase login and one workspace role.
          </p>
          <div className="mt-6">
            <StaffUserForm roles={roles.map((role) => ({ id: role.id, name: role.name }))} />
          </div>
        </Card>

        <div className="space-y-6">
          <Card>
            <h2 className="text-lg font-semibold text-slate-950">Predefined roles</h2>
            <div className="mt-4 grid gap-4 md:grid-cols-2">
              {roles.map((role) => (
                <div
                  className="rounded-2xl border border-slate-200 p-4"
                  key={role.id}
                >
                  <div className="flex items-center justify-between gap-3">
                    <h3 className="font-semibold text-slate-950">{role.name}</h3>
                    <StatusBadge label={role.name} />
                  </div>
                  <div className="mt-4 flex flex-wrap gap-2">
                    {Object.entries(role.permissions)
                      .filter(([, enabled]) => enabled)
                      .map(([permission]) => (
                        <span
                          className="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-700"
                          key={permission}
                        >
                          {permission}
                        </span>
                      ))}
                  </div>
                  <div className="mt-4 flex justify-end">
                    <RoleRowActions roleId={role.id} />
                  </div>
                </div>
              ))}
            </div>
          </Card>

          <Card>
            <h2 className="text-lg font-semibold text-slate-950">Workspace users</h2>
            <div className="mt-4 space-y-3">
              {users.length ? (
                users.map((user) => (
                  <div
                    className="flex items-start justify-between gap-4 rounded-2xl border border-slate-200 p-4"
                    key={user.id}
                  >
                    <div>
                      <p className="font-medium text-slate-950">
                        {user.fullName || user.email}
                        {user.banned ? " (deactivated)" : ""}
                      </p>
                      <p className="mt-1 text-sm text-slate-600">{user.email}</p>
                      <p className="mt-1 text-xs text-slate-500">
                        Created {formatDateTime(user.createdAt)}
                      </p>
                    </div>
                    <div className="flex flex-col items-end gap-2">
                      <StatusBadge label={user.roleName} />
                      <StaffUserRowActions
                        banned={user.banned}
                        isSelf={user.id === context.userId}
                        userId={user.id}
                      />
                    </div>
                  </div>
                ))
              ) : (
                <EmptyState
                  description="Create the first non-owner staff user to delegate work."
                  title="No staff users yet"
                />
              )}
            </div>
            <Pagination hasMore={hasMore} page={page} />
          </Card>
        </div>
      </div>
    </div>
  );
}
