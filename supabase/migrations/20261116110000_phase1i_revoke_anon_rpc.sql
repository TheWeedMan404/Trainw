-- ============================================================================
-- TRAINW ROUND 9 — REVOKE ANON ON ALL PREVIOUSLY-REVOKED RPCs (DB-03/DB-04)
-- Branch: phase1-security-fixes.
--
-- WHY THIS EXISTS: every REVOKE in the chain so far says FROM PUBLIC only.
-- On Supabase that does NOT remove anonymous access: Supabase's default
-- privileges grant EXECUTE on a new function explicitly to
-- anon, authenticated AND service_role (plus Postgres's own PUBLIC
-- default). REVOKE FROM PUBLIC removes only the PUBLIC pseudo-grant; the
-- explicit anon grant survives on every one of these functions.
--
-- PROVED LIVE 2026-11-15 (TEST data only): with the anon key alone and
-- NO Authorization header, POST /rest/v1/rpc/ensure_gym_default_roles
-- on 'TEST R9 Anon Probe Gym' returned HTTP 204 and seeded 5 default
-- roles (0 -> 5). The P1-4 internal check cannot stop this: it treats
-- auth.uid() IS NULL as trusted server/migration context, so the grant
-- was the only barrier — and it was never there. DB-03/DB-04 (audit
-- CRITICAL: anyone can rewrite any gym's roles/permissions) was still
-- exploitable by any stranger holding the publishable anon key.
--
-- FIX: revoke EXECUTE from anon (and PUBLIC, for completeness) on every
-- function the chain ever revoked from PUBLIC — 36 signatures, including
-- the 4 round-9 join RPCs. Authenticated grants are untouched (the
-- frontend needs them); internal SECURITY DEFINER callers are unaffected
-- (they run as the function owner). After this, the auth.uid() IS NULL
-- branch in the role functions is reachable only by the owner /
-- service_role — the server context it was written for.
--
-- Each REVOKE is guarded by an existence check so a fresh apply can
-- never fail on a signature that drifted.
-- ============================================================================

DO $$
BEGIN
  IF to_regprocedure('public.approve_gym_membership(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.approve_gym_membership(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.auth_user_email(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.auth_user_email(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.book_coach_session(uuid, date, time, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.book_coach_session(uuid, date, time, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.cancel_membership_freeze(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.cancel_membership_freeze(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.cancel_session_booking(uuid, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.cancel_session_booking(uuid, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.complete_session_booking(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.complete_session_booking(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.confirm_coach_client_assignment(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.confirm_coach_client_assignment(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.create_gym_specialty_tag(uuid, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.create_gym_specialty_tag(uuid, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.end_coach_client_assignment(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.end_coach_client_assignment(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.ensure_gym_default_roles(uuid, uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.ensure_gym_default_roles(uuid, uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.ensure_role_permission_codes(uuid, text[])') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.ensure_role_permission_codes(uuid, text[]) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.ensure_role_permission_codes_missing(uuid, text[])') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.ensure_role_permission_codes_missing(uuid, text[]) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.export_member_data(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.export_member_data(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.get_bookable_slots(uuid, date)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.get_bookable_slots(uuid, date) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.hash_member_credential(text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.hash_member_credential(text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.leave_session_review(uuid, integer, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.leave_session_review(uuid, integer, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.list_public_gyms()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.list_public_gyms() FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.mark_session_no_show(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.mark_session_no_show(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.permission_codes_for_membership(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.permission_codes_for_membership(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.record_gate_credential_failure(uuid, text, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.record_gate_credential_failure(uuid, text, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.record_payment_refund(uuid, numeric, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.record_payment_refund(uuid, numeric, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.reject_gym_membership(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.reject_gym_membership(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.request_gym_membership(uuid, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.request_gym_membership(uuid, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.request_membership_freeze(uuid, uuid, date, date, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.request_membership_freeze(uuid, uuid, date, date, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.respond_to_session_booking(uuid, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.respond_to_session_booking(uuid, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.soft_delete_message(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.soft_delete_message(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.storage_object_is_public(text, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.storage_object_is_public(text, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.sync_legacy_user_membership_projection(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.sync_legacy_user_membership_projection(uuid) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.trainw_ai_proxy_consume_quota(integer)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.trainw_ai_proxy_consume_quota(integer) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.trainw_backfill_member_credential_hashes()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.trainw_backfill_member_credential_hashes() FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.trainw_gate_rate_limit_consume(text, integer)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.trainw_gate_rate_limit_consume(text, integer) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.turnstile_truncate_credential_ref(text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.turnstile_truncate_credential_ref(text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.validate_booking_consistency()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.validate_booking_consistency() FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.validate_gate_session(text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.validate_gate_session(text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.validate_member_credential(uuid, text, text, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.validate_member_credential(uuid, text, text, text) FROM anon, PUBLIC;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regprocedure('public.validate_session_coach_update()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.validate_session_coach_update() FROM anon, PUBLIC;
  END IF;
END $$;
