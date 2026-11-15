-- ============================================================================
-- Phase 1 — P1-1 (DB-01), P1-2 (DB-02), P1-3 (DB-05, DB-06)
-- Audit: trainw-security-audit-2026-11-14.md
--
-- Closes the self-update holes with BEFORE UPDATE triggers:
--   * client_profiles: a client can no longer change payment_status,
--     price_paid, membership_start_date, membership_end_date or
--     membership_tier on their own row (DB-01 — self-pay hole).
--   * coach_profiles: a coach can only edit bio/specialty/contact fields
--     on their own row; approval_status, rating, stats and pricing are
--     manager-only (DB-02 — self-approve hole).
--   * users: a user can only change name, phone, avatar_url and
--     language_preference on their own row; role, gym_id, is_active,
--     is_managed and the gym pointers are manager/server-side only (DB-05).
--   * gyms_update policy restored to the 004 form: only manages_gym(id)
--     may UPDATE a gym (DB-06 — any member could rewrite the gym).
--
-- HOW THE GUARDS TELL "SELF-UPDATE" FROM "SERVER-SIDE UPDATE":
--   Legitimate server-side code updates these same rows as the user
--   themselves: bootstrap_authenticated_user upserts the users row on login,
--   sync_legacy_user_membership_projection rewrites users.role/gym_id when
--   a user switches gyms (set_active_gym), and the review-aggregate trigger
--   updates coach_profiles. All of that runs inside SECURITY DEFINER
--   functions (or migrations), where current_user is the function/table
--   owner ('postgres'), or as the service role from edge functions.
--   Direct API calls from a browser run as the 'authenticated' (or 'anon')
--   role. The guards therefore only enforce when
--   current_user NOT IN ('postgres', 'service_role').
--   The trigger functions MUST stay SECURITY INVOKER (the default) or this
--   check stops working.
--   >>> LIVE-TEST REQUIRED (P1-13): after applying, log in as a normal
--   user, switch gyms (set_active_gym) and re-run bootstrap; both must
--   still work. If current_user does not reflect the caller context in the
--   live project, replace this discriminator with an explicit SET LOCAL
--   flag set inside bootstrap_authenticated_user and
--   sync_legacy_user_membership_projection.
--
-- VERIFICATION (no live DB was available when this was written):
--   As a test client, UPDATE client_profiles SET payment_status='paid'
--   on your own row via the API -> must fail with the trigger exception.
--   As a pending coach, UPDATE coach_profiles SET approval_status='approved'
--   on your own row -> must fail. As a client, UPDATE users SET
--   role='gym_owner' on your own row -> must fail. As a client, UPDATE
--   gyms SET name='x' on your own gym -> must fail (policy).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- P1-1 — client_profiles self-update guard (DB-01)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trainw_guard_client_profile_self_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Server-side context (migrations, SECURITY DEFINER functions, service
  -- role): not a direct API call, guard does not apply.
  IF current_user IN ('postgres', 'service_role') THEN
    RETURN NEW;
  END IF;

  -- The profile owner acting alone may not touch money/date/tier fields.
  -- A manager of the gym (manages_gym) is unrestricted; RLS already limits
  -- who can reach this trigger as a manager.
  IF OLD.user_id = auth.uid() AND NOT public.manages_gym(OLD.gym_id) THEN
    IF NEW.payment_status IS DISTINCT FROM OLD.payment_status THEN
      RAISE EXCEPTION 'Clients cannot change payment_status. Ask a gym manager.';
    END IF;
    IF NEW.price_paid IS DISTINCT FROM OLD.price_paid THEN
      RAISE EXCEPTION 'Clients cannot change price_paid. Ask a gym manager.';
    END IF;
    IF NEW.membership_start_date IS DISTINCT FROM OLD.membership_start_date THEN
      RAISE EXCEPTION 'Clients cannot change membership_start_date. Ask a gym manager.';
    END IF;
    IF NEW.membership_end_date IS DISTINCT FROM OLD.membership_end_date THEN
      RAISE EXCEPTION 'Clients cannot change membership_end_date. Ask a gym manager.';
    END IF;
    IF NEW.membership_tier IS DISTINCT FROM OLD.membership_tier THEN
      RAISE EXCEPTION 'Clients cannot change membership_tier. Ask a gym manager.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Runs before trg_client_profiles_upd (set_updated_at) by trigger-name order.
DROP TRIGGER IF EXISTS trg_client_profiles_self_guard ON public.client_profiles;
CREATE TRIGGER trg_client_profiles_self_guard
  BEFORE UPDATE ON public.client_profiles
  FOR EACH ROW EXECUTE FUNCTION public.trainw_guard_client_profile_self_update();

-- ----------------------------------------------------------------------------
-- P1-2 — coach_profiles self-update guard (DB-02)
-- Self-service allow-list: bio, specialty, specialties, experience_years,
-- certifications, instagram_url, whatsapp_number. Everything else
-- (approval_status, rating, total_reviews, sessions_completed, pricing,
-- identity columns, is_active) is manager/server-side only.
-- updated_at is excluded from the check: trg_coach_profiles_upd maintains it.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trainw_guard_coach_profile_self_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('postgres', 'service_role') THEN
    RETURN NEW;
  END IF;

  IF OLD.user_id = auth.uid() AND NOT public.manages_gym(OLD.gym_id) THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
      OR NEW.gym_id IS DISTINCT FROM OLD.gym_id
      OR NEW.sessions_completed IS DISTINCT FROM OLD.sessions_completed
      OR NEW.hourly_rate IS DISTINCT FROM OLD.hourly_rate
      OR NEW.price_per_session IS DISTINCT FROM OLD.price_per_session
      OR NEW.rating IS DISTINCT FROM OLD.rating
      OR NEW.total_reviews IS DISTINCT FROM OLD.total_reviews
      OR NEW.approval_status IS DISTINCT FROM OLD.approval_status
      OR NEW.approved_at IS DISTINCT FROM OLD.approved_at
      OR NEW.approved_by IS DISTINCT FROM OLD.approved_by
      OR NEW.is_active IS DISTINCT FROM OLD.is_active
    THEN
      RAISE EXCEPTION 'Coaches can only edit their bio, specialty, experience, certifications and contact details. Approval, rating, stats and pricing are manager-only.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_coach_profiles_self_guard ON public.coach_profiles;
CREATE TRIGGER trg_coach_profiles_self_guard
  BEFORE UPDATE ON public.coach_profiles
  FOR EACH ROW EXECUTE FUNCTION public.trainw_guard_coach_profile_self_update();

-- ----------------------------------------------------------------------------
-- P1-3 — users self-update guard (DB-05)
-- Self-service allow-list: name, phone, avatar_url, language_preference.
-- Everything else (email, role, gym_id, is_active, is_managed,
-- default_gym_id, default_membership_id, last_seen_at, created_at) is
-- manager/server-side only. updated_at is excluded: server-side code
-- maintains it (bootstrap / sync_legacy_user_membership_projection run as
-- the function owner and are skipped by the current_user check above).
-- NOTE: bootstrap_authenticated_user re-activates a banned user on login
-- (it sets is_active = true as the function owner, so this guard does not
-- stop it). That pre-existing behaviour is out of Phase 1 scope; see
-- PHASE1_IMPLEMENTATION_NOTES.md.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trainw_guard_users_self_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('postgres', 'service_role') THEN
    RETURN NEW;
  END IF;

  IF OLD.id = auth.uid() THEN
    IF NEW.email IS DISTINCT FROM OLD.email
      OR NEW.role IS DISTINCT FROM OLD.role
      OR NEW.gym_id IS DISTINCT FROM OLD.gym_id
      OR NEW.is_managed IS DISTINCT FROM OLD.is_managed
      OR NEW.is_active IS DISTINCT FROM OLD.is_active
      OR NEW.default_gym_id IS DISTINCT FROM OLD.default_gym_id
      OR NEW.default_membership_id IS DISTINCT FROM OLD.default_membership_id
      OR NEW.last_seen_at IS DISTINCT FROM OLD.last_seen_at
      OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
      RAISE EXCEPTION 'You can only change your name, phone, avatar and language. Role, gym and account status are manager-only.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_self_guard ON public.users;
CREATE TRIGGER trg_users_self_guard
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.trainw_guard_users_self_update();

-- ----------------------------------------------------------------------------
-- P1-3 — gyms_update policy restored to the 004 form (DB-06)
-- 005 replaced it with (id = get_my_gym_id() OR manager_id = auth.uid()),
-- which let every member of the gym rewrite it. Only manages_gym(id) may
-- UPDATE a gym row.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS gyms_update ON public.gyms;
CREATE POLICY gyms_update ON public.gyms
  FOR UPDATE
  USING (public.manages_gym(id))
  WITH CHECK (public.manages_gym(id));
