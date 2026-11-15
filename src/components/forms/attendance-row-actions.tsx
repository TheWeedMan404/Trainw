"use client";

import { useActionState } from "react";

import { deleteAttendanceAction } from "@/actions/attendance";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";

// NX-10: gym-side delete for an attendance record (e.g. a duplicate
// manual check-in).
export function AttendanceRowActions({ attendanceId }: { attendanceId: string }) {
  const [deleteState, deleteAction] = useActionState(
    deleteAttendanceAction,
    EMPTY_FORM_STATE,
  );

  return (
    <div className="flex flex-col items-end gap-2">
      <form
        action={deleteAction}
        onSubmit={(event) => {
          if (!window.confirm("Delete this attendance record?")) {
            event.preventDefault();
          }
        }}
      >
        <input name="attendanceId" type="hidden" value={attendanceId} />
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
