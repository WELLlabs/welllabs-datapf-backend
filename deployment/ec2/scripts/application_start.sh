#!/bin/bash
# ApplicationStart:
#   1. docker compose up -d --build
#   2. install the Nginx site, check it with nginx -t, reload Nginx
. "$(dirname "$0")/common.sh"

compose up -d --build || fail "docker compose up failed."

sed -e "s#listen 80 default_server;#listen ${PROXY_PORT} default_server;#" \
    "$RELEASE_DIR/nginx/data-platform.conf" >/etc/nginx/conf.d/data-platform.conf
nginx -t || fail "nginx -t failed."
systemctl reload nginx
