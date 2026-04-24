"use client";

import { useActionState } from "react";

import { createCoachAction } from "@/actions/coaches";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SubmitButton } from "@/components/ui/submit-button";

export function CoachForm() {
  const [state, formAction] = useActionState(createCoachAction, EMPTY_FORM_STATE);

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-2">
        <label htmlFor="coach-name">Coach name</label>
        <input id="coach-name" name="name" placeholder="Youssef Trabelsi" />
      </div>

      <div className="space-y-2">
        <label htmlFor="coach-rating">Rating (optional)</label>
        <input id="coach-rating" max="5" min="0" name="rating" placeholder="4.8" step="0.1" type="number" />
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

      <SubmitButton pendingLabel="Creating coach...">Create coach</SubmitButton>
    </form>
  );
}
