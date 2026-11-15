-- U9 item 10: branding colours had nowhere to live — the Branding
-- cards displayed the raw CSS variable names ("var(--ac)" etc.) and
-- did nothing on click. Store the three theme colours on the gyms row
-- (nullable = theme default). The existing gyms_update policy
-- (manages_gym) covers the new columns, so no new policy is needed;
-- the hex CHECK is the only new constraint, and NULL rows (all
-- existing gyms) pass it.
ALTER TABLE public.gyms
  ADD COLUMN IF NOT EXISTS accent_color text,
  ADD COLUMN IF NOT EXISTS surface_color text,
  ADD COLUMN IF NOT EXISTS muted_color text;

ALTER TABLE public.gyms
  ADD CONSTRAINT gyms_branding_colours_hex
  CHECK (
    (accent_color IS NULL OR accent_color ~ '^#[0-9a-fA-F]{6}$')
    AND (surface_color IS NULL OR surface_color ~ '^#[0-9a-fA-F]{6}$')
    AND (muted_color IS NULL OR muted_color ~ '^#[0-9a-fA-F]{6}$')
  );
