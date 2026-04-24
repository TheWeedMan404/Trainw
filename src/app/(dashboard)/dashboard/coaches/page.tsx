import { CoachForm } from "@/components/forms/coach-form";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeader } from "@/components/ui/page-header";
import { PERMISSIONS } from "@/lib/permissions";
import { getCoachesPageData } from "@/lib/queries";
import { formatDateTime } from "@/lib/utils";
import { requirePermission } from "@/lib/workspace";

export default async function CoachesPage() {
  const context = await requirePermission(PERMISSIONS.coachesManage);
  const coaches = await getCoachesPageData(context.gymId);

  return (
    <div className="space-y-6">
      <PageHeader
        description="Create coaches and assign them to classes in this workspace."
        title="Coaches"
      />

      <div className="grid gap-6 xl:grid-cols-[0.9fr_1.1fr]">
        <Card>
          <h2 className="text-lg font-semibold text-slate-950">Create coach</h2>
          <p className="mt-2 text-sm text-slate-600">
            Ratings are optional and can be used as simple quality indicators.
          </p>
          <div className="mt-6">
            <CoachForm />
          </div>
        </Card>

        <Card>
          <h2 className="text-lg font-semibold text-slate-950">Coach list</h2>
          <div className="mt-4 space-y-3">
            {coaches.length ? (
              coaches.map((coach) => (
                <div
                  className="flex items-start justify-between gap-4 rounded-2xl border border-slate-200 p-4"
                  key={coach.id}
                >
                  <div>
                    <p className="font-medium text-slate-950">{coach.name}</p>
                    <p className="mt-1 text-sm text-slate-600">
                      Rating: {coach.rating ?? "Not set"}
                    </p>
                    <p className="mt-1 text-xs text-slate-500">
                      Created {formatDateTime(coach.created_at)}
                    </p>
                  </div>
                </div>
              ))
            ) : (
              <EmptyState
                description="Create your first coach to start assigning classes."
                title="No coaches yet"
              />
            )}
          </div>
        </Card>
      </div>
    </div>
  );
}
