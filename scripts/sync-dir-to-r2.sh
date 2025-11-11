#!/usr/bin/env bash
set -euo pipefail

# Sync a local directory to Cloudflare R2 using AWS S3-compatible API
# Defaults to syncing your bak directory if no path is provided.
#
# Required env vars:
#   R2_ACCOUNT_ID            Cloudflare account ID (for endpoint URL)
#   R2_BUCKET                Target R2 bucket name
#   R2_ACCESS_KEY_ID         R2 access key
#   R2_SECRET_ACCESS_KEY     R2 secret key
#
# Optional env vars:
#   R2_REGION                Default 'auto' for R2 (AWS_DEFAULT_REGION)
#   PREFIX                   Prefix inside the bucket (default: bak)
#   DRY_RUN                  Set to '1' to preview actions (no upload)
#   DELETE                   Set to '1' to delete remote files not present locally
#   EXCLUDE                  Comma-separated patterns to exclude (e.g. "cache/*,*.tmp")
#
# Usage:
#   # sync explicit path
#   R2_ACCOUNT_ID=... R2_BUCKET=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... \
#   ./backend/scripts/sync-dir-to-r2.sh /Users/vuquangthinh/Documents/teamsoft/POD/store-vendure/bak
#
#   # with prefix and delete
#   PREFIX=prod/bak DELETE=1 ./backend/scripts/sync-dir-to-r2.sh ./bak
#
#   # exclude some patterns
#   EXCLUDE="cache/*,*.DS_Store" ./backend/scripts/sync-dir-to-r2.sh ./bak

log() { echo "[sync-r2] $*" >&2; }

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    log "ERROR: Missing required env: $name"
    MISSING=1
  fi
}

MISSING=0
require_env R2_ACCOUNT_ID
require_env R2_BUCKET
require_env R2_ACCESS_KEY_ID
require_env R2_SECRET_ACCESS_KEY
if [ "$MISSING" = "1" ]; then
  cat >&2 <<EOF
Usage: set required env vars and run the script
  R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY are required.
Optional env:
  R2_REGION (default 'auto'), PREFIX (default 'bak'), DRY_RUN=1, DELETE=1, EXCLUDE
EOF
  exit 1
fi

LOCAL_DIR="${1:-/Users/vuquangthinh/Documents/teamsoft/POD/store-vendure/bak}"
if [ ! -d "$LOCAL_DIR" ]; then
  log "ERROR: Local directory not found: $LOCAL_DIR"
  exit 1
fi

AWS_DEFAULT_REGION="${R2_REGION:-auto}"
ENDPOINT_URL="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
# Use default 'bak' only if PREFIX is truly unset; allow empty for root
PREFIX="${PREFIX-bak}"
S3_URI="s3://${R2_BUCKET}"
if [ -n "$PREFIX" ]; then
  S3_URI="${S3_URI}/${PREFIX}"
fi

DRY_FLAG=""
if [ "${DRY_RUN:-0}" = "1" ]; then
  DRY_FLAG="--dryrun"
fi

DELETE_FLAG=""
if [ "${DELETE:-0}" = "1" ]; then
  DELETE_FLAG="--delete"
fi

EXCLUDE_FLAGS=()
if [ -n "${EXCLUDE:-}" ]; then
  IFS=',' read -r -a patterns <<< "$EXCLUDE"
  for p in "${patterns[@]}"; do
    EXCLUDE_FLAGS+=("--exclude" "$p")
  done
fi

log "Local dir  : $LOCAL_DIR"
log "Endpoint    : $ENDPOINT_URL"
log "Bucket URI  : $S3_URI"
log "Options     : DRY_RUN=${DRY_RUN:-0} DELETE=${DELETE:-0} EXCLUDE=${EXCLUDE:-}" 

# Run aws-cli in a container to perform the sync
# --follow-symlinks to dereference symlinks if present
# --no-progress and --only-show-errors for cleaner output
#
docker run --rm \
  -e AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
  -e AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
  -e AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
  -v "$LOCAL_DIR:/data:ro" \
  amazon/aws-cli:2.17.40 \
  s3 sync /data "$S3_URI" \
  --endpoint-url "$ENDPOINT_URL" \
  --follow-symlinks \
  --no-progress \
  --only-show-errors \
  $DRY_FLAG $DELETE_FLAG ${EXCLUDE_FLAGS[@]:-}

log "Sync completed."