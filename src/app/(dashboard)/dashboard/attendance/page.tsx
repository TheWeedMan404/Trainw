import { AttendanceForm } from "@/components/forms/attendance-form";
import { AttendanceRowActions } from "@/components/forms/attendance-row-actions";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeader } from "@/components/ui/page-header";
import { Pagination } from "@/components/ui/pagination";
import { StatusBadge } from "@/components/ui/status-badge";
import { PERMISSIONS } from "@/lib/permissions";
import { getAttendancePageData } from "@/lib/queries";
import { parsePageParam } from "@/lib/pagination";
import { formatDateTime } from "@/lib/utils";
import { requirePermission } from "@/lib/workspace";

export default async function AttendancePage({ searchParams }: { searchParams: Promise<{ page?: string }> }) {
  const context = await requirePermission(PERMISSIONS.attendanceManage);
  const params = await searchParams;
  const page = parsePageParam(params.page);
  const { attendance, classes, clients, hasMore } = await getAttendancePageData(context.gymId, page);

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
                  <div className="flex flex-col items-end gap-2">
                    <StatusBadge label={entry.status.replace("_", " ")} tone={entry.status} />
                    <AttendanceRowActions attendanceId={entry.id} />
                  </div>
                </div>
              ))
            ) : (
              <EmptyState
                description="Record the first manual check-in to start building attendance history."
                title="No attendance yet"
              />
            )}
          </div>
          <Pagination hasMore={hasMore} page={page} />
        </Card>
      </div>
    </div>
  );
}
