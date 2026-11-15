-- Round 6 (audit closure) — DB-14 owner-role guard, remaining paths.
--
-- The round-6 verification suite proved a manage_staff holder could
-- directly INSERT an ACTIVE membership with the gym_owner role for
-- someone else (the RLS insert/update policies had no owner-role
-- exclusion), and set_membership_role had no owner-role guard either.
-- Only the gym's manager (gyms.manager_id = auth.uid()) may assign the
-- gym_owner role. The invite path was fixed in 20261115360000.
--
-- Safe: the app's own owner-role writes go through SECURITY DEFINER
-- functions (ensure_gym_default_roles, provision_new_gym, bootstrap),
-- which bypass RLS; the frontend's submitNewClient inserts CLIENT
-- roles only; ownership transfer by the manager stays allowed.

-- 1) set_membership_role: refuse the gym_owner role to non-managers.
CREATE OR REPLACE FUNCTION public.set_membership_role(p_membership_id uuid, p_role_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- DB-14: no self-grants — a manager cannot change their own membership's
  -- role (that is how a staff member promotes themselves to gym_owner).
  IF v_membership.user_id IS NOT NULL AND v_membership.user_id = auth.uid() THEN
    RAISE EXCEPTION 'You cannot change your own role.';
  END IF;

  -- DB-12: the new role must belong to the membership's gym.
  IF NOT EXISTS (
    SELECT 1
    FROM public.roles r
    WHERE r.id = p_role_id
      AND r.gym_id = v_membership.gym_id
  ) THEN
    RAISE EXCEPTION 'Role does not belong to this gym.';
  END IF;

  -- DB-14 (round 6): only the gym's manager may assign the gym_owner
  -- role. A manage_staff holder could otherwise promote anyone to
  -- owner of the gym.
  IF EXISTS (
    SELECT 1 FROM public.roles r
    WHERE r.id = p_role_id AND r.code = 'gym_owner'
  ) AND NOT EXISTS (
    SELECT 1 FROM public.gyms g
    WHERE g.id = v_membership.gym_id AND g.manager_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only the gym manager can assign the gym_owner role.';
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
$function$;

-- 2) RLS: direct INSERT/UPDATE of gym_memberships may not assign the
-- gym_owner role unless the caller is the gym's manager.
DROP POLICY IF EXISTS gym_memberships_insert_v17b ON public.gym_memberships;
CREATE POLICY gym_memberships_insert_v17b ON public.gym_memberships
FOR INSERT WITH CHECK (
  has_permission('manage_staff', gym_id)
  AND ((user_id IS NULL) OR (user_id <> auth.uid()))
  AND (EXISTS (
    SELECT 1 FROM roles r
    WHERE ((r.id = gym_memberships.role_id) AND (r.gym_id = gym_memberships.gym_id))
  ))
  AND (status = ANY (ARRAY['pending'::text, 'accepted'::text, 'active'::text]))
  AND (
    NOT EXISTS (
      SELECT 1 FROM public.roles r
      WHERE r.id = gym_memberships.role_id AND r.code = 'gym_owner'
    )
    OR EXISTS (
      SELECT 1 FROM public.gyms g
      WHERE g.id = gym_memberships.gym_id AND g.manager_id = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS gym_memberships_update_v17b ON public.gym_memberships;
CREATE POLICY gym_memberships_update_v17b ON public.gym_memberships
FOR UPDATE USING (
  has_permission('manage_staff', gym_id)
  AND ((user_id IS NULL) OR (user_id <> auth.uid()))
) WITH CHECK (
  has_permission('manage_staff', gym_id)
  AND ((user_id IS NULL) OR (user_id <> auth.uid()))
  AND (EXISTS (
    SELECT 1 FROM roles r
    WHERE ((r.id = gym_memberships.role_id) AND (r.gym_id = gym_memberships.gym_id))
  ))
  AND (status = ANY (ARRAY['pending'::text, 'accepted'::text, 'active'::text, 'declined'::text, 'revoked'::text]))
  AND (
    NOT EXISTS (
      SELECT 1 FROM public.roles r
      WHERE r.id = gym_memberships.role_id AND r.code = 'gym_owner'
    )
    OR EXISTS (
      SELECT 1 FROM public.gyms g
      WHERE g.id = gym_memberships.gym_id AND g.manager_id = auth.uid()
    )
  )
);
