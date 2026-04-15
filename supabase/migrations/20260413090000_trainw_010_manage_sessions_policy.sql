CREATE OR REPLACE FUNCTION public.can_manage_sessions(p_gym_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    public.user_has_membership(p_gym_id)
    AND (
      public.manages_gym(p_gym_id)
      OR public.has_permission('manage_sessions', p_gym_id)
    ),
    false
  );
$$;

DROP POLICY IF EXISTS sessions_insert ON public.sessions;
DROP POLICY IF EXISTS sessions_update ON public.sessions;
DROP POLICY IF EXISTS sessions_delete ON public.sessions;

CREATE POLICY sessions_insert ON public.sessions
  FOR INSERT
  WITH CHECK (
    public.can_manage_sessions(gym_id)
  );

CREATE POLICY sessions_update ON public.sessions
  FOR UPDATE
  USING (
    public.can_manage_sessions(gym_id)
    OR coach_id = auth.uid()
  )
  WITH CHECK (
    public.can_manage_sessions(gym_id)
    OR coach_id = auth.uid()
  );

CREATE POLICY sessions_delete ON public.sessions
  FOR DELETE
  USING (
    public.can_manage_sessions(gym_id)
  );
