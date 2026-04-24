"use client";

import { useActionState } from "react";

import { createClassAction } from "@/actions/classes";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SubmitButton } from "@/components/ui/submit-button";

export function ClassForm({
  coaches,
}: {
  coaches: Array<{ id: string; name: string }>;
}) {
  const [state, formAction] = useActionState(createClassAction, EMPTY_FORM_STATE);

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-2">
        <label htmlFor="class-name">Class name</label>
        <input id="class-name" name="name" placeholder="Morning Strength" />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2">
          <label htmlFor="class-type">Class type</label>
          <select defaultValue="group" id="class-type" name="type">
            <option value="group">Group</option>
            <option value="private">Private</option>
            <option value="supervising">Supervising</option>
          </select>
        </div>

        <div className="space-y-2">
          <label htmlFor="class-capacity">Capacity (optional)</label>
          <input id="class-capacity" min="1" name="capacity" placeholder="10" type="number" />
        </div>
      </div>

      <div className="space-y-2">
        <label htmlFor="coachId">Assigned coach</label>
        <select defaultValue="" id="coachId" name="coachId">
          <option disabled value="">
            Select a coach
          </option>
          {coaches.map((coach) => (
            <option key={coach.id} value={coach.id}>
              {coach.name}
            </option>
          ))}
        </select>
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

      <SubmitButton pendingLabel="Creating class...">Create class</SubmitButton>
    </form>
  );
}
