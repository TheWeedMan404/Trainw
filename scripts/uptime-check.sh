#!/usr/bin/env bash
# P2-7 — uptime probe for Trainw. Exits 0 when both checks pass, 1 otherwise.
#
# Usage:
#   TRAINW_URL='https://trainw-....vercel.app' \
#   SUPABASE_URL='https://caylegavnekidhytlswo.supabase.co' \
#     ./scripts/uptime-check.sh
#
# This script only probes — it needs a scheduler (cron, UptimeRobot,
# Better Stack, ...) to actually page someone. See docs/DEPLOY_RUNBOOK.md.
set -uo pipefail

TRAINW_URL="${TRAINW_URL:-}"
SUPABASE_URL="${SUPABASE_URL:-https://caylegavnekidhytlswo.supabase.co}"
FAIL=0

check() {
  local name="$1" url="$2"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url" || echo '000')"
  if [ "$code" = "200" ] || [ "$code" = "302" ]; then
    echo "OK   $name ($code) $url"
  else
    echo "FAIL $name ($code) $url" >&2
    FAIL=1
  fi
}

if [ -n "$TRAINW_URL" ]; then
  check "trainw site" "$TRAINW_URL"
else
  echo "SKIP trainw site (TRAINW_URL not set)"
fi

# The Supabase REST endpoint needs the anon key for a 200. With
# SUPABASE_ANON_KEY set, expect 200; without it, a 401 still proves the
# project answers (the infra is up and the project exists) — anything
# else (000, timeout, 5xx) is a failure.
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"
if [ -n "$SUPABASE_ANON_KEY" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
    "$SUPABASE_URL/rest/v1/" || echo '000')"
  if [ "$code" = "200" ]; then
    echo "OK   supabase rest ($code) $SUPABASE_URL/rest/v1/"
  else
    echo "FAIL supabase rest ($code) $SUPABASE_URL/rest/v1/" >&2
    FAIL=1
  fi
else
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$SUPABASE_URL/rest/v1/" || echo '000')"
  if [ "$code" = "401" ]; then
    echo "OK   supabase rest (401 = reachable, no anon key given) $SUPABASE_URL/rest/v1/"
  else
    echo "FAIL supabase rest ($code) $SUPABASE_URL/rest/v1/" >&2
    FAIL=1
  fi
fi

exit "$FAIL"
