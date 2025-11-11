#!/usr/bin/env bash
set -euo pipefail

# Upload Docker volumes as compressed archives to Cloudflare R2 (S3-compatible)
#
# Requirements:
# - Docker (for reading volumes and running helper containers)
# - No need to install AWS CLI on host; we use the amazon/aws-cli container
#
# Environment variables (required):
# - R2_ACCOUNT_ID: Cloudflare account ID (used to form endpoint URL)
# - R2_BUCKET: Target R2 bucket name
# - R2_ACCESS_KEY_ID: R2 access key ID
# - R2_SECRET_ACCESS_KEY: R2 secret key
#
# Optional env:
# - R2_REGION: Set AWS region for the CLI; for R2, use 'auto' (default)
# - PREFIX: Path prefix inside bucket (default: backups/YYYY/MM/DD)
# - BACKUP_VOLUMES: Space-separated list of docker volume names to upload
# - DRY_RUN: If set to '1', do not actually upload (prints commands only)
#
# Usage examples:
#   R2_ACCOUNT_ID=abc123 R2_BUCKET=my-bucket \
#   R2_ACCESS_KEY_ID=AKIA... R2_SECRET_ACCESS_KEY=... \
#   ./backend/scripts/upload-volumes-to-r2.sh
#
#   # Specify volumes explicitly
#   BACKUP_VOLUMES="pgdata_prod assets-data" ./backend/scripts/upload-volumes-to-r2.sh
#
#   # Specify custom prefix
#   PREFIX="backups/prod/$(date +%F)" ./backend/scripts/upload-volumes-to-r2.sh

log() {
  echo "[upload-volumes] $*" >&2
}

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
  R2_REGION (default 'auto'), PREFIX (default backups/YYYY/MM/DD), BACKUP_VOLUMES, DRY_RUN=1
EOF
  exit 1
fi

AWS_DEFAULT_REGION="${R2_REGION:-auto}"
ENDPOINT_URL="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
DATE_PREFIX="$(date +%Y/%m/%d)"
PREFIX="${PREFIX:-backups/${DATE_PREFIX}}"

# Build candidate volumes list from common names in this repo if BACKUP_VOLUMES unset
if [ -z "${BACKUP_VOLUMES:-}" ]; then
  # Known volume names in this project’s compose files
  CANDIDATES=(pgdata pgdata_prod assets-data)
  BACKUP_VOLUMES=""
  for v in "${CANDIDATES[@]}"; do
    if docker volume inspect "$v" >/dev/null 2>&1; then
      BACKUP_VOLUMES="$BACKUP_VOLUMES $v"
    fi
  done
  # If none of the known names exist, fallback to all volumes
  if [ -z "${BACKUP_VOLUMES// /}" ]; then
    BACKUP_VOLUMES="$(docker volume ls --format '{{.Name}}')"
  fi
fi

if [ -z "${BACKUP_VOLUMES// /}" ]; then
  log "ERROR: No docker volumes found to back up"
  exit 1
fi

log "Using endpoint: ${ENDPOINT_URL}"
log "Bucket: ${R2_BUCKET}"
log "Prefix: ${PREFIX}"
log "Volumes: ${BACKUP_VOLUMES}"

# Iterate volumes and stream tar.gz directly to R2 via aws-cli container
for VOL in ${BACKUP_VOLUMES}; do
  TS="$(date +%Y%m%d-%H%M%S)"
  ARCHIVE_NAME="${VOL}-${TS}.tar.gz"
  S3_URI="s3://${R2_BUCKET}/${PREFIX}/${ARCHIVE_NAME}"

  log "Backing up volume '${VOL}' to '${S3_URI}'"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log "DRY_RUN: docker run -v ${VOL}:/data:ro alpine tar -czf - -C /data . | docker run -i -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION amazon/aws-cli s3 cp - ${S3_URI} --endpoint-url ${ENDPOINT_URL}"
    continue
  fi

  # Stream compressed archive to aws-cli container
  docker run --rm -v "${VOL}:/data:ro" alpine:3.19 \
    tar -czf - -C /data . | \
  docker run --rm -i \
    -e AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    amazon/aws-cli:2.17.40 \
    s3 cp - "${S3_URI}" --endpoint-url "${ENDPOINT_URL}"

  log "Uploaded: ${S3_URI}"

done

log "All requested volumes uploaded to R2."