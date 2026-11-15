-- ============================================================================
-- TRAINW PHASE 1B — ROLE SEEDING + POLICY HARDENING + MISSING INDEXES
-- Audit 2026-11-14: DB-32, DB-34, DB-29, DB-30, DB-39, DB-53, DB-54, DB-56,
--   DB-58, DB-60, DB-26. Plus the client_profiles.gym_id backfill the
--   FE-07 frontend fixes depend on.
-- Branch: phase1-security-fixes. Local only — NOT applied to any live DB.
--
-- DB-32 — users_role_check only allowed ('client','coach','gym_owner',
--   'gym','admin'), but sync_legacy_user_membership_projection writes the
--   RAW role_code, which can be 'gym_admin' or 'staff' — so syncing a
--   gym_admin/staff member failed the check. The check now also allows
--   'gym_admin' and 'staff'.
-- DB-34 — ensure_gym_default_roles() used ON CONFLICT DO UPDATE (rewriting
--   name/description/portal/is_system on every deploy) and called the
--   destructive ensure_role_permission_codes() (DELETE + re-INSERT of all
--   role_permissions). Deploy-time seeding is now insert-only: roles use
--   ON CONFLICT DO NOTHING, and permissions go through the new
--   ensure_role_permission_codes_missing() (ON CONFLICT DO NOTHING).
--   ensure_role_permission_codes() itself is unchanged — it stays the
--   explicit replace used by save_role_definition(), which is an admin
--   action, not a deploy step.
-- DB-29 — every gym_profiles policy was satisfied by user_id = auth.uid()
--   alone: any user could create/update/delete a gym_profiles row with ANY
--   gym_id. The self branch now also requires a membership in that gym
--   (a NULL gym_id row stays owner-editable — it belongs to no gym).
-- DB-30 — messages_update let the receiver update ANY column (sender_id,
--   receiver_id, gym_id, content...). A trigger now freezes everything
--   except is_read.
-- DB-39 — the seven missing indexes from the audit (hot RLS/policy paths
--   at 5,000+ members per tenant).
-- DB-53 — messages had no gym-consistency enforcement on INSERT: a trigger
--   now requires gym_id and requires both sender and receiver to belong
--   to that gym (active/accepted membership, or the gym's manager). The
--   trigger is SECURITY DEFINER so its membership lookups are not subject
--   to the caller's RLS.
-- DB-54 — staff_profiles_update let a user edit their own row with no gym
--   check and change gym_id, national_id, is_active, hire_date. A trigger
--   now forbids gym_id/user_id changes outright, and forbids self-edits of
--   national_id / is_active / hire_date (manager-only).
-- DB-56 — personal_records had no value CHECK and no UPDATE policy;
--   milestone_photos had no UPDATE policy; both INSERT policies accepted
--   any gym_id. Added: value > 0 CHECK (NOT VALID — validate on staging
--   after reviewing existing rows), owner-only UPDATE policies, and a
--   gym-membership requirement on INSERT/UPDATE.
-- DB-58 — coach_profiles.approved_by had its FK dropped in 006. Re-added
--   as FOREIGN KEY ... ON DELETE SET NULL, NOT VALID (existing rows are
--   not re-validated; validate on staging after review).
-- DB-60 — the trainw-media bucket allowed image/svg+xml (stored-XSS
--   vector via an SVG that executes in the browser). Removed from the
--   bucket's allowed MIME types.
-- DB-26 — manual check-ins (any non-service_role insert into check_ins)
--   must pass membership_is_active_for_access for that gym. The gate
--   functions insert as service_role and enforce membership themselves,
--   so they bypass; managers/coaches/clients inserting manually are
--   checked. A data-repair insert by the owner must disable the trigger
--   first (documented).
-- BACKFILL — client_profiles.gym_id is NULL for manager-created and
--   self-registered clients, which would make the new FE-07
--   .eq('gym_id', currentGymId) filters miss their rows. This migration
--   backfills gym_id from users.gym_id (the default gym) where no
--   profile row already exists for (user, gym) — the unique partial
--   index uq_client_profiles_user_gym forbids a second row for the same
--   pair, so conflicting rows are skipped and reported in the notes.
--
-- VERIFICATION (no live DB was available when this was written):
--   * Sync a gym_admin member: users.role='gym_admin' must not fail.
--   * Run ensure_gym_default_roles twice: the second run must not change
--     any role row or delete any role_permissions row.
--   * As a plain user, INSERT/UPDATE a gym_profiles row with another
--     gym's id must fail; with your own gym must work.
--   * UPDATE a message's content/sender_id as the receiver must fail;
--     updating is_read must work.
--   * INSERT a message naming a sender/receiver outside the gym must fail.
--   * UPDATE your own staff_profiles row changing national_id must fail.
--   * INSERT a check_in for an expired member (non-service_role) must fail.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BACKFILL — client_profiles.gym_id from users.gym_id (FE-07 prerequisite).
-- ----------------------------------------------------------------------------

UPDATE public.client_profiles cp
SET gym_id = u.gym_id
FROM public.users u
WHERE cp.gym_id IS NULL
  AND cp.user_id = u.id
  AND u.gym_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.client_profiles cp2
    WHERE cp2.user_id = cp.user_id
      AND cp2.gym_id = u.gym_id
  );

-- ----------------------------------------------------------------------------
-- DB-32 — widen users_role_check.
-- ----------------------------------------------------------------------------

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE public.users
  ADD CONSTRAINT users_role_check
  CHECK (role IN ('client', 'coach', 'gym_owner', 'gym', 'admin', 'gym_admin', 'staff'));

-- ----------------------------------------------------------------------------
-- DB-34 — insert-only role seeding.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ensure_role_permission_codes_missing(
  p_role_id uuid,
  p_permission_codes text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gym_id uuid;
BEGIN
  SELECT gym_id INTO v_gym_id FROM public.roles WHERE id = p_role_id;
  IF v_gym_id IS NULL THEN
    RAISE EXCEPTION 'role not found: %', p_role_id;
  END IF;

  -- Same authorisation as ensure_role_permission_codes (round 1, P1-4).
  IF auth.uid() IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = v_gym_id AND g.manager_id = auth.uid()) THEN
      NULL; -- gym manager: allowed
    ELSIF public.has_permission('manage_roles', v_gym_id) THEN
      NULL; -- manage_roles holder: allowed
    ELSE
      RAISE EXCEPTION 'permission denied: manage_roles required for gym %', v_gym_id;
    END IF;
  END IF;

  -- Insert-only: never DELETEs existing permissions (unlike
  -- ensure_role_permission_codes, which is the explicit admin replace).
  INSERT INTO public.role_permissions (role_id, permission_id)
  SELECT
    p_role_id,
    p.id
  FROM public.permissions p
  WHERE p.code = ANY(COALESCE(p_permission_codes, ARRAY[]::text[]))
  ON CONFLICT DO NOTHING;
END;
$$;

-- Internal-only, like its sibling (round 1 revoked both from PUBLIC and
-- authenticated): deploy seeding must not be callable as an RPC.
REVOKE ALL ON FUNCTION public.ensure_role_permission_codes_missing(uuid, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_role_permission_codes_missing(uuid, text[]) FROM authenticated;

CREATE OR REPLACE FUNCTION public.ensure_gym_default_roles(
  p_gym_id uuid,
  p_created_by uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_id uuid;
BEGIN
  -- P1-4: same authorisation as ensure_role_permission_codes above.
  IF auth.uid() IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = p_gym_id AND g.manager_id = auth.uid()) THEN
      NULL; -- gym manager: allowed
    ELSIF public.has_permission('manage_roles', v_gym_id) THEN
      NULL; -- manage_roles holder: allowed
    ELSE
      RAISE EXCEPTION 'permission denied: manage_roles required for gym %', p_gym_id;
    END IF;
  END IF;

  -- DB-34: insert-only. A re-run must not rewrite an existing role's
  -- name/description/portal/is_system (a manager may have customised them).
  INSERT INTO public.roles (gym_id, code, name, description, portal, is_system, is_default, created_by)
  VALUES
    (p_gym_id, 'gym_owner', 'Gym Owner', 'Full tenant administration access.', 'admin', true, true, p_created_by),
    (p_gym_id, 'gym_admin', 'Gym Admin', 'Operational administration for a tenant.', 'admin', true, false, p_created_by),
    (p_gym_id, 'staff', 'Staff', 'Read-only or operational front-desk staff role.', 'admin', true, false, p_created_by),
    (p_gym_id, 'coach', 'Coach', 'Coach workspace access.', 'coach', true, false, p_created_by),
    (p_gym_id, 'client', 'Client', 'Client workspace access.', 'client', true, false, p_created_by)
  ON CONFLICT (gym_id, code) DO NOTHING;

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'gym_owner';
  PERFORM public.ensure_role_permission_codes_missing(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'edit_clients', 'delete_clients',
    'view_coaches', 'edit_coaches', 'manage_sessions', 'manage_bookings',
    'manage_payments', 'view_analytics', 'manage_staff', 'manage_roles',
    'manage_branding', 'manage_messages', 'manage_checkins', 'manage_classes',
    'manage_media', 'self_manage_profile', 'view_staff_profiles',
    'edit_staff_profiles', 'manage_access_control', 'view_access_logs'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'gym_admin';
  PERFORM public.ensure_role_permission_codes_missing(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'edit_clients', 'delete_clients',
    'view_coaches', 'edit_coaches', 'manage_sessions', 'manage_bookings',
    'manage_payments', 'view_analytics', 'manage_staff', 'manage_branding',
    'manage_messages', 'manage_checkins', 'manage_classes', 'manage_media',
    'self_manage_profile', 'view_staff_profiles', 'edit_staff_profiles',
    'manage_access_control', 'view_access_logs'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'staff';
  PERFORM public.ensure_role_permission_codes_missing(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'view_coaches', 'manage_bookings',
    'manage_messages', 'manage_checkins', 'manage_classes', 'self_manage_profile',
    'view_staff_profiles'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'coach';
  PERFORM public.ensure_role_permission_codes_missing(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'edit_clients', 'manage_sessions',
    'manage_bookings', 'manage_messages', 'manage_media', 'self_manage_profile'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'client';
  PERFORM public.ensure_role_permission_codes_missing(v_role_id, ARRAY[
    'view_dashboard', 'manage_bookings', 'manage_messages', 'manage_media',
    'self_manage_profile'
  ]);
END;
$$;

-- ----------------------------------------------------------------------------
-- DB-29 — gym_profiles self branch requires a membership in that gym.
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS gym_profiles_select ON public.gym_profiles;
DROP POLICY IF EXISTS gym_profiles_insert ON public.gym_profiles;
DROP POLICY IF EXISTS gym_profiles_update ON public.gym_profiles;
DROP POLICY IF EXISTS gym_profiles_delete ON public.gym_profiles;

CREATE POLICY gym_profiles_select ON public.gym_profiles
  FOR SELECT
  USING (
    (user_id = auth.uid() AND (gym_id IS NULL OR public.user_has_membership(gym_id)))
    OR public.manages_gym(gym_id)
  );

CREATE POLICY gym_profiles_insert ON public.gym_profiles
  FOR INSERT
  WITH CHECK (
    (user_id = auth.uid() AND (gym_id IS NULL OR public.user_has_membership(gym_id)))
    OR public.manages_gym(gym_id)
  );

CREATE POLICY gym_profiles_update ON public.gym_profiles
  FOR UPDATE
  USING (
    (user_id = auth.uid() AND (gym_id IS NULL OR public.user_has_membership(gym_id)))
    OR public.manages_gym(gym_id)
  )
  WITH CHECK (
    (user_id = auth.uid() AND (gym_id IS NULL OR public.user_has_membership(gym_id)))
    OR public.manages_gym(gym_id)
  );

CREATE POLICY gym_profiles_delete ON public.gym_profiles
  FOR DELETE
  USING (
    (user_id = auth.uid() AND (gym_id IS NULL OR public.user_has_membership(gym_id)))
    OR public.manages_gym(gym_id)
  );

-- ----------------------------------------------------------------------------
-- DB-30 — messages: only is_read may change on UPDATE.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.forbid_message_field_updates()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.sender_id IS DISTINCT FROM OLD.sender_id
     OR NEW.receiver_id IS DISTINCT FROM OLD.receiver_id
     OR NEW.gym_id IS DISTINCT FROM OLD.gym_id
     OR NEW.content IS DISTINCT FROM OLD.content
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.is_automated IS DISTINCT FROM OLD.is_automated THEN
    RAISE EXCEPTION 'Only is_read may be updated on a message.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_forbid_field_updates ON public.messages;
CREATE TRIGGER trg_messages_forbid_field_updates
  BEFORE UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.forbid_message_field_updates();

-- ----------------------------------------------------------------------------
-- DB-53 — messages: gym consistency on INSERT (both parties belong).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_message_gym()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.gym_id IS NULL THEN
    RAISE EXCEPTION 'Message gym is required.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.gym_memberships gm
    WHERE gm.gym_id = NEW.gym_id
      AND gm.user_id = NEW.sender_id
      AND gm.status IN ('accepted', 'active')
  ) AND NOT EXISTS (
    SELECT 1
    FROM public.gyms g
    WHERE g.id = NEW.gym_id
      AND g.manager_id = NEW.sender_id
  ) THEN
    RAISE EXCEPTION 'Sender does not belong to this gym.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.gym_memberships gm
    WHERE gm.gym_id = NEW.gym_id
      AND gm.user_id = NEW.receiver_id
      AND gm.status IN ('accepted', 'active')
  ) AND NOT EXISTS (
    SELECT 1
    FROM public.gyms g
    WHERE g.id = NEW.gym_id
      AND g.manager_id = NEW.receiver_id
  ) THEN
    RAISE EXCEPTION 'Receiver does not belong to this gym.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_enforce_gym ON public.messages;
CREATE TRIGGER trg_messages_enforce_gym
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.enforce_message_gym();

-- ----------------------------------------------------------------------------
-- DB-54 — staff_profiles: no gym/user changes; sensitive fields manager-only.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_staff_profile_gym()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.gym_id IS DISTINCT FROM OLD.gym_id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
      RAISE EXCEPTION 'Staff profile gym and user cannot be changed.';
    END IF;

    -- Self-edits (caller is the profile owner, not a manager): sensitive
    -- fields are manager-only.
    IF OLD.user_id = auth.uid() AND NOT public.manages_gym(OLD.gym_id) THEN
      IF NEW.national_id IS DISTINCT FROM OLD.national_id
         OR NEW.is_active IS DISTINCT FROM OLD.is_active
         OR NEW.hire_date IS DISTINCT FROM OLD.hire_date THEN
        RAISE EXCEPTION 'national_id, is_active and hire_date are manager-only.';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_staff_profiles_enforce_gym ON public.staff_profiles;
CREATE TRIGGER trg_staff_profiles_enforce_gym
  BEFORE UPDATE ON public.staff_profiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_staff_profile_gym();

-- ----------------------------------------------------------------------------
-- DB-56 — personal_records / milestone_photos: value CHECK, UPDATE policies,
-- gym restriction on INSERT/UPDATE.
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.personal_records'::regclass
      AND conname = 'personal_records_value_positive'
  ) THEN
    ALTER TABLE public.personal_records
      ADD CONSTRAINT personal_records_value_positive
      CHECK (value > 0) NOT VALID;
  END IF;
END $$;

DROP POLICY IF EXISTS personal_records_insert ON public.personal_records;
CREATE POLICY personal_records_insert ON public.personal_records
  FOR INSERT
  WITH CHECK (
    client_id = auth.uid()
    AND (gym_id IS NULL OR public.user_has_membership(gym_id))
  );

DROP POLICY IF EXISTS personal_records_update ON public.personal_records;
CREATE POLICY personal_records_update ON public.personal_records
  FOR UPDATE
  USING (
    client_id = auth.uid()
    AND (gym_id IS NULL OR public.user_has_membership(gym_id))
  )
  WITH CHECK (
    client_id = auth.uid()
    AND (gym_id IS NULL OR public.user_has_membership(gym_id))
  );

DROP POLICY IF EXISTS milestone_photos_insert ON public.milestone_photos;
CREATE POLICY milestone_photos_insert ON public.milestone_photos
  FOR INSERT
  WITH CHECK (
    client_id = auth.uid()
    AND (gym_id IS NULL OR public.user_has_membership(gym_id))
  );

DROP POLICY IF EXISTS milestone_photos_update ON public.milestone_photos;
CREATE POLICY milestone_photos_update ON public.milestone_photos
  FOR UPDATE
  USING (
    client_id = auth.uid()
    AND (gym_id IS NULL OR public.user_has_membership(gym_id))
  )
  WITH CHECK (
    client_id = auth.uid()
    AND (gym_id IS NULL OR public.user_has_membership(gym_id))
  );

-- ----------------------------------------------------------------------------
-- DB-58 — coach_profiles.approved_by FK (ON DELETE SET NULL, NOT VALID).
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.coach_profiles'::regclass
      AND conname = 'coach_profiles_approved_by_fkey'
  ) THEN
    ALTER TABLE public.coach_profiles
      ADD CONSTRAINT coach_profiles_approved_by_fkey
      FOREIGN KEY (approved_by) REFERENCES public.users(id)
      ON DELETE SET NULL NOT VALID;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- DB-60 — trainw-media bucket: no SVG uploads.
-- ----------------------------------------------------------------------------

UPDATE storage.buckets
SET allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/webp']
WHERE id = 'trainw-media';

-- ----------------------------------------------------------------------------
-- DB-39 — the seven missing indexes.
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_phase1b_milestone_photos_client_created
  ON public.milestone_photos(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_phase1b_workout_plans_gym_updated
  ON public.workout_plans(gym_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_phase1b_workout_logs_gym_completed
  ON public.workout_logs(gym_id, completed_at DESC);
CREATE INDEX IF NOT EXISTS idx_phase1b_client_goals_gym_created
  ON public.client_goals(gym_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_phase1b_staff_profiles_membership
  ON public.staff_profiles(membership_id);
CREATE INDEX IF NOT EXISTS idx_phase1b_sessions_client_date
  ON public.sessions(client_id, session_date);
CREATE INDEX IF NOT EXISTS idx_phase1b_users_default_gym
  ON public.users(default_gym_id);

-- ----------------------------------------------------------------------------
-- DB-26 — manual check-ins must pass the membership check.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_check_in_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Service-role callers (the gate functions) enforce membership
  -- themselves before inserting, so they bypass. Everyone else — a
  -- manager, coach or client inserting manually — must hold an active
  -- membership for this gym.
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    IF NOT public.membership_is_active_for_access(NEW.client_id, NEW.gym_id, CURRENT_DATE) THEN
      RAISE EXCEPTION 'Membership is not active for check-in.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_ins_membership ON public.check_ins;
CREATE TRIGGER trg_check_ins_membership
  BEFORE INSERT ON public.check_ins
  FOR EACH ROW EXECUTE FUNCTION public.enforce_check_in_membership();
