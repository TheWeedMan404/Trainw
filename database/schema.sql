BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'client_type') THEN
    CREATE TYPE public.client_type AS ENUM ('individual', 'gym');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'class_type') THEN
    CREATE TYPE public.class_type AS ENUM ('private', 'group', 'supervising');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_status') THEN
    CREATE TYPE public.attendance_status AS ENUM ('checked_in', 'late', 'missed', 'excused');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.gyms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  name text NOT NULL,
  permissions jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT roles_name_per_gym_unique UNIQUE (gym_id, name),
  CONSTRAINT roles_id_gym_unique UNIQUE (id, gym_id)
);

CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email citext NOT NULL,
  full_name text,
  gym_id uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  role_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_email_per_gym_unique UNIQUE (gym_id, email),
  CONSTRAINT users_role_gym_fk
    FOREIGN KEY (role_id, gym_id)
    REFERENCES public.roles(id, gym_id)
    ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.coaches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  name text NOT NULL,
  rating numeric(2,1),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT coaches_rating_range CHECK (rating IS NULL OR (rating >= 0 AND rating <= 5)),
  CONSTRAINT coaches_id_gym_unique UNIQUE (id, gym_id)
);

CREATE TABLE IF NOT EXISTS public.clients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid REFERENCES public.gyms(id) ON DELETE SET NULL,
  name text NOT NULL,
  client_code text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  type public.client_type NOT NULL,
  CONSTRAINT clients_gym_required_when_linked CHECK (
    type <> 'gym' OR gym_id IS NOT NULL
  )
);

CREATE TABLE IF NOT EXISTS public.classes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  name text NOT NULL,
  coach_id uuid NOT NULL,
  type public.class_type NOT NULL,
  capacity integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT classes_capacity_check CHECK (capacity IS NULL OR capacity > 0),
  CONSTRAINT classes_coach_gym_fk
    FOREIGN KEY (coach_id, gym_id)
    REFERENCES public.coaches(id, gym_id)
    ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.class_clients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  CONSTRAINT class_clients_unique UNIQUE (class_id, client_id)
);

CREATE TABLE IF NOT EXISTS public.attendance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  status public.attendance_status NOT NULL DEFAULT 'checked_in',
  "timestamp" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_roles_gym_id ON public.roles(gym_id);
CREATE INDEX IF NOT EXISTS idx_users_gym_id ON public.users(gym_id);
CREATE INDEX IF NOT EXISTS idx_coaches_gym_id ON public.coaches(gym_id);
CREATE INDEX IF NOT EXISTS idx_clients_gym_id ON public.clients(gym_id);
CREATE INDEX IF NOT EXISTS idx_classes_gym_id ON public.classes(gym_id);
CREATE INDEX IF NOT EXISTS idx_class_clients_class_id ON public.class_clients(class_id);
CREATE INDEX IF NOT EXISTS idx_class_clients_client_id ON public.class_clients(client_id);
CREATE INDEX IF NOT EXISTS idx_attendance_gym_id ON public.attendance(gym_id);
CREATE INDEX IF NOT EXISTS idx_attendance_client_id ON public.attendance(client_id);
CREATE INDEX IF NOT EXISTS idx_gyms_name_search ON public.gyms USING gin (to_tsvector('simple', name));

CREATE OR REPLACE FUNCTION public.slug_prefix_from_gym_name(p_name text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  clean_name text;
  parts text[];
  part text;
  prefix text := '';
BEGIN
  clean_name := upper(regexp_replace(coalesce(p_name, ''), '[^A-Z0-9 ]', '', 'g'));
  parts := regexp_split_to_array(clean_name, '\s+');

  FOREACH part IN ARRAY parts LOOP
    IF part <> '' THEN
      prefix := prefix || left(part, 1);
    END IF;
  END LOOP;

  IF prefix = '' THEN
    prefix := left(replace(clean_name, ' ', ''), 3);
  END IF;

  IF prefix = '' THEN
    prefix := 'IND';
  END IF;

  RETURN left(prefix, 3);
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_unique_client_code(
  p_gym_id uuid,
  p_type public.client_type
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  prefix text;
  gym_name text;
  next_code text;
BEGIN
  IF p_gym_id IS NOT NULL THEN
    SELECT name INTO gym_name
    FROM public.gyms
    WHERE id = p_gym_id;
  END IF;

  prefix := CASE
    WHEN p_gym_id IS NOT NULL THEN public.slug_prefix_from_gym_name(gym_name)
    ELSE 'IND'
  END;

  LOOP
    next_code := format(
      '%s-%s-%s',
      prefix,
      lpad((floor(random() * 1000))::int::text, 3, '0'),
      chr(65 + floor(random() * 26)::int)
    );

    EXIT WHEN NOT EXISTS (
      SELECT 1
      FROM public.clients
      WHERE client_code = next_code
    );
  END LOOP;

  RETURN next_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_client_code()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.client_code IS NULL OR btrim(NEW.client_code) = '' THEN
    NEW.client_code := public.generate_unique_client_code(NEW.gym_id, NEW.type);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_client_code_trigger ON public.clients;
CREATE TRIGGER set_client_code_trigger
  BEFORE INSERT ON public.clients
  FOR EACH ROW
  EXECUTE FUNCTION public.set_client_code();

CREATE OR REPLACE FUNCTION public.ensure_class_client_enrollment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  class_capacity integer;
  class_gym uuid;
  client_gym uuid;
  enrollment_count integer;
BEGIN
  SELECT gym_id, capacity
  INTO class_gym, class_capacity
  FROM public.classes
  WHERE id = NEW.class_id;

  SELECT gym_id
  INTO client_gym
  FROM public.clients
  WHERE id = NEW.client_id;

  IF class_gym IS NULL THEN
    RAISE EXCEPTION 'Class was not found.';
  END IF;

  IF client_gym IS NULL OR client_gym <> class_gym THEN
    RAISE EXCEPTION 'Client must belong to the same gym as the class.';
  END IF;

  IF class_capacity IS NOT NULL THEN
    SELECT COUNT(*)
    INTO enrollment_count
    FROM public.class_clients
    WHERE class_id = NEW.class_id;

    IF enrollment_count >= class_capacity THEN
      RAISE EXCEPTION 'Class capacity reached.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ensure_class_client_enrollment_trigger ON public.class_clients;
CREATE TRIGGER ensure_class_client_enrollment_trigger
  BEFORE INSERT ON public.class_clients
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_class_client_enrollment();

CREATE OR REPLACE FUNCTION public.ensure_attendance_tenant_consistency()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  class_gym uuid;
  client_gym uuid;
BEGIN
  SELECT gym_id
  INTO client_gym
  FROM public.clients
  WHERE id = NEW.client_id;

  IF client_gym IS NULL OR client_gym <> NEW.gym_id THEN
    RAISE EXCEPTION 'Attendance client must belong to the same gym.';
  END IF;

  IF NEW.class_id IS NOT NULL THEN
    SELECT gym_id
    INTO class_gym
    FROM public.classes
    WHERE id = NEW.class_id;

    IF class_gym IS NULL OR class_gym <> NEW.gym_id THEN
      RAISE EXCEPTION 'Attendance class must belong to the same gym.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ensure_attendance_tenant_consistency_trigger ON public.attendance;
CREATE TRIGGER ensure_attendance_tenant_consistency_trigger
  BEFORE INSERT OR UPDATE ON public.attendance
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_attendance_tenant_consistency();

CREATE OR REPLACE FUNCTION public.current_user_gym_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT gym_id
  FROM public.users
  WHERE id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_user_permissions()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(r.permissions, '{}'::jsonb)
  FROM public.users u
  JOIN public.roles r
    ON r.id = u.role_id
   AND r.gym_id = u.gym_id
  WHERE u.id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.has_permission(p_permission text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((public.current_user_permissions() ->> p_permission)::boolean, false);
$$;

CREATE OR REPLACE FUNCTION public.provision_new_gym(
  p_user_id uuid,
  p_email text,
  p_gym_name text,
  p_full_name text DEFAULT NULL
)
RETURNS TABLE(gym_id uuid, admin_role_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_role_id uuid;
  v_gym_id uuid;
BEGIN
  INSERT INTO public.gyms (name)
  VALUES (p_gym_name)
  RETURNING id INTO v_gym_id;

  INSERT INTO public.roles (gym_id, name, permissions)
  VALUES
    (
      v_gym_id,
      'admin',
      jsonb_build_object(
        'dashboard.view', true,
        'clients.manage', true,
        'coaches.manage', true,
        'classes.manage', true,
        'attendance.manage', true,
        'roles.manage', true,
        'finance.view', true
      )
    ),
    (
      v_gym_id,
      'manager',
      jsonb_build_object(
        'dashboard.view', true,
        'clients.manage', true,
        'coaches.manage', true,
        'classes.manage', true,
        'attendance.manage', true,
        'finance.view', true
      )
    ),
    (
      v_gym_id,
      'finance',
      jsonb_build_object(
        'dashboard.view', true,
        'finance.view', true
      )
    ),
    (
      v_gym_id,
      'frontdesk',
      jsonb_build_object(
        'dashboard.view', true,
        'clients.manage', true,
        'classes.manage', true,
        'attendance.manage', true
      )
    );

  SELECT id INTO v_admin_role_id FROM public.roles WHERE gym_id = v_gym_id AND name = 'admin';

  INSERT INTO public.users (id, email, full_name, gym_id, role_id)
  VALUES (p_user_id, p_email, p_full_name, v_gym_id, v_admin_role_id);

  RETURN QUERY
  SELECT v_gym_id, v_admin_role_id;
END;
$$;

ALTER TABLE public.gyms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS gyms_select_policy ON public.gyms;
CREATE POLICY gyms_select_policy ON public.gyms
  FOR SELECT
  USING (id = public.current_user_gym_id());

DROP POLICY IF EXISTS roles_select_policy ON public.roles;
CREATE POLICY roles_select_policy ON public.roles
  FOR SELECT
  USING (gym_id = public.current_user_gym_id());

DROP POLICY IF EXISTS roles_manage_policy ON public.roles;
CREATE POLICY roles_manage_policy ON public.roles
  FOR ALL
  USING (gym_id = public.current_user_gym_id() AND public.has_permission('roles.manage'))
  WITH CHECK (gym_id = public.current_user_gym_id() AND public.has_permission('roles.manage'));

DROP POLICY IF EXISTS users_select_policy ON public.users;
CREATE POLICY users_select_policy ON public.users
  FOR SELECT
  USING (gym_id = public.current_user_gym_id());

DROP POLICY IF EXISTS users_manage_policy ON public.users;
CREATE POLICY users_manage_policy ON public.users
  FOR ALL
  USING (gym_id = public.current_user_gym_id() AND public.has_permission('roles.manage'))
  WITH CHECK (gym_id = public.current_user_gym_id() AND public.has_permission('roles.manage'));

DROP POLICY IF EXISTS coaches_select_policy ON public.coaches;
CREATE POLICY coaches_select_policy ON public.coaches
  FOR SELECT
  USING (gym_id = public.current_user_gym_id());

DROP POLICY IF EXISTS coaches_manage_policy ON public.coaches;
CREATE POLICY coaches_manage_policy ON public.coaches
  FOR ALL
  USING (gym_id = public.current_user_gym_id() AND public.has_permission('coaches.manage'))
  WITH CHECK (gym_id = public.current_user_gym_id() AND public.has_permission('coaches.manage'));

DROP POLICY IF EXISTS clients_select_policy ON public.clients;
CREATE POLICY clients_select_policy ON public.clients
  FOR SELECT
  USING (gym_id = public.current_user_gym_id());

DROP POLICY IF EXISTS clients_manage_policy ON public.clients;
CREATE POLICY clients_manage_policy ON public.clients
  FOR ALL
  USING (gym_id = public.current_user_gym_id() AND public.has_permission('clients.manage'))
  WITH CHECK (gym_id = public.current_user_gym_id() AND public.has_permission('clients.manage'));

DROP POLICY IF EXISTS classes_select_policy ON public.classes;
CREATE POLICY classes_select_policy ON public.classes
  FOR SELECT
  USING (gym_id = public.current_user_gym_id());

DROP POLICY IF EXISTS classes_manage_policy ON public.classes;
CREATE POLICY classes_manage_policy ON public.classes
  FOR ALL
  USING (gym_id = public.current_user_gym_id() AND public.has_permission('classes.manage'))
  WITH CHECK (gym_id = public.current_user_gym_id() AND public.has_permission('classes.manage'));

DROP POLICY IF EXISTS class_clients_select_policy ON public.class_clients;
CREATE POLICY class_clients_select_policy ON public.class_clients
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.classes c
      WHERE c.id = class_clients.class_id
        AND c.gym_id = public.current_user_gym_id()
    )
  );

DROP POLICY IF EXISTS class_clients_manage_policy ON public.class_clients;
CREATE POLICY class_clients_manage_policy ON public.class_clients
  FOR ALL
  USING (
    public.has_permission('classes.manage')
    AND EXISTS (
      SELECT 1
      FROM public.classes c
      WHERE c.id = class_clients.class_id
        AND c.gym_id = public.current_user_gym_id()
    )
  )
  WITH CHECK (
    public.has_permission('classes.manage')
    AND EXISTS (
      SELECT 1
      FROM public.classes c
      WHERE c.id = class_clients.class_id
        AND c.gym_id = public.current_user_gym_id()
    )
  );

DROP POLICY IF EXISTS attendance_select_policy ON public.attendance;
CREATE POLICY attendance_select_policy ON public.attendance
  FOR SELECT
  USING (gym_id = public.current_user_gym_id());

DROP POLICY IF EXISTS attendance_manage_policy ON public.attendance;
CREATE POLICY attendance_manage_policy ON public.attendance
  FOR ALL
  USING (gym_id = public.current_user_gym_id() AND public.has_permission('attendance.manage'))
  WITH CHECK (gym_id = public.current_user_gym_id() AND public.has_permission('attendance.manage'));

GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT SELECT ON public.gyms TO authenticated;
GRANT SELECT ON public.roles TO authenticated;
GRANT SELECT ON public.users TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.coaches TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.classes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.class_clients TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.attendance TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_gym_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_permissions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_permission(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.provision_new_gym(uuid, text, text, text) TO service_role;

COMMIT;
