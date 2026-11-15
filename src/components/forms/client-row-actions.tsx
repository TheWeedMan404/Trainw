"use client";

import { useActionState } from "react";

import {
  approveWorkspaceClientAction,
  deleteWorkspaceClientAction,
} from "@/actions/clients";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";

// NX-05: gym-side actions for a client row — approve a pending public
// registration (reveals the client code in the list) or delete the record.
// Both actions are gym-scoped server-side; the buttons only render for
// the states that make sense (approve only while pending).
export function ClientRowActions({
  clientId,
  status,
}: {
  clientId: string;
  status: string;
}) {
  const [approveState, approveAction] = useActionState(
    approveWorkspaceClientAction,
    EMPTY_FORM_STATE,
  );
  const [deleteState, deleteAction] = useActionState(
    deleteWorkspaceClientAction,
    EMPTY_FORM_STATE,
  );

  return (
    <div className="flex flex-col items-end gap-2">
      <div className="flex gap-2">
        {status === "pending" ? (
          <form action={approveAction}>
            <input name="clientId" type="hidden" value={clientId} />
            <Button type="submit">Approve</Button>
          </form>
        ) : null}
        <form
          action={deleteAction}
          onSubmit={(event) => {
            if (
              !window.confirm("Delete this client? This cannot be undone.")
            ) {
              event.preventDefault();
            }
          }}
        >
          <input name="clientId" type="hidden" value={clientId} />
          <Button type="submit" variant="ghost">
            Delete
          </Button>
        </form>
      </div>
      {approveState.error || deleteState.error ? (
        <p className="text-xs text-rose-700">
          {approveState.error ?? deleteState.error}
        </p>
      ) : null}
    </div>
  );
}
