#!/usr/bin/env bash

# CodeDeploy AfterInstall
#
# 1. Link the host .env into the release (compose reads ./.env).
# 2. Validate Docker Compose configuration.
# 3. Pull public service images.
# 4. Build Backend and Email images locally on EC2.
# 5. Run Alembic migrations.
#
# Existing running containers are NOT restarted in this hook.
# ApplicationStart handles starting the new release.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

log "Starting AfterInstall deployment preparation."

# --------------------------------------------------
# 1. Link .env and validate Compose configuration
# --------------------------------------------------

ln -sfn "$ENV_FILE" "$RELEASE_DIR/.env"

log "Validating Docker Compose configuration."

compose config --quiet \
  || fail "docker-compose.yml is invalid. Check the deployment .env."

# --------------------------------------------------
# 2. Pull public service images
# --------------------------------------------------

log "Pulling public service images."

# No service list: pulls every enabled one (db too when the localdb profile is on).
compose pull --quiet --ignore-buildable \
  || fail "Docker image pull failed."

# --------------------------------------------------
# 3. Build images on EC2 (backend, email-worker)
# --------------------------------------------------

log "Building application images."

compose build \
  || fail "Docker image build failed."

# --------------------------------------------------
# 4. Rollback handling
# --------------------------------------------------

# A rollback deploys an older application revision.
# Do not run old migrations against a database that may
# already have a newer schema.

if is_rollback; then
  log "Rollback deployment detected. Skipping migrations."
  exit 0
fi

# --------------------------------------------------
# 5. Run Alembic database migrations (new backend image)
# --------------------------------------------------

# The migration runs with --no-deps, so a local database must already be up.
if has_profile localdb; then
  log "Starting the local PostgreSQL container."
  compose up -d --wait db \
    || fail "PostgreSQL container did not become healthy."
fi

log "Running Alembic database migrations."

compose run --rm --no-deps backend uv run alembic upgrade head \
  || fail "Alembic migration failed. ApplicationStart will not run."

log "AfterInstall completed successfully."
