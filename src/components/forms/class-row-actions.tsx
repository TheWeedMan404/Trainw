"use client";

import { useActionState } from "react";

import { deleteClassAction } from "@/actions/classes";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";

// NX-10: gym-side delete for a class. Enrollments cascade; attendance
// rows keep the class reference as NULL.
export function ClassRowActions({ classId }: { classId: string }) {
  const [deleteState, deleteAction] = useActionState(
    deleteClassAction,
    EMPTY_FORM_STATE,
  );

  return (
    <div className="flex flex-col items-end gap-2">
      <form
        action={deleteAction}
        onSubmit={(event) => {
          if (!window.confirm("Delete this class? Enrollments are removed too.")) {
            event.preventDefault();
          }
        }}
      >
        <input name="classId" type="hidden" value={classId} />
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
