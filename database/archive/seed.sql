DO $$
DECLARE
  v_gym_id uuid;
  v_group_class_id uuid;
  v_private_class_id uuid;
  v_group_coach_id uuid;
  v_private_coach_id uuid;
  v_client_a uuid;
  v_client_b uuid;
  v_client_c uuid;
BEGIN
  -- DB-63: the gym must be named explicitly (trainw.seed_gym_id), and the
  -- script refuses to run when more than one gym exists — never pick the
  -- oldest gym with ORDER BY created_at LIMIT 1. Set it first, in the
  -- same SQL Editor session:
  --   SELECT set_config('trainw.seed_gym_id', '<gym uuid>', false);
  v_gym_id := NULLIF(BTRIM(current_setting('trainw.seed_gym_id', true)), '')::uuid;
  IF v_gym_id IS NULL THEN
    IF (SELECT count(*) FROM public.gyms) = 1 THEN
      SELECT id INTO v_gym_id FROM public.gyms;
    ELSE
      RAISE EXCEPTION 'Set the target gym first: SELECT set_config(''trainw.seed_gym_id'', ''<gym uuid>'', false); then re-run database/archive/seed.sql.';
    END IF;
  END IF;

  IF (SELECT count(*) FROM public.gyms) > 1 THEN
    RAISE EXCEPTION 'Refusing: more than one gym exists in this database. This seed script only runs on a single-gym database.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.gyms WHERE id = v_gym_id) THEN
    RAISE EXCEPTION 'Gym % does not exist.', v_gym_id;
  END IF;

  INSERT INTO public.coaches (gym_id, name, rating)
  SELECT v_gym_id, 'Nadia Ben Salem', 4.9
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.coaches
    WHERE gym_id = v_gym_id
      AND name = 'Nadia Ben Salem'
  );

  INSERT INTO public.coaches (gym_id, name, rating)
  SELECT v_gym_id, 'Youssef Trabelsi', 4.7
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.coaches
    WHERE gym_id = v_gym_id
      AND name = 'Youssef Trabelsi'
  );

  SELECT id INTO v_group_coach_id
  FROM public.coaches
  WHERE gym_id = v_gym_id
    AND name = 'Nadia Ben Salem'
  LIMIT 1;

  SELECT id INTO v_private_coach_id
  FROM public.coaches
  WHERE gym_id = v_gym_id
    AND name = 'Youssef Trabelsi'
  LIMIT 1;

  INSERT INTO public.clients (gym_id, name, type)
  SELECT v_gym_id, 'Leila Mansour', 'gym'
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.clients
    WHERE gym_id = v_gym_id
      AND name = 'Leila Mansour'
      AND type = 'gym'
  );

  INSERT INTO public.clients (gym_id, name, type)
  SELECT v_gym_id, 'Karim Jaziri', 'gym'
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.clients
    WHERE gym_id = v_gym_id
      AND name = 'Karim Jaziri'
      AND type = 'gym'
  );

  INSERT INTO public.clients (gym_id, name, type)
  SELECT v_gym_id, 'Sana Triki', 'individual'
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.clients
    WHERE gym_id = v_gym_id
      AND name = 'Sana Triki'
      AND type = 'individual'
  );

  SELECT id INTO v_client_a
  FROM public.clients
  WHERE gym_id = v_gym_id
    AND name = 'Leila Mansour'
  LIMIT 1;

  SELECT id INTO v_client_b
  FROM public.clients
  WHERE gym_id = v_gym_id
    AND name = 'Karim Jaziri'
  LIMIT 1;

  SELECT id INTO v_client_c
  FROM public.clients
  WHERE gym_id = v_gym_id
    AND name = 'Sana Triki'
  LIMIT 1;

  INSERT INTO public.classes (gym_id, name, coach_id, type, capacity)
  SELECT v_gym_id, 'Morning Strength', v_group_coach_id, 'group', 12
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.classes
    WHERE gym_id = v_gym_id
      AND name = 'Morning Strength'
  );

  INSERT INTO public.classes (gym_id, name, coach_id, type, capacity)
  SELECT v_gym_id, 'Private Performance', v_private_coach_id, 'private', 1
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.classes
    WHERE gym_id = v_gym_id
      AND name = 'Private Performance'
  );

  SELECT id INTO v_group_class_id
  FROM public.classes
  WHERE gym_id = v_gym_id
    AND name = 'Morning Strength'
  LIMIT 1;

  SELECT id INTO v_private_class_id
  FROM public.classes
  WHERE gym_id = v_gym_id
    AND name = 'Private Performance'
  LIMIT 1;

  INSERT INTO public.class_clients (class_id, client_id)
  VALUES
    (v_group_class_id, v_client_a),
    (v_group_class_id, v_client_b),
    (v_private_class_id, v_client_c)
  ON CONFLICT (class_id, client_id) DO NOTHING;

  INSERT INTO public.attendance (gym_id, client_id, class_id, status, "timestamp")
  SELECT
    v_gym_id,
    v_client_a,
    v_group_class_id,
    'checked_in',
    date_trunc('minute', now() - interval '2 hours')
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.attendance
    WHERE gym_id = v_gym_id
      AND client_id = v_client_a
      AND class_id = v_group_class_id
      AND status = 'checked_in'
      AND "timestamp"::date = current_date
  );

  INSERT INTO public.attendance (gym_id, client_id, class_id, status, "timestamp")
  SELECT
    v_gym_id,
    v_client_b,
    v_group_class_id,
    'late',
    date_trunc('minute', now() - interval '90 minutes')
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.attendance
    WHERE gym_id = v_gym_id
      AND client_id = v_client_b
      AND class_id = v_group_class_id
      AND status = 'late'
      AND "timestamp"::date = current_date
  );

  INSERT INTO public.attendance (gym_id, client_id, class_id, status, "timestamp")
  SELECT
    v_gym_id,
    v_client_c,
    v_private_class_id,
    'checked_in',
    date_trunc('minute', now() - interval '45 minutes')
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.attendance
    WHERE gym_id = v_gym_id
      AND client_id = v_client_c
      AND class_id = v_private_class_id
      AND status = 'checked_in'
      AND "timestamp"::date = current_date
  );
END $$;

