-- ============================================================================
-- TRAINW V16 - MULTI-TENANT RBAC SAAS HARDENING
-- Purpose:
--   - Replace single-gym role assumptions with explicit gym memberships
--   - Store roles and permissions in the database
--   - Add invitation, branding, media, and booking foundations
--   - Keep legacy columns synchronized for compatibility with the current app
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;


-- ----------------------------------------------------------------------------
-- BASE TABLE PATCHES
-- ----------------------------------------------------------------------------

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS default_gym_id uuid,
  ADD COLUMN IF NOT EXISTS default_membership_id uuid,
  ADD COLUMN IF NOT EXISTS avatar_storage_bucket text,
  ADD COLUMN IF NOT EXISTS avatar_storage_path text;

ALTER TABLE public.gyms
  ADD COLUMN IF NOT EXISTS logo_storage_bucket text,
  ADD COLUMN IF NOT EXISTS logo_storage_path text,
  ADD COLUMN IF NOT EXISTS price_monthly numeric(12,2) NOT NULL DEFAULT 150,
  ADD COLUMN IF NOT EXISTS price_quarterly numeric(12,2) NOT NULL DEFAULT 400,
  ADD COLUMN IF NOT EXISTS price_annual numeric(12,2) NOT NULL DEFAULT 1400;

ALTER TABLE public.coach_profiles
  ADD COLUMN IF NOT EXISTS media_asset_id uuid;

ALTER TABLE public.client_profiles
  ADD COLUMN IF NOT EXISTS media_asset_id uuid;


-- ----------------------------------------------------------------------------
-- NEW MULTI-TENANT TABLES
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.permissions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL UNIQUE,
  name        text NOT NULL,
  description text,
  category    text NOT NULL DEFAULT 'general',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.roles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id      uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  code        text NOT NULL,
  name        text NOT NULL,
  description text,
  portal      text NOT NULL DEFAULT 'client',
  is_system   boolean NOT NULL DEFAULT false,
  is_default  boolean NOT NULL DEFAULT false,
  created_by  uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT roles_portal_check CHECK (portal IN ('admin', 'coach', 'client'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_roles_gym_code
  ON public.roles(gym_id, code);

CREATE TABLE IF NOT EXISTS public.role_permissions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id       uuid NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_role_permissions_pair
  ON public.role_permissions(role_id, permission_id);

CREATE TABLE IF NOT EXISTS public.gym_memberships (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id            uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  user_id           uuid REFERENCES public.users(id) ON DELETE CASCADE,
  role_id           uuid NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
  status            text NOT NULL DEFAULT 'pending',
  invitation_status text NOT NULL DEFAULT 'pending',
  invite_email      citext,
  invited_name      text,
  invited_phone     text,
  invite_token      text UNIQUE,
  invited_by        uuid REFERENCES public.users(id) ON DELETE SET NULL,
  invited_at        timestamptz NOT NULL DEFAULT now(),
  accepted_at       timestamptz,
  activated_at      timestamptz,
  declined_at       timestamptz,
  revoked_at        timestamptz,
  is_default        boolean NOT NULL DEFAULT false,
  last_active_at    timestamptz,
  metadata          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT gym_memberships_status_check CHECK (
    status IN ('pending', 'accepted', 'active', 'declined', 'revoked')
  ),
  CONSTRAINT gym_memberships_invitation_status_check CHECK (
    invitation_status IN ('pending', 'accepted', 'declined', 'revoked')
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_gym_memberships_active_user
  ON public.gym_memberships(gym_id, user_id)
  WHERE user_id IS NOT NULL AND status IN ('pending', 'accepted', 'active');

CREATE UNIQUE INDEX IF NOT EXISTS uq_gym_memberships_pending_email
  ON public.gym_memberships(gym_id, invite_email)
  WHERE invite_email IS NOT NULL AND user_id IS NULL AND status IN ('pending', 'accepted', 'active');

CREATE INDEX IF NOT EXISTS idx_gym_memberships_gym_id
  ON public.gym_memberships(gym_id);

CREATE INDEX IF NOT EXISTS idx_gym_memberships_user_id
  ON public.gym_memberships(user_id);

CREATE TABLE IF NOT EXISTS public.user_permissions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id         uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  permission_id  uuid NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  effect         text NOT NULL DEFAULT 'allow',
  created_by     uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_permissions_effect_check CHECK (effect IN ('allow', 'deny'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_permissions_triplet
  ON public.user_permissions(gym_id, user_id, permission_id);

CREATE TABLE IF NOT EXISTS public.media_assets (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id           uuid REFERENCES public.gyms(id) ON DELETE CASCADE,
  owner_user_id    uuid REFERENCES public.users(id) ON DELETE SET NULL,
  entity_type      text NOT NULL,
  entity_id        uuid,
  media_kind       text NOT NULL,
  storage_bucket   text NOT NULL,
  storage_path     text NOT NULL,
  mime_type        text,
  file_size        bigint,
  created_by       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_media_assets_storage_ref
  ON public.media_assets(storage_bucket, storage_path);

CREATE INDEX IF NOT EXISTS idx_media_assets_gym_id
  ON public.media_assets(gym_id);

CREATE INDEX IF NOT EXISTS idx_media_assets_owner_user_id
  ON public.media_assets(owner_user_id);

CREATE TABLE IF NOT EXISTS public.bookings (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id         uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  session_id     uuid NOT NULL UNIQUE REFERENCES public.sessions(id) ON DELETE CASCADE,
  coach_id       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  client_id      uuid REFERENCES public.users(id) ON DELETE CASCADE,
  booked_by      uuid REFERENCES public.users(id) ON DELETE SET NULL,
  booking_source text NOT NULL DEFAULT 'session',
  status         text NOT NULL DEFAULT 'confirmed',
  notes          text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bookings_status_check CHECK (
    status IN ('pending', 'confirmed', 'completed', 'cancelled', 'declined', 'no_show')
  )
);

CREATE INDEX IF NOT EXISTS idx_bookings_gym_id
  ON public.bookings(gym_id);

CREATE INDEX IF NOT EXISTS idx_bookings_client_id
  ON public.bookings(client_id);

CREATE INDEX IF NOT EXISTS idx_bookings_coach_id
  ON public.bookings(coach_id);


-- ----------------------------------------------------------------------------
-- UPDATED-AT TRIGGERS
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_permissions_updated_at'
  ) THEN
    CREATE TRIGGER set_permissions_updated_at
    BEFORE UPDATE ON public.permissions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_roles_updated_at'
  ) THEN
    CREATE TRIGGER set_roles_updated_at
    BEFORE UPDATE ON public.roles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_gym_memberships_updated_at'
  ) THEN
    CREATE TRIGGER set_gym_memberships_updated_at
    BEFORE UPDATE ON public.gym_memberships
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_user_permissions_updated_at'
  ) THEN
    CREATE TRIGGER set_user_permissions_updated_at
    BEFORE UPDATE ON public.user_permissions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_media_assets_updated_at'
  ) THEN
    CREATE TRIGGER set_media_assets_updated_at
    BEFORE UPDATE ON public.media_assets
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_bookings_updated_at'
  ) THEN
    CREATE TRIGGER set_bookings_updated_at
    BEFORE UPDATE ON public.bookings
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- PERMISSION CATALOG
-- ----------------------------------------------------------------------------

INSERT INTO public.permissions (code, name, description, category)
VALUES
  ('view_dashboard', 'View dashboard', 'Access workspace summary views.', 'dashboard'),
  ('view_clients', 'View clients', 'Read client records for the active gym.', 'members'),
  ('edit_clients', 'Edit clients', 'Update client profiles and progress.', 'members'),
  ('delete_clients', 'Delete clients', 'Remove or revoke client access.', 'members'),
  ('view_coaches', 'View coaches', 'Read coach records for the active gym.', 'members'),
  ('edit_coaches', 'Edit coaches', 'Update coach profiles and assignments.', 'members'),
  ('manage_sessions', 'Manage sessions', 'Create and manage training sessions.', 'operations'),
  ('manage_bookings', 'Manage bookings', 'Create, confirm, and cancel bookings.', 'operations'),
  ('manage_payments', 'Manage payments', 'Create and reconcile payment records.', 'finance'),
  ('view_analytics', 'View analytics', 'Read analytics and business metrics.', 'analytics'),
  ('manage_staff', 'Manage staff', 'Invite members, edit roles, and revoke access.', 'admin'),
  ('manage_roles', 'Manage roles', 'Create custom roles and permission matrices.', 'admin'),
  ('manage_branding', 'Manage branding', 'Upload logos and workspace branding.', 'branding'),
  ('manage_messages', 'Manage messages', 'Read and send operational messages.', 'communication'),
  ('manage_checkins', 'Manage check-ins', 'Record and review access events.', 'operations'),
  ('manage_classes', 'Manage classes', 'Create classes and capacity plans.', 'operations'),
  ('manage_media', 'Manage media', 'Upload and attach media assets.', 'branding'),
  ('self_manage_profile', 'Manage own profile', 'Update profile and avatar for self-service use.', 'self')
ON CONFLICT (code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();


-- ----------------------------------------------------------------------------
-- HELPER FUNCTIONS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.safe_uuid(p_value text)
RETURNS uuid
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_value IS NULL OR BTRIM(p_value) = '' THEN
    RETURN NULL;
  END IF;
  RETURN p_value::uuid;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.normalize_role_code(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    NULLIF(
      regexp_replace(lower(BTRIM(COALESCE(p_value, ''))), '[^a-z0-9]+', '_', 'g'),
      ''
    ),
    'custom_role'
  );
$$;

CREATE OR REPLACE FUNCTION public.map_legacy_role_code(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(BTRIM(COALESCE(p_value, 'client')))
    WHEN 'gym_owner' THEN 'gym_owner'
    WHEN 'gym' THEN 'gym_admin'
    WHEN 'admin' THEN 'gym_admin'
    WHEN 'gym_admin' THEN 'gym_admin'
    WHEN 'coach' THEN 'coach'
    WHEN 'client' THEN 'client'
    ELSE 'staff'
  END;
$$;

CREATE OR REPLACE FUNCTION public.auth_user_email(p_user_id uuid DEFAULT auth.uid())
RETURNS citext
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT NULLIF(lower(BTRIM(u.email)), '')::citext
  FROM auth.users u
  WHERE u.id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION public.ensure_role_permission_codes(
  p_role_id uuid,
  p_permission_codes text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.role_permissions
  WHERE role_id = p_role_id;

  INSERT INTO public.role_permissions (role_id, permission_id)
  SELECT
    p_role_id,
    p.id
  FROM public.permissions p
  WHERE p.code = ANY(COALESCE(p_permission_codes, ARRAY[]::text[]));
END;
$$;

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
  INSERT INTO public.roles (gym_id, code, name, description, portal, is_system, is_default, created_by)
  VALUES
    (p_gym_id, 'gym_owner', 'Gym Owner', 'Full tenant administration access.', 'admin', true, true, p_created_by),
    (p_gym_id, 'gym_admin', 'Gym Admin', 'Operational administration for a tenant.', 'admin', true, false, p_created_by),
    (p_gym_id, 'staff', 'Staff', 'Read-only or operational front-desk staff role.', 'admin', true, false, p_created_by),
    (p_gym_id, 'coach', 'Coach', 'Coach workspace access.', 'coach', true, false, p_created_by),
    (p_gym_id, 'client', 'Client', 'Client workspace access.', 'client', true, false, p_created_by)
  ON CONFLICT (gym_id, code) DO UPDATE
  SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    portal = EXCLUDED.portal,
    is_system = EXCLUDED.is_system,
    updated_at = now();

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'gym_owner';
  PERFORM public.ensure_role_permission_codes(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'edit_clients', 'delete_clients',
    'view_coaches', 'edit_coaches', 'manage_sessions', 'manage_bookings',
    'manage_payments', 'view_analytics', 'manage_staff', 'manage_roles',
    'manage_branding', 'manage_messages', 'manage_checkins', 'manage_classes',
    'manage_media', 'self_manage_profile'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'gym_admin';
  PERFORM public.ensure_role_permission_codes(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'edit_clients', 'delete_clients',
    'view_coaches', 'edit_coaches', 'manage_sessions', 'manage_bookings',
    'manage_payments', 'view_analytics', 'manage_staff', 'manage_branding',
    'manage_messages', 'manage_checkins', 'manage_classes', 'manage_media',
    'self_manage_profile'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'staff';
  PERFORM public.ensure_role_permission_codes(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'view_coaches', 'manage_bookings',
    'manage_messages', 'manage_checkins', 'manage_classes', 'self_manage_profile'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'coach';
  PERFORM public.ensure_role_permission_codes(v_role_id, ARRAY[
    'view_dashboard', 'view_clients', 'edit_clients', 'manage_sessions',
    'manage_bookings', 'manage_messages', 'manage_media', 'self_manage_profile'
  ]);

  SELECT id INTO v_role_id FROM public.roles WHERE gym_id = p_gym_id AND code = 'client';
  PERFORM public.ensure_role_permission_codes(v_role_id, ARRAY[
    'view_dashboard', 'manage_bookings', 'manage_messages', 'manage_media',
    'self_manage_profile'
  ]);
END;
$$;

CREATE OR REPLACE FUNCTION public.permission_codes_for_membership(
  p_membership_id uuid
)
RETURNS text[]
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH membership_row AS (
    SELECT gm.id, gm.user_id, gm.gym_id, gm.role_id
    FROM public.gym_memberships gm
    WHERE gm.id = p_membership_id
  ),
  role_codes AS (
    SELECT p.code
    FROM membership_row mr
    JOIN public.role_permissions rp
      ON rp.role_id = mr.role_id
    JOIN public.permissions p
      ON p.id = rp.permission_id
  ),
  denied_codes AS (
    SELECT p.code
    FROM membership_row mr
    JOIN public.user_permissions up
      ON up.user_id = mr.user_id
     AND up.gym_id = mr.gym_id
     AND up.effect = 'deny'
    JOIN public.permissions p
      ON p.id = up.permission_id
  ),
  allowed_codes AS (
    SELECT p.code
    FROM membership_row mr
    JOIN public.user_permissions up
      ON up.user_id = mr.user_id
     AND up.gym_id = mr.gym_id
     AND up.effect = 'allow'
    JOIN public.permissions p
      ON p.id = up.permission_id
  )
  SELECT COALESCE(
    ARRAY(
      SELECT DISTINCT code
      FROM (
        SELECT code FROM role_codes
        UNION
        SELECT code FROM allowed_codes
      ) merged
      WHERE code NOT IN (SELECT code FROM denied_codes)
      ORDER BY code
    ),
    ARRAY[]::text[]
  );
$$;

CREATE OR REPLACE FUNCTION public.current_membership(
  p_requested_gym_id uuid DEFAULT NULL
)
RETURNS TABLE (
  membership_id uuid,
  gym_id uuid,
  role_id uuid,
  role_code text,
  role_name text,
  portal text,
  status text,
  is_default boolean,
  last_active_at timestamptz,
  permissions text[]
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH preferred_gym AS (
    SELECT COALESCE(
      p_requested_gym_id,
      (SELECT u.default_gym_id FROM public.users u WHERE u.id = auth.uid())
    ) AS gym_id
  ),
  ranked AS (
    SELECT
      gm.id AS membership_id,
      gm.gym_id,
      gm.role_id,
      r.code AS role_code,
      r.name AS role_name,
      r.portal,
      gm.status,
      gm.is_default,
      gm.last_active_at,
      public.permission_codes_for_membership(gm.id) AS permissions,
      ROW_NUMBER() OVER (
        ORDER BY
          CASE WHEN gm.gym_id = (SELECT gym_id FROM preferred_gym) THEN 0 ELSE 1 END,
          CASE gm.status WHEN 'active' THEN 0 WHEN 'accepted' THEN 1 ELSE 2 END,
          gm.is_default DESC,
          CASE r.code WHEN 'gym_owner' THEN 0 WHEN 'gym_admin' THEN 1 WHEN 'staff' THEN 2 WHEN 'coach' THEN 3 ELSE 4 END,
          gm.last_active_at DESC NULLS LAST,
          gm.created_at ASC
      ) AS rn
    FROM public.gym_memberships gm
    JOIN public.roles r
      ON r.id = gm.role_id
    WHERE gm.user_id = auth.uid()
      AND gm.status IN ('accepted', 'active')
      AND (p_requested_gym_id IS NULL OR gm.gym_id = p_requested_gym_id)
  )
  SELECT
    membership_id,
    gym_id,
    role_id,
    role_code,
    role_name,
    portal,
    status,
    is_default,
    last_active_at,
    permissions
  FROM ranked
  WHERE rn = 1;
$$;

CREATE OR REPLACE FUNCTION public.user_has_membership(
  p_gym_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.gym_memberships gm
    WHERE gm.user_id = p_user_id
      AND gm.gym_id = p_gym_id
      AND gm.status IN ('accepted', 'active')
  );
$$;

CREATE OR REPLACE FUNCTION public.get_my_gym_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT gym_id
  FROM public.current_membership(NULL)
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role_code
  FROM public.current_membership(NULL)
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_my_portal()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT portal
  FROM public.current_membership(NULL)
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_my_permissions(
  p_gym_id uuid DEFAULT NULL
)
RETURNS text[]
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT permissions
  FROM public.current_membership(p_gym_id)
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.has_permission(
  p_permission_code text,
  p_gym_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(p_permission_code = ANY(public.get_my_permissions(p_gym_id)), false);
$$;

CREATE OR REPLACE FUNCTION public.is_gym_manager()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(public.get_my_portal() = 'admin', false);
$$;

CREATE OR REPLACE FUNCTION public.manages_gym(p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    public.user_has_membership(p_gym_id)
    AND (
      public.get_my_portal() = 'admin'
      OR public.has_permission('manage_staff', p_gym_id)
      OR public.has_permission('manage_branding', p_gym_id)
    ),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.user_gym_id(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    u.default_gym_id,
    (
      SELECT gm.gym_id
      FROM public.gym_memberships gm
      WHERE gm.user_id = p_user_id
        AND gm.status IN ('accepted', 'active')
      ORDER BY gm.is_default DESC, gm.last_active_at DESC NULLS LAST, gm.created_at ASC
      LIMIT 1
    )
  )
  FROM public.users u
  WHERE u.id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION public.user_role(p_user_id uuid)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    u.role,
    (
      SELECT r.code
      FROM public.gym_memberships gm
      JOIN public.roles r
        ON r.id = gm.role_id
      WHERE gm.user_id = p_user_id
        AND gm.status IN ('accepted', 'active')
      ORDER BY gm.is_default DESC, gm.last_active_at DESC NULLS LAST, gm.created_at ASC
      LIMIT 1
    )
  )
  FROM public.users u
  WHERE u.id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION public.is_same_gym_user(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.gym_memberships target_membership
    WHERE target_membership.user_id = p_user_id
      AND target_membership.status IN ('accepted', 'active')
      AND public.user_has_membership(target_membership.gym_id)
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_client_data(p_client_id uuid, p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN false
    WHEN p_client_id IS NULL OR p_gym_id IS NULL THEN false
    WHEN NOT public.user_has_membership(p_gym_id) THEN false
    WHEN public.get_my_portal() = 'admin' THEN true
    WHEN public.get_my_portal() = 'coach' THEN EXISTS (
      SELECT 1
      FROM public.coach_client_assignments cca
      WHERE cca.coach_id = auth.uid()
        AND cca.client_id = p_client_id
        AND cca.gym_id = p_gym_id
        AND cca.is_active = true
    )
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION public.can_view_user(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = p_user_id
      AND (
        u.id = auth.uid()
        OR public.is_same_gym_user(p_user_id)
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_message_user(p_other_user_id uuid, p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN false
    WHEN p_other_user_id IS NULL OR p_gym_id IS NULL THEN false
    WHEN NOT public.user_has_membership(p_gym_id) THEN false
    WHEN public.get_my_portal() = 'admin' THEN true
    WHEN public.get_my_portal() = 'coach' THEN EXISTS (
      SELECT 1
      FROM public.coach_client_assignments cca
      WHERE cca.coach_id = auth.uid()
        AND cca.client_id = p_other_user_id
        AND cca.gym_id = p_gym_id
        AND cca.is_active = true
    )
    WHEN public.get_my_portal() = 'client' THEN (
      EXISTS (
        SELECT 1
        FROM public.gym_memberships gm
        JOIN public.roles r
          ON r.id = gm.role_id
        WHERE gm.user_id = p_other_user_id
          AND gm.gym_id = p_gym_id
          AND gm.status IN ('accepted', 'active')
          AND r.portal IN ('admin', 'coach')
      )
    )
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION public.sync_legacy_user_membership_projection(
  p_user_id uuid
)
RETURNS public.users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_membership record;
  v_profile public.users%ROWTYPE;
BEGIN
  SELECT
    gm.id AS membership_id,
    gm.gym_id,
    r.code AS role_code
  INTO v_membership
  FROM public.gym_memberships gm
  JOIN public.roles r
    ON r.id = gm.role_id
  WHERE gm.user_id = p_user_id
    AND gm.status IN ('accepted', 'active')
  ORDER BY
    gm.is_default DESC,
    gm.last_active_at DESC NULLS LAST,
    gm.created_at ASC
  LIMIT 1;

  UPDATE public.users
  SET
    gym_id = v_membership.gym_id,
    default_gym_id = v_membership.gym_id,
    default_membership_id = v_membership.membership_id,
    role = COALESCE(v_membership.role_code, role),
    updated_at = now()
  WHERE id = p_user_id
  RETURNING * INTO v_profile;

  RETURN v_profile;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_active_gym(
  p_gym_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_membership record;
  v_profile public.users%ROWTYPE;
BEGIN
  SELECT
    gm.id,
    gm.gym_id,
    r.code AS role_code,
    r.name AS role_name,
    r.portal
  INTO v_membership
  FROM public.gym_memberships gm
  JOIN public.roles r
    ON r.id = gm.role_id
  WHERE gm.user_id = auth.uid()
    AND gm.gym_id = p_gym_id
    AND gm.status IN ('accepted', 'active')
  LIMIT 1;

  IF v_membership.id IS NULL THEN
    RAISE EXCEPTION 'No active membership for this gym.';
  END IF;

  UPDATE public.gym_memberships
  SET
    is_default = (id = v_membership.id),
    last_active_at = CASE WHEN id = v_membership.id THEN now() ELSE last_active_at END,
    updated_at = now()
  WHERE user_id = auth.uid()
    AND status IN ('accepted', 'active');

  v_profile := public.sync_legacy_user_membership_projection(auth.uid());

  RETURN jsonb_build_object(
    'membership_id', v_membership.id,
    'gym_id', v_membership.gym_id,
    'role_code', v_membership.role_code,
    'role_name', v_membership.role_name,
    'portal', v_membership.portal,
    'user', to_jsonb(v_profile)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_auth_context(
  p_requested_gym_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user public.users%ROWTYPE;
  v_active record;
  v_email citext;
  v_memberships jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object(
      'user', NULL,
      'active_membership', NULL,
      'memberships', '[]'::jsonb
    );
  END IF;

  SELECT * INTO v_user
  FROM public.users
  WHERE id = auth.uid();

  v_email := public.auth_user_email(auth.uid());

  SELECT * INTO v_active
  FROM public.current_membership(p_requested_gym_id)
  LIMIT 1;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'membership_id', gm.id,
        'gym_id', gm.gym_id,
        'gym_name', g.name,
        'gym_logo_storage_bucket', g.logo_storage_bucket,
        'gym_logo_storage_path', g.logo_storage_path,
        'user_id', gm.user_id,
        'status', gm.status,
        'invitation_status', gm.invitation_status,
        'invite_email', gm.invite_email,
        'role_id', r.id,
        'role_code', r.code,
        'role_name', r.name,
        'portal', r.portal,
        'is_default', gm.is_default,
        'last_active_at', gm.last_active_at,
        'permissions', public.permission_codes_for_membership(gm.id)
      )
      ORDER BY
        CASE WHEN gm.id = v_active.membership_id THEN 0 ELSE 1 END,
        gm.is_default DESC,
        gm.last_active_at DESC NULLS LAST,
        gm.created_at ASC
    ),
    '[]'::jsonb
  ) INTO v_memberships
  FROM public.gym_memberships gm
  JOIN public.roles r
    ON r.id = gm.role_id
  JOIN public.gyms g
    ON g.id = gm.gym_id
  WHERE (
      gm.user_id = auth.uid()
      OR (gm.user_id IS NULL AND gm.invite_email = v_email)
    )
    AND gm.status IN ('pending', 'accepted', 'active');

  RETURN jsonb_build_object(
    'user', to_jsonb(v_user),
    'active_membership',
      CASE WHEN v_active.membership_id IS NULL THEN NULL ELSE jsonb_build_object(
        'membership_id', v_active.membership_id,
        'gym_id', v_active.gym_id,
        'role_id', v_active.role_id,
        'role_code', v_active.role_code,
        'role_name', v_active.role_name,
        'portal', v_active.portal,
        'status', v_active.status,
        'is_default', v_active.is_default,
        'last_active_at', v_active.last_active_at,
        'permissions', v_active.permissions
      ) END,
    'memberships', v_memberships
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.bootstrap_authenticated_user(
  p_role text DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_gym_name text DEFAULT NULL
)
RETURNS public.users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
SET row_security = off
AS $$
DECLARE
  v_auth_user auth.users%ROWTYPE;
  v_profile public.users%ROWTYPE;
  v_role text;
  v_name text;
  v_email text;
  v_lang text;
  v_gym_name text;
  v_gym_id uuid;
  v_role_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_auth_user
  FROM auth.users
  WHERE id = auth.uid();

  SELECT * INTO v_profile
  FROM public.users
  WHERE id = auth.uid();

  v_role := public.map_legacy_role_code(COALESCE(
    NULLIF(lower(BTRIM(v_profile.role)), ''),
    NULLIF(lower(BTRIM(p_role)), ''),
    NULLIF(lower(BTRIM(v_auth_user.raw_user_meta_data->>'role')), ''),
    'client'
  ));

  v_name := COALESCE(
    NULLIF(BTRIM(v_profile.name), ''),
    NULLIF(BTRIM(p_name), ''),
    NULLIF(BTRIM(v_auth_user.raw_user_meta_data->>'name'), ''),
    split_part(COALESCE(v_profile.email, p_email, v_auth_user.email, 'User'), '@', 1),
    'User'
  );

  v_email := COALESCE(
    NULLIF(lower(BTRIM(v_profile.email)), ''),
    NULLIF(lower(BTRIM(p_email)), ''),
    NULLIF(lower(BTRIM(v_auth_user.email)), '')
  );

  v_lang := COALESCE(
    NULLIF(lower(BTRIM(v_profile.language_preference)), ''),
    NULLIF(lower(BTRIM(v_auth_user.raw_user_meta_data->>'language_preference')), ''),
    'fr'
  );

  v_gym_name := COALESCE(
    NULLIF(BTRIM(p_gym_name), ''),
    NULLIF(BTRIM(v_auth_user.raw_user_meta_data->>'gym_name'), '')
  );

  INSERT INTO public.users (
    id,
    name,
    email,
    role,
    phone,
    avatar_url,
    language_preference,
    is_managed,
    is_active,
    created_at,
    updated_at
  )
  VALUES (
    auth.uid(),
    v_name,
    v_email,
    v_role,
    NULLIF(BTRIM(v_auth_user.raw_user_meta_data->>'phone'), ''),
    v_profile.avatar_url,
    CASE WHEN v_lang IN ('fr', 'en', 'ar') THEN v_lang ELSE 'fr' END,
    COALESCE(v_profile.is_managed, false),
    true,
    COALESCE(v_profile.created_at, now()),
    now()
  )
  ON CONFLICT (id) DO UPDATE
  SET
    name = EXCLUDED.name,
    email = COALESCE(EXCLUDED.email, public.users.email),
    language_preference = EXCLUDED.language_preference,
    is_active = true,
    updated_at = now()
  RETURNING * INTO v_profile;

  IF v_role = 'gym_owner'
     AND NOT EXISTS (
       SELECT 1
       FROM public.gym_memberships gm
       WHERE gm.user_id = auth.uid()
         AND gm.status IN ('accepted', 'active')
     ) THEN
    INSERT INTO public.gyms (name, manager_id, owner_name, email)
    VALUES (
      COALESCE(v_gym_name, 'My Gym'),
      auth.uid(),
      v_name,
      v_email
    )
    RETURNING id INTO v_gym_id;

    PERFORM public.ensure_gym_default_roles(v_gym_id, auth.uid());

    SELECT id INTO v_role_id
    FROM public.roles
    WHERE gym_id = v_gym_id
      AND code = 'gym_owner'
    LIMIT 1;

    INSERT INTO public.gym_memberships (
      gym_id,
      user_id,
      role_id,
      status,
      invitation_status,
      invite_email,
      invited_name,
      invited_by,
      accepted_at,
      activated_at,
      is_default,
      last_active_at
    )
    VALUES (
      v_gym_id,
      auth.uid(),
      v_role_id,
      'active',
      'accepted',
      v_email,
      v_name,
      auth.uid(),
      now(),
      now(),
      true,
      now()
    )
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN public.sync_legacy_user_membership_projection(auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.invite_gym_member(
  p_gym_id uuid,
  p_email text,
  p_name text,
  p_role_id uuid,
  p_phone text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  membership_id uuid,
  invite_token text,
  existing_user boolean,
  invite_email text,
  role_name text,
  gym_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_email citext;
  v_existing_user_id uuid;
  v_existing_auth_user_id uuid;
  v_role record;
  v_gym_name text;
BEGIN
  IF NOT public.has_permission('manage_staff', p_gym_id) THEN
    RAISE EXCEPTION 'You do not have permission to invite members to this gym.';
  END IF;

  v_email := NULLIF(lower(BTRIM(p_email)), '')::citext;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Invitation email is required.';
  END IF;

  SELECT r.id, r.name, r.gym_id
  INTO v_role
  FROM public.roles r
  WHERE r.id = p_role_id
    AND r.gym_id = p_gym_id;

  IF v_role.id IS NULL THEN
    RAISE EXCEPTION 'Role does not belong to this gym.';
  END IF;

  SELECT g.name INTO v_gym_name
  FROM public.gyms g
  WHERE g.id = p_gym_id;

  SELECT u.id INTO v_existing_user_id
  FROM public.users u
  WHERE u.email = v_email
  LIMIT 1;

  SELECT au.id INTO v_existing_auth_user_id
  FROM auth.users au
  WHERE lower(BTRIM(au.email))::citext = v_email
  LIMIT 1;

  IF v_existing_user_id IS NULL AND v_existing_auth_user_id IS NOT NULL THEN
    INSERT INTO public.users (id, name, email, role, language_preference, is_active)
    VALUES (
      v_existing_auth_user_id,
      COALESCE(NULLIF(BTRIM(p_name), ''), split_part(v_email::text, '@', 1)),
      v_email::text,
      public.map_legacy_role_code((SELECT code FROM public.roles WHERE id = p_role_id)),
      'fr',
      true
    )
    ON CONFLICT (id) DO UPDATE
    SET
      name = COALESCE(NULLIF(BTRIM(EXCLUDED.name), ''), public.users.name),
      email = COALESCE(EXCLUDED.email, public.users.email),
      updated_at = now()
    RETURNING id INTO v_existing_user_id;
  END IF;

  UPDATE public.gym_memberships
  SET
    user_id = COALESCE(user_id, v_existing_user_id),
    role_id = p_role_id,
    status = 'pending',
    invitation_status = 'pending',
    invite_email = v_email,
    invited_name = NULLIF(BTRIM(p_name), ''),
    invited_phone = NULLIF(BTRIM(p_phone), ''),
    invite_token = encode(gen_random_bytes(18), 'hex'),
    invited_by = auth.uid(),
    invited_at = now(),
    accepted_at = NULL,
    activated_at = NULL,
    declined_at = NULL,
    revoked_at = NULL,
    metadata = COALESCE(p_metadata, '{}'::jsonb),
    updated_at = now()
  WHERE gym_id = p_gym_id
    AND (
      (v_existing_user_id IS NOT NULL AND user_id = v_existing_user_id)
      OR invite_email = v_email
    )
    AND status IN ('pending', 'accepted', 'active')
  RETURNING id, public.gym_memberships.invite_token INTO membership_id, invite_token;

  IF membership_id IS NULL THEN
    INSERT INTO public.gym_memberships (
      gym_id,
      user_id,
      role_id,
      status,
      invitation_status,
      invite_email,
      invited_name,
      invited_phone,
      invite_token,
      invited_by,
      invited_at,
      metadata
    )
    VALUES (
      p_gym_id,
      v_existing_user_id,
      p_role_id,
      'pending',
      'pending',
      v_email,
      NULLIF(BTRIM(p_name), ''),
      NULLIF(BTRIM(p_phone), ''),
      encode(gen_random_bytes(18), 'hex'),
      auth.uid(),
      now(),
      COALESCE(p_metadata, '{}'::jsonb)
    )
    RETURNING id, public.gym_memberships.invite_token INTO membership_id, invite_token;
  END IF;

  invite_email := v_email::text;
  role_name := v_role.name;
  gym_name := COALESCE(v_gym_name, 'Trainw Gym');
  existing_user := v_existing_user_id IS NOT NULL OR v_existing_auth_user_id IS NOT NULL;

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_gym_invitation(
  p_invite_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_email citext;
  v_membership record;
  v_profile public.users%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to accept an invitation.';
  END IF;

  v_email := public.auth_user_email(auth.uid());

  SELECT
    gm.id,
    gm.gym_id,
    gm.role_id,
    gm.status,
    r.code AS role_code,
    r.portal
  INTO v_membership
  FROM public.gym_memberships gm
  JOIN public.roles r
    ON r.id = gm.role_id
  WHERE gm.invite_token = NULLIF(BTRIM(p_invite_token), '')
    AND gm.status = 'pending'
    AND (
      gm.user_id = auth.uid()
      OR gm.user_id IS NULL
      OR gm.invite_email = v_email
    )
  LIMIT 1;

  IF v_membership.id IS NULL THEN
    RAISE EXCEPTION 'Invitation not found or already processed.';
  END IF;

  UPDATE public.gym_memberships
  SET
    user_id = auth.uid(),
    status = 'active',
    invitation_status = 'accepted',
    accepted_at = COALESCE(accepted_at, now()),
    activated_at = now(),
    declined_at = NULL,
    revoked_at = NULL,
    is_default = CASE
      WHEN EXISTS (
        SELECT 1
        FROM public.gym_memberships existing_default
        WHERE existing_default.user_id = auth.uid()
          AND existing_default.status IN ('accepted', 'active')
      ) THEN is_default
      ELSE true
    END,
    last_active_at = now(),
    updated_at = now()
  WHERE id = v_membership.id;

  IF v_membership.portal = 'coach' THEN
    INSERT INTO public.coach_profiles (user_id, gym_id, is_active)
    VALUES (auth.uid(), v_membership.gym_id, true)
    ON CONFLICT DO NOTHING;
  ELSIF v_membership.portal = 'client' THEN
    INSERT INTO public.client_profiles (user_id, gym_id, payment_status)
    VALUES (auth.uid(), v_membership.gym_id, 'pending')
    ON CONFLICT DO NOTHING;
  END IF;

  v_profile := public.sync_legacy_user_membership_projection(auth.uid());
  PERFORM public.set_active_gym(v_membership.gym_id);

  RETURN jsonb_build_object(
    'membership_id', v_membership.id,
    'gym_id', v_membership.gym_id,
    'role_code', v_membership.role_code,
    'portal', v_membership.portal,
    'user', to_jsonb(v_profile)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.decline_gym_invitation(
  p_invite_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_email citext;
  v_membership record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to decline an invitation.';
  END IF;

  v_email := public.auth_user_email(auth.uid());

  SELECT gm.id, gm.gym_id
  INTO v_membership
  FROM public.gym_memberships gm
  WHERE gm.invite_token = NULLIF(BTRIM(p_invite_token), '')
    AND gm.status = 'pending'
    AND (
      gm.user_id = auth.uid()
      OR gm.user_id IS NULL
      OR gm.invite_email = v_email
    )
  LIMIT 1;

  IF v_membership.id IS NULL THEN
    RAISE EXCEPTION 'Invitation not found or already processed.';
  END IF;

  UPDATE public.gym_memberships
  SET
    status = 'declined',
    invitation_status = 'declined',
    declined_at = now(),
    updated_at = now()
  WHERE id = v_membership.id;

  RETURN jsonb_build_object(
    'membership_id', v_membership.id,
    'gym_id', v_membership.gym_id,
    'status', 'declined'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_gym_member_directory(
  p_gym_id uuid
)
RETURNS TABLE (
  membership_id uuid,
  gym_id uuid,
  user_id uuid,
  name text,
  email text,
  phone text,
  role_id uuid,
  role_code text,
  role_name text,
  portal text,
  status text,
  invitation_status text,
  permissions text[],
  avatar_storage_bucket text,
  avatar_storage_path text,
  invite_email text,
  invited_at timestamptz,
  last_active_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    gm.id AS membership_id,
    gm.gym_id,
    gm.user_id,
    COALESCE(u.name, gm.invited_name, split_part(gm.invite_email::text, '@', 1), 'Pending user') AS name,
    COALESCE(u.email, gm.invite_email::text) AS email,
    COALESCE(u.phone, gm.invited_phone) AS phone,
    r.id AS role_id,
    r.code AS role_code,
    r.name AS role_name,
    r.portal,
    gm.status,
    gm.invitation_status,
    public.permission_codes_for_membership(gm.id) AS permissions,
    u.avatar_storage_bucket,
    u.avatar_storage_path,
    gm.invite_email::text,
    gm.invited_at,
    gm.last_active_at
  FROM public.gym_memberships gm
  JOIN public.roles r
    ON r.id = gm.role_id
  LEFT JOIN public.users u
    ON u.id = gm.user_id
  WHERE gm.gym_id = p_gym_id
    AND public.user_has_membership(p_gym_id)
  ORDER BY
    CASE gm.status WHEN 'active' THEN 0 WHEN 'pending' THEN 1 WHEN 'accepted' THEN 2 ELSE 3 END,
    r.portal,
    COALESCE(u.name, gm.invited_name, gm.invite_email::text);
$$;

CREATE OR REPLACE FUNCTION public.list_role_matrix(
  p_gym_id uuid
)
RETURNS TABLE (
  role_id uuid,
  code text,
  name text,
  description text,
  portal text,
  is_system boolean,
  permissions text[]
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    r.id AS role_id,
    r.code,
    r.name,
    r.description,
    r.portal,
    r.is_system,
    COALESCE(
      ARRAY(
        SELECT p.code
        FROM public.role_permissions rp
        JOIN public.permissions p
          ON p.id = rp.permission_id
        WHERE rp.role_id = r.id
        ORDER BY p.code
      ),
      ARRAY[]::text[]
    ) AS permissions
  FROM public.roles r
  WHERE r.gym_id = p_gym_id
    AND public.user_has_membership(p_gym_id)
  ORDER BY r.is_system DESC, r.portal, r.name;
$$;

CREATE OR REPLACE FUNCTION public.save_role_definition(
  p_gym_id uuid,
  p_role_id uuid DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_code text DEFAULT NULL,
  p_portal text DEFAULT 'client',
  p_description text DEFAULT NULL,
  p_permission_codes text[] DEFAULT ARRAY[]::text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_id uuid;
BEGIN
  IF NOT public.has_permission('manage_roles', p_gym_id) THEN
    RAISE EXCEPTION 'You do not have permission to manage roles for this gym.';
  END IF;

  IF COALESCE(NULLIF(BTRIM(p_name), ''), '') = '' THEN
    RAISE EXCEPTION 'Role name is required.';
  END IF;

  IF COALESCE(NULLIF(BTRIM(p_portal), ''), '') NOT IN ('admin', 'coach', 'client') THEN
    RAISE EXCEPTION 'Role portal must be admin, coach, or client.';
  END IF;

  IF p_role_id IS NULL THEN
    INSERT INTO public.roles (
      gym_id,
      code,
      name,
      description,
      portal,
      is_system,
      is_default,
      created_by
    )
    VALUES (
      p_gym_id,
      public.normalize_role_code(COALESCE(p_code, p_name)),
      BTRIM(p_name),
      NULLIF(BTRIM(p_description), ''),
      BTRIM(p_portal),
      false,
      false,
      auth.uid()
    )
    RETURNING id INTO v_role_id;
  ELSE
    UPDATE public.roles
    SET
      code = public.normalize_role_code(COALESCE(p_code, p_name)),
      name = BTRIM(p_name),
      description = NULLIF(BTRIM(p_description), ''),
      portal = BTRIM(p_portal),
      updated_at = now()
    WHERE id = p_role_id
      AND gym_id = p_gym_id
    RETURNING id INTO v_role_id;
  END IF;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Role could not be saved.';
  END IF;

  PERFORM public.ensure_role_permission_codes(v_role_id, COALESCE(p_permission_codes, ARRAY[]::text[]));
  RETURN v_role_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_membership_role(
  p_membership_id uuid,
  p_role_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_membership record;
BEGIN
  SELECT gm.id, gm.gym_id, gm.user_id
  INTO v_membership
  FROM public.gym_memberships gm
  WHERE gm.id = p_membership_id;

  IF v_membership.id IS NULL THEN
    RAISE EXCEPTION 'Membership not found.';
  END IF;

  IF NOT public.has_permission('manage_staff', v_membership.gym_id) THEN
    RAISE EXCEPTION 'You do not have permission to assign roles in this gym.';
  END IF;

  UPDATE public.gym_memberships
  SET
    role_id = p_role_id,
    updated_at = now()
  WHERE id = p_membership_id;

  IF v_membership.user_id IS NOT NULL THEN
    PERFORM public.sync_legacy_user_membership_projection(v_membership.user_id);
  END IF;

  RETURN jsonb_build_object('membership_id', p_membership_id, 'role_id', p_role_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_gym_membership(
  p_membership_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_membership record;
BEGIN
  SELECT gm.id, gm.gym_id, gm.user_id
  INTO v_membership
  FROM public.gym_memberships gm
  WHERE gm.id = p_membership_id;

  IF v_membership.id IS NULL THEN
    RAISE EXCEPTION 'Membership not found.';
  END IF;

  IF NOT public.has_permission('manage_staff', v_membership.gym_id) THEN
    RAISE EXCEPTION 'You do not have permission to revoke members in this gym.';
  END IF;

  UPDATE public.gym_memberships
  SET
    status = 'revoked',
    invitation_status = 'revoked',
    revoked_at = now(),
    is_default = false,
    updated_at = now()
  WHERE id = p_membership_id;

  IF v_membership.user_id IS NOT NULL THEN
    PERFORM public.sync_legacy_user_membership_projection(v_membership.user_id);
  END IF;

  RETURN jsonb_build_object('membership_id', p_membership_id, 'status', 'revoked');
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_booking_from_session()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.bookings
    WHERE session_id = OLD.id;
    RETURN OLD;
  END IF;

  IF NEW.client_id IS NULL THEN
    DELETE FROM public.bookings
    WHERE session_id = NEW.id;
    RETURN NEW;
  END IF;

  INSERT INTO public.bookings (
    gym_id,
    session_id,
    coach_id,
    client_id,
    booked_by,
    booking_source,
    status,
    notes
  )
  VALUES (
    NEW.gym_id,
    NEW.id,
    NEW.coach_id,
    NEW.client_id,
    COALESCE(NEW.created_by, NEW.client_id, NEW.coach_id),
    'session',
    COALESCE(NEW.status, 'confirmed'),
    NEW.notes
  )
  ON CONFLICT (session_id) DO UPDATE
  SET
    gym_id = EXCLUDED.gym_id,
    coach_id = EXCLUDED.coach_id,
    client_id = EXCLUDED.client_id,
    booked_by = EXCLUDED.booked_by,
    status = EXCLUDED.status,
    notes = EXCLUDED.notes,
    updated_at = now();

  RETURN NEW;
END;
$$;


-- ----------------------------------------------------------------------------
-- DATA BACKFILL
-- ----------------------------------------------------------------------------

SELECT public.ensure_gym_default_roles(g.id, g.manager_id)
FROM public.gyms g;

INSERT INTO public.gym_memberships (
  gym_id,
  user_id,
  role_id,
  status,
  invitation_status,
  invite_email,
  invited_name,
  invited_by,
  accepted_at,
  activated_at,
  is_default,
  last_active_at,
  created_at,
  updated_at
)
SELECT
  u.gym_id,
  u.id,
  r.id,
  'active',
  'accepted',
  u.email,
  u.name,
  g.manager_id,
  COALESCE(u.created_at, now()),
  COALESCE(u.updated_at, u.created_at, now()),
  true,
  COALESCE(u.last_seen_at, u.updated_at, u.created_at, now()),
  COALESCE(u.created_at, now()),
  COALESCE(u.updated_at, now())
FROM public.users u
JOIN public.roles r
  ON r.gym_id = u.gym_id
 AND r.code = public.map_legacy_role_code(u.role)
LEFT JOIN public.gyms g
  ON g.id = u.gym_id
WHERE u.gym_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.gym_memberships gm
    WHERE gm.gym_id = u.gym_id
      AND gm.user_id = u.id
      AND gm.status IN ('pending', 'accepted', 'active')
  );

UPDATE public.coach_profiles cp
SET gym_id = COALESCE(
  cp.gym_id,
  public.user_gym_id(cp.user_id)
)
WHERE cp.gym_id IS NULL
  AND cp.user_id IS NOT NULL;

UPDATE public.client_profiles cp
SET gym_id = COALESCE(
  cp.gym_id,
  public.user_gym_id(cp.user_id)
)
WHERE cp.gym_id IS NULL
  AND cp.user_id IS NOT NULL;

DROP INDEX IF EXISTS public.uq_coach_profiles_user_id;
DROP INDEX IF EXISTS public.uq_client_profiles_user_id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_coach_profiles_user_gym
  ON public.coach_profiles(user_id, gym_id)
  WHERE gym_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_client_profiles_user_gym
  ON public.client_profiles(user_id, gym_id)
  WHERE gym_id IS NOT NULL;

INSERT INTO public.bookings (
  gym_id,
  session_id,
  coach_id,
  client_id,
  booked_by,
  booking_source,
  status,
  notes,
  created_at,
  updated_at
)
SELECT
  s.gym_id,
  s.id,
  s.coach_id,
  s.client_id,
  COALESCE(s.created_by, s.client_id, s.coach_id),
  'session',
  COALESCE(s.status, 'confirmed'),
  s.notes,
  COALESCE(s.created_at, now()),
  COALESCE(s.updated_at, now())
FROM public.sessions s
WHERE s.client_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.bookings b
    WHERE b.session_id = s.id
  );

UPDATE public.users u
SET
  default_gym_id = public.user_gym_id(u.id),
  updated_at = now()
WHERE EXISTS (
  SELECT 1
  FROM public.gym_memberships gm
  WHERE gm.user_id = u.id
    AND gm.status IN ('accepted', 'active')
);

SELECT public.sync_legacy_user_membership_projection(u.id)
FROM public.users u
WHERE EXISTS (
  SELECT 1
  FROM public.gym_memberships gm
  WHERE gm.user_id = u.id
    AND gm.status IN ('accepted', 'active')
);


-- ----------------------------------------------------------------------------
-- FOREIGN KEYS AFTER BACKFILL
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'users_default_gym_id_fkey'
      AND conrelid = 'public.users'::regclass
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_default_gym_id_fkey
      FOREIGN KEY (default_gym_id)
      REFERENCES public.gyms(id)
      ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'users_default_membership_id_fkey'
      AND conrelid = 'public.users'::regclass
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_default_membership_id_fkey
      FOREIGN KEY (default_membership_id)
      REFERENCES public.gym_memberships(id)
      ON DELETE SET NULL;
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- SESSION TO BOOKING TRIGGER
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'sync_booking_from_session_trigger'
  ) THEN
    CREATE TRIGGER sync_booking_from_session_trigger
    AFTER INSERT OR UPDATE OR DELETE ON public.sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_booking_from_session();
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------

ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS permissions_select_v16 ON public.permissions;
DROP POLICY IF EXISTS roles_select_v16 ON public.roles;
DROP POLICY IF EXISTS roles_manage_v16 ON public.roles;
DROP POLICY IF EXISTS role_permissions_select_v16 ON public.role_permissions;
DROP POLICY IF EXISTS role_permissions_manage_v16 ON public.role_permissions;
DROP POLICY IF EXISTS gym_memberships_select_v16 ON public.gym_memberships;
DROP POLICY IF EXISTS gym_memberships_manage_v16 ON public.gym_memberships;
DROP POLICY IF EXISTS user_permissions_select_v16 ON public.user_permissions;
DROP POLICY IF EXISTS user_permissions_manage_v16 ON public.user_permissions;
DROP POLICY IF EXISTS media_assets_select_v16 ON public.media_assets;
DROP POLICY IF EXISTS media_assets_manage_v16 ON public.media_assets;
DROP POLICY IF EXISTS bookings_select_v16 ON public.bookings;
DROP POLICY IF EXISTS bookings_manage_v16 ON public.bookings;

CREATE POLICY permissions_select_v16 ON public.permissions
  FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY roles_select_v16 ON public.roles
  FOR SELECT
  USING (public.user_has_membership(gym_id));

CREATE POLICY roles_manage_v16 ON public.roles
  FOR ALL
  USING (public.has_permission('manage_roles', gym_id))
  WITH CHECK (public.has_permission('manage_roles', gym_id));

CREATE POLICY role_permissions_select_v16 ON public.role_permissions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.roles r
      WHERE r.id = role_permissions.role_id
        AND public.user_has_membership(r.gym_id)
    )
  );

CREATE POLICY role_permissions_manage_v16 ON public.role_permissions
  FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM public.roles r
      WHERE r.id = role_permissions.role_id
        AND public.has_permission('manage_roles', r.gym_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.roles r
      WHERE r.id = role_permissions.role_id
        AND public.has_permission('manage_roles', r.gym_id)
    )
  );

CREATE POLICY gym_memberships_select_v16 ON public.gym_memberships
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR (
      invite_email IS NOT NULL
      AND invite_email = public.auth_user_email(auth.uid())
    )
    OR public.has_permission('manage_staff', gym_id)
  );

CREATE POLICY gym_memberships_manage_v16 ON public.gym_memberships
  FOR ALL
  USING (
    public.has_permission('manage_staff', gym_id)
  )
  WITH CHECK (
    public.has_permission('manage_staff', gym_id)
  );

CREATE POLICY user_permissions_select_v16 ON public.user_permissions
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR public.has_permission('manage_roles', gym_id)
    OR public.has_permission('manage_staff', gym_id)
  );

CREATE POLICY user_permissions_manage_v16 ON public.user_permissions
  FOR ALL
  USING (
    public.has_permission('manage_roles', gym_id)
    OR public.has_permission('manage_staff', gym_id)
  )
  WITH CHECK (
    public.has_permission('manage_roles', gym_id)
    OR public.has_permission('manage_staff', gym_id)
  );

CREATE POLICY media_assets_select_v16 ON public.media_assets
  FOR SELECT
  USING (
    owner_user_id = auth.uid()
    OR (gym_id IS NOT NULL AND public.user_has_membership(gym_id))
  );

CREATE POLICY media_assets_manage_v16 ON public.media_assets
  FOR ALL
  USING (
    owner_user_id = auth.uid()
    OR (
      gym_id IS NOT NULL
      AND (
        public.has_permission('manage_branding', gym_id)
        OR public.has_permission('manage_media', gym_id)
      )
    )
  )
  WITH CHECK (
    owner_user_id = auth.uid()
    OR (
      gym_id IS NOT NULL
      AND (
        public.has_permission('manage_branding', gym_id)
        OR public.has_permission('manage_media', gym_id)
      )
    )
  );

CREATE POLICY bookings_select_v16 ON public.bookings
  FOR SELECT
  USING (
    client_id = auth.uid()
    OR coach_id = auth.uid()
    OR public.manages_gym(gym_id)
  );

CREATE POLICY bookings_manage_v16 ON public.bookings
  FOR ALL
  USING (
    client_id = auth.uid()
    OR coach_id = auth.uid()
    OR public.has_permission('manage_bookings', gym_id)
  )
  WITH CHECK (
    client_id = auth.uid()
    OR coach_id = auth.uid()
    OR public.has_permission('manage_bookings', gym_id)
  );


-- ----------------------------------------------------------------------------
-- STORAGE BUCKETS AND POLICIES
-- ----------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'trainw-media',
  'trainw-media',
  false,
  5242880,
  ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS trainw_media_select_v16 ON storage.objects;
DROP POLICY IF EXISTS trainw_media_insert_v16 ON storage.objects;
DROP POLICY IF EXISTS trainw_media_update_v16 ON storage.objects;
DROP POLICY IF EXISTS trainw_media_delete_v16 ON storage.objects;

CREATE POLICY trainw_media_select_v16 ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'trainw-media'
    AND (
      (
        (storage.foldername(name))[1] = 'gyms'
        AND public.user_has_membership(public.safe_uuid((storage.foldername(name))[2]))
      )
      OR (
        (storage.foldername(name))[1] = 'profiles'
        AND public.user_has_membership(public.safe_uuid((storage.foldername(name))[2]))
      )
    )
  );

CREATE POLICY trainw_media_insert_v16 ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'trainw-media'
    AND (
      (
        (storage.foldername(name))[1] = 'gyms'
        AND public.has_permission('manage_branding', public.safe_uuid((storage.foldername(name))[2]))
      )
      OR (
        (storage.foldername(name))[1] = 'profiles'
        AND public.user_has_membership(public.safe_uuid((storage.foldername(name))[2]))
        AND (
          public.safe_uuid((storage.foldername(name))[3]) = auth.uid()
          OR public.has_permission('manage_staff', public.safe_uuid((storage.foldername(name))[2]))
        )
      )
    )
  );

CREATE POLICY trainw_media_update_v16 ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'trainw-media'
    AND (
      (
        (storage.foldername(name))[1] = 'gyms'
        AND public.has_permission('manage_branding', public.safe_uuid((storage.foldername(name))[2]))
      )
      OR (
        (storage.foldername(name))[1] = 'profiles'
        AND public.user_has_membership(public.safe_uuid((storage.foldername(name))[2]))
        AND (
          public.safe_uuid((storage.foldername(name))[3]) = auth.uid()
          OR public.has_permission('manage_staff', public.safe_uuid((storage.foldername(name))[2]))
        )
      )
    )
  )
  WITH CHECK (
    bucket_id = 'trainw-media'
    AND (
      (
        (storage.foldername(name))[1] = 'gyms'
        AND public.has_permission('manage_branding', public.safe_uuid((storage.foldername(name))[2]))
      )
      OR (
        (storage.foldername(name))[1] = 'profiles'
        AND public.user_has_membership(public.safe_uuid((storage.foldername(name))[2]))
        AND (
          public.safe_uuid((storage.foldername(name))[3]) = auth.uid()
          OR public.has_permission('manage_staff', public.safe_uuid((storage.foldername(name))[2]))
        )
      )
    )
  );

CREATE POLICY trainw_media_delete_v16 ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'trainw-media'
    AND (
      (
        (storage.foldername(name))[1] = 'gyms'
        AND public.has_permission('manage_branding', public.safe_uuid((storage.foldername(name))[2]))
      )
      OR (
        (storage.foldername(name))[1] = 'profiles'
        AND public.user_has_membership(public.safe_uuid((storage.foldername(name))[2]))
        AND (
          public.safe_uuid((storage.foldername(name))[3]) = auth.uid()
          OR public.has_permission('manage_staff', public.safe_uuid((storage.foldername(name))[2]))
        )
      )
    )
  );


-- ----------------------------------------------------------------------------
-- GRANTS
-- ----------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.ensure_gym_default_roles(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.permission_codes_for_membership(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_membership(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_permissions(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_active_gym(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bootstrap_authenticated_user(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.invite_gym_member(uuid, text, text, uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_gym_invitation(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decline_gym_invitation(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_gym_member_directory(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_role_matrix(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_role_definition(uuid, uuid, text, text, text, text, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_membership_role(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_gym_membership(uuid) TO authenticated;
