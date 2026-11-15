-- ============================================================================
-- U8 (2026-11-15) — the owner's message to the client is invisible to the
-- client: the client Messages page lists only the Test Coach conversation.
-- ============================================================================
-- Root cause (proven live, 2026-11-15, TEST Gym 8a07bf89):
--   * The owner -> client message row EXISTS and the client's exact messages
--     query returns it (messages SELECT policy: sender or receiver = caller).
--   * But tw-client-acc.js builds the thread list from participants =
--     [primaryCoachId, ownerInfo.user_id], and ownerInfo comes from
--     list_gym_member_directory(). DB-21 (phase1b/phase1c) gates that RPC to
--     staff — caller must manage the gym or hold view_clients — so a plain
--     client gets ZERO rows, ownerInfo is null, and the owner thread is
--     never built. The message is loaded and then filtered out by the
--     thread builder, not by RLS.
--   * The reply path needs no change: can_message_user() already lets a
--     client message any active/accepted admin- or coach-portal member of
--     the same gym, and the owner's loadConversation() queries both
--     directions, so the owner sees the reply once the client can send it.
--
-- Fix: a minimal SECURITY DEFINER RPC, get_gym_owner_contact(p_gym_id),
-- returning ONLY the gym's owner/manager contact — user_id, display name,
-- role_code, portal — to a caller who holds an active, non-revoked
-- membership in that gym. No email, no phone, no permissions, no other
-- members: list_gym_member_directory stays staff-only (DB-21 untouched).
-- The client swaps one RPC name; the ownerInfo .find() filter and the
-- thread builder are unchanged, so the coach thread is unaffected.
-- Grants follow the round-9 / P2-6 pattern: REVOKE FROM anon, PUBLIC;
-- GRANT EXECUTE TO authenticated. The in-function membership gate also
-- rejects anon (auth.uid() NULL matches no membership row).
-- No RLS change. No data migration.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_gym_owner_contact(p_gym_id uuid)
RETURNS TABLE (
  user_id uuid,
  name text,
  role_code text,
  portal text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    gm.user_id,
    COALESCE(u.name, gm.invited_name, split_part(gm.invite_email::text, '@', 1), 'Contact') AS name,
    r.code AS role_code,
    r.portal
  FROM public.gym_memberships gm
  JOIN public.roles r
    ON r.id = gm.role_id
  LEFT JOIN public.users u
    ON u.id = gm.user_id
  WHERE gm.gym_id = p_gym_id
    AND gm.user_id IS NOT NULL
    AND gm.status <> 'revoked'
    AND r.portal = 'admin'
    AND r.code IN ('gym_owner', 'gym_admin')
    AND EXISTS (
      SELECT 1
      FROM public.gym_memberships caller
      WHERE caller.gym_id = p_gym_id
        AND caller.user_id = auth.uid()
        AND caller.status <> 'revoked'
    )
  ORDER BY
    CASE r.code WHEN 'gym_owner' THEN 0 ELSE 1 END,
    COALESCE(u.name, gm.invited_name, gm.invite_email::text);
$$;

REVOKE ALL ON FUNCTION public.get_gym_owner_contact(uuid) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_gym_owner_contact(uuid) TO authenticated;
