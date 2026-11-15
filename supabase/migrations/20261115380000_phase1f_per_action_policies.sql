-- Round 6 (audit closure) — DB-16, per-action permission checks.
--
-- The round-6 verification suite proved the round-1 fix was incomplete
-- in practice: manages_gym() returns true for ANY role in the admin
-- portal, so a user holding only manage_branding (in an admin-portal
-- custom role) could still INSERT a payment — the audit's own P1-10
-- verification criterion ("a branding-only user cannot insert a
-- payment") failed. The policies below still required manages_gym, but
-- never the permission for the action itself.
--
-- Fix (the audit's recommended fix, applied to the four sensitive write
-- surfaces it named): each policy now ALSO requires the specific
-- permission — manage_payments for money, manage_access_control for
-- gate credentials and devices, manage_checkins for deleting check-ins.
-- This is strictly a tightening: nobody who could write before gains
-- anything; the gym_owner and gym_admin roles hold all four
-- permissions, so manager flows are unchanged.
--
-- BEHAVIOUR CHANGE: the default `staff` role holds none of
-- manage_payments / manage_access_control, so front-desk staff can no
-- longer record payments or enrol gate credentials/devices. That is the
-- secure default the audit asks for; an owner can grant those
-- permissions to the staff role from the roles UI if reception is meant
-- to take payments. The default staff role DOES hold manage_checkins,
-- so check-in deletion is unchanged for staff.
-- The remaining manages_gym-gated policies (classes, availability,
-- assignments, freezes, tags, gym settings, SELECTs) keep the current
-- gate; they are lower-stakes and are listed as residual work in
-- AUDIT_CLOSURE.md.

-- Payments: money writes need manage_payments.
DROP POLICY IF EXISTS payments_insert ON public.payments;
CREATE POLICY payments_insert ON public.payments
FOR INSERT WITH CHECK (
  manages_gym(gym_id) AND has_permission('manage_payments', gym_id)
);
DROP POLICY IF EXISTS payments_update ON public.payments;
CREATE POLICY payments_update ON public.payments
FOR UPDATE USING (
  manages_gym(gym_id) AND has_permission('manage_payments', gym_id)
) WITH CHECK (
  manages_gym(gym_id) AND has_permission('manage_payments', gym_id)
);

-- Gate credentials (biometric/card templates + hashes): manage_access_control.
DROP POLICY IF EXISTS member_credentials_insert ON public.member_credentials;
CREATE POLICY member_credentials_insert ON public.member_credentials
FOR INSERT WITH CHECK (
  manages_gym(gym_id)
  AND has_permission('manage_access_control', gym_id)
  AND (user_gym_id(client_id) = gym_id)
  AND (user_role(client_id) = 'client'::text)
  AND ((enrolled_by IS NULL) OR is_same_gym_user(enrolled_by))
);
DROP POLICY IF EXISTS member_credentials_update ON public.member_credentials;
CREATE POLICY member_credentials_update ON public.member_credentials
FOR UPDATE USING (
  manages_gym(gym_id) AND has_permission('manage_access_control', gym_id)
) WITH CHECK (
  manages_gym(gym_id)
  AND has_permission('manage_access_control', gym_id)
  AND (user_gym_id(client_id) = gym_id)
  AND (user_role(client_id) = 'client'::text)
  AND ((enrolled_by IS NULL) OR is_same_gym_user(enrolled_by))
);
DROP POLICY IF EXISTS member_credentials_delete ON public.member_credentials;
CREATE POLICY member_credentials_delete ON public.member_credentials
FOR DELETE USING (
  manages_gym(gym_id) AND has_permission('manage_access_control', gym_id)
);

-- Check-in deletion (attendance fraud surface): manage_checkins.
DROP POLICY IF EXISTS check_ins_delete ON public.check_ins;
CREATE POLICY check_ins_delete ON public.check_ins
FOR DELETE USING (
  manages_gym(gym_id) AND has_permission('manage_checkins', gym_id)
);

-- Gate devices / terminals: manage_access_control.
DROP POLICY IF EXISTS devices_insert ON public.devices;
CREATE POLICY devices_insert ON public.devices
FOR INSERT WITH CHECK (
  manages_gym(gym_id) AND has_permission('manage_access_control', gym_id)
);
DROP POLICY IF EXISTS devices_update ON public.devices;
CREATE POLICY devices_update ON public.devices
FOR UPDATE USING (
  manages_gym(gym_id) AND has_permission('manage_access_control', gym_id)
) WITH CHECK (
  manages_gym(gym_id) AND has_permission('manage_access_control', gym_id)
);
DROP POLICY IF EXISTS devices_delete ON public.devices;
CREATE POLICY devices_delete ON public.devices
FOR DELETE USING (
  manages_gym(gym_id) AND has_permission('manage_access_control', gym_id)
);
