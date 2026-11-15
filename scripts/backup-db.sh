#!/usr/bin/env bash
# P2-7 — back up the Trainw Supabase database with pg_dump.
#
# Usage:
#   DATABASE_URL='postgres://postgres:<db-password>@db.caylegavnekidhytlswo.supabase.co:5432/postgres' \
#     ./scripts/backup-db.sh [output-dir]
#
# The connection string comes from the environment only — never commit
# it, never paste it into chat. The DB password lives in the Supabase
# dashboard (Settings -> Database). Dumps are written outside the repo
# by default (~/workspace/backups/trainw) so they can never be committed
# by accident.
set -euo pipefail

OUT_DIR="${1:-$HOME/workspace/backups/trainw}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_FILE="$OUT_DIR/trainw-$STAMP.dump"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "error: DATABASE_URL is not set (postgres://...@db.<ref>.supabase.co:5432/postgres)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
echo "Backing up to $OUT_FILE ..."
pg_dump --format=custom --no-owner --no-privileges --dbname="$DATABASE_URL" --file="$OUT_FILE"
echo "Backup complete: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"
echo "Keep this file safe — it is the rollback for the next migration apply."
