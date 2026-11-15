// Trainw runtime configuration.
//
// The Supabase URL and anon key are injected into this file at build time by
// env-config.js (which writes dist/trainw-config.js) or served dynamically by
// dev-server.js (local development). The app reads them as
// window.__TRAINW_URL__ / window.__TRAINW_KEY__ before trainw-core.js loads.
//
// This committed copy MUST only contain the %%...%% placeholders — never real
// values. Keeping the config in this external file (instead of an inline
// <script> block in every HTML page) is what lets the Content-Security-Policy
// forbid inline scripts entirely (P1-6).
//
// TURNSTILES_ENABLED — the single feature flag for the turnstile / gate
// hardware (user requirement, 2026-11-15). Default OFF (false): the
// gate-checkin edge function refuses every check-in while it is off, and
// the terminal + dashboard turnstile UI stay hidden. The turnstile code,
// tables, RPCs and the gate-checkin function are all still there — nothing
// was deleted. To re-enable turnstiles later: set TURNSTILES_ENABLED=true
// in the deploy environment (env-config.js reads it at build time,
// dev-server.js reads it for local dev, the edge function reads the
// TURNSTILES_ENABLED edge secret) and redeploy. The gate-terminal-auth
// edge function also needs its GATE_TERMINAL_PEPPER secret set.
window.__TRAINW_URL__ = '%%SUPABASE_URL%%';
window.__TRAINW_KEY__ = '%%SUPABASE_ANON_KEY%%';
window.__TRAINW_TURNSTILES_ENABLED__ = false;
