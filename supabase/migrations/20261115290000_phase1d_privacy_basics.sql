-- P2-9 — privacy basics: consent timestamp + data export.
--
-- (1) client_profiles.consent_given_at records when the user accepted
--     the privacy terms at signup. The static login page and the Next.js
--     signup form both send consent_given_at in the signup metadata, and
--     handle_new_user() (rewritten here verbatim from the DB-62 version,
--     plus the consent wiring) stores it. The column stays NULL for
--     accounts created before this lands and for users invited by a gym
--     (the gym attests their consent offline — a consent checkbox on the
--     public register-client flow is a follow-up, since the archived
--     schema's clients table has no consent column).
-- (2) export_member_data() returns the caller's own data as one JSON
--     document (or, for a gym manager, a member of one of their gyms).
--     Biometric credential material is never exported — only the type,
--     label and dates. Deletion itself is already covered by the NX-10
--     delete actions (client, coach, staff user).

ALTER TABLE public.client_profiles
  ADD COLUMN IF NOT EXISTS consent_given_at timestamptz;

COMMENT ON COLUMN public.client_profiles.consent_given_at IS
  'When the user accepted the privacy terms at signup (P2-9). NULL for accounts created before this column existed and for gym-invited users.';

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_name      text;
  v_phone     text;
  v_consent   timestamptz;
BEGIN
  -- DB-10: role and gym_id from raw_user_meta_data are untrusted client
  -- input. Every signup is a plain client with no gym; privilege and gym
  -- membership come only from invite / bootstrap / the owner flow.
  v_name := COALESCE(NULLIF(BTRIM(NEW.raw_user_meta_data->>'name'), ''), 'User');
  v_phone := NULLIF(BTRIM(NEW.raw_user_meta_data->>'phone'), '');

  -- P2-9: consent timestamp from the signup metadata. The signup forms
  -- send consent_given_at when the user ticks the privacy checkbox.
  -- Metadata is client-supplied, so validate before casting:
  -- pg_input_is_valid() answers without raising (no EXCEPTION block —
  -- DB-62 forbids blanket handlers in this trigger, and a scoped one
  -- would trip the same tripwire). A future timestamp is clamped to now().
  IF (NEW.raw_user_meta_data->>'consent_given_at') IS NOT NULL
     AND pg_input_is_valid(NEW.raw_user_meta_data->>'consent_given_at', 'timestamptz') THEN
    v_consent := (NEW.raw_user_meta_data->>'consent_given_at')::timestamptz;
  ELSE
    v_consent := NULL;
  END IF;
  IF v_consent IS NOT NULL AND v_consent > now() THEN
    v_consent := now();
  END IF;

  INSERT INTO public.users (
    id, name, email, role, gym_id, phone, language_preference, is_managed, is_active
  )
  VALUES (
    NEW.id,
    v_name,
    NULLIF(lower(BTRIM(NEW.email)), ''),
    'client',
    NULL,
    v_phone,
    COALESCE(NULLIF(lower(BTRIM(NEW.raw_user_meta_data->>'language_preference')), ''), 'fr'),
    false,
    true
  )
  ON CONFLICT (id) DO UPDATE
  SET
    name = COALESCE(NULLIF(EXCLUDED.name, ''), public.users.name),
    email = COALESCE(public.users.email, EXCLUDED.email),
    role = COALESCE(NULLIF(public.users.role, ''), EXCLUDED.role),
    gym_id = COALESCE(public.users.gym_id, EXCLUDED.gym_id),
    phone = COALESCE(public.users.phone, EXCLUDED.phone),
    language_preference = COALESCE(public.users.language_preference, EXCLUDED.language_preference),
    updated_at = now();

  -- DB-10: no gym is ever created here, no manager_id is ever set here,
  -- and no coach profile is auto-created. A client profile is the only
  -- side effect of a signup.
  IF NOT EXISTS (
    SELECT 1
    FROM public.client_profiles cp
    WHERE cp.user_id = NEW.id
  ) THEN
    INSERT INTO public.client_profiles (
      user_id, membership_tier, payment_status, experience_level, consent_given_at
    )
    VALUES (
      NEW.id,
      'basic',
      'pending',
      'beginner',
      v_consent
    );
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- P2-9 — data export (GDPR-style access right, Loi tunisienne n° 2004-63).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.export_member_data(p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_target uuid := COALESCE(p_user_id, v_caller);
  v_result jsonb;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF v_target IS NULL THEN
    RAISE EXCEPTION 'export_target_required';
  END IF;

  -- Anyone may export their own data. Exporting someone else's data
  -- requires managing a gym they hold an active membership in.
  IF v_target IS DISTINCT FROM v_caller THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.gym_memberships gm
      WHERE gm.user_id = v_target
        AND gm.status IN ('accepted', 'active')
        AND public.manages_gym(gm.gym_id)
    ) THEN
      RAISE EXCEPTION 'export_forbidden: not your data and not a manager of their gym';
    END IF;
  END IF;

  SELECT jsonb_build_object(
    'exported_at', now(),
    'exported_by', v_caller,
    'subject_id', v_target,
    'user', (SELECT to_jsonb(u) FROM public.users u WHERE u.id = v_target),
    'client_profiles', COALESCE((SELECT jsonb_agg(to_jsonb(cp)) FROM public.client_profiles cp WHERE cp.user_id = v_target), '[]'::jsonb),
    'gym_memberships', COALESCE((SELECT jsonb_agg(to_jsonb(gm)) FROM public.gym_memberships gm WHERE gm.user_id = v_target), '[]'::jsonb),
    'payments', COALESCE((SELECT jsonb_agg(to_jsonb(p)) FROM public.payments p WHERE p.client_id = v_target), '[]'::jsonb),
    'payment_events', COALESCE((SELECT jsonb_agg(to_jsonb(pe)) FROM public.payment_events pe WHERE pe.payment_id IN (SELECT p.id FROM public.payments p WHERE p.client_id = v_target)), '[]'::jsonb),
    'sessions', COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM public.sessions s WHERE s.client_id = v_target OR s.coach_id = v_target), '[]'::jsonb),
    'bookings', COALESCE((SELECT jsonb_agg(to_jsonb(b)) FROM public.bookings b WHERE b.client_id = v_target OR b.coach_id = v_target), '[]'::jsonb),
    'check_ins', COALESCE((SELECT jsonb_agg(to_jsonb(c)) FROM public.check_ins c WHERE c.client_id = v_target), '[]'::jsonb),
    'messages', COALESCE((SELECT jsonb_agg(to_jsonb(mm)) FROM public.messages mm WHERE mm.sender_id = v_target OR mm.receiver_id = v_target), '[]'::jsonb),
    'reviews', COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM public.reviews r WHERE r.client_id = v_target OR r.coach_id = v_target), '[]'::jsonb),
    'coach_assignments', COALESCE((SELECT jsonb_agg(to_jsonb(a)) FROM public.coach_client_assignments a WHERE a.client_id = v_target OR a.coach_id = v_target), '[]'::jsonb),
    'membership_freezes', COALESCE((SELECT jsonb_agg(to_jsonb(f)) FROM public.membership_freezes f WHERE f.user_id = v_target), '[]'::jsonb),
    -- Biometric credential material is NEVER exported: type, label and
    -- dates only — no credential_data (the HMAC hash).
    'member_credentials', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', mc.id, 'gym_id', mc.gym_id, 'type', mc.type, 'label', mc.label,
        'is_active', mc.is_active, 'enrolled_at', mc.enrolled_at,
        'last_used_at', mc.last_used_at, 'created_at', mc.created_at
      )) FROM public.member_credentials mc WHERE mc.client_id = v_target), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- DB-42/43/44 pattern: SECURITY DEFINER functions are revoked from PUBLIC
-- and granted only to the authenticated role.
REVOKE ALL ON FUNCTION public.export_member_data(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.export_member_data(uuid) TO authenticated;

COMMENT ON FUNCTION public.export_member_data(uuid) IS
  'P2-9 data export: returns the subject''s Trainw data as one JSON document. Self-export for anyone; a manager may export a member of one of their gyms. Credential material is never included.';
