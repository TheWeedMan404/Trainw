-- DB-38 — forbid deleting a gym that still holds tenant data, and make
-- user deletion fail with a clear error instead of an opaque FK violation.
--
-- The finding: deleting a gym cascades (ON DELETE CASCADE on gym_id
-- throughout) to payments, sessions, memberships, media and more, with
-- no archive/soft-delete — one DELETE erases a tenant's entire
-- financial history. The full fix (is_active/archived flags plus an
-- admin-only purge job) is L and is NOT done here; this is the audit's
-- stated minimum, widened slightly from "payments only" to the data
-- whose loss is irreversible:
--   * a BEFORE DELETE trigger on gyms raises when the gym still has
--     payments, member profiles, sessions, check-ins, or coach profiles,
--     naming the blocking category and its count. An empty gym (only the
--     owner's membership row) can still be deleted.
--   * RLS already denies gym DELETEs for authenticated users (there is
--     no gyms DELETE policy and DB-41 grants no DELETE on gyms), so the
--     trigger is the backstop for service-role / direct-SQL deletes.
--   * a BEFORE DELETE trigger on users raises a clear error when
--     payments reference the user, instead of the opaque
--     "violates foreign key payments_client_id_fkey" the ON DELETE
--     RESTRICT produces today.
--
-- NOT changed here (deferred to the soft-delete work): messages.sender_id
-- and messages.receiver_id are NOT NULL ... ON DELETE CASCADE, so
-- deleting a user still erases the other party's copy of the
-- conversation. Fixing that needs the columns to become nullable (plus
-- chat UI handling for a deleted counterpart) — a schema + app change,
-- not a trigger.

CREATE OR REPLACE FUNCTION public.prevent_gym_delete_with_data()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payments integer;
  v_members integer;
  v_sessions integer;
  v_check_ins integer;
  v_coaches integer;
BEGIN
  SELECT count(*) INTO v_payments FROM public.payments WHERE gym_id = OLD.id;
  IF v_payments > 0 THEN
    RAISE EXCEPTION 'cannot_delete_gym: gym still has % payment(s); archive or refund them first', v_payments;
  END IF;

  SELECT count(*) INTO v_members FROM public.client_profiles WHERE gym_id = OLD.id;
  IF v_members > 0 THEN
    RAISE EXCEPTION 'cannot_delete_gym: gym still has % member profile(s); remove members first', v_members;
  END IF;

  SELECT count(*) INTO v_sessions FROM public.sessions WHERE gym_id = OLD.id;
  IF v_sessions > 0 THEN
    RAISE EXCEPTION 'cannot_delete_gym: gym still has % session(s)', v_sessions;
  END IF;

  SELECT count(*) INTO v_check_ins FROM public.check_ins WHERE gym_id = OLD.id;
  IF v_check_ins > 0 THEN
    RAISE EXCEPTION 'cannot_delete_gym: gym still has % check-in(s)', v_check_ins;
  END IF;

  SELECT count(*) INTO v_coaches FROM public.coach_profiles WHERE gym_id = OLD.id;
  IF v_coaches > 0 THEN
    RAISE EXCEPTION 'cannot_delete_gym: gym still has % coach profile(s); remove coaches first', v_coaches;
  END IF;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_gym_delete_with_data ON public.gyms;
CREATE TRIGGER trg_prevent_gym_delete_with_data
  BEFORE DELETE ON public.gyms
  FOR EACH ROW EXECUTE FUNCTION public.prevent_gym_delete_with_data();

CREATE OR REPLACE FUNCTION public.prevent_user_delete_with_payments()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payments integer;
BEGIN
  SELECT count(*) INTO v_payments FROM public.payments WHERE client_id = OLD.id;
  IF v_payments > 0 THEN
    RAISE EXCEPTION 'cannot_delete_user: user still has % payment(s); archive or refund them first', v_payments;
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_user_delete_with_payments ON public.users;
CREATE TRIGGER trg_prevent_user_delete_with_payments
  BEFORE DELETE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_delete_with_payments();
