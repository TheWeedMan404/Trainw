"use client";

import { useActionState } from "react";

import { loginAction } from "@/actions/auth";
import { EMPTY_FORM_STATE } from "@/actions/shared";
import { SubmitButton } from "@/components/ui/submit-button";

export function LoginForm({ redirectTo }: { redirectTo?: string }) {
  const [state, formAction] = useActionState(loginAction, EMPTY_FORM_STATE);

  return (
    <form action={formAction} className="space-y-4">
      <input name="redirectTo" type="hidden" value={redirectTo ?? "/dashboard"} />

      <div className="space-y-2">
        <label htmlFor="email">Email</label>
        <input id="email" name="email" placeholder="owner@trainw.app" type="email" />
      </div>

      <div className="space-y-2">
        <label htmlFor="password">Password</label>
        <input
          id="password"
          name="password"
          placeholder="Enter your password"
          type="password"
        />
      </div>

      {state.error ? (
        <p className="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700">
          {state.error}
        </p>
      ) : null}

      <SubmitButton pendingLabel="Signing in...">Sign in</SubmitButton>
    </form>
  );
}

