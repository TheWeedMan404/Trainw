import { ClientForm } from "@/components/forms/client-form";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeader } from "@/components/ui/page-header";
import { StatusBadge } from "@/components/ui/status-badge";
import { PERMISSIONS } from "@/lib/permissions";
import { getClientsPageData } from "@/lib/queries";
import { formatDateTime } from "@/lib/utils";
import { requirePermission } from "@/lib/workspace";

export default async function ClientsPage() {
  const context = await requirePermission(PERMISSIONS.clientsManage);
  const clients = await getClientsPageData(context.gymId);

  return (
    <div className="space-y-6">
      <PageHeader
        description="Manage client records that belong to this gym workspace."
        title="Clients"
      />

      <div className="grid gap-6 xl:grid-cols-[0.9fr_1.1fr]">
        <Card>
          <h2 className="text-lg font-semibold text-slate-950">Create client</h2>
          <p className="mt-2 text-sm text-slate-600">
            Add a client manually and let the database generate a unique client code.
          </p>
          <div className="mt-6">
            <ClientForm />
          </div>
        </Card>

        <Card>
          <h2 className="text-lg font-semibold text-slate-950">Client list</h2>
          <div className="mt-4 space-y-3">
            {clients.length ? (
              clients.map((client) => (
                <div
                  className="flex items-start justify-between gap-4 rounded-2xl border border-slate-200 p-4"
                  key={client.id}
                >
                  <div>
                    <p className="font-medium text-slate-950">{client.name}</p>
                    <p className="mt-1 text-sm text-slate-600">{client.client_code}</p>
                    <p className="mt-1 text-xs text-slate-500">
                      Created {formatDateTime(client.created_at)}
                    </p>
                  </div>
                  <StatusBadge label={client.type} />
                </div>
              ))
            ) : (
              <EmptyState
                description="Create your first client to start assigning memberships and classes."
                title="No clients yet"
              />
            )}
          </div>
        </Card>
      </div>
    </div>
  );
}
