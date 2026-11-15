"use client";

import { useActionState } from "react";

import { unenrollClientFromClassAction } from "@/actions/classes";
import { EMPTY_FORM_STATE } from "@/actions/shared";

// NX-10: remove one client from a class. Rendered as a small × on the
// enrollment chip.
export function ClassEnrollmentActions({
  classId,
  clientId,
}: {
  classId: string;
  clientId: string;
}) {
  const [state, action] = useActionState(
    unenrollClientFromClassAction,
    EMPTY_FORM_STATE,
  );

  return (
    <span className="inline-flex items-center gap-1">
      <form
        action={action}
        onSubmit={(event) => {
          if (!window.confirm("Remove this client from the class?")) {
            event.preventDefault();
          }
        }}
      >
        <input name="classId" type="hidden" value={classId} />
        <input name="clientId" type="hidden" value={clientId} />
        <button
          aria-label="Remove client from class"
          className="rounded-full px-1 text-slate-500 hover:bg-slate-200 hover:text-slate-900"
          title="Remove from class"
          type="submit"
        >
          ×
        </button>
      </form>
      {state.error ? (
        <span className="text-xs text-rose-700">{state.error}</span>
      ) : null}
    </span>
  );
}
