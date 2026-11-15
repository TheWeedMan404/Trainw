-- P1-12 (GT-03): per-IP + per-device rate limiting for the gate-checkin edge
-- function.
--
-- The gate-checkin handler calls trainw_gate_rate_limit_consume() once per
-- request, before any token/credential lookup, with two buckets:
--   'ip:<client ip>'      — 60 requests/minute (see handler.mjs)
--   'device:<device_id>'  — 30 requests/minute (only when the payload carries
--                            a device_id; the gate terminal always sends one)
-- The counter only increments while under the limit, so a rejected over-limit
-- attempt does not inflate the count. Windows are fixed calendar minutes
-- (date_trunc('minute', now())), so a burst at a minute boundary can briefly
-- exceed the limit — acceptable for a gate terminal; the token itself is
-- 96-bit, single-use, and short-lived, so the limiter is defence-in-depth
-- against hammering the database, not the sole brute-force control.
--
-- RLS is enabled on gate_rate_limits with NO policies: nobody can read or
-- write the table directly. Only this SECURITY DEFINER function touches it.
-- The handler calls it with the service-role client.
--
-- Housekeeping: each bucket key keeps at most one row (stale windows for the
-- same key are deleted by the function). Rows for keys that stop appearing
-- linger; purge them occasionally:
--   DELETE FROM public.gate_rate_limits
--   WHERE window_start < now() - interval '1 day';

CREATE TABLE IF NOT EXISTS public.gate_rate_limits (
  bucket_key text NOT NULL,
  window_start timestamptz NOT NULL,
  hits integer NOT NULL DEFAULT 0 CHECK (hits >= 0),
  PRIMARY KEY (bucket_key, window_start)
);

ALTER TABLE public.gate_rate_limits ENABLE ROW LEVEL SECURITY;

-- No policies on purpose: the table is only reachable through the
-- SECURITY DEFINER function below. Direct access is denied by default when
-- RLS is enabled with no policy.

CREATE OR REPLACE FUNCTION public.trainw_gate_rate_limit_consume(
  p_bucket_key text,
  p_limit integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window_start timestamptz := date_trunc('minute', now());
  v_hits integer;
BEGIN
  IF p_bucket_key IS NULL OR p_bucket_key = '' OR p_limit IS NULL OR p_limit < 1 THEN
    RETURN false;
  END IF;

  -- Keep at most one row per bucket key: drop this key's previous windows.
  DELETE FROM public.gate_rate_limits
  WHERE bucket_key = p_bucket_key
    AND window_start < v_window_start;

  -- First hit of the window inserts the row (hits = 1). Later hits bump the
  -- counter only while still under the limit; when already at the limit the
  -- UPDATE matches no row and RETURNING yields NULL, so the request is
  -- refused without inflating the counter.
  INSERT INTO public.gate_rate_limits (bucket_key, window_start, hits)
  VALUES (p_bucket_key, v_window_start, 1)
  ON CONFLICT (bucket_key, window_start)
  DO UPDATE SET hits = gate_rate_limits.hits + 1
    WHERE gate_rate_limits.hits < p_limit
  RETURNING hits INTO v_hits;

  RETURN v_hits IS NOT NULL AND v_hits <= p_limit;
END;
$$;

-- Only the service-role client (the gate-checkin handler) may execute it.
REVOKE ALL ON FUNCTION public.trainw_gate_rate_limit_consume(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trainw_gate_rate_limit_consume(text, integer) TO service_role;
