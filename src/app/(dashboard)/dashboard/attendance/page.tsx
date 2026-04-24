import { AttendanceForm } from "@/components/forms/attendance-form";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeader } from "@/components/ui/page-header";
import { StatusBadge } from "@/components/ui/status-badge";
import { PERMISSIONS } from "@/lib/permissions";
import { getAttendancePageData } from "@/lib/queries";
import { formatDateTime } from "@/lib/utils";
import { requirePermission } from "@/lib/workspace";

export default async function AttendancePage() {
  const context = await requirePermission(PERMISSIONS.attendanceManage);
  const { attendance, classes, clients } = await getAttendancePageData(context.gymId);

  return (
    <div className="space-y-6">
      <PageHeader
        description="Record attendance manually and review the most recent check-ins."
        title="Attendance"
      />

      <div className="grid gap-6 xl:grid-cols-[0.85fr_1.15fr]">
        <Card>
          <h2 className="text-lg font-semibold text-slate-950">Manual check-in</h2>
          <p className="mt-2 text-sm text-slate-600">
            Store attendance with a timestamp and optional class reference.
          </p>
          <div className="mt-6">
            <AttendanceForm classes={classes} clients={clients} />
          </div>
        </Card>

        <Card>
          <h2 className="text-lg font-semibold text-slate-950">Recent attendance</h2>
          <div className="mt-4 space-y-3">
            {attendance.length ? (
              attendance.map((entry) => (
                <div
                  className="flex items-start justify-between gap-4 rounded-2xl border border-slate-200 p-4"
                  key={entry.id}
                >
                  <div>
                    <p className="font-medium text-slate-950">
                      {entry.clientName} ({entry.clientCode})
                    </p>
                    <p className="mt-1 text-sm text-slate-600">
                      {entry.className ? `Class: ${entry.className}` : "No class attached"}
                    </p>
                    <p className="mt-1 text-xs text-slate-500">
                      {formatDateTime(entry.timestamp)}
                    </p>
                  </div>
                  <StatusBadge label={entry.status.replace("_", " ")} tone={entry.status} />
                </div>
              ))
            ) : (
              <EmptyState
                description="Record the first manual check-in to start building attendance history."
                title="No attendance yet"
              />
            )}
          </div>
        </Card>
      </div>
    </div>
  );
}
