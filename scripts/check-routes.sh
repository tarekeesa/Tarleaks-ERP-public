#!/usr/bin/env bash
# =============================================================================
# The gateway sends each address to the router meant for it: the real Traefik
# image loads config/traefik/dynamic/routes.yml and every path below must be
# handled by the named router. Catches a public (no sign-in) router that
# swallows a signed-in path, and the reverse. Needs Docker. Run by CI.
#
#   bash scripts/check-routes.sh
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
command -v jq >/dev/null || { echo "jq is needed"; exit 2; }

# path                                         router
expect=$(cat <<'TABLE'
/api/notifications/webhooks                    notifications
/api/notifications/webhooks/events             notifications
/api/notifications/unsubscribe                 notifications-public
/api/notifications/oauth/google/callback       notifications-public
/api/documents/onlyoffice/stream/abc           documents-stream
/api/documents/onlyoffice/callback/abc         documents-stream
/api/documents/files                           documents
/api/public/documents/abc                      documents-public
/api/project/public/share/abc                  project-public
/api/project/intake/public/abc                 project-public
/api/project/tasks                             project_management
/api/insights/public/abc                       insights-public
/api/insights/dashboards                       insights
/api/public/lms/abc                            lms-public
/api/public/gamification/abc                   gamification-public
/api/public/jobs                               careers-public
/api/public/recruitment/apply                  careers-public
/api/public/procurement/acme/otp/request       procurement-public-otp
/api/public/contracts/sign/abc                 contracts-public
/api/public/unknown                            api-fallback
/api/activities/invite/respond/abc             activities-public
/api/activities/tasks                          activities
/api/auth/login                                auth-public
/api/auth/sso/start                            auth-public
/api/auth/sso/config                           auth
/api/auth/saml/config                          auth
/api/auth/users                                auth
/api/auth/installation                         auth-public
/api/sales-orders/public/abc                   sales-orders-public
/api/sales-orders/orders                       sales_orders
/api/fleet/public/abc                          fleet-public
/api/attendance/public/v1/punch                attendance-public
/api/hr/employees                              hr
/api/platform/tenants                          api-fallback
/tarleaks-files/a/b.pdf                        files
/onlyoffice/web-apps/apps/api/documents/api.js onlyoffice
/onlyoffice                                    onlyoffice
/drawio/index.html                             drawio
/admin/                                        web
TABLE
)

img=$(sed -n 's/.*TRAEFIK_IMAGE:-\([^}]*\)}.*/\1/p' docker-compose.yml | head -1)
name="tarleaks-route-check-$$"
docker run -d --name "$name" -p 127.0.0.1::80 -e STORAGE_BUCKET=tarleaks-files \
  -v "$PWD/config/traefik/dynamic:/etc/traefik/dynamic:ro" "$img" \
  --providers.file.directory=/etc/traefik/dynamic --providers.file.watch=false \
  --entrypoints.web.address=:80 \
  --accesslog=true --accesslog.format=json --log.level=ERROR >/dev/null
trap 'docker rm -f "$name" >/dev/null' EXIT
port=$(docker port "$name" 80 | head -1 | sed 's/.*://')
for _ in $(seq 1 30); do
  curl -s -o /dev/null -m 2 "http://127.0.0.1:$port/admin/" && break
  sleep 1
done
# The file provider loads the routes a moment after the port opens (longer on
# a busy machine): wait until /admin/ is answered by its own router. No file
# watch: a machine out of inotify instances would start with no routes at all.
for _ in $(seq 1 30); do
  curl -s -o /dev/null -m 2 "http://127.0.0.1:$port/admin/" || true
  docker logs "$name" 2>/dev/null | grep '^{' | jq -r 'select(.RequestPath == "/admin/") | .RouterName // empty' \
    | grep -q '^web' && break
  sleep 1
done
while read -r path _; do
  [ -n "$path" ] && curl -s -o /dev/null -m 5 "http://127.0.0.1:$port$path" || true
done <<<"$expect"
sleep 1
log=$(docker logs "$name" 2>/dev/null | grep '^{' || true)

fail=0
while read -r path want; do
  [ -n "$path" ] || continue
  got=$(printf '%s\n' "$log" | jq -r --arg p "$path" 'select(.RequestPath == $p) | .RouterName // "-"' | tail -1)
  got=${got%@file}
  if [ "$got" != "$want" ]; then
    printf '::error::%s goes to router "%s", should go to "%s"\n' "$path" "${got:-none}" "$want"
    fail=1
  fi
done <<<"$expect"
[ "$fail" = 0 ] && echo "OK: $(printf '%s\n' "$expect" | grep -c .) addresses reach the right gateway router."
exit "$fail"
