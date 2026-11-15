-- ============================================================================
-- TRAINW PHASE 1C — MEMBERSHIP FREEZES (DB-36, P2-3 core)
-- Audit 2026-11-14. Branch: phase1-security-fixes. Local only — NOT applied
-- to any live DB.
--
-- Model (per the audit's P2-3 verification): a freeze PAUSES the
-- membership. While a freeze is active, the gate treats the member as
-- NOT active (they cannot check in). When the freeze ends, the membership
-- end date has moved forward by the frozen days — the member does not
-- lose the days they paid for.
--
-- How it works here:
--   * `membership_freezes` holds one row per freeze (member, gym, start,
--     end, reason, status active/cancelled, created_by).
--   * `membership_is_active_for_access` (B1) is rewritten with the same
--     body plus one clause: no active freeze covering the reference date.
--     Everything that already calls it (gate, manual check-in trigger
--     DB-26, client_membership_is_active) inherits the freeze check.
--   * A trigger extends `client_profiles.membership_end_date` by
--     (end - start) days when a freeze is created, and rolls it back by
--     the same amount when the freeze is cancelled (floored at the
--     membership start date). The extension only applies when the freeze
--     ends today or later; a freeze that already ended is record-keeping
--     only.
--   * Freezes are created/cancelled through the RPCs below (manager-only
--     via manages_gym). Overlapping active freezes for the same member
--     are rejected.
--   * Caveat: the end-date extension is applied at freeze creation, not
--     at freeze end. If a freeze is created far in advance, the end date
--     moves immediately. Cancelling before the freeze starts reverses it
--     exactly. Editing a freeze's dates after creation is not supported
--     — cancel it and create a new one.
--
-- VERIFICATION (no live DB was available when this was written):
--   * Create a freeze for a paid member -> membership_end_date moves
--     forward by the frozen days; membership_is_active_for_access
--     returns false for a date inside the freeze and true after it ends.
--   * Create a second overlapping freeze -> must raise.
--   * Cancel the freeze -> end date rolls back; the member is active
--     again.
--   * A non-manager calling request_membership_freeze -> must raise.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The freezes table.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.membership_freezes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id      uuid NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  start_date  date NOT NULL,
  end_date    date NOT NULL,
  reason      text,
  status      text NOT NULL DEFAULT 'active',
  created_by  uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT membership_freezes_dates_check CHECK (end_date >= start_date),
  CONSTRAINT membership_freezes_status_check CHECK (status IN ('active', 'cancelled'))
);

ALTER TABLE public.membership_freezes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS membership_freezes_select ON public.membership_freezes;
CREATE POLICY membership_freezes_select ON public.membership_freezes
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR public.manages_gym(gym_id)
  );

DROP POLICY IF EXISTS membership_freezes_insert ON public.membership_freezes;
CREATE POLICY membership_freezes_insert ON public.membership_freezes
  FOR INSERT
  WITH CHECK (public.manages_gym(gym_id));

DROP POLICY IF EXISTS membership_freezes_update ON public.membership_freezes;
CREATE POLICY membership_freezes_update ON public.membership_freezes
  FOR UPDATE
  USING (public.manages_gym(gym_id))
  WITH CHECK (public.manages_gym(gym_id));

-- No DELETE policy: freezes are cancelled via status, never deleted.

CREATE INDEX IF NOT EXISTS idx_membership_freezes_member
  ON public.membership_freezes (gym_id, user_id, start_date);

-- ----------------------------------------------------------------------------
-- 1b. Gym-local "today" (Phase 1h chain-order repair, 2026-11-15).
--     The freeze clause below (and the 1g repairs in 20261115190000 /
--     20261115210000) call public.gym_today(p_gym_id), but gym_today is
--     only created in 20261115230000 — so a FRESH chain apply failed on
--     these files (the live DB never saw it: the live apply ran before
--     the 1g edit, and 20261115190000 was applied as a patch afterwards).
--     gyms.timezone exists since the foundation (001), so the helpers
--     can be defined here. Bodies are verbatim copies of the canonical
--     definitions in 20261115230000, which redefines them identically.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.gym_timezone(p_gym_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    NULLIF(BTRIM((SELECT g.timezone FROM public.gyms g WHERE g.id = p_gym_id)), ''),
    'Africa/Tunis'
  );
$$;

CREATE OR REPLACE FUNCTION public.gym_today(p_gym_id uuid)
RETURNS date
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT (now() AT TIME ZONE public.gym_timezone(p_gym_id))::date;
$$;

-- ----------------------------------------------------------------------------
-- 2. Gate check: a frozen membership is not active (DB-36 / P2-3).
--    Body kept verbatim from 20261115010000 (B1) plus the freeze clause.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.membership_is_active_for_access(
  p_client_id uuid,
  p_gym_id uuid,
  p_reference_date date DEFAULT CURRENT_DATE
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.client_profiles cp
    JOIN public.users u
      ON u.id = cp.user_id
    WHERE cp.user_id = p_client_id
      AND cp.gym_id = p_gym_id
      AND u.role = 'client'
      AND COALESCE(u.is_active, true)
      AND (
        cp.payment_status IN ('paid', 'trial', 'waived')
        OR (
          cp.price_paid > 0
          AND cp.payment_status NOT IN ('cancelled', 'refunded', 'overdue')
        )
      )
      AND (
        cp.membership_start_date IS NULL
        OR cp.membership_start_date <= p_reference_date
      )
      AND (
        cp.membership_end_date IS NULL
        OR cp.membership_end_date >= p_reference_date
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.membership_freezes f
        WHERE f.user_id = p_client_id
          AND f.gym_id = p_gym_id
          AND f.status = 'active'
          AND COALESCE(p_reference_date, public.gym_today(p_gym_id)) BETWEEN f.start_date AND f.end_date
      )
  );
$$;

-- ----------------------------------------------------------------------------
-- 3. End-date shift trigger: extend on freeze, roll back on cancel.
--    SECURITY DEFINER so it runs as the function owner (same pattern as
--    the settlement trigger; avoids the P1-1 self-update guard).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.shift_membership_for_freeze()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days integer;
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'active' AND NEW.end_date >= CURRENT_DATE THEN
    v_days := NEW.end_date - NEW.start_date;
    IF v_days > 0 THEN
      UPDATE public.client_profiles
      SET membership_end_date = (
            CASE WHEN membership_end_date IS NULL THEN NULL
                 ELSE (membership_end_date + v_days)::date END),
          updated_at = now()
      WHERE user_id = NEW.user_id AND gym_id = NEW.gym_id;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
    AND OLD.status = 'active'
    AND NEW.status = 'cancelled'
    AND OLD.end_date >= CURRENT_DATE THEN
    v_days := OLD.end_date - OLD.start_date;
    IF v_days > 0 THEN
      UPDATE public.client_profiles
      SET membership_end_date = (
            CASE WHEN membership_end_date IS NULL THEN NULL
                 ELSE GREATEST(
                   COALESCE(membership_start_date, CURRENT_DATE),
                   (membership_end_date - v_days)::date
                 ) END),
          updated_at = now()
      WHERE user_id = NEW.user_id AND gym_id = NEW.gym_id;
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_freeze_shift_membership ON public.membership_freezes;
CREATE TRIGGER trg_freeze_shift_membership
  AFTER INSERT OR UPDATE ON public.membership_freezes
  FOR EACH ROW EXECUTE FUNCTION public.shift_membership_for_freeze();

-- ----------------------------------------------------------------------------
-- 4. Freeze RPCs (manager-only).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.request_membership_freeze(
  p_user_id uuid,
  p_gym_id uuid,
  p_start_date date,
  p_end_date date,
  p_reason text DEFAULT NULL
)
RETURNS public.membership_freezes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.membership_freezes%ROWTYPE;
BEGIN
  IF NOT public.manages_gym(p_gym_id) THEN
    RAISE EXCEPTION 'not authorized: only a manager of this gym can freeze a membership';
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL THEN
    RAISE EXCEPTION 'freeze start and end dates are required';
  END IF;
  IF p_end_date < p_start_date THEN
    RAISE EXCEPTION 'freeze end date must be on or after the start date';
  END IF;
  IF p_end_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'freeze end date must be today or later';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.client_profiles cp
    WHERE cp.user_id = p_user_id AND cp.gym_id = p_gym_id
  ) THEN
    RAISE EXCEPTION 'member has no profile in this gym';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.membership_freezes f
    WHERE f.user_id = p_user_id
      AND f.gym_id = p_gym_id
      AND f.status = 'active'
      AND f.start_date <= p_end_date
      AND f.end_date >= p_start_date
  ) THEN
    RAISE EXCEPTION 'member already has an active freeze overlapping these dates';
  END IF;

  INSERT INTO public.membership_freezes (
    gym_id, user_id, start_date, end_date, reason, status, created_by
  ) VALUES (
    p_gym_id, p_user_id, p_start_date, p_end_date,
    NULLIF(BTRIM(p_reason), ''), 'active', auth.uid()
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_membership_freeze(
  p_freeze_id uuid
)
RETURNS public.membership_freezes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.membership_freezes%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public.membership_freezes WHERE id = p_freeze_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'freeze not found';
  END IF;
  IF NOT public.manages_gym(v_row.gym_id) THEN
    RAISE EXCEPTION 'not authorized: only a manager of this gym can cancel a freeze';
  END IF;
  IF v_row.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'only an active freeze can be cancelled';
  END IF;

  UPDATE public.membership_freezes
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_freeze_id
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.request_membership_freeze(uuid, uuid, date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_membership_freeze(uuid, uuid, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.cancel_membership_freeze(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_membership_freeze(uuid) TO authenticated;
