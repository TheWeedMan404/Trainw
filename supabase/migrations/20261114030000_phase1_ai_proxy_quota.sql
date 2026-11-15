-- P1-7 (GT-01): per-user daily quota for the ai-proxy edge function.
--
-- The ai-proxy function calls trainw_ai_proxy_consume_quota() once per request,
-- before spending any Anthropic tokens. The function derives the caller from
-- auth.uid() (never from a caller-supplied id), so a user can only ever burn
-- their own quota. The counter only increments while under the limit, so a
-- rejected over-limit attempt does not inflate the count.
--
-- RLS is enabled on ai_proxy_usage with NO policies: nobody can read or write
-- the table directly (not even their own rows). Only this SECURITY DEFINER
-- function touches it.

CREATE TABLE IF NOT EXISTS public.ai_proxy_usage (
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  day date NOT NULL DEFAULT CURRENT_DATE,
  calls integer NOT NULL DEFAULT 0 CHECK (calls >= 0),
  PRIMARY KEY (user_id, day)
);

ALTER TABLE public.ai_proxy_usage ENABLE ROW LEVEL SECURITY;

-- No policies on purpose: the table is only reachable through the
-- SECURITY DEFINER function below. Direct SELECT/INSERT/UPDATE/DELETE by
-- authenticated users is denied by default when RLS is enabled with no policy.

CREATE OR REPLACE FUNCTION public.trainw_ai_proxy_consume_quota(p_limit integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_calls integer;
BEGIN
  -- No JWT (or an unresolvable caller) can never consume quota.
  IF v_user IS NULL THEN
    RETURN false;
  END IF;

  IF p_limit IS NULL OR p_limit < 1 THEN
    RETURN false;
  END IF;

  -- First call of the day inserts the row (calls = 1). Later calls bump the
  -- counter only while still under the limit; when already at the limit the
  -- UPDATE matches no row and RETURNING yields NULL, so the call is refused
  -- without inflating the counter.
  INSERT INTO public.ai_proxy_usage (user_id, day, calls)
  VALUES (v_user, CURRENT_DATE, 1)
  ON CONFLICT (user_id, day)
  DO UPDATE SET calls = ai_proxy_usage.calls + 1
    WHERE ai_proxy_usage.calls < p_limit
  RETURNING calls INTO v_calls;

  RETURN v_calls IS NOT NULL AND v_calls <= p_limit;
END;
$$;

-- Only signed-in callers may execute the quota function. (anon has no JWT, so
-- auth.uid() is NULL inside the function and it returns false anyway.)
REVOKE ALL ON FUNCTION public.trainw_ai_proxy_consume_quota(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trainw_ai_proxy_consume_quota(integer) TO authenticated;
