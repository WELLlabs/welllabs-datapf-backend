#!/bin/bash
# BeforeInstall: stop early, before anything changes, if the host is not ready.
. "$(dirname "$0")/common.sh"

[ -s "$ENV_FILE" ] || fail "$ENV_FILE is missing. Create it from the app's env.template; deployments never write it."
[ -s "$TLS_CERT_DIR/fullchain.pem" ] && [ -s "$TLS_CERT_DIR/privkey.pem" ] \
  || fail "TLS certificate not found in $TLS_CERT_DIR (fullchain.pem, privkey.pem)."
command -v docker >/dev/null 2>&1 || fail "docker is not installed."
docker compose version >/dev/null 2>&1 || fail "The docker compose plugin is not installed."
command -v aws >/dev/null 2>&1 || fail "The AWS CLI is not installed."
command -v nginx >/dev/null 2>&1 || fail "Nginx is not installed on the host."
systemctl is-active --quiet nginx || fail "Nginx is not running (systemctl start nginx)."

log "Host checks passed for $IMAGE_TAG."
