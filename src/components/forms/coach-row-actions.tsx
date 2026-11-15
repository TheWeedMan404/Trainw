"use client";

import { useActionState, useState } from "react";

import { deleteCoachAction } from "@/actions/coaches";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";
import { CoachEditForm } from "@/components/forms/coach-edit-form";

// NX-10: gym-side delete for a coach row. The server action refuses the
// delete while the coach still has classes (ON DELETE RESTRICT).
//
// NX-10 follow-up: an Edit toggle reveals the prefilled inline edit form
// (CoachEditForm) below the buttons. The form is full-width, so the row
// renders the actions block under the info row — see the coaches page.
export function CoachRowActions({
  coachId,
  name,
  rating,
}: {
  coachId: string;
  name: string;
  rating: number | null;
}) {
  const [deleteState, deleteAction] = useActionState(
    deleteCoachAction,
    EMPTY_FORM_STATE,
  );
  const [editing, setEditing] = useState(false);

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap justify-end gap-2">
        <Button onClick={() => setEditing((current) => !current)} type="button" variant="secondary">
          {editing ? "Close editor" : "Edit"}
        </Button>
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
      </div>
      {deleteState.error ? (
        <p className="text-xs text-rose-700">{deleteState.error}</p>
      ) : null}
      {editing ? (
        <CoachEditForm
          coachId={coachId}
          name={name}
          onCancel={() => setEditing(false)}
          rating={rating}
        />
      ) : null}
    </div>
  );
}
