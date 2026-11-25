#!/bin/bash
# BeforeInstall: stop early, before anything changes, if the host is not ready,
# then write the host .env from Secrets Manager.
. "$(dirname "$0")/common.sh"

command -v docker >/dev/null 2>&1 || fail "docker is not installed."
docker compose version >/dev/null 2>&1 || fail "The docker compose plugin is not installed."
command -v aws >/dev/null 2>&1 || fail "The AWS CLI is not installed."
command -v python3 >/dev/null 2>&1 || fail "python3 is not installed."
command -v nginx >/dev/null 2>&1 || fail "Nginx is not installed on the host."
systemctl is-active --quiet nginx || fail "Nginx is not running (systemctl start nginx)."

# --------------------------------------------------
# .env from Secrets Manager
# The secret value is one JSON object: {"KEY":"value", ...}. It is read with
# the EC2 role and never passes through CodeBuild or the pipeline artifact.
# Values are single-quoted (literal for docker compose; no $ interpolation).
# --------------------------------------------------
[ -n "${BACKEND_ENV_SECRET_ID:-}" ] || fail "BACKEND_ENV_SECRET_ID is missing from deploy.env."
log "Writing $ENV_FILE from secret $BACKEND_ENV_SECRET_ID."

mkdir -p "$APP_DIR"
TMP_ENV="$(mktemp "$APP_DIR/.env.XXXXXX")" # mode 600
trap 'rm -f "$TMP_ENV"' EXIT

TO_ENV="$(cat <<'PY'
import json, re, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit("secret value is not valid JSON")
if not isinstance(data, dict) or not data:
    sys.exit("secret value must be a non-empty JSON object")
for key, value in data.items():
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        sys.exit("invalid key name: " + key)
    if value is None:
        value = ""
    elif isinstance(value, bool):
        value = "true" if value else "false"
    else:
        value = str(value)
    if "\n" in value or "\r" in value or "'" in value:
        sys.exit("value of " + key + " contains a newline or a single quote")
    print(key + "='" + value + "'")
PY
)"

aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$BACKEND_ENV_SECRET_ID" \
    --query SecretString --output text \
  | python3 -c "$TO_ENV" >"$TMP_ENV" \
  || fail "Could not build .env from $BACKEND_ENV_SECRET_ID. Check that the secret has a JSON value and that the EC2 role can read it."

for key in POSTGRES_URL REDIS_URL DOMAIN SECRET S3_BUCKET; do
  grep -q "^$key=" "$TMP_ENV" || fail "Secret $BACKEND_ENV_SECRET_ID has no $key."
done

# The localdb profile (dev Postgres container) needs its own password.
if grep -Eq "^COMPOSE_PROFILES='([^']*,)?localdb(,[^']*)?'" "$TMP_ENV"; then
  grep -Eq "^POSTGRES_PASSWORD='.+'" "$TMP_ENV" \
    || fail "COMPOSE_PROFILES has localdb, but the secret has no POSTGRES_PASSWORD."
fi

chmod 600 "$TMP_ENV"
mv -f "$TMP_ENV" "$ENV_FILE"
trap - EXIT
log ".env written ($(wc -l <"$ENV_FILE") keys)."

log "Host checks passed for $IMAGE_TAG."
