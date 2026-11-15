"use client";

import { useActionState, useState } from "react";

import {
  approveWorkspaceClientAction,
  deleteWorkspaceClientAction,
} from "@/actions/clients";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";
import { ClientEditForm } from "@/components/forms/client-edit-form";

// NX-05: gym-side actions for a client row — approve a pending public
// registration (reveals the client code in the list) or delete the record.
// Both actions are gym-scoped server-side; the buttons only render for
// the states that make sense (approve only while pending).
//
// NX-10 follow-up: an Edit toggle reveals the prefilled inline edit form
// (ClientEditForm) below the buttons. The form is full-width, so the row
// renders the actions block under the info row — see the clients page.
export function ClientRowActions({
  clientId,
  name,
  status,
  type,
}: {
  clientId: string;
  name: string;
  status: string;
  type: string;
}) {
  const [approveState, approveAction] = useActionState(
    approveWorkspaceClientAction,
    EMPTY_FORM_STATE,
  );
  const [deleteState, deleteAction] = useActionState(
    deleteWorkspaceClientAction,
    EMPTY_FORM_STATE,
  );
  const [editing, setEditing] = useState(false);

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap justify-end gap-2">
        {status === "pending" ? (
          <form action={approveAction}>
            <input name="clientId" type="hidden" value={clientId} />
            <Button type="submit">Approve</Button>
          </form>
        ) : null}
        <Button onClick={() => setEditing((current) => !current)} type="button" variant="secondary">
          {editing ? "Close editor" : "Edit"}
        </Button>
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
      {editing ? (
        <ClientEditForm
          clientId={clientId}
          name={name}
          onCancel={() => setEditing(false)}
          type={type}
        />
      ) : null}
    </div>
  );
}
