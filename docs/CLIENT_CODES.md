# Client codes — display-only identifiers (NX-29)

## The rule

A client code (e.g. `GYM-042-K`) is a **display-only label**. It must
**never be accepted as proof of identity** — not at the gate, not in
any API, not in any lookup that grants access, and not as a password
substitute.

## Why

The format is short and predictable: a gym prefix + 3 random digits +
1 random letter, roughly 26,000 combinations per prefix. Anyone who has
seen one code (they are shown throughout the dashboard and were
returned to the registrant) can guess others by brute force. A code
proves nothing except that a row with that label exists.

## What the code proves today

Grep-verified 2026-11-15 (round 4, NX-29): no flow accepts a bare
client code as a credential.

- Next.js app (`src/`, deleted 2026-11-15 per P2-10): it selected
  `client_code` for display in lists, forms and enrolment chips only.
  No route or action looked a member up by code to grant access.
- Gate terminal (`gate-terminal.js`): scans an opaque QR token and
  sends it to the `gate-checkin` edge function. It never reads or sends
  a client code.
- Gate check-in (`supabase/functions/gate-checkin/handler.mjs`): no
  `client_code` reference at all. Entry is decided by the QR
  `gate_sessions` token + the hashed member credential
  (`validate_member_credential`), never by a code.
- Public registration (deleted with `src/` in 2026-11-15): the code
  was not returned to the registrant — it was issued (shown) only when
  a gym manager approved the registration in the dashboard.

## If a code is ever needed as a credential

Do not reuse this format. Lengthen to 8+ random alphanumeric
characters, store only a hash, and rate-limit the lookup — or better,
use the QR-token + credential flow the gate already has.

## Schema note (P2-10 — decided: src/ deleted 2026-11-15)

The generator (`generate_unique_client_code` + `set_client_code`
trigger) lives **only** in `database/archive/schema.sql`. The migration
chain has no `client_code` column, generator, or trigger at all — the
deleted Next.js app selected a column the chain never creates.
Lengthening the generator is therefore moot until the chain gains a
client-code definition.
