CREATE OR REPLACE FUNCTION public.revoke_gym_membership_by_user(
  p_user_id uuid,
  p_gym_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_membership_id uuid;
  v_revoked_count integer := 0;
BEGIN
  IF p_user_id IS NULL OR p_gym_id IS NULL THEN
    RAISE EXCEPTION 'User and gym are required.';
  END IF;

  FOR v_membership_id IN
    SELECT gm.id
    FROM public.gym_memberships gm
    WHERE gm.user_id = p_user_id
      AND gm.gym_id = p_gym_id
      AND gm.status IN ('pending', 'accepted', 'active')
    ORDER BY gm.created_at DESC
  LOOP
    PERFORM public.revoke_gym_membership(v_membership_id);
    v_revoked_count := v_revoked_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'gym_id', p_gym_id,
    'revoked_count', v_revoked_count,
    'status', CASE WHEN v_revoked_count > 0 THEN 'revoked' ELSE 'missing' END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_gym_membership_by_user(uuid, uuid) TO authenticated;
