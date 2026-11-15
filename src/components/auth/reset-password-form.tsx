"use client";

import Link from "next/link";
import { useActionState } from "react";

import { updatePasswordAction } from "@/actions/auth";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SubmitButton } from "@/components/ui/submit-button";

// NX-14: the new-password form shown after the reset link's code has been
// exchanged for a session.
export function ResetPasswordForm() {
  const [state, formAction] = useActionState(
    updatePasswordAction,
    EMPTY_FORM_STATE,
  );

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-2">
        <label htmlFor="password">New password</label>
        <input
          id="password"
          name="password"
          placeholder="At least 8 characters"
          type="password"
        />
      </div>

      <div className="space-y-2">
        <label htmlFor="confirmPassword">Confirm new password</label>
        <input
          id="confirmPassword"
          name="confirmPassword"
          placeholder="Repeat the new password"
          type="password"
        />
      </div>

      {state.error ? (
        <p className="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700">
          {state.error}
        </p>
      ) : null}
      {state.success ? (
        <p className="rounded-xl bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
          {state.success}{" "}
          <Link className="font-medium text-emerald-800" href="/login">
            Sign in
          </Link>
        </p>
      ) : null}

      <SubmitButton pendingLabel="Updating...">Update password</SubmitButton>
    </form>
  );
}
