"use client";

import { useActionState } from "react";

import { updateClassAction } from "@/actions/classes";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";
import { SearchableSelect } from "@/components/ui/searchable-select";
import { SubmitButton } from "@/components/ui/submit-button";

// NX-10 follow-up: the inline edit form for a class row. Prefilled from
// the row, wired to the existing updateClassAction (gym-scoped
// server-side; it re-checks the coach belongs to the gym). The coach
// picker is the same SearchableSelect as the create form. The page
// revalidates on success, so the card behind the form shows the new
// values.
export function ClassEditForm({
  capacity,
  classId,
  coachId,
  coaches,
  name,
  onCancel,
  type,
}: {
  capacity: number | null;
  classId: string;
  coachId: string;
  coaches: Array<{ id: string; name: string }>;
  name: string;
  onCancel: () => void;
  type: string;
}) {
  const [state, formAction] = useActionState(
    updateClassAction,
    EMPTY_FORM_STATE,
  );

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-2xl border border-slate-200 bg-slate-50 p-4"
    >
      <input name="classId" type="hidden" value={classId} />

      <div className="space-y-2">
        <label htmlFor={`edit-class-name-${classId}`}>Class name</label>
        <input
          defaultValue={name}
          id={`edit-class-name-${classId}`}
          name="name"
        />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2">
          <label htmlFor={`edit-class-type-${classId}`}>Class type</label>
          <select
            defaultValue={type}
            id={`edit-class-type-${classId}`}
            name="type"
          >
            <option value="group">Group</option>
            <option value="private">Private</option>
            <option value="supervising">Supervising</option>
          </select>
        </div>

        <div className="space-y-2">
          <label htmlFor={`edit-class-capacity-${classId}`}>
            Capacity (optional)
          </label>
          <input
            defaultValue={capacity ?? ""}
            id={`edit-class-capacity-${classId}`}
            min="1"
            name="capacity"
            placeholder="10"
            type="number"
          />
        </div>
      </div>

      <div className="space-y-2">
        <label htmlFor={`edit-class-coach-${classId}`}>Assigned coach</label>
        <SearchableSelect
          defaultValue={coachId}
          id={`edit-class-coach-${classId}`}
          name="coachId"
          options={coaches.map((coach) => ({
            label: coach.name,
            value: coach.id,
          }))}
          placeholder="Select a coach"
        />
      </div>

      {state.error ? (
        <p className="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700">
          {state.error}
        </p>
      ) : null}

      {state.success ? (
        <p className="rounded-xl bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
          {state.success}
        </p>
      ) : null}

      <div className="flex gap-2">
        <SubmitButton pendingLabel="Saving changes...">
          Save changes
        </SubmitButton>
        <Button onClick={onCancel} type="button" variant="ghost">
          Cancel
        </Button>
      </div>
    </form>
  );
}
