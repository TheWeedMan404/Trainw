export type FormState = {
  error?: string;
  success?: string;
};

export const EMPTY_FORM_STATE: FormState = {};

export function getErrorMessage(error: unknown, fallback = "Something went wrong.") {
  if (error instanceof Error) {
    return error.message || fallback;
  }

  return fallback;
}
