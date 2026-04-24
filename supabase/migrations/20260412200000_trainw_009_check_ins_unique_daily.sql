-- 1. Add a deterministic date column (force UTC)
ALTER TABLE public.check_ins
ADD COLUMN IF NOT EXISTS checked_in_date date
GENERATED ALWAYS AS ((checked_in_at AT TIME ZONE 'UTC')::date) STORED;

-- 2. Remove duplicates (keep earliest per day)
WITH ranked_check_ins AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY gym_id, client_id, checked_in_date
      ORDER BY checked_in_at ASC, id ASC
    ) AS row_num
  FROM public.check_ins
)
DELETE FROM public.check_ins ci
USING ranked_check_ins ranked
WHERE ci.id = ranked.id
  AND ranked.row_num > 1;

-- 3. Create unique index
CREATE UNIQUE INDEX IF NOT EXISTS uq_check_ins_gym_client_day
ON public.check_ins (gym_id, client_id, checked_in_date);