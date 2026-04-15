WITH ranked_check_ins AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY gym_id, client_id, date(checked_in_at)
      ORDER BY checked_in_at ASC, id ASC
    ) AS row_num
  FROM public.check_ins
)
DELETE FROM public.check_ins ci
USING ranked_check_ins ranked
WHERE ci.id = ranked.id
  AND ranked.row_num > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_check_ins_gym_client_day
ON public.check_ins (gym_id, client_id, (date(checked_in_at)));
