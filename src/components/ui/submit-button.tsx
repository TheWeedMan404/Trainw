"use client";

import { useFormStatus } from "react-dom";

import { Button } from "@/components/ui/button";

export function SubmitButton({
  children,
  pendingLabel = "Saving...",
}: {
  children: React.ReactNode;
  pendingLabel?: string;
}) {
  const { pending } = useFormStatus();

  // NX-13: the pending state must actually disable the button — without
  // this, a double click submits the same server action twice.
  return (
    <Button disabled={pending} type="submit">
      {pending ? pendingLabel : children}
    </Button>
  );
}
