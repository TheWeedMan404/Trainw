"use client";

import { useActionState } from "react";

import { updateWorkspaceClientAction } from "@/actions/clients";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";
import { SubmitButton } from "@/components/ui/submit-button";

// NX-10 follow-up: the inline edit form for a client row. Prefilled from
// the row, wired to the existing updateWorkspaceClientAction (gym-scoped
// server-side). The page revalidates on success, so the row behind the
// form shows the new values.
export function ClientEditForm({
  clientId,
  name,
  onCancel,
  type,
}: {
  clientId: string;
  name: string;
  onCancel: () => void;
  type: string;
}) {
  const [state, formAction] = useActionState(
    updateWorkspaceClientAction,
    EMPTY_FORM_STATE,
  );

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-2xl border border-slate-200 bg-slate-50 p-4"
    >
      <input name="clientId" type="hidden" value={clientId} />

      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2">
          <label htmlFor={`edit-client-name-${clientId}`}>Client name</label>
          <input
            defaultValue={name}
            id={`edit-client-name-${clientId}`}
            name="name"
          />
        </div>

        <div className="space-y-2">
          <label htmlFor={`edit-client-type-${clientId}`}>Client type</label>
          <select
            defaultValue={type}
            id={`edit-client-type-${clientId}`}
            name="type"
          >
            <option value="gym">Gym-linked</option>
            <option value="individual">Individual</option>
          </select>
        </div>
      </div>

      {state.error ? (
        <p className="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700">
          {state.error}
        </p>
      ) : null}

      {state.success ? (
        <p className="rounded-xl bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
          {state.success}
        </p>
      ) : null}

      <div className="flex gap-2">
        <SubmitButton pendingLabel="Saving changes...">
          Save changes
        </SubmitButton>
        <Button onClick={onCancel} type="button" variant="ghost">
          Cancel
        </Button>
      </div>
    </form>
  );
}
