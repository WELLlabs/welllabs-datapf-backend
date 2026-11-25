#!/bin/bash
# Shared by the CodeDeploy hooks. Sourced, not run.
#
# deploy.env (written by the build stage, non-secret) provides:
#   IMAGE_TAG AWS_REGION COMPOSE_PROJECT PROXY_PORT
#   BACKEND_ENV_SECRET_ID (secret name only)
# Secrets live in Secrets Manager; before_install.sh writes them to
# /opt/data-platform/.env (mode 600) on every deploy.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(dirname "$HOOK_DIR")"

APP_DIR=/opt/data-platform
RELEASE_DIR="$APP_DIR/release"
ENV_FILE="$APP_DIR/.env"

[ -s "$BUNDLE_DIR/deploy.env" ] || { echo "deploy.env missing from the revision" >&2; exit 1; }
set -a
# shellcheck source=/dev/null
. "$BUNDLE_DIR/deploy.env"
set +a
export APP_DIR

log() { printf '%s [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${LIFECYCLE_EVENT:-deploy}" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

# Shell variables (deploy.env) win over .env for compose interpolation.
# COMPOSE_PROFILES comes from .env (dev: localdb; prod: unset).
compose() {
  COMPOSE_PROFILES="$(read_env_var COMPOSE_PROFILES)" \
    docker compose -p "$COMPOSE_PROJECT" --env-file "$ENV_FILE" -f "$RELEASE_DIR/docker-compose.yml" "$@"
}

# True when COMPOSE_PROFILES in .env includes the given profile.
has_profile() {
  [[ ",$(read_env_var COMPOSE_PROFILES)," == *",$1,"* ]]
}

# Reads KEY from .env without sourcing it.
read_env_var() {
  local key="$1" line value
  line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$ENV_FILE" 2>/dev/null | tail -n 1 || true)"
  value="${line#*=}"
  value="${value//$'\r'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$value"
}

# True when CodeDeploy is redeploying the last good revision after a failure.
is_rollback() {
  [ -n "${DEPLOYMENT_ID:-}" ] || return 1
  local creator
  creator="$(aws deploy get-deployment --region "$AWS_REGION" --deployment-id "$DEPLOYMENT_ID" \
    --query 'deploymentInfo.creator' --output text 2>/dev/null || true)"
  [ "$creator" = "codeDeployRollback" ]
}
