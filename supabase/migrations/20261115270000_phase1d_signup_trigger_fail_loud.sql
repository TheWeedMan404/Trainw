-- DB-62 — let the signup trigger fail loudly.
--
-- handle_new_user() swallowed every error (EXCEPTION WHEN OTHERS THEN
-- RAISE LOG ...; RETURN NEW), so a failed profile creation never failed
-- the signup: a user could end up with an auth.users row and no
-- public.users row, and that gap is exactly what makes the self-INSERT
-- path in users_insert reachable. The users_insert half of DB-62 was
-- already done in round 2 (20261115020000: a self-insert may only
-- create role='client' with gym_id NULL) — this migration does the
-- remaining half: the blanket handler is removed, so an unexpected
-- error now fails the signup (the auth.users INSERT rolls back and the
-- caller sees the error) instead of silently creating a half-provisioned
-- account. The audit's alternative — alert on the log line — needs a
-- monitoring setup that does not exist yet (P2-7); failing loudly is
-- the correct behaviour until it does.
--
-- Removing the handler is safe for legitimate signups: the users write
-- is an ON CONFLICT upsert (it cannot fail on a duplicate), the profile
-- write is guarded by IF NOT EXISTS, and the profile's gym_id is NULL
-- (NULLs are distinct in the (user_id, gym_id) unique index, so the
-- insert cannot unique-violate). The only errors left are genuine
-- failures — constraint, permission, or database errors — which must
-- not be swallowed. The data-repair audit (DB-50) already detects any
-- auth user with no public row, so an orphan that somehow still occurs
-- is caught by the audit instead of hidden by the trigger.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_name      text;
  v_phone     text;
BEGIN
  -- DB-10: role and gym_id from raw_user_meta_data are untrusted client
  -- input. Every signup is a plain client with no gym; privilege and gym
  -- membership come only from invite / bootstrap / the owner flow.
  v_name := COALESCE(NULLIF(BTRIM(NEW.raw_user_meta_data->>'name'), ''), 'User');
  v_phone := NULLIF(BTRIM(NEW.raw_user_meta_data->>'phone'), '');

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
      user_id, membership_tier, payment_status, experience_level
    )
    VALUES (
      NEW.id,
      'basic',
      'pending',
      'beginner'
    );
  END IF;

  RETURN NEW;
END;
$$;
