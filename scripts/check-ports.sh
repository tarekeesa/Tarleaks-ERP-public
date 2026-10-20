#!/usr/bin/env bash
# Only the gateway publishes a port (docs/security.md "What is exposed").
#
# Reads the compose file the way Docker will run it (`docker compose config`)
# with the current .env, then:
#   1. the kit alone: exactly one published port, the gateway's, on HTTP_BIND;
#      the database, cache, message queue and file store publish nothing;
#   2. with examples/database-access: the database is published on 127.0.0.1
#      unless POSTGRES_BIND says otherwise, and still nothing else is.
# Needs docker compose and python3; starts no container.
set -euo pipefail
cd "$(dirname "$0")/.."

published() {  # prints "<service> <host_ip> <published>" per published port
  docker compose "$@" config --format json | python3 -c '
import json, sys
for name, svc in sorted(json.load(sys.stdin)["services"].items()):
    for p in svc.get("ports") or []:
        print(name, p.get("host_ip") or "ALL", p.get("published"))
'
}

fail=0
bad() { echo "::error::$*"; fail=1; }

bind=$(grep -E '^HTTP_BIND=' .env 2>/dev/null | tail -1 | cut -d= -f2- || true)
bind=${bind:-0.0.0.0}
got=$(published)
echo "published by the kit:"; echo "$got" | sed 's/^/  /'
[ "$(echo "$got" | grep -c .)" = 1 ] || bad "the kit must publish exactly one port (the gateway), got: $got"
grep -Eq "^gateway $bind " <<<"$got" || bad "the gateway must listen on HTTP_BIND=$bind, got: $got"

ov=examples/database-access/docker-compose.override.yml
got=$(published -f docker-compose.yml -f "$ov")
grep -Eq '^postgres 127\.0\.0\.1 5432$' <<<"$got" || bad "database-access must default to 127.0.0.1:5432, got: $got"
got=$(POSTGRES_BIND=192.168.1.20 POSTGRES_PUBLISH_PORT=6543 published -f docker-compose.yml -f "$ov")
grep -Eq '^postgres 192\.168\.1\.20 6543$' <<<"$got" || bad "POSTGRES_BIND / POSTGRES_PUBLISH_PORT are not honoured, got: $got"
grep -Ev '^(gateway|postgres) ' <<<"$got" | grep . && bad "only the gateway and (opt-in) the database may publish a port"

[ "$fail" = 0 ] && echo "ports: OK (gateway on $bind; database only by opt-in, 127.0.0.1 by default)"
exit "$fail"
