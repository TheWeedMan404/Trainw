"use client";

import { useActionState } from "react";

import { requestPasswordResetAction } from "@/actions/auth";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SubmitButton } from "@/components/ui/submit-button";

// NX-14: the forgot-password form. The server action replies identically
// whether the email belongs to an account or not.
export function ForgotPasswordForm() {
  const [state, formAction] = useActionState(
    requestPasswordResetAction,
    EMPTY_FORM_STATE,
  );

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-2">
        <label htmlFor="email">Email</label>
        <input id="email" name="email" placeholder="owner@trainw.app" type="email" />
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

      <SubmitButton pendingLabel="Sending...">Send reset link</SubmitButton>
    </form>
  );
}
