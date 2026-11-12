#!/usr/bin/env bash
# =============================================================================
# The app sheet (config/apps.tsv), the compose file and the gateway routes must
# agree, or choosing an app starts nothing, starts the wrong thing, or starts a
# service the gateway cannot reach. Run by CI; run it after editing any of them.
#
#   bash scripts/check-apps.sh
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib-apps.sh
. scripts/lib-apps.sh

fail=0
bad() { printf '::error::%s\n' "$*"; fail=1; }

rows=$(awk '!/^[[:space:]]*#/ && NF' config/apps.tsv)
short=$(printf '%s\n' "$rows" | awk 'NF < 8 {print $1}')
[ -z "$short" ] || bad "apps.tsv rows with fewer than 8 columns: $short"
names=" $(printf '%s\n' "$rows" | awk '{print $1}' | tr '\n' ' ') "

# 1. Every app the sheet names in needs / works_with exists, and kinds are known.
while read -r app kind unit needs works _aliases ram _name; do
  case "$kind" in platform|base|app|addon) ;; *) bad "$app: unknown kind '$kind'" ;; esac
  case "$ram" in ''|*[!0-9]*) bad "$app: ram_mb '$ram' is not a number" ;; esac
  for d in ${needs//,/ } ${works//,/ }; do
    [ "$d" = - ] && continue
    case "$names" in *" $d "*) ;; *) bad "$app names '$d', which is not in the sheet" ;; esac
  done
  [ -n "$unit" ] || bad "$app has no unit"
done <<<"$rows"

# 2. Compose: base and platform units run without a profile; each app unit has
#    exactly its own profile; no product service is missing from the sheet.
compose_profile() { # service → its profiles line, or "-" when always on, "?" when absent
  awk -v s="$1" '
    $0 ~ "^  " s ":$" { inb = 1; found = 1; next }
    inb && /^  [a-z]/ { inb = 0 }
    inb && /^    profiles:/ { sub(/^    profiles: */, ""); p = $0 }
    END { if (!found) print "?"; else if (p == "") print "-"; else print p }' docker-compose.yml
}
while read -r app kind unit _rest; do
  p=$(compose_profile "$unit")
  case "$kind" in
    platform|base) [ "$p" = - ] || bad "$app ($kind): service '$unit' must run without a profile, has $p" ;;
    app|addon) [ "$p" = "[$unit]" ] || bad "$app: service '$unit' must have 'profiles: [$unit]', has '$p'" ;;
  esac
done <<<"$rows"
units=" $(printf '%s\n' "$rows" | awk '{print $3}' | tr '\n' ' ') "
for svc in $(grep -E '^  [a-z][a-z0-9_-]*:$' docker-compose.yml | tr -d ' :'); do
  img=$(awk -v s="$svc" '$0 ~ "^  " s ":$" {inb=1; next} inb && /^  [a-z]/ {inb=0} inb && /^    image:/ {print; exit}' docker-compose.yml)
  case "$img" in *TARLEAKS_REGISTRY*) ;; *) continue ;; esac
  case "$svc" in
    migrate) continue ;;
    # A service's one-shot database step and its scheduled jobs run with the
    # service: same image, same profile.
    *-migrate|*-jobs)
      base=${svc%-migrate}; base=${base%-jobs}
      case "$units" in *" $base "*) ;; *) bad "compose service '$svc' belongs to no unit ('$base' is not in apps.tsv)" ;; esac
      [ "$(compose_profile "$svc")" = "$(compose_profile "$base")" ] \
        || bad "$svc must have the same profile as $base ('$(compose_profile "$base")'), has '$(compose_profile "$svc")'"
      case "$img" in *"/$base:"*) ;; *) bad "$svc must run the $base image, runs: $img" ;; esac
      continue ;;
  esac
  case "$units" in *" $svc "*) ;; *) bad "compose service '$svc' runs a product image but no app in apps.tsv names it as its unit" ;; esac
done

# 3. Gateway: every unit that answers HTTP has a backend in routes.yml.
while read -r app kind unit _rest; do
  case "$unit" in postgres|redis|rabbitmq|objects|gateway|authproxy|web) continue ;; esac
  grep -qE "^    $unit:\$" <(sed -n '/^  services:/,$p' config/traefik/dynamic/routes.yml) \
    || bad "$app: the gateway has no service '$unit' in config/traefik/dynamic/routes.yml"
done <<<"$rows"

# 3b. What each app needs matches the product. config/dependencies.tsv is
#     generated in the product repository from its own code and copied here
#     with every release; apps.tsv must agree with it, app by app.
if [ -f config/dependencies.tsv ]; then
  while read -r app kind unit needs _rest; do
    [ "$kind" = platform ] && continue
    [ "$kind" = addon ] && continue   # editors are the kit's own, not product apps
    # An app a release took out (app-releases.tsv, third column) is not in that
    # release's sheet; the kit keeps it for the releases that have it.
    awk -v a="$app" '!/^[[:space:]]*#/ && $1 == a && NF >= 3 {f=1} END {exit !f}' config/app-releases.tsv && continue
    line=$(awk -v a="$app" -F'\t' '!/^#/ && $1 == a' config/dependencies.tsv)
    [ -n "$line" ] || { bad "$app is not in config/dependencies.tsv (copy the file from the release)"; continue; }
    p_unit=$(printf '%s' "$line" | cut -f2); p_needs=$(printf '%s' "$line" | cut -f3)
    norm() { printf '%s' "$1" | tr ',' '\n' | grep -v '^-$' | sort | tr '\n' ','; }
    [ "$p_unit" = "$unit" ] || bad "$app: apps.tsv runs it in '$unit', the product in '$p_unit'"
    [ "$(norm "$needs")" = "$(norm "$p_needs")" ] || bad "$app: apps.tsv says it needs '$needs', the product says '$p_needs'"
  done <<<"$rows"
fi

# 3c. The editors: each addon's unit has a service with its profile (checked
#     above); the gateway sign-in check goes through the keep-alive proxy, which
#     the compose file must define; the proxy of the document editor too.
grep -q 'address: http://authproxy:8099/internal/authorize' config/traefik/dynamic/routes.yml \
  || bad "routes.yml: the sign-in check (forwardAuth address) must go through http://authproxy:8099/internal/authorize (QA-PERF-04)"
[ "$(compose_profile authproxy)" = - ] || bad "compose service 'authproxy' must run without a profile"
[ "$(compose_profile onlyoffice-proxy)" = "[onlyoffice]" ] || bad "compose service 'onlyoffice-proxy' must have 'profiles: [onlyoffice]'"
grep -qE '^    onlyoffice:$' <(sed -n '/^  services:/,$p' config/traefik/dynamic/routes.yml) \
  || bad "routes.yml has no backend service 'onlyoffice' (the editor's proxy)"

# 4. Presets resolve, and every preset brings what its apps need.
for p in small standard full; do
  apps_resolve "$(apps_preset "$p")" >/dev/null || bad "preset $p names an unknown app"
done

# 5. config/app-releases.tsv names real apps and real versions, and on the
#    oldest release every preset still resolves without them (no preset may need
#    an app whose image that release does not have).
while read -r app since gone _rest; do
  case "$names" in *" $app "*) ;; *) bad "app-releases.tsv names '$app', which is not in apps.tsv" ;; esac
  printf '%s' "$since" | grep -qE '^[0-9]+[.][0-9]+[.][0-9]+$' || bad "app-releases.tsv: '$since' is not a version like 1.2.0"
  if [ -n "$gone" ]; then
    printf '%s' "$gone" | grep -qE '^[0-9]+[.][0-9]+[.][0-9]+$' || bad "app-releases.tsv: '$gone' (withdrawn in) is not a version like 1.2.0"
    _apps_version_older "$gone" "$since" && bad "app-releases.tsv: $app is withdrawn in $gone, before its first release $since"
  fi
done < <(awk '!/^[[:space:]]*#/ && NF' config/app-releases.tsv)
for p in small standard full; do
  list=$(APPS_VERSION=1.0.0 apps_preset "$p")
  for a in $(APPS_VERSION=1.0.0 apps_unreleased | tr ',' ' '); do
    case ",$list," in *",$a,"*) bad "preset $p keeps $a on release 1.0.0" ;; esac
  done
  ( APPS_VERSION=1.0.0; apps_resolve "$list" >/dev/null ) || bad "preset $p does not resolve on release 1.0.0"
done
( APPS_VERSION=1.0.0; apps_resolve procurement >/dev/null 2>&1 ) && bad "release 1.0.0 accepted procurement, whose image it does not have"
# Diagram Studio is back: no row in app-releases.tsv, so every release accepts
# it by name and the full preset (and its editor list) brings it.
( APPS_VERSION=1.0.0; apps_resolve diagrams >/dev/null ) || bad "release 1.0.0 refused diagrams, which it has"
( APPS_VERSION=1.2.0; apps_resolve diagrams >/dev/null 2>&1 ) || bad "release 1.2.0 refused diagrams, which it has again"
for v in 1.0.0 1.2.0; do
  case ",$(APPS_VERSION=$v apps_preset full)," in *",diagrams,"*) ;; *) bad "preset full lacks diagrams on release $v" ;; esac
done

# 6. The document editor runs the release's own image (Arabic fonts),
#    and the pin an older release falls back to is the one compose names.
grep -qE 'onlyoffice:\$\{TARLEAKS_VERSION' docker-compose.yml \
  || bad "docker-compose.yml: the onlyoffice service must default to the release's own image (<registry>/onlyoffice:\${TARLEAKS_VERSION})"
stock=$(sed -n 's/^APPS_ONLYOFFICE_STOCK_IMAGE=//p' scripts/lib-apps.sh)
grep -qF "$stock" scripts/lib-apps.ps1 || bad "scripts/lib-apps.ps1 does not use the stock editor pin $stock that lib-apps.sh falls back to"
grep -qF "$stock" docs/configuration.md || true

[ "$fail" = 0 ] && echo "OK: apps.tsv, docker-compose.yml and the gateway routes agree ($(printf '%s\n' "$rows" | wc -l | tr -d ' ') rows)."
exit "$fail"
