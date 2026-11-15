"use client";

import { useActionState } from "react";

import { updateCoachAction } from "@/actions/coaches";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { Button } from "@/components/ui/button";
import { SubmitButton } from "@/components/ui/submit-button";

// NX-10 follow-up: the inline edit form for a coach row. Prefilled from
// the row, wired to the existing updateCoachAction (gym-scoped
// server-side). The page revalidates on success, so the row behind the
// form shows the new values.
export function CoachEditForm({
  coachId,
  name,
  onCancel,
  rating,
}: {
  coachId: string;
  name: string;
  onCancel: () => void;
  rating: number | null;
}) {
  const [state, formAction] = useActionState(
    updateCoachAction,
    EMPTY_FORM_STATE,
  );

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-2xl border border-slate-200 bg-slate-50 p-4"
    >
      <input name="coachId" type="hidden" value={coachId} />

      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2">
          <label htmlFor={`edit-coach-name-${coachId}`}>Coach name</label>
          <input
            defaultValue={name}
            id={`edit-coach-name-${coachId}`}
            name="name"
          />
        </div>

        <div className="space-y-2">
          <label htmlFor={`edit-coach-rating-${coachId}`}>
            Rating (optional)
          </label>
          <input
            defaultValue={rating ?? ""}
            id={`edit-coach-rating-${coachId}`}
            max="5"
            min="0"
            name="rating"
            placeholder="4.8"
            step="0.1"
            type="number"
          />
        </div>
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
