# shellcheck shell=bash
# =============================================================================
# Signing Docker in to the Tarleaks image registry with the licence key.
# Sourced by scripts/lib-apps.sh (so by install.sh and ./tarleaks);
# Windows: scripts/lib-registry.ps1.
#
# The images are at registry.tarleaks.com/tarleaks-erp/<unit>:<version>. The
# user name is `licence` and the password is the licence key, so nobody types
# `docker login`: every download (install, upgrade, apps add, editors on)
# signs in first, with the key read from
#   1. TARLEAKS_LICENSE_KEY in .env (or the older NEXUS_LICENSE_KEY),
#   2. the key the installation holds in its database (entered on the setup
#      screen or in Settings, Licence), when the database is running,
#   3. TARLEAKS_DOWNLOAD_KEY in .env: the trial the installer started.
# The key goes to Docker on stdin and to curl in a config read from stdin:
# never on a command line (other users can read those), never printed.
#
#   registry_value                 → TARLEAKS_REGISTRY (or the default)
#   registry_host                  → its host name
#   registry_takes_licence         → true for the Tarleaks registry
#   registry_licence_key           → the key to sign in with (may be empty)
#   registry_login "<command>"     → sign in (prints the fix and fails if not)
#   registry_tags <unit>           → the published tags of one image, one a
#                                     line (Tarleaks registry; read with the
#                                     licence key, like a download)
#   registry_start_trial co email  → a trial key from tarleaks.com, on stdout
#   registry_move_off_retired      → .env still names the retired default:
#                                     switch it, and re-tag the images here
#                                     (not when TARLEAKS_REGISTRY_KEEP=1)
#   registry_adopt_loaded          → stdin: `docker load` output; tags each
#                                     Tarleaks image under TARLEAKS_REGISTRY
#
# A registry you run yourself (TARLEAKS_REGISTRY=your.host/path) is left alone:
# sign Docker in to it the way that registry says.
# =============================================================================

REGISTRY_DEFAULT=registry.tarleaks.com/tarleaks-erp
# The private-preview location (1.0.x): the same images, behind a personal
# GitHub token. An .env that still names it is moved to the default.
REGISTRY_RETIRED=ghcr.io/tarekeesa/tarleaks-erp
# Registries that take the licence key. TARLEAKS_REGISTRY_LICENCE_HOSTS adds
# more (a Tarleaks staging registry), space-separated.
REGISTRY_LICENCE_HOSTS="registry.tarleaks.com"
REGISTRY_USER=licence
REGISTRY_SIGNED_IN=""

_reg_env() { [ -f .env ] && grep -E "^$1=" .env | tail -1 | cut -d= -f2- || true; }

_reg_set_env() { # key value — replace or append, keep everything else
  local tmp; tmp=$(mktemp)
  K="$1" V="$2" awk 'BEGIN{k=ENVIRON["K"]; v=ENVIRON["V"]; d=0} index($0, k "=") == 1 {print k"="v; d=1; next} {print} END{if(!d) print k"="v}' .env > "$tmp"
  cat "$tmp" > .env && rm -f "$tmp"
}

registry_value() {
  # The shell's value wins over .env, exactly as for docker compose.
  local v=${TARLEAKS_REGISTRY:-}
  [ -n "$v" ] || v=$(_reg_env TARLEAKS_REGISTRY)
  v=${v%/}
  printf '%s' "${v:-$REGISTRY_DEFAULT}"
}

registry_host() { local v; v=$(registry_value); printf '%s' "${v%%/*}"; }

registry_takes_licence() {
  local h; h=$(registry_host)
  case " $REGISTRY_LICENCE_HOSTS ${TARLEAKS_REGISTRY_LICENCE_HOSTS:-} " in
    *" $h "*) return 0 ;;
  esac
  return 1
}

# A licence key is one line of letters, digits, - _ and dots.
_reg_plausible_key() { printf '%s' "$1" | grep -qE '^(tlk1|nxs1)[.][A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)*$'; }

registry_licence_key() {
  local k user db
  k=$(_reg_env TARLEAKS_LICENSE_KEY)
  [ -n "$k" ] || k=$(_reg_env NEXUS_LICENSE_KEY)
  if [ -z "$k" ] && command -v docker >/dev/null 2>&1 \
     && docker compose ps --status running --services 2>/dev/null | grep -x postgres >/dev/null; then
    user=$(_reg_env POSTGRES_USER); db=$(_reg_env POSTGRES_DB)
    k=$(docker compose exec -T postgres psql -X -q -At -U "${user:-tarleaks}" -d "${db:-tarleaks}" \
          -c "SELECT token FROM auth.installation_state WHERE id AND token IS NOT NULL" 2>/dev/null \
        | head -1 | tr -d '\r') || k=""
  fi
  [ -n "$k" ] || k=$(_reg_env TARLEAKS_DOWNLOAD_KEY)
  printf '%s' "$k"
}

# The registry's own sign-in service, asked directly: its refusal is a
# sentence ("This licence ended on …"), which `docker login` would bury.
# Returns 0 (accepted), 1 (refused: message printed), 2 (could not ask).
_reg_check_key() { # host key
  local host=$1 key=$2 hdr realm service body code msg
  command -v curl >/dev/null 2>&1 || return 2
  hdr=$(curl -sS -I --max-time 15 ${REGISTRY_CURL_PROXY:+--proxy "$REGISTRY_CURL_PROXY"} "https://$host/v2/" 2>/dev/null | tr -d '\r') || return 2
  realm=$(printf '%s\n' "$hdr" | sed -n 's/^[Ww][Ww][Ww]-[Aa]uthenticate: *Bearer .*realm="\([^"]*\)".*/\1/p' | head -1)
  service=$(printf '%s\n' "$hdr" | sed -n 's/^[Ww][Ww][Ww]-[Aa]uthenticate: .*service="\([^"]*\)".*/\1/p' | head -1)
  [ -n "$realm" ] || return 2
  case "$realm" in https://*) ;; *) return 2 ;; esac
  body=$(mktemp)
  # The key travels in a curl config read from stdin, never on the command line.
  code=$(printf 'user = "%s:%s"\n' "$REGISTRY_USER" "$key" \
    | curl -sS -K - -G --max-time 20 ${REGISTRY_CURL_PROXY:+--proxy "$REGISTRY_CURL_PROXY"} \
        -o "$body" -w '%{http_code}' --data-urlencode "service=${service:-$host}" "$realm" 2>/dev/null) || code=000
  msg=$(sed -n 's/.*"error_description" *: *"\(\([^"\\]\|\\.\)*\)".*/\1/p' "$body" | head -1 | sed 's/\\"/"/g')
  rm -f "$body"
  case "$code" in
    200) return 0 ;;
    000) return 2 ;;
    429) echo "The image registry is busy for this address: ${msg:-too many sign-ins}. Wait a minute and run it again." >&2; return 1 ;;
    5*) echo "The image registry cannot check licence keys right now${msg:+: $msg}. Try again in a few minutes; if it lasts, contact info@tarleaks.com." >&2; return 1 ;;
    *) echo "The image registry did not accept the licence key: ${msg:-it was refused (HTTP $code)}" >&2; return 1 ;;
  esac
}

# The tags of registry.tarleaks.com/tarleaks-erp/<unit>, one a line: the
# releases ./tarleaks update can move to. Asks the registry's sign-in service
# for a read token with the licence key (in a curl config on stdin, never on a
# command line), then the Docker registry API for the tag list.
# Returns 0 (tags printed), 1 (refused: message printed), 2 (could not ask).
registry_tags() { # unit
  local unit=$1 host repo key hdr realm service tok body code
  command -v curl >/dev/null 2>&1 || return 2
  registry_takes_licence || return 2
  host=$(registry_host); repo=$(registry_value); repo=${repo#*/}
  key=$(registry_licence_key)
  _reg_plausible_key "$key" || { echo "No usable licence key in .env or in the installation, so the list of releases cannot be read. Give it with ./install.sh --licence-key <key>." >&2; return 1; }
  hdr=$(curl -sS -I --max-time 15 ${REGISTRY_CURL_PROXY:+--proxy "$REGISTRY_CURL_PROXY"} "https://$host/v2/" 2>/dev/null | tr -d '\r') || return 2
  realm=$(printf '%s\n' "$hdr" | sed -n 's/^[Ww][Ww][Ww]-[Aa]uthenticate: *Bearer .*realm="\([^"]*\)".*/\1/p' | head -1)
  service=$(printf '%s\n' "$hdr" | sed -n 's/^[Ww][Ww][Ww]-[Aa]uthenticate: .*service="\([^"]*\)".*/\1/p' | head -1)
  case "$realm" in https://*) ;; *) return 2 ;; esac
  body=$(mktemp)
  code=$(printf 'user = "%s:%s"\n' "$REGISTRY_USER" "$key" \
    | curl -sS -K - -G --max-time 20 ${REGISTRY_CURL_PROXY:+--proxy "$REGISTRY_CURL_PROXY"} -o "$body" -w '%{http_code}' \
        --data-urlencode "service=${service:-$host}" --data-urlencode "scope=repository:$repo/$unit:pull" "$realm" 2>/dev/null) || code=000
  tok=$(sed -n 's/.*"\(access_\)\{0,1\}token" *: *"\([^"]*\)".*/\2/p' "$body" | head -1)
  rm -f "$body"
  case "$code" in 200) ;; 000) return 2 ;; *) echo "The image registry did not accept the licence key (HTTP $code), so the list of releases cannot be read." >&2; return 1 ;; esac
  [ -n "$tok" ] || return 2
  body=$(mktemp)
  code=$(printf 'header = "Authorization: Bearer %s"\n' "$tok" \
    | curl -sS -K - --max-time 20 ${REGISTRY_CURL_PROXY:+--proxy "$REGISTRY_CURL_PROXY"} -o "$body" -w '%{http_code}' \
        "https://$host/v2/$repo/$unit/tags/list?n=1000" 2>/dev/null) || code=000
  if [ "$code" != 200 ]; then rm -f "$body"; [ "$code" = 000 ] && return 2; echo "The image registry answered HTTP $code for the list of releases." >&2; return 1; fi
  # {"name":"…","tags":["1.0.0","1.2.0-rc.2",…]} → one tag a line
  sed -n 's/.*"tags" *: *\[\([^]]*\)\].*/\1/p' "$body" | tr ',' '\n' | tr -d '" \t' | sed '/^$/d'
  rm -f "$body"
}

registry_login() { # "<command to run again>"
  local again=${1:-./install.sh} host key out rc
  [ "${TARLEAKS_NO_DOWNLOAD:-0}" = 1 ] && return 0
  registry_takes_licence || return 0
  host=$(registry_host)
  [ "$REGISTRY_SIGNED_IN" = "$host" ] && return 0
  key=$(registry_licence_key)
  if [ -z "$key" ]; then
    echo "Downloading Tarleaks ERP needs a licence key: it is also the download password. Give it with ./install.sh --licence-key <key>, or start a free trial: ./install.sh --trial you@yourcompany.com --company \"Your company\" --accept-terms. Then run $again again." >&2
    return 1
  fi
  if ! _reg_plausible_key "$key"; then
    echo "The licence key in .env (or in the installation) is damaged: it must be one line that starts with nxs1. or tlk1. Paste it again with ./install.sh --licence-key <key>." >&2
    return 1
  fi
  _reg_check_key "$host" "$key"; rc=$?
  if [ "$rc" = 1 ]; then
    echo "Nothing was downloaded. Fix the licence (Settings, Licence, or ./install.sh --licence-key <key>), then run $again again." >&2
    return 1
  fi
  if ! out=$(printf '%s' "$key" | docker login "$host" --username "$REGISTRY_USER" --password-stdin 2>&1); then
    if printf '%s' "$out" | grep -qiE 'timeout|dial tcp|no such host|connection refused|network is unreachable|i/o timeout|EOF'; then
      echo "Docker could not reach $host. Allow outbound HTTPS to $host and tarleaks.com (behind a company proxy, give Docker the proxy: examples/outbound-proxy), then run $again again." >&2
    elif printf '%s' "$out" | grep -qiE 'x509|certificate'; then
      echo "Docker did not accept the certificate of $host: a proxy is probably inspecting HTTPS. Ask your network team to exempt $host and tarleaks.com, then run $again again." >&2
    else
      printf '%s\n' "$out" | tail -2 >&2
      echo "Docker could not sign in to $host with the licence key (above). Run $again again; if it keeps failing, send this message to info@tarleaks.com." >&2
    fi
    return 1
  fi
  REGISTRY_SIGNED_IN=$host
  return 0
}

_reg_json() { # a JSON string: quotes and backslashes escaped, control characters dropped
  printf '"%s"' "$(printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

registry_start_trial() { # company email — prints the trial key; messages on stderr
  local company=$1 email=$2 vendor fp body code out msg arch
  vendor=$(_reg_env TARLEAKS_VENDOR_URL); vendor=${vendor:-https://tarleaks.com}; vendor=${vendor%/}
  command -v curl >/dev/null 2>&1 || { echo "curl is needed to start the trial. Install curl, or ask info@tarleaks.com for a licence key." >&2; return 1; }
  # Only for the vendor's records until the installation itself checks in:
  # its first check-in moves the trial to the installation's own identity.
  fp=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  arch=$(uname -m)
  body=$(printf '{"company":%s,"email":%s,"fingerprint":"%s","version":%s,"arch":%s,"accept_terms":true}' \
    "$(_reg_json "$company")" "$(_reg_json "$email")" "$fp" "$(_reg_json "$(_reg_env TARLEAKS_VERSION)")" "$(_reg_json "$arch")")
  out=$(mktemp)
  code=$(printf '%s' "$body" | curl -sS --max-time 30 ${REGISTRY_CURL_PROXY:+--proxy "$REGISTRY_CURL_PROXY"} \
      -H 'Content-Type: application/json' --data-binary @- -o "$out" -w '%{http_code}' \
      "$vendor/api/activation/trial" 2>/dev/null) || code=000
  if [ "$code" = 200 ]; then
    sed -n 's/.*"token" *: *"\([^"]*\)".*/\1/p' "$out" | head -1
    rm -f "$out"; return 0
  fi
  msg=$(sed -n 's/.*"message" *: *"\(\([^"\\]\|\\.\)*\)".*/\1/p' "$out" | head -1 | sed 's/\\"/"/g')
  rm -f "$out"
  if [ "$code" = 000 ]; then
    echo "Could not reach $vendor to start the trial. Allow outbound HTTPS to tarleaks.com (behind a proxy: HTTPS_PROXY), or ask info@tarleaks.com for a licence key." >&2
  else
    echo "The trial was not started: ${msg:-tarleaks.com answered HTTP $code}" >&2
  fi
  return 1
}

registry_move_off_retired() {
  local cur img n=0 keep
  cur=$(_reg_env TARLEAKS_REGISTRY); cur=${cur%/}
  [ "$cur" = "$REGISTRY_RETIRED" ] || return 0
  # TARLEAKS_REGISTRY_KEEP=1 keeps the address as written: a test machine that
  # reads the private-preview location with its own sign-in.
  keep=${TARLEAKS_REGISTRY_KEEP:-}; [ -n "$keep" ] || keep=$(_reg_env TARLEAKS_REGISTRY_KEEP)
  [ "$keep" = 1 ] && return 0
  _reg_set_env TARLEAKS_REGISTRY "$REGISTRY_DEFAULT"
  # The images already here keep their content; give them the new name too, so
  # nothing is downloaded again and an installation without internet still starts.
  if command -v docker >/dev/null 2>&1; then
    for img in $(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -F "$REGISTRY_RETIRED/" | grep -v ':<none>$'); do
      docker tag "$img" "$REGISTRY_DEFAULT/${img#"$REGISTRY_RETIRED"/}" 2>/dev/null && n=$((n + 1))
    done
  fi
  local note=""; [ "$n" = 0 ] || note="; $n image name(s) here moved over"
  echo "Images now come from $REGISTRY_DEFAULT, signed in with the licence key (no docker login any more)$note."
}

registry_adopt_loaded() { # stdin: the output of docker load
  local reg line img rest n=0
  reg=$(registry_value)
  while IFS= read -r line; do
    img=${line#Loaded image: }
    [ "$img" != "$line" ] || continue
    case "$img" in */tarleaks-erp/*:*) ;; *) continue ;; esac
    rest=${img##*/tarleaks-erp/}
    [ "$img" = "$reg/$rest" ] && continue
    docker tag "$img" "$reg/$rest" && n=$((n + 1))
  done
  [ "$n" = 0 ] || echo "Named $n image(s) for $reg (TARLEAKS_REGISTRY)."
}
