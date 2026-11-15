-- ============================================================================
-- Round 5 (DB-37 follow-up) — get_bookable_slots filters past slots in
-- the gym's timezone, not UTC.
--
-- Slots are generated as naive `p_session_date + start_time` (wall time
-- in the gym's zone) but were filtered with `rs.slot_start_ts > now()`
-- — now() is UTC on the server. Near midnight the filter was wrong: a
-- 09:00 Tunis slot still showed bookable at 08:30 UTC (09:30 Tunis).
-- The fix carries gym_tz (public.gym_timezone of the window's gym)
-- through the windows/raw_slots CTEs and compares against the current
-- wall time in the gym's zone: `rs.slot_start_ts > (now() AT TIME
-- ZONE rs.gym_tz)` — timestamp > timestamp, both naive wall time in
-- the gym's zone.
--
-- The overlap check is NOT touched: session_time_range is naive on
-- both sides and internally consistent.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_bookable_slots(
  p_coach_id uuid,
  p_session_date date
)
RETURNS TABLE (
  slot_time text,
  slot_end_time text,
  slot_minutes integer,
  price_per_session numeric
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH coach_data AS (
    SELECT
      u.id AS coach_id,
      COALESCE(cp.gym_id, u.gym_id) AS gym_id,
      cp.approval_status,
      cp.is_active,
      COALESCE(cp.price_per_session, cp.hourly_rate, 0) AS price_per_session
    FROM public.users u
    JOIN public.coach_profiles cp
      ON cp.user_id = u.id
    WHERE u.id = p_coach_id
      AND u.role = 'coach'
  ),
  windows AS (
    SELECT
      ca.start_time,
      ca.end_time,
      ca.slot_minutes,
      cd.price_per_session,
      -- The gym's IANA timezone: slot timestamps below are naive wall
      -- times in this zone, so the past-filter must compare against
      -- the current wall time in the same zone (see the WHERE clause).
      public.gym_timezone(COALESCE(ca.gym_id, cd.gym_id)) AS gym_tz
    FROM public.coach_availability ca
    JOIN coach_data cd
      ON TRUE
    WHERE p_session_date IS NOT NULL
      AND p_session_date >= public.gym_today(public.get_my_gym_id())
      AND ca.coach_id = p_coach_id
      AND ca.is_active = true
      AND cd.approval_status = 'approved'
      AND cd.is_active = true
      AND COALESCE(ca.gym_id, cd.gym_id) = public.get_my_gym_id()
      AND ca.day_of_week = EXTRACT(DOW FROM p_session_date)::integer
      AND (ca.valid_from IS NULL OR p_session_date >= ca.valid_from)
      AND (ca.valid_until IS NULL OR p_session_date <= ca.valid_until)
  ),
  raw_slots AS (
    SELECT
      gs.slot_start_ts,
      (gs.slot_start_ts + make_interval(mins => w.slot_minutes)) AS slot_end_ts,
      w.slot_minutes,
      w.price_per_session,
      w.gym_tz
    FROM windows w
    CROSS JOIN LATERAL generate_series(
      p_session_date + w.start_time,
      p_session_date + w.end_time - make_interval(mins => w.slot_minutes),
      make_interval(mins => w.slot_minutes)
    ) AS gs(slot_start_ts)
  )
  SELECT
    to_char(rs.slot_start_ts, 'HH24:MI') AS slot_time,
    to_char(rs.slot_end_ts, 'HH24:MI') AS slot_end_time,
    rs.slot_minutes,
    rs.price_per_session
  FROM raw_slots rs
  -- Was `rs.slot_start_ts > now()`: now() is UTC on the server, but the
  -- slot timestamps are naive wall times in the gym's zone — near
  -- midnight a slot could show bookable after it had already passed in
  -- the gym's zone (e.g. 09:00 Tunis still listed at 08:30 UTC = 09:30
  -- Tunis). Compare against the current wall time in the gym's zone.
  WHERE rs.slot_start_ts > (now() AT TIME ZONE rs.gym_tz)
    AND NOT EXISTS (
      SELECT 1
      FROM public.sessions s
      WHERE s.coach_id = p_coach_id
        AND s.session_date = p_session_date
        AND COALESCE(s.status, 'pending') IN ('pending', 'confirmed')
        AND public.session_time_range(
              s.session_date,
              s.start_time,
              s.end_time,
              s.duration_minutes
            ) && tsrange(rs.slot_start_ts, rs.slot_end_ts, '[)')
    )
  ORDER BY rs.slot_start_ts;
$$;
