#!/usr/bin/env bash
# =============================================================================
# The HTTPS and offline compose files stay in step with docker-compose.yml.
#
#   * config/https/*.yml REPLACE the gateway's command (compose cannot add to a
#     list), so each must repeat every line of the base command: a flag added
#     to docker-compose.yml and forgotten there would silently vanish on every
#     HTTPS installation.
#   * Each file must give a valid configuration with the base file, publish
#     ports on the gateway only, and keep HSTS off plain http.
#   * config/offline/compose.sealed.yml must leave every service on an
#     internal network except the gateway.
#
#   bash scripts/check-https.sh      (CI; needs docker compose and python3)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
bad() { echo "::error::$*"; fail=1; }

env_file=$(mktemp); trap 'rm -f "$env_file"' EXIT
sed 's/=GENERATED$/=x/' .env.example > "$env_file"
cat >> "$env_file" <<'VARS'
TARLEAKS_VERSION=1.2.0
TARLEAKS_HOST=erp.example.test
TARLEAKS_URL=https://erp.example.test
ACME_EMAIL=it@example.test
CF_DNS_API_TOKEN=x
VARS
config() { docker compose --env-file "$env_file" -f docker-compose.yml "$@" config --format json; }

base=$(config | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["services"]["gateway"]["command"]))')
for f in config/https/compose.https-*.yml; do
  json=$(config -f "$f") || { bad "$f does not give a valid configuration"; continue; }
  got=$(python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["services"]["gateway"]["command"]))' <<<"$json")
  missing=$(comm -23 <(sort <<<"$base") <(sort <<<"$got"))
  [ -z "$missing" ] || bad "$f drops gateway flags of docker-compose.yml: $(tr '\n' ' ' <<<"$missing")"
  grep -qx -- '--entrypoints.websecure.http.middlewares=hsts@file' <<<"$got" || bad "$f: HSTS must be on the 443 entry point"
  grep -q -- 'entrypoints.web.http.middlewares' <<<"$got" && bad "$f: no middleware on plain http (HSTS there locks a local install out)"
  pubs=$(python3 -c '
import json,sys
for n,s in json.load(sys.stdin)["services"].items():
    for p in s.get("ports") or []: print(n, p.get("published"))' <<<"$json")
  [ "$(grep -c . <<<"$pubs")" = 2 ] && ! grep -qv '^gateway ' <<<"$pubs" \
    || bad "$f: only the gateway may publish ports (80 and 443), got: $(tr '\n' ';' <<<"$pubs")"
  echo "ok: $f"
done

sealed_json=$(mktemp); trap 'rm -f "$env_file" "$sealed_json"' EXIT
config -f config/offline/compose.sealed.yml > "$sealed_json" || bad "compose.sealed.yml does not give a valid configuration"
python3 - "$sealed_json" <<'PY' || fail=1
import json, sys
c = json.load(open(sys.argv[1]))
nets = c.get("networks", {})
ok = True
if not nets.get("default", {}).get("internal"):
    print("::error::sealed: the default network must be internal"); ok = False
for name, svc in c["services"].items():
    on = set((svc.get("networks") or {}).keys())
    if name == "gateway":
        if on != {"default", "edge"}:
            print(f"::error::sealed: the gateway must be on default and edge, is on {sorted(on)}"); ok = False
    elif svc.get("network_mode") == "none":
        continue
    elif on - {"default"}:
        print(f"::error::sealed: {name} is on {sorted(on)}: only the gateway may leave the internal network"); ok = False
print("ok: config/offline/compose.sealed.yml" if ok else "")
sys.exit(0 if ok else 1)
PY
[ "$fail" = 0 ] && echo "https/offline compose files: OK"
exit "$fail"
