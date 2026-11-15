-- ============================================================================
-- data-repair-audit.sql — DB-50 dry-run (READ-ONLY, changes nothing).
--
-- Reports what the historical data repairs (migrations 003 and 004) would
-- touch if they ran today, plus the signup-gap check from DB-62:
--   A. every FK orphan in schema public (generic — covers all of 004's
--      orphan DELETEs without transcribing their 32 predicates);
--   B. duplicate availability windows (003, normalized_availability);
--   C. conflicting (overlapping) availability windows (003);
--   D. conflicting sessions (003);
--   E. auth.users rows with no public.users row (DB-62 signup gap).
--
-- Usage:  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/data-repair-audit.sql
-- Exit 0 when nothing needs repair; exits non-zero (after printing the
-- full report) when any rule finds rows. See docs/DATA_REPAIR_RUNBOOK.md
-- for what to do with a non-zero result — never repair from a migration.
-- ============================================================================

CREATE TEMP TABLE IF NOT EXISTS db50_findings (
  rule text PRIMARY KEY,
  affected_rows bigint NOT NULL
);
TRUNCATE db50_findings;

-- ---------------------------------------------------------------------------
-- A. Generic FK orphan audit: every foreign key in schema public.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  c record;
  i int;
  v_tbl text;
  v_ref text;
  v_cols text := '';
  v_cond text := '';
  v_notnull text := '';
  v_sql text;
  v_count bigint;
BEGIN
  FOR c IN
    SELECT conrelid, confrelid, conkey, confkey, conname
    FROM pg_constraint
    WHERE contype = 'f'
      AND connamespace = 'public'::regnamespace
    ORDER BY conrelid::regclass::text, conname
  LOOP
    v_tbl := c.conrelid::regclass::text;
    v_ref := c.confrelid::regclass::text;
    v_cols := '';
    v_cond := '';
    v_notnull := '';
    FOR i IN 1 .. array_length(c.conkey, 1) LOOP
      IF i > 1 THEN
        v_cols := v_cols || ',';
        v_cond := v_cond || ' AND ';
        v_notnull := v_notnull || ' AND ';
      END IF;
      v_cols := v_cols || (SELECT attname FROM pg_attribute WHERE attrelid = c.conrelid AND attnum = c.conkey[i]);
      v_cond := v_cond || format('r.%I = t.%I',
        (SELECT attname FROM pg_attribute WHERE attrelid = c.confrelid AND attnum = c.confkey[i]),
        (SELECT attname FROM pg_attribute WHERE attrelid = c.conrelid AND attnum = c.conkey[i]));
      v_notnull := v_notnull || format('t.%I IS NOT NULL',
        (SELECT attname FROM pg_attribute WHERE attrelid = c.conrelid AND attnum = c.conkey[i]));
    END LOOP;
    v_sql := format('SELECT count(*) FROM %s t WHERE (%s) AND NOT EXISTS (SELECT 1 FROM %s r WHERE %s)',
      v_tbl, v_notnull, v_ref, v_cond);
    EXECUTE v_sql INTO v_count;
    IF v_count > 0 THEN
      INSERT INTO db50_findings (rule, affected_rows)
      VALUES (format('orphan:%s.%s->%s', v_tbl, v_cols, v_ref), v_count);
      RAISE NOTICE 'ORPHAN % -> % (%): % rows', v_tbl, v_ref, v_cols, v_count;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- B. Duplicate availability windows (003: same coach/gym/day/window twice).
-- ---------------------------------------------------------------------------
INSERT INTO db50_findings (rule, affected_rows)
WITH normalized_availability AS (
  SELECT
    ca.id,
    ca.is_active,
    ROW_NUMBER() OVER (
      PARTITION BY ca.coach_id,
                   COALESCE(ca.gym_id, u.gym_id),
                   ca.day_of_week,
                   COALESCE(ca.valid_from, '-infinity'::date),
                   COALESCE(ca.valid_until, 'infinity'::date),
                   ca.start_time,
                   ca.end_time
      ORDER BY ca.created_at ASC, ca.id ASC
    ) AS rn
  FROM public.coach_availability ca
  LEFT JOIN public.users u
    ON u.id = ca.coach_id
)
SELECT 'duplicate_availability', count(*)
FROM normalized_availability
WHERE rn > 1 AND is_active = true;

-- ---------------------------------------------------------------------------
-- C. Conflicting availability windows (003: overlapping times, same coach).
-- ---------------------------------------------------------------------------
INSERT INTO db50_findings (rule, affected_rows)
WITH conflicting_availability AS (
  SELECT DISTINCT later.id
  FROM public.coach_availability earlier
  JOIN public.coach_availability later
    ON later.id <> earlier.id
   AND later.coach_id = earlier.coach_id
   AND COALESCE(later.gym_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = COALESCE(earlier.gym_id, '00000000-0000-0000-0000-000000000000'::uuid)
   AND later.day_of_week = earlier.day_of_week
   AND later.is_active = true
   AND earlier.is_active = true
   AND daterange(
         COALESCE(later.valid_from, '-infinity'::date),
         COALESCE(later.valid_until + 1, 'infinity'::date),
         '[)'
       ) && daterange(
         COALESCE(earlier.valid_from, '-infinity'::date),
         COALESCE(earlier.valid_until + 1, 'infinity'::date),
         '[)'
       )
   AND later.start_time IS NOT NULL
   AND later.end_time IS NOT NULL
   AND earlier.start_time IS NOT NULL
   AND earlier.end_time IS NOT NULL
   AND later.start_time < earlier.end_time
   AND earlier.start_time < later.end_time
   AND (
     COALESCE(later.created_at, now()) > COALESCE(earlier.created_at, now())
     OR (
       COALESCE(later.created_at, now()) = COALESCE(earlier.created_at, now())
       AND later.id > earlier.id
     )
   )
)
SELECT 'conflicting_availability', count(*) FROM conflicting_availability;

-- ---------------------------------------------------------------------------
-- D. Conflicting sessions (003: same coach or client, same date, overlap).
-- ---------------------------------------------------------------------------
INSERT INTO db50_findings (rule, affected_rows)
WITH conflicting_sessions AS (
  SELECT DISTINCT later.id
  FROM public.sessions earlier
  JOIN public.sessions later
    ON later.id <> earlier.id
   AND later.session_date = earlier.session_date
   AND COALESCE(later.status, 'pending') IN ('pending', 'confirmed')
   AND COALESCE(earlier.status, 'pending') IN ('pending', 'confirmed')
   AND (
     (
       later.coach_id IS NOT NULL
       AND later.coach_id = earlier.coach_id
     )
     OR (
       later.client_id IS NOT NULL
       AND later.client_id = earlier.client_id
     )
   )
   AND later.start_time IS NOT NULL
   AND earlier.start_time IS NOT NULL
   AND COALESCE(later.end_time, (later.start_time + make_interval(mins => COALESCE(later.duration_minutes, 60)))::time)
       > earlier.start_time
   AND COALESCE(earlier.end_time, (earlier.start_time + make_interval(mins => COALESCE(earlier.duration_minutes, 60)))::time)
       > later.start_time
   AND (
     COALESCE(later.confirmed_at, later.booked_at, later.created_at, now())
       > COALESCE(earlier.confirmed_at, earlier.booked_at, earlier.created_at, now())
     OR (
       COALESCE(later.confirmed_at, later.booked_at, later.created_at, now())
         = COALESCE(earlier.confirmed_at, earlier.booked_at, earlier.created_at, now())
       AND later.id > earlier.id
     )
   )
)
SELECT 'conflicting_sessions', count(*) FROM conflicting_sessions;

-- ---------------------------------------------------------------------------
-- E. Signup gap (DB-62): auth user with no public.users row.
-- ---------------------------------------------------------------------------
INSERT INTO db50_findings (rule, affected_rows)
SELECT 'auth_users_without_public_users', count(*)
FROM auth.users au
WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = au.id);

-- ---------------------------------------------------------------------------
-- Report + exit code.
-- ---------------------------------------------------------------------------
SELECT rule, affected_rows FROM db50_findings ORDER BY rule;

DO $$
DECLARE
  v_total bigint;
  v_rules bigint;
BEGIN
  SELECT COALESCE(sum(affected_rows), 0), count(*) INTO v_total, v_rules FROM db50_findings;
  IF v_total > 0 THEN
    RAISE EXCEPTION 'data repair needed: % rows across % rules — see docs/DATA_REPAIR_RUNBOOK.md (this script changes nothing)', v_total, v_rules;
  END IF;
  RAISE NOTICE 'data-repair audit clean: no rows to repair';
END $$;
