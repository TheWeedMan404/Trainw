import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { StatusBadge } from "@/components/ui/status-badge";
import { PERMISSIONS } from "@/lib/permissions";
import { getDashboardMetrics } from "@/lib/queries";
import { formatDateTime } from "@/lib/utils";
import { requirePermission } from "@/lib/workspace";

const METRIC_LABELS = [
  { key: "clients", label: "Clients" },
  { key: "coaches", label: "Coaches" },
  { key: "classes", label: "Classes" },
  { key: "attendanceToday", label: "Attendance today" },
] as const;

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: Promise<{ forbidden?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.dashboardView);
  const metrics = await getDashboardMetrics(context.gymId);
  const params = await searchParams;

  return (
    <div className="space-y-6">
      <PageHeader
        description="Daily gym visibility across staff, people, classes, and attendance."
        title="Gym overview"
      />

      {params.forbidden ? (
        <Card className="border-amber-200 bg-amber-50">
          <p className="text-sm font-medium text-amber-900">
            Your role does not have permission to access that area.
          </p>
        </Card>
      ) : null}

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        {METRIC_LABELS.map((metric) => (
          <Card key={metric.key}>
            <p className="text-sm text-slate-500">{metric.label}</p>
            <p className="mt-3 text-3xl font-semibold text-slate-950">
              {metrics[metric.key]}
            </p>
          </Card>
        ))}
      </div>

      <div className="grid gap-6 xl:grid-cols-2">
        <Card>
          <h2 className="text-lg font-semibold text-slate-950">Recently created classes</h2>
          <div className="mt-4 space-y-4">
            {metrics.recentClasses.length ? (
              metrics.recentClasses.map((gymClass) => (
                <div
                  className="flex items-start justify-between gap-4 rounded-2xl border border-slate-200 p-4"
                  key={gymClass.id}
                >
                  <div>
                    <p className="font-medium text-slate-950">{gymClass.name}</p>
                    <p className="mt-1 text-sm text-slate-600">
                      Coach: {gymClass.coachName || "Unassigned"}
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
              ))
            ) : (
              <p className="text-sm text-slate-500">No classes have been created yet.</p>
            )}
          </div>
        </Card>

        <Card>
          <h2 className="text-lg font-semibold text-slate-950">Latest attendance</h2>
          <div className="mt-4 space-y-4">
            {metrics.latestAttendance.length ? (
              metrics.latestAttendance.map((entry) => (
                <div
                  className="flex items-start justify-between gap-4 rounded-2xl border border-slate-200 p-4"
                  key={entry.id}
                >
                  <div>
                    <p className="font-medium text-slate-950">
                      {entry.clientName} ({entry.clientCode})
                    </p>
                    <p className="mt-1 text-sm text-slate-600">
                      {entry.className ? `Class: ${entry.className}` : "Manual front-desk check-in"}
                    </p>
                    <p className="mt-1 text-xs text-slate-500">
                      {formatDateTime(entry.timestamp)}
                    </p>
                  </div>
                  <StatusBadge label={entry.status.replace("_", " ")} tone={entry.status} />
                </div>
              ))
            ) : (
              <p className="text-sm text-slate-500">No attendance has been logged yet.</p>
            )}
          </div>
        </Card>
      </div>
    </div>
  );
}
