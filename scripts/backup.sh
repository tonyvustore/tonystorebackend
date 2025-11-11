#!/usr/bin/env bash
set -euo pipefail

# Backup Vendure Postgres database and static assets
# Usage: bash backend/scripts/backup.sh [output_dir]
# Requires: pg_dump installed and access to the Postgres server

OUTPUT_DIR=${1:-"$(pwd)/../backups"}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Load env if present
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

DB_NAME=${DATABASE_NAME:-vendure}
DB_USER=${DATABASE_USER:-postgres}
DB_PASS=${DATABASE_PASSWORD:-password}
DB_HOST=${DATABASE_HOST:-localhost}
DB_PORT=${DATABASE_PORT:-5432}

ASSETS_DIR="$(dirname "$0")/../static/assets"
EMAIL_DIR="$(dirname "$0")/../static/email"

mkdir -p "$OUTPUT_DIR"

# Database dump (custom format, includes blobs)
DB_DUMP_FILE="$OUTPUT_DIR/db_${TIMESTAMP}.dump"
echo "[backup] Dumping database to $DB_DUMP_FILE"
PGPASSWORD="$DB_PASS" pg_dump \
  -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
  --format=custom --blobs --no-owner --no-privileges \
  --file "$DB_DUMP_FILE"

# Archive assets
ASSETS_ARCHIVE="$OUTPUT_DIR/assets_${TIMESTAMP}.tar.gz"
echo "[backup] Archiving assets to $ASSETS_ARCHIVE"
if [ -d "$ASSETS_DIR" ]; then
  tar -czf "$ASSETS_ARCHIVE" -C "$ASSETS_DIR" .
else
  echo "[backup] Assets directory not found: $ASSETS_DIR (skipping)"
fi

# Archive email templates (optional)
EMAIL_ARCHIVE="$OUTPUT_DIR/email_${TIMESTAMP}.tar.gz"
echo "[backup] Archiving email templates to $EMAIL_ARCHIVE"
if [ -d "$EMAIL_DIR" ]; then
  tar -czf "$EMAIL_ARCHIVE" -C "$EMAIL_DIR" .
else
  echo "[backup] Email directory not found: $EMAIL_DIR (skipping)"
fi

# Summary
echo "[backup] Completed"
echo "[backup] Files:"
echo "  - $DB_DUMP_FILE"
echo "  - $ASSETS_ARCHIVE"
echo "  - $EMAIL_ARCHIVE"