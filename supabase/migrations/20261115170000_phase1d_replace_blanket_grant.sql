-- ============================================================================
-- Round 4 (DB-41) — replace the blanket authenticated grant with
-- per-table grants derived from the RLS policies.
--
-- Migration 004 has:
--   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
--   TO authenticated;
-- That grant covers every current AND FUTURE table, so any table created
-- without RLS, or any policy gap, is immediately writable by every
-- authenticated user. It is the standing enabler for the
-- privilege-escalation paths (DB-03/DB-04).
--
-- This migration:
--   1. Revokes the blanket grant (including the explicit per-table
--      grants earlier migrations added on top of it — they are all
--      re-derived below, so nothing is lost).
--   2. Grants each public table exactly the operations its RLS policies
--      allow for the authenticated role (a policy with cmd ALL counts
--      for all four; a policy restricted to service_role does not count).
--      A table with RLS but no applicable policy gets NO grant — which
--      changes nothing behaviourally (RLS already denied every row) and
--      is the whole point: a future table without RLS is not writable.
--      Tables with no policies at all (ai_proxy_usage, gate_rate_limits,
--      gate_terminal_sessions) are service_role-only by design and keep
--      no grant.
--   3. Adds public.assert_all_tables_have_rls() and calls it: the
--      migration-time check that every public table has RLS enabled.
--
-- Behaviour is preserved by construction: a grant without a matching
-- policy is useless under RLS, and a policy without a grant is
-- unreachable — so granting exactly the policy operations changes no
-- legitimate flow. Verified behaviourally in the round-4 suite (a
-- manager payment insert as the authenticated role still settles).
--
-- Convention from here on (see the runbook): a migration that creates a
-- table MUST also grant it explicitly, matching its policies, and call
-- assert_all_tables_have_rls().
-- ============================================================================

-- 1. Revoke the blanket grant.
REVOKE SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM authenticated;

-- 2. Re-grant per table, per operation, from the policies that apply to
--    the authenticated role (polroles empty = PUBLIC = every role).
DO $$
DECLARE
  r record;
  v_privs text[];
  v_sql text;
BEGIN
  FOR r IN
    SELECT c.oid, c.relname AS tbl,
           COALESCE(bool_or(p.polcmd = '*'), false) AS has_all,
           COALESCE(bool_or(p.polcmd = 'r'), false) AS has_select,
           COALESCE(bool_or(p.polcmd = 'a'), false) AS has_insert,
           COALESCE(bool_or(p.polcmd = 'w'), false) AS has_update,
           COALESCE(bool_or(p.polcmd = 'd'), false) AS has_delete
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_policy p
      ON p.polrelid = c.oid
     AND (
       -- polroles = {0} means PUBLIC (the policy applies to every role);
       -- otherwise the policy must name the authenticated role.
       p.polroles::oid[] = '{0}'::oid[]
       OR 'authenticated'::regrole::oid = ANY (p.polroles::oid[])
     )
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
    GROUP BY c.oid, c.relname
    ORDER BY c.relname
  LOOP
    v_privs := ARRAY[]::text[];
    IF r.has_all OR r.has_select THEN v_privs := array_append(v_privs, 'SELECT'); END IF;
    IF r.has_all OR r.has_insert THEN v_privs := array_append(v_privs, 'INSERT'); END IF;
    IF r.has_all OR r.has_update THEN v_privs := array_append(v_privs, 'UPDATE'); END IF;
    IF r.has_all OR r.has_delete THEN v_privs := array_append(v_privs, 'DELETE'); END IF;
    IF array_length(v_privs, 1) IS NOT NULL THEN
      v_sql := format('GRANT %s ON TABLE public.%I TO authenticated',
                      array_to_string(v_privs, ', '), r.tbl);
      RAISE NOTICE 'DB-41 %', v_sql;
      EXECUTE v_sql;
    ELSE
      RAISE NOTICE 'DB-41 no grant for % (no authenticated policy; service_role-only)', r.tbl;
    END IF;
  END LOOP;
END $$;

-- 3. Migration-time check: every public table must have RLS enabled.
CREATE OR REPLACE FUNCTION public.assert_all_tables_have_rls()
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY 1)
  INTO v_bad
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND NOT c.relrowsecurity;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'tables without RLS enabled: %', v_bad;
  END IF;
END $$;

SELECT public.assert_all_tables_have_rls();

COMMENT ON FUNCTION public.assert_all_tables_have_rls() IS
  'DB-41: fails when any public table lacks RLS. Call after applying migrations that create tables.';
