#!/bin/bash
# ValidateService: the deployment succeeds only when the API, reached through
# the host Nginx with the site's Host header, reports "healthy".
. "$(dirname "$0")/common.sh"

DOMAIN_VALUE="$(read_env_var DOMAIN)"
SITE_HOST="${DOMAIN_VALUE#*://}"
SITE_HOST="${SITE_HOST%%/*}"
[ -n "$SITE_HOST" ] || fail "DOMAIN is not set in .env."

for attempt in $(seq 1 30); do
  body="$(curl -fs --max-time 10 -H "Host: ${SITE_HOST}" \
    "http://127.0.0.1:${PROXY_PORT}/api/health" 2>/dev/null || true)"
  if [[ "$body" == *'"healthy"'* ]]; then
    log "Health check passed: $body"
    exit 0
  fi
  sleep 5
done

fail "API not healthy after 30 attempts. Last response: ${body:-<none>}"
