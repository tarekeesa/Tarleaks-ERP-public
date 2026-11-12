#!/usr/bin/env bash
# =============================================================================
# Every app gets the secrets the hosted service gives it, or
# scripts/service-secrets.tsv says why not. Needs Docker and jq. Run by CI.
#
#   bash scripts/check-service-secrets.sh
#
# 1.2.0-rc.5 shipped with INTERNAL_API_TOKEN_SECRET given only to documents,
# contracts and the PDF tools, while the hosted service gives it to about
# twenty apps: every other app's internal call was refused (403), so the
# rental app never got Documents to retire customers' ID copies. The two lists
# drifted because nothing compared them.
#
# The table: VAR, decision, apps, why (tab-separated). `kit`: the kit gives it
# to the listed apps; an app written `!name` gets it on the hosted service but
# not from the kit, for the row's reason. `hosted`: only the hosted service
# uses it. `customer`: optional, the customer supplies it. `other`: the kit
# does the same another way (named in the why).
#
# Here: for each row decided `kit`, every container of the listed apps (the
# app and its `-jobs`) has the variable in the rendered compose file
# (`docker compose config`, every profile). Each release also compares the
# table with the hosted service's own list, so a new secret there fails the
# release until this table (and the compose file) say what the kit does.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
command -v jq >/dev/null || { echo "jq is needed"; exit 2; }
TABLE=scripts/service-secrets.tsv

norm() { printf '%s' "${1//_/-}"; }

json=$(docker compose --profile '*' -f docker-compose.yml --env-file .env.example config --format json)
# "service<TAB>VAR" for every variable of every service.
pairs=$(jq -r '.services | to_entries[] | .key as $s | (.value.environment // {} | keys[]) | "\($s)\t\(.)"' <<<"$json")
mapfile -t services < <(jq -r '.services | keys[]' <<<"$json")

declare -A svc has
for s in "${services[@]}"; do svc[$(norm "$s")]=1; done
while IFS=$'\t' read -r s v; do
  [ -n "$s" ] && has["$(norm "$s")|$v"]=1
done <<<"$pairs"

# The kit's apps: every service that is not a companion (`<app>-jobs`,
# `<app>-migrate`, ...) of another one.
declare -A app
for s in "${!svc[@]}"; do
  companion=0
  for o in "${!svc[@]}"; do
    if [ "$o" != "$s" ] && [[ "$s" == "$o"-* ]]; then companion=1; break; fi
  done
  [ "$companion" = 0 ] && app[$s]=1
done

errors=()
declare -A seen
kit_rows=0 rows=0 n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  case "$line" in ''|'#'*) continue ;; esac
  IFS=$'\t' read -r var decision apps why extra <<<"$line"
  if [ -z "${why:-}" ] || [ -n "${extra:-}" ]; then
    echo "$TABLE:$n: want 4 tab-separated columns (VAR, decision, apps, why)"; exit 1
  fi
  case "$decision" in kit|hosted|customer|other) ;; *)
    echo "$TABLE:$n: decision must be kit, hosted, customer or other, not '$decision'"; exit 1 ;;
  esac
  if [ -n "${seen[$var]:-}" ]; then echo "$TABLE:$n: $var is listed twice"; exit 1; fi
  seen[$var]=1
  rows=$((rows + 1))
  [ "$decision" = kit ] || continue
  kit_rows=$((kit_rows + 1))
  listed=0
  IFS=',' read -ra names <<<"$apps"
  for a in "${names[@]}"; do
    a=$(norm "$a")
    [[ "$a" == '!'* || "$a" == '-' ]] && continue
    listed=1
    if [ -z "${app[$a]:-}" ]; then
      errors+=("$var: the table names app '$a', which the kit does not have"); continue
    fi
    for s in "$a" "$a-jobs"; do
      if [ -n "${svc[$s]:-}" ] && [ -z "${has[$s|$var]:-}" ]; then
        errors+=("$s lacks $var (the hosted service gives it to $a)")
      fi
    done
  done
  [ "$listed" = 1 ] || { echo "$TABLE:$n: $var: a kit row names the apps"; exit 1; }
done <"$TABLE"

if [ "${#errors[@]}" -gt 0 ]; then
  echo "Service secrets differ from the hosted service:"
  printf '  - %s\n' "${errors[@]}" | sort
  exit 1
fi
echo "OK: $kit_rows secrets the kit gives, $rows rows"
