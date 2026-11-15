"use client";

import { useActionState } from "react";

import { deleteCoachAction } from "@/actions/coaches";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";

// NX-10: gym-side delete for a coach row. The server action refuses the
// delete while the coach still has classes (ON DELETE RESTRICT).
export function CoachRowActions({ coachId }: { coachId: string }) {
  const [deleteState, deleteAction] = useActionState(
    deleteCoachAction,
    EMPTY_FORM_STATE,
  );

  return (
    <div className="flex flex-col items-end gap-2">
      <form
        action={deleteAction}
        onSubmit={(event) => {
          if (!window.confirm("Delete this coach? This cannot be undone.")) {
            event.preventDefault();
          }
        }}
      >
        <input name="coachId" type="hidden" value={coachId} />
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
