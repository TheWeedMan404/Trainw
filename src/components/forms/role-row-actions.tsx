"use client";

import { useActionState } from "react";

import { deleteRoleAction } from "@/actions/roles";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";

// NX-10: gym-side delete for a role. The server action refuses the
// delete while any staff user still holds the role, and never for the
// gym owner role.
export function RoleRowActions({ roleId }: { roleId: string }) {
  const [deleteState, deleteAction] = useActionState(
    deleteRoleAction,
    EMPTY_FORM_STATE,
  );

  return (
    <div className="flex flex-col items-end gap-2">
      <form
        action={deleteAction}
        onSubmit={(event) => {
          if (
            !window.confirm(
              "Delete this role? Staff holding it must be reassigned first.",
            )
          ) {
            event.preventDefault();
          }
        }}
      >
        <input name="roleId" type="hidden" value={roleId} />
        <Button type="submit" variant="ghost">
          Delete
        </Button>
      </form>
      {deleteState.error ? (
        <p className="text-xs text-rose-700">{deleteState.error}</p>
      ) : null}
    </div>
  );
}
