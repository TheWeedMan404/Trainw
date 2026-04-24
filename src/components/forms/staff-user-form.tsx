"use client";

import { useActionState } from "react";

import { createStaffUserAction } from "@/actions/roles";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SubmitButton } from "@/components/ui/submit-button";

export function StaffUserForm({
  roles,
}: {
  roles: Array<{ id: string; name: string }>;
}) {
  const [state, formAction] = useActionState(
    createStaffUserAction,
    EMPTY_FORM_STATE,
  );

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-2">
        <label htmlFor="staff-name">Full name</label>
        <input id="staff-name" name="fullName" placeholder="Rim Receptionist" />
      </div>

      <div className="space-y-2">
        <label htmlFor="staff-email">Email</label>
        <input id="staff-email" name="email" placeholder="staff@lakeclub.tn" type="email" />
      </div>

      <div className="space-y-2">
        <label htmlFor="staff-password">Temporary password</label>
        <input id="staff-password" name="password" placeholder="Minimum 8 characters" type="password" />
      </div>

      <div className="space-y-2">
        <label htmlFor="staff-role">Assigned role</label>
        <select defaultValue="" id="staff-role" name="roleId">
          <option disabled value="">
            Select a role
          </option>
          {roles.map((role) => (
            <option key={role.id} value={role.id}>
              {role.name}
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

      <SubmitButton pendingLabel="Creating staff user...">Create staff user</SubmitButton>
    </form>
  );
}
