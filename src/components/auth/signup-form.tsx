"use client";

import { useActionState } from "react";

import { signupGymOwnerAction } from "@/actions/auth";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SubmitButton } from "@/components/ui/submit-button";

export function SignupForm() {
  const [state, formAction] = useActionState(
    signupGymOwnerAction,
    EMPTY_FORM_STATE,
  );

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-2">
        <label htmlFor="gymName">Gym name</label>
        <input id="gymName" name="gymName" placeholder="Lake Club" />
      </div>

      <div className="space-y-2">
        <label htmlFor="fullName">Owner full name</label>
        <input id="fullName" name="fullName" placeholder="Sami Ben Ali" />
      </div>

      <div className="space-y-2">
        <label htmlFor="email">Email</label>
        <input id="email" name="email" placeholder="owner@lakeclub.tn" type="email" />
      </div>

      <div className="space-y-2">
        <label htmlFor="password">Password</label>
        <input id="password" name="password" placeholder="Minimum 8 characters" type="password" />
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

      <SubmitButton pendingLabel="Creating workspace...">
        Create gym workspace
      </SubmitButton>
    </form>
  );
}
