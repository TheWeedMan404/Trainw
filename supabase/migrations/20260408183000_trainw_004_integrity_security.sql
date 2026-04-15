-- ============================================================================
-- TRAINW V16 PRODUCTION - INTEGRITY AND SECURITY
-- Purpose:
--   - Repair orphaned relationships before tightening constraints
--   - Add missing uniqueness and foreign key protections
--   - Replace legacy overlapping RLS policies with one coherent policy model
--   - Grant only the RPC surface needed by the V14 frontend
-- ============================================================================

-- ----------------------------------------------------------------------------
-- LEGACY COMPATIBILITY
-- ----------------------------------------------------------------------------

ALTER TABLE public.gym_classes
  ADD COLUMN IF NOT EXISTS created_by uuid;

ALTER TABLE public.check_ins
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS source_session_id uuid,
  ADD COLUMN IF NOT EXISTS notes text;

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS class_id uuid,
  ADD COLUMN IF NOT EXISTS payment_id uuid,
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS updated_by uuid;

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS created_by uuid;

ALTER TABLE public.payment_events
  ADD COLUMN IF NOT EXISTS created_by uuid;

ALTER TABLE public.session_status_history
  ADD COLUMN IF NOT EXISTS changed_by uuid;

-- ----------------------------------------------------------------------------
-- RELATIONSHIP CLEANUP
-- ----------------------------------------------------------------------------

DELETE FROM public.coach_profiles cp
WHERE NOT EXISTS (
  SELECT 1
  FROM public.users u
  WHERE u.id = cp.user_id
);

DELETE FROM public.client_profiles cp
WHERE NOT EXISTS (
  SELECT 1
  FROM public.users u
  WHERE u.id = cp.user_id
);

DELETE FROM public.coach_client_assignments cca
WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = cca.coach_id)
   OR NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = cca.client_id)
   OR NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = cca.gym_id);

UPDATE public.coach_client_assignments cca
SET assigned_by = NULL
WHERE assigned_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = cca.assigned_by
  );

DELETE FROM public.messages m
WHERE NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = m.gym_id)
   OR NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = m.sender_id)
   OR NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = m.receiver_id);

DELETE FROM public.gym_classes gc
WHERE NOT EXISTS (
  SELECT 1
  FROM public.gyms g
  WHERE g.id = gc.gym_id
);

UPDATE public.gym_classes gc
SET created_by = NULL
WHERE created_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = gc.created_by
  );

UPDATE public.gym_classes gc
SET coach_id = NULL
WHERE coach_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = gc.coach_id
  );

DELETE FROM public.weight_logs wl
WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = wl.client_id)
   OR NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = wl.gym_id);

UPDATE public.weight_logs wl
SET logged_by = NULL
WHERE logged_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = wl.logged_by
  );

DELETE FROM public.workout_plans wp
WHERE NOT EXISTS (
  SELECT 1
  FROM public.gyms g
  WHERE g.id = wp.gym_id
);

UPDATE public.workout_plans wp
SET created_by = NULL
WHERE created_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = wp.created_by
  );

UPDATE public.workout_plans wp
SET client_id = NULL
WHERE client_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = wp.client_id
  );

DELETE FROM public.workout_exercises we
WHERE NOT EXISTS (
  SELECT 1
  FROM public.workout_plans wp
  WHERE wp.id = we.plan_id
);

DELETE FROM public.workout_logs wl
WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = wl.client_id)
   OR NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = wl.gym_id);

UPDATE public.workout_logs wl
SET plan_id = NULL
WHERE plan_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.workout_plans wp
    WHERE wp.id = wl.plan_id
  );

UPDATE public.workout_logs wl
SET logged_by = NULL
WHERE logged_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = wl.logged_by
  );

DELETE FROM public.workout_log_sets wls
WHERE NOT EXISTS (
  SELECT 1
  FROM public.workout_logs wl
  WHERE wl.id = wls.log_id
);

DELETE FROM public.client_goals cg
WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = cg.client_id)
   OR NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = cg.gym_id);

DELETE FROM public.check_ins ci
WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = ci.client_id)
   OR NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = ci.gym_id);

UPDATE public.check_ins ci
SET created_by = NULL
WHERE created_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = ci.created_by
  );

UPDATE public.check_ins ci
SET source_session_id = NULL
WHERE source_session_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.sessions s
    WHERE s.id = ci.source_session_id
  );

DELETE FROM public.gate_sessions gs
WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = gs.client_id)
   OR NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = gs.gym_id);

UPDATE public.coach_availability ca
SET gym_id = u.gym_id
FROM public.users u
WHERE u.id = ca.coach_id
  AND u.role = 'coach'
  AND ca.gym_id IS DISTINCT FROM u.gym_id;

DELETE FROM public.coach_availability ca
WHERE NOT EXISTS (
  SELECT 1
  FROM public.users u
  WHERE u.id = ca.coach_id
    AND u.role = 'coach'
);

UPDATE public.sessions s
SET coach_id = NULL
WHERE coach_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = s.coach_id
      AND u.role = 'coach'
  );

UPDATE public.sessions s
SET client_id = NULL
WHERE client_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = s.client_id
      AND u.role = 'client'
  );

UPDATE public.sessions s
SET class_id = NULL
WHERE s.class_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.gym_classes gc
    WHERE gc.id = s.class_id
  );

UPDATE public.sessions s
SET payment_id = NULL
WHERE s.payment_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.payments p
    WHERE p.id = s.payment_id
  );

UPDATE public.sessions s
SET created_by = NULL
WHERE s.created_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = s.created_by
  );

UPDATE public.sessions s
SET updated_by = NULL
WHERE s.updated_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = s.updated_by
  );

DELETE FROM public.sessions s
WHERE NOT EXISTS (
  SELECT 1
  FROM public.gyms g
  WHERE g.id = s.gym_id
);

UPDATE public.session_enrollments se
SET gym_id = s.gym_id
FROM public.sessions s
WHERE s.id = se.session_id
  AND se.gym_id IS DISTINCT FROM s.gym_id;

WITH ranked_enrollments AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY session_id, client_id
      ORDER BY enrolled_at DESC, id DESC
    ) AS rn
  FROM public.session_enrollments
)
DELETE FROM public.session_enrollments se
USING ranked_enrollments r
WHERE se.id = r.id
  AND r.rn > 1;

DELETE FROM public.session_enrollments se
WHERE NOT EXISTS (SELECT 1 FROM public.sessions s WHERE s.id = se.session_id)
   OR NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = se.client_id)
   OR NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = se.gym_id);

WITH ranked_reviews AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY session_id
      ORDER BY created_at DESC, id DESC
    ) AS rn
  FROM public.reviews
)
DELETE FROM public.reviews r
USING ranked_reviews rr
WHERE r.id = rr.id
  AND rr.rn > 1;

DELETE FROM public.reviews r
WHERE NOT EXISTS (SELECT 1 FROM public.sessions s WHERE s.id = r.session_id)
   OR NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = r.coach_id)
   OR NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = r.client_id);

UPDATE public.reviews r
SET gym_id = s.gym_id
FROM public.sessions s
WHERE s.id = r.session_id
  AND r.gym_id IS DISTINCT FROM s.gym_id;

DELETE FROM public.payments p
WHERE NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = p.gym_id)
   OR NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = p.client_id);

UPDATE public.payments p
SET created_by = NULL
WHERE created_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = p.created_by
  );

UPDATE public.payments p
SET session_id = NULL
WHERE session_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.sessions s
    WHERE s.id = p.session_id
  );

DELETE FROM public.payment_events pe
WHERE NOT EXISTS (SELECT 1 FROM public.payments p WHERE p.id = pe.payment_id)
   OR NOT EXISTS (SELECT 1 FROM public.gyms g WHERE g.id = pe.gym_id);

UPDATE public.payment_events pe
SET created_by = NULL
WHERE created_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = pe.created_by
  );

DELETE FROM public.session_status_history ssh
WHERE NOT EXISTS (
  SELECT 1
  FROM public.gyms g
  WHERE g.id = ssh.gym_id
);

UPDATE public.session_status_history ssh
SET changed_by = NULL
WHERE changed_by IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = ssh.changed_by
  );


-- ----------------------------------------------------------------------------
-- UNIQUENESS AND FOREIGN KEYS
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.session_enrollments'::regclass
      AND conname = 'session_enrollments_session_client_key'
  ) THEN
    ALTER TABLE public.session_enrollments
      ADD CONSTRAINT session_enrollments_session_client_key
      UNIQUE (session_id, client_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.reviews'::regclass
      AND conname = 'reviews_session_id_key'
  ) THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_session_id_key
      UNIQUE (session_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coach_profiles_user_id_fkey' AND conrelid = 'public.coach_profiles'::regclass) THEN
    ALTER TABLE public.coach_profiles ADD CONSTRAINT coach_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coach_profiles_gym_id_fkey' AND conrelid = 'public.coach_profiles'::regclass) THEN
    ALTER TABLE public.coach_profiles ADD CONSTRAINT coach_profiles_gym_id_fkey FOREIGN KEY (gym_id) REFERENCES public.gyms(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'client_profiles_user_id_fkey' AND conrelid = 'public.client_profiles'::regclass) THEN
    ALTER TABLE public.client_profiles ADD CONSTRAINT client_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coach_client_assignments_assigned_by_fkey' AND conrelid = 'public.coach_client_assignments'::regclass) THEN
    ALTER TABLE public.coach_client_assignments ADD CONSTRAINT coach_client_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'messages_sender_id_fkey' AND conrelid = 'public.messages'::regclass) THEN
    ALTER TABLE public.messages ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'messages_receiver_id_fkey' AND conrelid = 'public.messages'::regclass) THEN
    ALTER TABLE public.messages ADD CONSTRAINT messages_receiver_id_fkey FOREIGN KEY (receiver_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'gym_classes_created_by_fkey' AND conrelid = 'public.gym_classes'::regclass) THEN
    ALTER TABLE public.gym_classes ADD CONSTRAINT gym_classes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'gym_classes_coach_id_fkey' AND conrelid = 'public.gym_classes'::regclass) THEN
    ALTER TABLE public.gym_classes ADD CONSTRAINT gym_classes_coach_id_fkey FOREIGN KEY (coach_id) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'weight_logs_logged_by_fkey' AND conrelid = 'public.weight_logs'::regclass) THEN
    ALTER TABLE public.weight_logs ADD CONSTRAINT weight_logs_logged_by_fkey FOREIGN KEY (logged_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'workout_plans_created_by_fkey' AND conrelid = 'public.workout_plans'::regclass) THEN
    ALTER TABLE public.workout_plans ADD CONSTRAINT workout_plans_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'workout_logs_logged_by_fkey' AND conrelid = 'public.workout_logs'::regclass) THEN
    ALTER TABLE public.workout_logs ADD CONSTRAINT workout_logs_logged_by_fkey FOREIGN KEY (logged_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'check_ins_created_by_fkey' AND conrelid = 'public.check_ins'::regclass) THEN
    ALTER TABLE public.check_ins ADD CONSTRAINT check_ins_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sessions_created_by_fkey' AND conrelid = 'public.sessions'::regclass) THEN
    ALTER TABLE public.sessions ADD CONSTRAINT sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sessions_updated_by_fkey' AND conrelid = 'public.sessions'::regclass) THEN
    ALTER TABLE public.sessions ADD CONSTRAINT sessions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sessions_class_id_fkey' AND conrelid = 'public.sessions'::regclass) THEN
    ALTER TABLE public.sessions ADD CONSTRAINT sessions_class_id_fkey FOREIGN KEY (class_id) REFERENCES public.gym_classes(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coach_availability_gym_id_fkey' AND conrelid = 'public.coach_availability'::regclass) THEN
    ALTER TABLE public.coach_availability ADD CONSTRAINT coach_availability_gym_id_fkey FOREIGN KEY (gym_id) REFERENCES public.gyms(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'session_status_history_changed_by_fkey' AND conrelid = 'public.session_status_history'::regclass) THEN
    ALTER TABLE public.session_status_history ADD CONSTRAINT session_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payment_events_created_by_fkey' AND conrelid = 'public.payment_events'::regclass) THEN
    ALTER TABLE public.payment_events ADD CONSTRAINT payment_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- RLS RESET
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  v_table text;
  v_policy record;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'gyms',
    'users',
    'coach_profiles',
    'client_profiles',
    'coach_client_assignments',
    'messages',
    'gym_classes',
    'weight_logs',
    'workout_plans',
    'workout_exercises',
    'workout_logs',
    'workout_log_sets',
    'client_goals',
    'check_ins',
    'gate_sessions',
    'sessions',
    'session_enrollments',
    'coach_availability',
    'reviews',
    'specialty_tags',
    'coach_specialties',
    'payments',
    'payment_events',
    'session_status_history'
  ] LOOP
    FOR v_policy IN
      SELECT policyname
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = v_table
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', v_policy.policyname, v_table);
    END LOOP;
  END LOOP;
END $$;

ALTER TABLE public.gyms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_client_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weight_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_log_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.check_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gate_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.specialty_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_specialties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_status_history ENABLE ROW LEVEL SECURITY;


-- ----------------------------------------------------------------------------
-- POLICIES
-- ----------------------------------------------------------------------------

CREATE POLICY gyms_select ON public.gyms
  FOR SELECT
  USING (id = public.get_my_gym_id());

CREATE POLICY gyms_insert ON public.gyms
  FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND COALESCE(public.get_my_role(), public.get_signup_role()) IN ('gym_owner', 'gym', 'admin')
  );

CREATE POLICY gyms_update ON public.gyms
  FOR UPDATE
  USING (public.manages_gym(id))
  WITH CHECK (public.manages_gym(id));

CREATE POLICY users_select ON public.users
  FOR SELECT
  USING (public.can_view_user(id));

CREATE POLICY users_insert ON public.users
  FOR INSERT
  WITH CHECK (
    id = auth.uid()
    OR (
      public.is_gym_manager()
      AND gym_id = public.get_my_gym_id()
      AND role IN ('coach', 'client')
    )
  );

CREATE POLICY users_update ON public.users
  FOR UPDATE
  USING (
    id = auth.uid()
    OR (
      public.is_gym_manager()
      AND gym_id = public.get_my_gym_id()
    )
  )
  WITH CHECK (
    id = auth.uid()
    OR (
      public.is_gym_manager()
      AND gym_id = public.get_my_gym_id()
    )
  );

CREATE POLICY users_delete ON public.users
  FOR DELETE
  USING (
    id = auth.uid()
    OR (
      public.is_gym_manager()
      AND gym_id = public.get_my_gym_id()
    )
  );

CREATE POLICY coach_profiles_select ON public.coach_profiles
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR public.is_same_gym_user(user_id)
  );

CREATE POLICY coach_profiles_insert ON public.coach_profiles
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    OR (
      public.is_gym_manager()
      AND public.is_same_gym_user(user_id)
    )
  );

CREATE POLICY coach_profiles_update ON public.coach_profiles
  FOR UPDATE
  USING (
    user_id = auth.uid()
    OR (
      public.is_gym_manager()
      AND public.is_same_gym_user(user_id)
    )
  )
  WITH CHECK (
    user_id = auth.uid()
    OR (
      public.is_gym_manager()
      AND public.is_same_gym_user(user_id)
    )
  );

CREATE POLICY coach_profiles_delete ON public.coach_profiles
  FOR DELETE
  USING (
    public.is_gym_manager()
    AND public.is_same_gym_user(user_id)
  );

CREATE POLICY client_profiles_select ON public.client_profiles
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR (
      public.is_gym_manager()
      AND public.is_same_gym_user(user_id)
    )
    OR (
      public.get_my_role() = 'coach'
      AND public.can_manage_client_data(user_id, public.user_gym_id(user_id))
    )
  );

CREATE POLICY client_profiles_insert ON public.client_profiles
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    OR (
      public.is_gym_manager()
      AND public.is_same_gym_user(user_id)
    )
  );

CREATE POLICY client_profiles_update ON public.client_profiles
  FOR UPDATE
  USING (
    user_id = auth.uid()
    OR (
      public.is_gym_manager()
      AND public.is_same_gym_user(user_id)
    )
  )
  WITH CHECK (
    user_id = auth.uid()
    OR (
      public.is_gym_manager()
      AND public.is_same_gym_user(user_id)
    )
  );

CREATE POLICY client_profiles_delete ON public.client_profiles
  FOR DELETE
  USING (
    public.is_gym_manager()
    AND public.is_same_gym_user(user_id)
  );

CREATE POLICY assignments_select ON public.coach_client_assignments
  FOR SELECT
  USING (
    coach_id = auth.uid()
    OR client_id = auth.uid()
    OR public.manages_gym(gym_id)
  );

CREATE POLICY assignments_insert ON public.coach_client_assignments
  FOR INSERT
  WITH CHECK (
    public.manages_gym(gym_id)
    AND public.is_same_gym_user(coach_id)
    AND public.is_same_gym_user(client_id)
  );

CREATE POLICY assignments_update ON public.coach_client_assignments
  FOR UPDATE
  USING (public.manages_gym(gym_id))
  WITH CHECK (
    public.manages_gym(gym_id)
    AND public.is_same_gym_user(coach_id)
    AND public.is_same_gym_user(client_id)
  );

CREATE POLICY assignments_delete ON public.coach_client_assignments
  FOR DELETE
  USING (public.manages_gym(gym_id));

CREATE POLICY messages_select ON public.messages
  FOR SELECT
  USING (sender_id = auth.uid() OR receiver_id = auth.uid());

CREATE POLICY messages_insert ON public.messages
  FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND public.can_message_user(receiver_id, gym_id)
  );

CREATE POLICY messages_update ON public.messages
  FOR UPDATE
  USING (receiver_id = auth.uid())
  WITH CHECK (receiver_id = auth.uid());

CREATE POLICY gym_classes_select ON public.gym_classes
  FOR SELECT
  USING (gym_id = public.get_my_gym_id());

CREATE POLICY gym_classes_insert ON public.gym_classes
  FOR INSERT
  WITH CHECK (public.manages_gym(gym_id));

CREATE POLICY gym_classes_update ON public.gym_classes
  FOR UPDATE
  USING (public.manages_gym(gym_id))
  WITH CHECK (public.manages_gym(gym_id));

CREATE POLICY gym_classes_delete ON public.gym_classes
  FOR DELETE
  USING (public.manages_gym(gym_id));

CREATE POLICY weight_logs_select ON public.weight_logs
  FOR SELECT
  USING (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY weight_logs_insert ON public.weight_logs
  FOR INSERT
  WITH CHECK (
    (
      client_id = auth.uid()
      AND gym_id = public.get_my_gym_id()
      AND (logged_by IS NULL OR logged_by = auth.uid())
    )
    OR (
      public.can_manage_client_data(client_id, gym_id)
      AND (logged_by IS NULL OR logged_by = auth.uid())
    )
  );

CREATE POLICY weight_logs_update ON public.weight_logs
  FOR UPDATE
  USING (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  )
  WITH CHECK (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY weight_logs_delete ON public.weight_logs
  FOR DELETE
  USING (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY workout_plans_select ON public.workout_plans
  FOR SELECT
  USING (
    public.manages_gym(gym_id)
    OR created_by = auth.uid()
    OR client_id = auth.uid()
    OR (client_id IS NOT NULL AND public.can_manage_client_data(client_id, gym_id))
  );

CREATE POLICY workout_plans_insert ON public.workout_plans
  FOR INSERT
  WITH CHECK (
    gym_id = public.get_my_gym_id()
    AND created_by = auth.uid()
    AND (
      public.is_gym_manager()
      OR public.get_my_role() = 'coach'
    )
    AND (
      client_id IS NULL
      OR public.can_manage_client_data(client_id, gym_id)
    )
  );

CREATE POLICY workout_plans_update ON public.workout_plans
  FOR UPDATE
  USING (public.can_write_workout_plan(id))
  WITH CHECK (
    gym_id = public.get_my_gym_id()
    AND (
      public.is_gym_manager()
      OR created_by = auth.uid()
      OR (
        public.get_my_role() = 'coach'
        AND client_id IS NOT NULL
        AND public.can_manage_client_data(client_id, gym_id)
      )
    )
  );

CREATE POLICY workout_plans_delete ON public.workout_plans
  FOR DELETE
  USING (public.can_write_workout_plan(id));

CREATE POLICY workout_exercises_select ON public.workout_exercises
  FOR SELECT
  USING (public.can_read_workout_plan(plan_id));

CREATE POLICY workout_exercises_insert ON public.workout_exercises
  FOR INSERT
  WITH CHECK (public.can_write_workout_plan(plan_id));

CREATE POLICY workout_exercises_update ON public.workout_exercises
  FOR UPDATE
  USING (public.can_write_workout_plan(plan_id))
  WITH CHECK (public.can_write_workout_plan(plan_id));

CREATE POLICY workout_exercises_delete ON public.workout_exercises
  FOR DELETE
  USING (public.can_write_workout_plan(plan_id));

CREATE POLICY workout_logs_select ON public.workout_logs
  FOR SELECT
  USING (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY workout_logs_insert ON public.workout_logs
  FOR INSERT
  WITH CHECK (
    (
      client_id = auth.uid()
      AND gym_id = public.get_my_gym_id()
      AND (logged_by IS NULL OR logged_by = auth.uid())
    )
    OR (
      public.can_manage_client_data(client_id, gym_id)
      AND (logged_by IS NULL OR logged_by = auth.uid())
    )
  );

CREATE POLICY workout_logs_update ON public.workout_logs
  FOR UPDATE
  USING (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  )
  WITH CHECK (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY workout_logs_delete ON public.workout_logs
  FOR DELETE
  USING (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY workout_log_sets_select ON public.workout_log_sets
  FOR SELECT
  USING (public.can_read_workout_log(log_id));

CREATE POLICY workout_log_sets_insert ON public.workout_log_sets
  FOR INSERT
  WITH CHECK (public.can_write_workout_log(log_id));

CREATE POLICY workout_log_sets_update ON public.workout_log_sets
  FOR UPDATE
  USING (public.can_write_workout_log(log_id))
  WITH CHECK (public.can_write_workout_log(log_id));

CREATE POLICY workout_log_sets_delete ON public.workout_log_sets
  FOR DELETE
  USING (public.can_write_workout_log(log_id));

CREATE POLICY client_goals_select ON public.client_goals
  FOR SELECT
  USING (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY client_goals_insert ON public.client_goals
  FOR INSERT
  WITH CHECK (
    (
      client_id = auth.uid()
      AND gym_id = public.get_my_gym_id()
    )
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY client_goals_update ON public.client_goals
  FOR UPDATE
  USING (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  )
  WITH CHECK (
    (
      client_id = auth.uid()
      AND gym_id = public.get_my_gym_id()
    )
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY client_goals_delete ON public.client_goals
  FOR DELETE
  USING (
    (client_id = auth.uid() AND gym_id = public.get_my_gym_id())
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY check_ins_select ON public.check_ins
  FOR SELECT
  USING (
    client_id = auth.uid()
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY check_ins_insert ON public.check_ins
  FOR INSERT
  WITH CHECK (
    (
      client_id = auth.uid()
      AND gym_id = public.get_my_gym_id()
    )
    OR public.can_manage_client_data(client_id, gym_id)
  );

CREATE POLICY check_ins_delete ON public.check_ins
  FOR DELETE
  USING (public.manages_gym(gym_id));

CREATE POLICY gate_sessions_select ON public.gate_sessions
  FOR SELECT
  USING (client_id = auth.uid());

CREATE POLICY gate_sessions_insert ON public.gate_sessions
  FOR INSERT
  WITH CHECK (
    client_id = auth.uid()
    AND gym_id = public.get_my_gym_id()
  );

CREATE POLICY gate_sessions_delete ON public.gate_sessions
  FOR DELETE
  USING (client_id = auth.uid());

CREATE POLICY sessions_select ON public.sessions
  FOR SELECT
  USING (
    public.manages_gym(gym_id)
    OR coach_id = auth.uid()
    OR client_id = auth.uid()
  );

CREATE POLICY sessions_insert ON public.sessions
  FOR INSERT
  WITH CHECK (public.manages_gym(gym_id));

CREATE POLICY sessions_update ON public.sessions
  FOR UPDATE
  USING (public.manages_gym(gym_id))
  WITH CHECK (public.manages_gym(gym_id));

CREATE POLICY sessions_delete ON public.sessions
  FOR DELETE
  USING (public.manages_gym(gym_id));

CREATE POLICY enrollments_select ON public.session_enrollments
  FOR SELECT
  USING (
    client_id = auth.uid()
    OR public.manages_gym(gym_id)
    OR EXISTS (
      SELECT 1
      FROM public.sessions s
      WHERE s.id = session_id
        AND s.coach_id = auth.uid()
    )
  );

CREATE POLICY enrollments_insert ON public.session_enrollments
  FOR INSERT
  WITH CHECK (
    (
      client_id = auth.uid()
      AND gym_id = public.get_my_gym_id()
    )
    OR public.manages_gym(gym_id)
  );

CREATE POLICY enrollments_delete ON public.session_enrollments
  FOR DELETE
  USING (
    client_id = auth.uid()
    OR public.manages_gym(gym_id)
  );

CREATE POLICY coach_availability_select ON public.coach_availability
  FOR SELECT
  USING (
    COALESCE(gym_id, public.user_gym_id(coach_id)) = public.get_my_gym_id()
  );

CREATE POLICY coach_availability_insert ON public.coach_availability
  FOR INSERT
  WITH CHECK (
    (
      coach_id = auth.uid()
      AND COALESCE(gym_id, public.get_my_gym_id()) = public.get_my_gym_id()
    )
    OR public.manages_gym(COALESCE(gym_id, public.get_my_gym_id()))
  );

CREATE POLICY coach_availability_update ON public.coach_availability
  FOR UPDATE
  USING (
    coach_id = auth.uid()
    OR public.manages_gym(COALESCE(gym_id, public.user_gym_id(coach_id)))
  )
  WITH CHECK (
    (
      coach_id = auth.uid()
      AND COALESCE(gym_id, public.get_my_gym_id()) = public.get_my_gym_id()
    )
    OR public.manages_gym(COALESCE(gym_id, public.get_my_gym_id()))
  );

CREATE POLICY coach_availability_delete ON public.coach_availability
  FOR DELETE
  USING (
    coach_id = auth.uid()
    OR public.manages_gym(COALESCE(gym_id, public.user_gym_id(coach_id)))
  );

CREATE POLICY reviews_select ON public.reviews
  FOR SELECT
  USING (
    coach_id = auth.uid()
    OR client_id = auth.uid()
    OR public.manages_gym(COALESCE(gym_id, public.user_gym_id(coach_id)))
  );

CREATE POLICY reviews_insert ON public.reviews
  FOR INSERT
  WITH CHECK (client_id = auth.uid());

CREATE POLICY reviews_update ON public.reviews
  FOR UPDATE
  USING (
    client_id = auth.uid()
    OR public.manages_gym(COALESCE(gym_id, public.user_gym_id(coach_id)))
  )
  WITH CHECK (
    client_id = auth.uid()
    OR public.manages_gym(COALESCE(gym_id, public.user_gym_id(coach_id)))
  );

CREATE POLICY reviews_delete ON public.reviews
  FOR DELETE
  USING (
    client_id = auth.uid()
    OR public.manages_gym(COALESCE(gym_id, public.user_gym_id(coach_id)))
  );

CREATE POLICY specialty_tags_select ON public.specialty_tags
  FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY coach_specialties_select ON public.coach_specialties
  FOR SELECT
  USING (COALESCE(gym_id, public.user_gym_id(coach_user_id)) = public.get_my_gym_id());

CREATE POLICY payments_select ON public.payments
  FOR SELECT
  USING (
    client_id = auth.uid()
    OR public.manages_gym(gym_id)
    OR EXISTS (
      SELECT 1
      FROM public.sessions s
      WHERE s.id = session_id
        AND s.coach_id = auth.uid()
    )
  );

CREATE POLICY payments_insert ON public.payments
  FOR INSERT
  WITH CHECK (public.manages_gym(gym_id));

CREATE POLICY payments_update ON public.payments
  FOR UPDATE
  USING (public.manages_gym(gym_id))
  WITH CHECK (public.manages_gym(gym_id));

CREATE POLICY payments_delete ON public.payments
  FOR DELETE
  USING (public.manages_gym(gym_id));

CREATE POLICY payment_events_select ON public.payment_events
  FOR SELECT
  USING (
    public.manages_gym(gym_id)
    OR EXISTS (
      SELECT 1
      FROM public.payments p
      WHERE p.id = payment_id
        AND p.client_id = auth.uid()
    )
  );

CREATE POLICY session_status_history_select ON public.session_status_history
  FOR SELECT
  USING (
    public.manages_gym(gym_id)
    OR EXISTS (
      SELECT 1
      FROM public.sessions s
      WHERE s.id = session_id
        AND (s.client_id = auth.uid() OR s.coach_id = auth.uid())
    )
  );


-- ----------------------------------------------------------------------------
-- GRANTS
-- ----------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.get_bookable_slots(uuid, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.book_coach_session(uuid, date, time, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.respond_to_session_booking(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_session_booking(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_session_booking(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_session_no_show(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.leave_session_review(uuid, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_bookable_slots(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.book_coach_session(uuid, date, time, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_to_session_booking(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_session_booking(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_session_booking(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_session_no_show(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_session_review(uuid, integer, text) TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;
