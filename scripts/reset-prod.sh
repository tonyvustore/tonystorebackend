#!/usr/bin/env bash
set -euo pipefail

# Reset production stack: stop & remove volumes, start clean, health-check,
# optional migrations and DB table listing.
# Usage:
#   reset-prod.sh [--force] [--skip-build] [--run-migrations] [--check-db]
#
# Flags:
#   --force           Skip confirmation prompt (DANGEROUS – deletes volumes)
#   --skip-build      Do not rebuild images on start
#   --run-migrations  Run yarn migration:run inside server container after start
#   --check-db        List tables in vendure database after start
#   --fix-tax-zone     Ensure default tax zone and 0% rate exist
#
# Examples:
#   ./reset-prod.sh                        # interactive confirmation, rebuild images
#   ./reset-prod.sh --force --skip-build   # no prompt, start without rebuild
#   ./reset-prod.sh --force --run-migrations --check-db

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.prod.yml"
HEALTH_URL="http://localhost:3000/health"

FORCE=0
SKIP_BUILD=0
RUN_MIGRATIONS=0
CHECK_DB=0
FIX_TAX_ZONE=0

usage() {
  cat <<USAGE
Reset production stack and volumes.

Usage: $(basename "$0") [--force] [--skip-build] [--run-migrations] [--check-db] [--fix-tax-zone]
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --run-migrations) RUN_MIGRATIONS=1 ;;
    --check-db) CHECK_DB=1 ;;
    --fix-tax-zone) FIX_TAX_ZONE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg"; usage; exit 1 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "docker is not installed or not in PATH"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is not installed or not in PATH"; exit 1; }

echo "Using compose file: $COMPOSE_FILE"
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Compose file not found: $COMPOSE_FILE"
  exit 1
fi

if [[ $FORCE -ne 1 ]]; then
  read -r -p "This will STOP prod stack and DELETE volumes. Continue? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

set -x
# Stop stack and remove volumes
docker compose -f "$COMPOSE_FILE" down -v --remove-orphans

# Start stack (with or without rebuild)
if [[ $SKIP_BUILD -eq 1 ]]; then
  docker compose -f "$COMPOSE_FILE" up -d
else
  docker compose -f "$COMPOSE_FILE" up -d --build
fi
set +x

# Health check loop
echo "Waiting for backend to become healthy at $HEALTH_URL ..."
attempts=30
sleep_between=2
ok=0
for ((i=1;i<=attempts;i++)); do
  if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep "$sleep_between"
done

if [[ $ok -eq 1 ]]; then
  echo "Backend health OK."
else
  echo "Backend health check FAILED. Showing server logs:"
  docker compose -f "$COMPOSE_FILE" logs --tail=200 server || true
  exit 1
fi

# Optional: run migrations
if [[ $RUN_MIGRATIONS -eq 1 ]]; then
  echo "Running migrations inside server container..."
  docker compose -f "$COMPOSE_FILE" exec -T server yarn migration:run
fi



fix_tax_zone() {
  local ADMIN_API="http://localhost:3000/admin-api"
  local COOKIE_FILE="$PROJECT_ROOT/.tmp/reset-cookie.txt"
  mkdir -p "$(dirname "$COOKIE_FILE")"

  echo "Logging into Admin API as superadmin..."
  curl -sS -c "$COOKIE_FILE" "$ADMIN_API" \
    -H 'Content-Type: application/json' \
    --data-binary '{"query":"mutation login($username:String!, $password:String!){ login(username:$username, password:$password){ __typename } }","variables":{"username":"superadmin","password":"superadmin"}}' \
    | jq -e '.data.login != null' >/dev/null || { echo "Admin login failed"; return 1; }

  local ZONE_NAME="Default Tax Zone"
  local ZONE_ID
  echo "Ensuring zone exists: $ZONE_NAME"
  ZONE_ID=$(curl -sS -b "$COOKIE_FILE" "$ADMIN_API" -H 'Content-Type: application/json' \
    --data-binary '{"query":"query { zones { items { id name } } }"}' \
    | jq -r --arg name "$ZONE_NAME" '.data.zones.items[] | select(.name==$name) | .id' | head -n1)

  if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
    ZONE_ID=$(curl -sS -b "$COOKIE_FILE" "$ADMIN_API" -H 'Content-Type: application/json' \
      --data-binary '{"query":"mutation($name:String!){ createZone(input:{name:$name}){ id name } }","variables":{"name":"Default Tax Zone"}}' \
      | jq -r '.data.createZone.id')
    echo "Created zone with id: $ZONE_ID"
  else
    echo "Found zone id: $ZONE_ID"
  fi

  echo "Fetching default channel id..."
  local CHANNEL_ID
  CHANNEL_ID=$(curl -sS -b "$COOKIE_FILE" "$ADMIN_API" -H 'Content-Type: application/json' \
    --data-binary '{"query":"query { channels { items { id code defaultTaxZone { id } } } }"}' \
    | jq -r '.data.channels.items[] | select(.code=="__default_channel__") | .id')

  if [[ -z "$CHANNEL_ID" || "$CHANNEL_ID" == "null" ]]; then
    echo "Could not determine default channel id"; return 1
  fi

  echo "Setting default tax zone for channel..."
  curl -sS -b "$COOKIE_FILE" "$ADMIN_API" -H 'Content-Type: application/json' \
    --data-binary "$(printf '{"query":"mutation($id:ID!,$zoneId:ID!){ updateChannel(input:{id:$id, defaultTaxZoneId:$zoneId){ ... on Channel { id code defaultTaxZone { id name } } ... on UpdateChannelError { message } } }","variables":{"id":"%s","zoneId":"%s"}}' "$CHANNEL_ID" "$ZONE_ID")" \
    | jq -e '.data.updateChannel.defaultTaxZone.id != null' >/dev/null || echo "Warning: setting default tax zone may have failed"

  echo "Ensuring Standard tax category exists..."
  local TAXCAT_ID
  TAXCAT_ID=$(curl -sS -b "$COOKIE_FILE" "$ADMIN_API" -H 'Content-Type: application/json' \
    --data-binary '{"query":"query { taxCategories { items { id name } } }"}' \
    | jq -r '.data.taxCategories.items[] | select(.name=="Standard") | .id' | head -n1)

  if [[ -z "$TAXCAT_ID" || "$TAXCAT_ID" == "null" ]]; then
    TAXCAT_ID=$(curl -sS -b "$COOKIE_FILE" "$ADMIN_API" -H 'Content-Type: application/json' \
      --data-binary '{"query":"mutation($name:String!){ createTaxCategory(input:{name:$name}){ id name } }","variables":{"name":"Standard"}}' \
      | jq -r '.data.createTaxCategory.id')
    echo "Created tax category id: $TAXCAT_ID"
  else
    echo "Found tax category id: $TAXCAT_ID"
  fi

  echo "Ensuring 0% tax rate exists for zone/category..."
  local RATE_ID
  RATE_ID=$(curl -sS -b "$COOKIE_FILE" "$ADMIN_API" -H 'Content-Type: application/json' \
    --data-binary '{"query":"query { taxRates { items { id name value enabled zone { id } category { id } } } }"}' \
    | jq -r --arg z "$ZONE_ID" --arg c "$TAXCAT_ID" '.data.taxRates.items[] | select(.zone.id==$z and .category.id==$c and (.value|tonumber)==0) | .id' | head -n1)

  if [[ -z "$RATE_ID" || "$RATE_ID" == "null" ]]; then
    RATE_ID=$(curl -sS -b "$COOKIE_FILE" "$ADMIN_API" -H 'Content-Type: application/json' \
      --data-binary "$(printf '{"query":"mutation($input:CreateTaxRateInput!){ createTaxRate(input:$input){ id name value enabled } }","variables":{"input":{"name":"US 0%%","value":0,"enabled":true,"categoryId":"%s","zoneId":"%s"}}}' "$TAXCAT_ID" "$ZONE_ID")" \
      | jq -r '.data.createTaxRate.id')
    echo "Created 0% tax rate id: $RATE_ID"
  else
    echo "Found existing 0% tax rate id: $RATE_ID"
  fi

  echo "Tax zone configuration complete."
}
if [[ $FIX_TAX_ZONE -eq 1 ]]; then
  echo "Configuring default tax zone and 0% rate via Admin API..."
  fix_tax_zone
fi
if [[ $CHECK_DB -eq 1 ]]; then
  echo "Listing tables in vendure database..."
  docker compose -f "$COMPOSE_FILE" exec -T database psql -U postgres -d vendure -c "\\dt" || true
fi

echo "Reset completed successfully."