#!/usr/bin/env bash
set -euo pipefail

# Copy all files from a Docker volume (assets) to a host directory
# Default volume name: backend_assets-data (can be overridden)
# Usage:
#   ./backend/scripts/copy-assets-volume.sh /path/to/output [VOLUME_NAME]
# Examples:
#   ./backend/scripts/copy-assets-volume.sh ~/backup-assets
#   ./backend/scripts/copy-assets-volume.sh ~/backup-assets backend_assets-data
#   ./backend/scripts/copy-assets-volume.sh ~/backup-assets assets-data
#
# Notes:
# - Requires Docker installed and permission to run docker commands.
# - This uses a temporary Alpine container to mount the volume read-only and copy files.

log() { echo "[copy-assets] $*" >&2; }

if ! command -v docker >/dev/null 2>&1; then
  log "ERROR: Docker not found. Please install Docker."
  exit 1
fi

if [ $# -lt 1 ]; then
  log "Usage: $0 OUTPUT_DIR [VOLUME_NAME]"
  exit 1
fi

OUTPUT_DIR="$1"
VOLUME_NAME="${2:-}" # optional arg

# If not provided, try common names
if [ -z "$VOLUME_NAME" ]; then
  for candidate in backend_assets-data assets-data; do
    if docker volume inspect "$candidate" >/dev/null 2>&1; then
      VOLUME_NAME="$candidate"
      break
    fi
  done
fi

if [ -z "$VOLUME_NAME" ]; then
  log "ERROR: No volume name provided and none of the common names exist (backend_assets-data, assets-data)."
  log "Tip: pass volume name explicitly as second argument."
  exit 1
fi

# Validate volume exists
if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  log "ERROR: Docker volume '$VOLUME_NAME' does not exist."
  exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

log "Copying from volume '$VOLUME_NAME' to '$OUTPUT_DIR'"

# Use Alpine to copy preserving attributes (-a)
docker run --rm \
  -v "$VOLUME_NAME:/data:ro" \
  -v "$OUTPUT_DIR:/backup" \
  alpine:3.19 \
  sh -c "cp -a /data/. /backup/"

log "Done. Files copied to: $OUTPUT_DIR"