-- ============================================================================
-- Phase 2, P2-8 (NX-16) — the DB CHECK on capacity exists only for sessions,
-- not for classes (audit finding, confirmed by round 6). A class created
-- with capacity -5 sailed through: the HTML input has min="1" but a typed
-- value bypasses it, and nothing else stopped it.
--
-- Live data is clean (checked 2026-11-15 before writing this: 1 gym_class,
-- capacity 20; 0 rows with capacity NULL or < 1), so the CHECK is added
-- validated in one step — no NOT VALID dance needed. The client-side
-- >= 1 check in saveGymClass (tw-gym-acc.js) is the readable front door;
-- this is the backstop.
-- ============================================================================

ALTER TABLE public.gym_classes
  ADD CONSTRAINT gym_classes_capacity_check CHECK (capacity > 0);

-- Prove the new CHECK is validated (DB-35 stays green).
SELECT public.assert_no_unvalidated_constraints();
