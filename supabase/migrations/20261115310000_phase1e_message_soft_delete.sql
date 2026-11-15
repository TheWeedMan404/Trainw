-- ============================================================================
-- Round 5 (DB-38 follow-up) — messages survive user deletion; soft-delete
-- replaces any hard delete.
--
-- Before: messages.sender_id / receiver_id were NOT NULL with ON DELETE
-- CASCADE, so deleting a user erased the other party's copy of the
-- conversation, and there was no way to remove a message short of a hard
-- DELETE (which RLS already denied — no DELETE policy — so removal was
-- only possible out-of-band as service_role).
--
-- After:
--   * sender_id / receiver_id are nullable with ON DELETE SET NULL: a
--     deleted user's messages stay in the table with a NULL counterpart,
--     still visible to the surviving party through the SELECT policy
--     (the other side's branch still matches).
--   * deleted_at / deleted_by soft-delete a message: the sender can
--     retract their own message via soft_delete_message(); the row is
--     hidden from SELECT/UPDATE for both parties but never removed.
--     Soft-deleting twice returns the same id (idempotent).
--   * The SELECT and UPDATE policies exclude soft-deleted rows. The
--     INSERT policy is unchanged (sender_id = auth.uid() still forces a
--     real sender, so NULL-sender inserts stay denied).
--   * The chat UIs render conversations keyed by live users and fall
--     back to 'Client' for a missing counterpart name, so a NULL
--     counterpart needs no UI change (see notes).
-- ============================================================================

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by uuid REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.messages ALTER COLUMN sender_id DROP NOT NULL;
ALTER TABLE public.messages ALTER COLUMN receiver_id DROP NOT NULL;

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_sender_id_fkey
  FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_receiver_id_fkey;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_receiver_id_fkey
  FOREIGN KEY (receiver_id) REFERENCES public.users(id) ON DELETE SET NULL;

DROP POLICY IF EXISTS messages_select ON public.messages;
CREATE POLICY messages_select ON public.messages
  FOR SELECT
  USING (deleted_at IS NULL AND (sender_id = auth.uid() OR receiver_id = auth.uid()));

DROP POLICY IF EXISTS messages_update ON public.messages;
CREATE POLICY messages_update ON public.messages
  FOR UPDATE
  USING (deleted_at IS NULL AND receiver_id = auth.uid())
  WITH CHECK (deleted_at IS NULL AND receiver_id = auth.uid());

-- The FK ON DELETE SET NULL above changes sender_id/receiver_id when a
-- user row is deleted, but forbid_message_field_updates() (round 2,
-- DB-53) rejects ANY change to those columns — so the SET NULL was
-- blocked and user deletion failed. The trigger now allows a
-- sender/receiver change only when the new value is NULL and the old
-- user row is gone (the FK action); a caller cannot NULL out a live
-- counterpart. SECURITY DEFINER so the existence check reads true state
-- rather than the caller's RLS-filtered view.
CREATE OR REPLACE FUNCTION public.forbid_message_field_updates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF (NEW.sender_id IS DISTINCT FROM OLD.sender_id
      AND NOT (NEW.sender_id IS NULL
               AND NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.sender_id)))
     OR (NEW.receiver_id IS DISTINCT FROM OLD.receiver_id
      AND NOT (NEW.receiver_id IS NULL
               AND NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.receiver_id)))
     OR NEW.gym_id IS DISTINCT FROM OLD.gym_id
     OR NEW.content IS DISTINCT FROM OLD.content
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.is_automated IS DISTINCT FROM OLD.is_automated THEN
    RAISE EXCEPTION 'Only is_read may be updated on a message.';
  END IF;
  RETURN NEW;
END;
$function$;

-- Soft-delete: only the sender may retract their own message; the row is
-- hidden from both parties but kept for audit/export. Idempotent: a second
-- call returns the same id instead of raising.
CREATE OR REPLACE FUNCTION public.soft_delete_message(p_message_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_sender uuid;
  v_deleted timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication_required: you must be logged in';
  END IF;

  SELECT sender_id, deleted_at INTO v_sender, v_deleted
  FROM public.messages
  WHERE id = p_message_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: message does not exist';
  END IF;

  IF v_deleted IS NOT NULL THEN
    RETURN p_message_id;
  END IF;

  IF v_sender IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'forbidden: only the sender can delete a message';
  END IF;

  UPDATE public.messages
  SET deleted_at = now(),
      deleted_by = auth.uid()
  WHERE id = p_message_id;

  RETURN p_message_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.soft_delete_message(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_message(uuid) TO authenticated;

COMMENT ON COLUMN public.messages.deleted_at IS
  'DB-38 (round 5): soft-delete timestamp; NULL means the message is live. Hidden from SELECT/UPDATE by policy, never hard-deleted.';
