-- Round 6 (audit closure) — DB-54: the staff-profile sensitive-field
-- guard never fired.
--
-- enforce_staff_profile_gym() blocked self-edits of national_id /
-- is_active / hire_date only when NOT manages_gym(). But manages_gym()
-- is true for ANY role in the admin portal — and every staff member is
-- in the admin portal — so the guard never fired for the people it was
-- meant to restrain: any front-desk staff member could rewrite their
-- own recorded national ID number. (Proved by the round-6 suite: a
-- plain default-role staff member's self-edit of national_id succeeded.)
--
-- Fix: gate the self-edit exception on manage_staff, the actual manager
-- permission, instead of the over-broad manages_gym(). Managers keep
-- full edit rights; non-manager staff can still edit their own
-- non-sensitive fields (job title, contact details) but not the
-- sensitive ones.
CREATE OR REPLACE FUNCTION public.enforce_staff_profile_gym()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.gym_id IS DISTINCT FROM OLD.gym_id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
      RAISE EXCEPTION 'Staff profile gym and user cannot be changed.';
    END IF;

    -- Self-edits (caller is the profile owner, not a manager): sensitive
    -- fields are manager-only. Round 6: this must test manage_staff,
    -- not manages_gym() — the latter is true for every admin-portal
    -- staff member, so the guard never fired.
    IF OLD.user_id = auth.uid() AND NOT public.has_permission('manage_staff', OLD.gym_id) THEN
      IF NEW.national_id IS DISTINCT FROM OLD.national_id
         OR NEW.is_active IS DISTINCT FROM OLD.is_active
         OR NEW.hire_date IS DISTINCT FROM OLD.hire_date THEN
        RAISE EXCEPTION 'national_id, is_active and hire_date are manager-only.';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
