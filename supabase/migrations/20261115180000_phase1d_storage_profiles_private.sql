-- ============================================================================
-- Round 4 (DB-46) — profiles/ objects in storage are no longer readable by
-- every member of the gym.
--
-- The v17 SELECT policy on storage.objects let ANY member of a gym read
-- ANY object under profiles/<gym_id>/ — every member's profile photo was
-- readable by every other member. The audit's fix: profiles/ reads need
-- owner or manage_staff/manage_media, or enforce is_public via a
-- media_assets/milestone_photos lookup.
--
-- As found, the audit's fix only half matches the code: milestone_photos
-- HAS is_public, but media_assets does NOT (its table definition in 007
-- has no is_public column). So this migration first adds
-- media_assets.is_public (default false — nothing becomes public by
-- default), then rewrites the policy as v18:
--   gyms/        — unchanged: any member of the gym (branding).
--   profiles/    — the object owner (foldername[3] = auth.uid()), OR a
--                  gym user with manage_staff or manage_media, OR the
--                  object is the public asset of a media_assets /
--                  milestone_photos row (storage_bucket + storage_path
--                  match, is_public = true).
-- The insert/update/delete policies are unchanged — they already
-- restrict profiles/ writes to the owner or manage_staff.
-- ============================================================================

ALTER TABLE public.media_assets
  ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.media_assets.is_public IS
  'DB-46: true only when the asset may be read by any gym member through storage. Defaults to false; profile photos are private unless explicitly made public.';

CREATE INDEX IF NOT EXISTS idx_milestone_photos_storage_ref
  ON public.milestone_photos(storage_bucket, storage_path);

-- The public-asset lookup must work even though milestone_photos rows are
-- only visible to their owner or a gym manager: a plain member's EXISTS
-- subquery would see no row at all. So the lookup is a SECURITY DEFINER
-- helper that exposes exactly one bit — "is this path a public asset?" —
-- and nothing else. (media_assets rows are visible to any gym member, so
-- its lookup would work inline; the helper keeps both lookups uniform
-- and immune to future tightening of the table policies.)
CREATE OR REPLACE FUNCTION public.storage_object_is_public(p_bucket text, p_path text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.media_assets ma
    WHERE ma.storage_bucket = p_bucket
      AND ma.storage_path = p_path
      AND ma.is_public = true
  ) OR EXISTS (
    SELECT 1 FROM public.milestone_photos mp
    WHERE mp.storage_bucket = p_bucket
      AND mp.storage_path = p_path
      AND mp.is_public = true
  );
$$;

REVOKE ALL ON FUNCTION public.storage_object_is_public(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.storage_object_is_public(text, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.storage_object_is_public(text, text) IS
  'DB-46: true when the given storage path is a public media_assets or milestone_photos row. SECURITY DEFINER so the storage policy can check publicity without exposing the asset rows themselves.';

DROP POLICY IF EXISTS trainw_media_select_v17 ON storage.objects;

CREATE POLICY trainw_media_select_v18 ON storage.objects
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
        AND (
          public.safe_uuid((storage.foldername(name))[3]) = auth.uid()
          OR public.has_permission('manage_staff', public.safe_uuid((storage.foldername(name))[2]))
          OR public.has_permission('manage_media', public.safe_uuid((storage.foldername(name))[2]))
          OR public.storage_object_is_public('trainw-media', name)
        )
      )
    )
  );

COMMENT ON POLICY trainw_media_select_v18 ON storage.objects IS
  'DB-46: profiles/ objects are readable only by the owner, gym staff with manage_staff/manage_media, or anyone when the asset row is marked is_public. The v17 policy let any gym member read any profile photo.';
