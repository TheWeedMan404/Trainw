"use client";

import { useActionState } from "react";

import { createWorkspaceClientAction } from "@/actions/clients";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SubmitButton } from "@/components/ui/submit-button";

export function ClientForm() {
  const [state, formAction] = useActionState(
    createWorkspaceClientAction,
    EMPTY_FORM_STATE,
  );

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-2">
        <label htmlFor="client-name">Client name</label>
        <input id="client-name" name="name" placeholder="Karim Jaziri" />
      </div>

      <div className="space-y-2">
        <label htmlFor="client-type">Client type</label>
        <select defaultValue="gym" id="client-type" name="type">
          <option value="gym">Gym-linked</option>
          <option value="individual">Individual</option>
        </select>
        <p className="text-xs text-slate-500">
          Workspace-created clients always stay inside the current gym workspace.
        </p>
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

      <SubmitButton pendingLabel="Creating client...">Create client</SubmitButton>
    </form>
  );
}
