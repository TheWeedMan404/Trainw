import { CoachForm } from "@/components/forms/coach-form";
import { CoachRowActions } from "@/components/forms/coach-row-actions";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeader } from "@/components/ui/page-header";
import { Pagination } from "@/components/ui/pagination";
import { PERMISSIONS } from "@/lib/permissions";
import { getCoachesPageData } from "@/lib/queries";
import { parsePageParam } from "@/lib/pagination";
import { formatDateTime } from "@/lib/utils";
import { requirePermission } from "@/lib/workspace";

export default async function CoachesPage({ searchParams }: { searchParams: Promise<{ page?: string }> }) {
  const context = await requirePermission(PERMISSIONS.coachesManage);
  const params = await searchParams;
  const page = parsePageParam(params.page);
  const { coaches, hasMore } = await getCoachesPageData(context.gymId, page);

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
                  <CoachRowActions coachId={coach.id} />
                </div>
              ))
            ) : (
              <EmptyState
                description="Create your first coach to start assigning classes."
                title="No coaches yet"
              />
            )}
          </div>
          <Pagination hasMore={hasMore} page={page} />
        </Card>
      </div>
    </div>
  );
}
