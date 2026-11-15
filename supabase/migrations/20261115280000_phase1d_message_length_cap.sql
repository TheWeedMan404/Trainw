-- FE-26 — cap chat messages at 2,000 characters (server-side backstop).
--
-- The three chat send paths (gym/coach/client) now reject over-long
-- messages client-side with a toast, and the textareas carry
-- maxlength="2000". This CHECK is the backstop for any other writer
-- (API, future client, direct SQL): an over-long insert fails instead
-- of storing an unbounded blob. It is a plain validating CHECK, not
-- NOT VALID — Postgres validates the existing rows on apply (chat
-- messages are user-typed and far below the cap in practice).

ALTER TABLE public.messages
  ADD CONSTRAINT messages_content_max_length
  CHECK (char_length(content) <= 2000);
