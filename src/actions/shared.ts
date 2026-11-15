export type FormState = {
  error?: string;
  success?: string;
};

export const EMPTY_FORM_STATE: FormState = {};

// NX-15 (round 6): the old version returned `error.message` verbatim, so
// raw Supabase/Postgres messages (table names, constraint names, RLS
// hints) reached the browser. Server actions now return only the generic
// fallback the caller supplies; the raw error is logged server-side
// (console.error in a server action never reaches the client).
export function getErrorMessage(error: unknown, fallback = "Something went wrong.") {
  if (error instanceof Error) {
    console.error("[action] ", error.message);
  } else if (error !== undefined && error !== null) {
    console.error("[action] ", error);
  }

  return fallback;
}
