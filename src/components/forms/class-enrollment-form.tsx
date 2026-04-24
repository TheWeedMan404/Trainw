"use client";

import { useActionState } from "react";

import { enrollClientInClassAction } from "@/actions/classes";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SubmitButton } from "@/components/ui/submit-button";

export function ClassEnrollmentForm({
  classId,
  clients,
}: {
  classId: string;
  clients: Array<{ client_code: string; id: string; name: string }>;
}) {
  const [state, formAction] = useActionState(
    enrollClientInClassAction,
    EMPTY_FORM_STATE,
  );

  return (
    <form action={formAction} className="space-y-3 rounded-2xl border border-slate-200 p-4">
      <input name="classId" type="hidden" value={classId} />

      <div className="space-y-2">
        <label htmlFor={`client-${classId}`}>Add client to class</label>
        <select defaultValue="" id={`client-${classId}`} name="clientId">
          <option disabled value="">
            Select client
          </option>
          {clients.map((client) => (
            <option key={client.id} value={client.id}>
              {client.name} ({client.client_code})
            </option>
          ))}
        </select>
      </div>

      {state.error ? (
        <p className="text-sm text-rose-700">{state.error}</p>
      ) : state.success ? (
        <p className="text-sm text-emerald-700">{state.success}</p>
      ) : null}

      <SubmitButton pendingLabel="Adding client...">Add client</SubmitButton>
    </form>
  );
}
