// NX-26: the auth server actions' input schemas live here, not in
// actions/auth.ts, so the smoke tests can import and exercise them
// without pulling in next/headers or the Supabase clients. The actions
// import them from here; the contract is identical.
import { z } from "zod";

export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  redirectTo: z.string().optional(),
});

export const signupSchema = z.object({
  email: z.string().email(),
  fullName: z.string().min(2),
  gymName: z.string().min(2),
  // P2-9: the gym-owner signup requires privacy consent; the form sends
  // "on" when the box is ticked (the action maps it to a boolean).
  consent: z.boolean().refine((value) => value === true, {
    message: "You must accept the privacy terms to create an account.",
  }),
  password: z.string().min(8),
});

export const resetRequestSchema = z.object({
  email: z.string().email(),
});

export const updatePasswordSchema = z
  .object({
    confirmPassword: z.string().min(8).max(128),
    password: z.string().min(8).max(128),
  })
  .refine((value) => value.password === value.confirmPassword, {
    message: "The passwords do not match.",
    path: ["confirmPassword"],
  });

export const recoverWorkspaceSchema = z.object({
  fullName: z.string().min(2).max(100),
  gymName: z.string().min(2).max(100),
});
