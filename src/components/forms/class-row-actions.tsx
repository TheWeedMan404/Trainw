"use client";

import { useActionState, useState } from "react";

import { deleteClassAction } from "@/actions/classes";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";
import { ClassEditForm } from "@/components/forms/class-edit-form";

// NX-10: gym-side delete for a class. Enrollments cascade; attendance
// rows keep the class reference as NULL.
//
// NX-10 follow-up: an Edit toggle reveals the prefilled inline edit form
// (ClassEditForm) below the buttons. The form is full-width, so the row
// renders the actions block under the header row — see the classes page.
export function ClassRowActions({
  capacity,
  classId,
  coachId,
  coaches,
  name,
  type,
}: {
  capacity: number | null;
  classId: string;
  coachId: string;
  coaches: Array<{ id: string; name: string }>;
  name: string;
  type: string;
}) {
  const [deleteState, deleteAction] = useActionState(
    deleteClassAction,
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
      </div>
      {deleteState.error ? (
        <p className="text-xs text-rose-700">{deleteState.error}</p>
      ) : null}
      {editing ? (
        <ClassEditForm
          capacity={capacity}
          classId={classId}
          coachId={coachId}
          coaches={coaches}
          name={name}
          onCancel={() => setEditing(false)}
          type={type}
        />
      ) : null}
    </div>
  );
}
