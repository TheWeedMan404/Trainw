-- Round 6 (audit closure) — DB-56, second half.
--
-- The audit asked for a dedup unique index on personal_records
-- (client_id, exercise_name, achieved_at). Round 2 added only the
-- value > 0 CHECK and the owner-only UPDATE policies; the index that
-- shipped (idx_personal_records_client_exercise_achieved_at) is
-- NON-unique, so the same personal record could still be inserted
-- twice. Add the unique index. achieved_at is timestamptz, so two
-- genuine records at different moments stay distinct.
--
-- Defensive dedup first: drop exact duplicates (keep the newest row)
-- so the index builds even on a database that already holds dupes.
DO $$
BEGIN
  DELETE FROM public.personal_records pr
  WHERE pr.id IN (
    SELECT id FROM (
      SELECT id, ROW_NUMBER() OVER (
        PARTITION BY client_id, exercise_name, achieved_at
        ORDER BY created_at DESC NULLS LAST, id DESC
      ) AS rn
      FROM public.personal_records
    ) ranked WHERE rn > 1
  );
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_personal_records_client_exercise_achieved
  ON public.personal_records (client_id, exercise_name, achieved_at);
