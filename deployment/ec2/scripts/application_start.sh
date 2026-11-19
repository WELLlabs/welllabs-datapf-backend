#!/bin/bash
# ApplicationStart:
#   1. docker compose up -d --build
#   2. install the Nginx site, check it with nginx -t, reload Nginx
. "$(dirname "$0")/common.sh"

compose up -d --build || fail "docker compose up failed."

sed -e "s#listen 443 ssl;#listen ${PROXY_HTTPS_PORT} ssl;#" \
    -e "s#/etc/data-platform/ssl/#${TLS_CERT_DIR%/}/#g" \
    "$RELEASE_DIR/nginx/data-platform.conf" >/etc/nginx/conf.d/data-platform.conf
nginx -t || fail "nginx -t failed."
systemctl reload nginx
