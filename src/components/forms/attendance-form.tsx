"use client";

import { useActionState } from "react";

import { createAttendanceAction } from "@/actions/attendance";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SearchableSelect } from "@/components/ui/searchable-select";
import { SubmitButton } from "@/components/ui/submit-button";

export function AttendanceForm({
  classes,
  clients,
}: {
  classes: Array<{ id: string; name: string }>;
  clients: Array<{ client_code: string; id: string; name: string }>;
}) {
  const [state, formAction] = useActionState(
    createAttendanceAction,
    EMPTY_FORM_STATE,
  );

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-2">
        <label htmlFor="attendance-client">Client</label>
        <SearchableSelect
          id="attendance-client"
          name="clientId"
          options={clients.map((client) => ({
            label: `${client.name} (${client.client_code})`,
            value: client.id,
          }))}
          placeholder="Select client"
        />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2">
          <label htmlFor="attendance-class">Class (optional)</label>
          <SearchableSelect
            defaultValue=""
            id="attendance-class"
            name="classId"
            options={[
              { label: "No class", value: "" },
              ...classes.map((gymClass) => ({
                label: gymClass.name,
                value: gymClass.id,
              })),
            ]}
            placeholder="No class"
          />
        </div>

        <div className="space-y-2">
          <label htmlFor="attendance-status">Status</label>
          <select defaultValue="checked_in" id="attendance-status" name="status">
            <option value="checked_in">Checked in</option>
            <option value="late">Late</option>
            <option value="excused">Excused</option>
            <option value="missed">Missed</option>
          </select>
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

      <SubmitButton pendingLabel="Saving attendance...">
        Record attendance
      </SubmitButton>
    </form>
  );
}
