import { ClassEnrollmentForm } from "@/components/forms/class-enrollment-form";
import { ClassForm } from "@/components/forms/class-form";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeader } from "@/components/ui/page-header";
import { StatusBadge } from "@/components/ui/status-badge";
import { PERMISSIONS } from "@/lib/permissions";
import { getClassesPageData } from "@/lib/queries";
import { formatDateTime } from "@/lib/utils";
import { requirePermission } from "@/lib/workspace";

export default async function ClassesPage() {
  const context = await requirePermission(PERMISSIONS.classesManage);
  const { classes, clients, coaches } = await getClassesPageData(context.gymId);

  return (
    <div className="space-y-6">
      <PageHeader
        description="Create classes, assign coaches, and manage enrollments with graceful capacity handling."
        title="Classes"
      />

      <div className="grid gap-6 xl:grid-cols-[0.85fr_1.15fr]">
        <Card>
          <h2 className="text-lg font-semibold text-slate-950">Create class</h2>
          <p className="mt-2 text-sm text-slate-600">
            Capacity is optional. Leave it blank for unlimited enrollment.
          </p>
          <div className="mt-6">
            <ClassForm coaches={coaches} />
          </div>
        </Card>

        <div className="space-y-4">
          {classes.length ? (
            classes.map((gymClass) => (
              <Card key={gymClass.id}>
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <h2 className="text-lg font-semibold text-slate-950">{gymClass.name}</h2>
                    <p className="mt-1 text-sm text-slate-600">
                      Coach: {gymClass.coachName}
                    </p>
                    <p className="mt-1 text-xs text-slate-500">
                      Created {formatDateTime(gymClass.createdAt)}
                    </p>
                  </div>

                  <div className="space-y-2 text-right">
                    <StatusBadge label={gymClass.type} />
                    <p className="text-xs text-slate-500">
                      Capacity: {gymClass.capacity ?? "Unlimited"}
                    </p>
                  </div>
                </div>

                <div className="mt-6">
                  <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">
                    Enrolled clients
                  </h3>
                  <div className="mt-3 flex flex-wrap gap-2">
                    {gymClass.enrollments.length ? (
                      gymClass.enrollments.map((client) => (
                        <div
                          className="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-700"
                          key={client.id}
                        >
                          {client.clientName} ({client.clientCode})
                        </div>
                      ))
                    ) : (
                      <p className="text-sm text-slate-500">No clients enrolled yet.</p>
                    )}
                  </div>
                </div>

                <div className="mt-6">
                  <ClassEnrollmentForm classId={gymClass.id} clients={clients} />
                </div>
              </Card>
            ))
          ) : (
            <Card>
              <EmptyState
                description="Create your first class, assign a coach, then start adding clients."
                title="No classes yet"
              />
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}
