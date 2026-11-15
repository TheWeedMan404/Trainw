"use client";

import { useActionState } from "react";

import {
  deleteOwnAccountAction,
  recoverWorkspaceAction,
} from "@/actions/auth";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SubmitButton } from "@/components/ui/submit-button";

// NX-28: the orphan-recovery form. defaultValue comes from the signup
// metadata when it exists; the user can correct it.
export function RecoverWorkspaceForm({
  defaultFullName,
  defaultGymName,
}: {
  defaultFullName?: string;
  defaultGymName?: string;
}) {
  const [state, formAction] = useActionState(
    recoverWorkspaceAction,
    EMPTY_FORM_STATE,
  );
  const [deleteState, deleteAction] = useActionState(
    deleteOwnAccountAction,
    EMPTY_FORM_STATE,
  );

  return (
    <div className="space-y-6">
      <form action={formAction} className="space-y-4">
        <div className="space-y-2">
          <label htmlFor="fullName">Your name</label>
          <input
            defaultValue={defaultFullName ?? ""}
            id="fullName"
            name="fullName"
            placeholder="Your full name"
            type="text"
          />
        </div>

        <div className="space-y-2">
          <label htmlFor="gymName">Gym name</label>
          <input
            defaultValue={defaultGymName ?? ""}
            id="gymName"
            name="gymName"
            placeholder="The name of your gym"
            type="text"
          />
        </div>

        {state.error ? (
          <p className="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700">
            {state.error}
          </p>
        ) : null}

        <SubmitButton pendingLabel="Creating your workspace...">
          Create my workspace
        </SubmitButton>
      </form>

      <form action={deleteAction}>
        <p className="text-sm text-slate-600">
          Don&apos;t want this account at all?{" "}
          <button className="font-medium text-rose-700" type="submit">
            Delete my account
          </button>
        </p>
        {deleteState.error ? (
          <p className="mt-3 rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700">
            {deleteState.error}
          </p>
        ) : null}
      </form>
    </div>
  );
}
