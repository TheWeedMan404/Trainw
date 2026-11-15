"use client";

import { useActionState } from "react";

import {
  deactivateStaffUserAction,
  deleteStaffUserAction,
  reactivateStaffUserAction,
} from "@/actions/roles";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";

// NX-10: staff login actions for one workspace user — deactivate (ban,
// reversible), reactivate, or delete the login entirely. The server
// actions refuse self-actions and removing the last gym owner; the
// buttons are not rendered for the signed-in user at all.
export function StaffUserRowActions({
  banned,
  isSelf,
  userId,
}: {
  banned: boolean;
  isSelf: boolean;
  userId: string;
}) {
  const [deactivateState, deactivateAction] = useActionState(
    deactivateStaffUserAction,
    EMPTY_FORM_STATE,
  );
  const [reactivateState, reactivateAction] = useActionState(
    reactivateStaffUserAction,
    EMPTY_FORM_STATE,
  );
  const [deleteState, deleteAction] = useActionState(
    deleteStaffUserAction,
    EMPTY_FORM_STATE,
  );

  if (isSelf) {
    return null;
  }

  const error =
    deactivateState.error ?? reactivateState.error ?? deleteState.error;

  return (
    <div className="flex flex-col items-end gap-2">
      <div className="flex gap-2">
        {banned ? (
          <form action={reactivateAction}>
            <input name="userId" type="hidden" value={userId} />
            <Button type="submit">Reactivate</Button>
          </form>
        ) : (
          <form
            action={deactivateAction}
            onSubmit={(event) => {
              if (
                !window.confirm(
                  "Deactivate this login? The staff member will not be able to sign in until reactivated.",
                )
              ) {
                event.preventDefault();
              }
            }}
          >
            <input name="userId" type="hidden" value={userId} />
            <Button type="submit" variant="secondary">
              Deactivate
            </Button>
          </form>
        )}
        <form
          action={deleteAction}
          onSubmit={(event) => {
            if (
              !window.confirm(
                "Delete this staff user and their login? This cannot be undone.",
              )
            ) {
              event.preventDefault();
            }
          }}
        >
          <input name="userId" type="hidden" value={userId} />
          <Button type="submit" variant="ghost">
            Delete
          </Button>
        </form>
      </div>
      {error ? <p className="text-xs text-rose-700">{error}</p> : null}
    </div>
  );
}
