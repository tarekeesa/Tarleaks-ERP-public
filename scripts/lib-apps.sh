# shellcheck shell=bash
# =============================================================================
# Which apps run, and what they need — read from config/apps.tsv.
# Sourced by install.sh and ./tarleaks (Windows: scripts/lib-apps.ps1).
#
#   apps_resolve "hr,CRM,projects"   → hr,crm,project_management (or an error)
#   apps_closure "hr,crm"            → every app that must run, base included
#   apps_units   "<closure>"         → the services to start (COMPOSE_PROFILES)
#   apps_modules "<closure>"         → the apps the running services serve
#   apps_ram_mb  "<closure>"         → memory to plan for, platform included
#   apps_needed_by app "<chosen>"    → chosen apps that cannot run without app
#   apps_preset small|standard|full  → that preset's list of apps
#   apps_unreleased                  → apps whose image APPS_VERSION does not have
#                                       (newer than it, or withdrawn by then)
#   apps_addons  "<closure>"         → the editors to run, as ",onlyoffice,drawio…"
#   apps_sync_editors "<closure>"    → write the editors' addresses into .env
#
# APPS_VERSION is the release this installation runs (TARLEAKS_VERSION); the
# caller sets it. An app listed in config/app-releases.tsv with a later release
# is left out of the presets and refused by name: its image does not exist yet.
# =============================================================================

# Signing in to the image registry with the licence key (apps_pull does it).
# shellcheck source=scripts/lib-registry.sh
. scripts/lib-registry.sh
# Checking the Tarleaks signature of what was downloaded (apps_pull does it).
# shellcheck source=scripts/lib-signature.sh
. scripts/lib-signature.sh

APPS_SHEET=${APPS_SHEET:-config/apps.tsv}
APPS_RELEASES=${APPS_RELEASES:-config/app-releases.tsv}
APPS_VERSION=${APPS_VERSION:-}

APPS_PRESET_SMALL="hr,recruitment,attendance,payroll,accounting,crm,inventory,sales_orders,chat"
APPS_PRESET_STANDARD="$APPS_PRESET_SMALL,project_management,lms,gamification,assets,helpdesk,fleet,correspondence,pos,rental,subscriptions,procurement,construction,contracts"
APPS_PRESET_FULL="$APPS_PRESET_STANDARD,pdftools,diagrams,imtithal,iso42001"

apps_preset() {
  local list
  case "$1" in
    small) list=$APPS_PRESET_SMALL ;;
    standard) list=$APPS_PRESET_STANDARD ;;
    full) list=$APPS_PRESET_FULL ;;
    *) return 1 ;;
  esac
  _apps_without "$list" "$(apps_unreleased)"
}

# The list without the apps in the second list (order kept).
_apps_without() {
  awk -v list="$1" -v drop="$2" 'BEGIN {
    n = split(drop, d, ","); for (i = 1; i <= n; i++) x[d[i]] = 1
    n = split(list, l, ","); out = ""
    for (i = 1; i <= n; i++) if (l[i] != "" && !(l[i] in x)) out = out (out ? "," : "") l[i]
    printf "%s", out }'
}

# The first release that publishes the `onlyoffice` image (Document Server with
# Arabic fonts), and what an older release runs instead. The stock pin moves
# with ONLYOFFICE_IMAGE in docker-compose.yml.
APPS_ONLYOFFICE_OWN_IMAGE_FROM=1.2.0
APPS_ONLYOFFICE_STOCK_IMAGE=onlyoffice/documentserver:9.4.0.1

# Is version $1 older than version $2? (pre-release suffixes ignored)
_apps_version_older() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    sub(/-.*/, "", a); sub(/-.*/, "", b)
    n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
    for (i = 1; i <= n; i++) { p = x[i] + 0; q = y[i] + 0; if (p < q) exit 0; if (p > q) exit 1 }
    exit 1 }'
}

# "app<TAB>first<TAB>withdrawn" for every app whose image APPS_VERSION does not
# have: newer than it, or withdrawn in it or an earlier release (the third
# field is empty unless the app was withdrawn).
_apps_unreleased_rows() {
  [ -n "$APPS_VERSION" ] && [ -f "$APPS_RELEASES" ] || return 0
  awk -v v="$APPS_VERSION" '
    function older(a, b,   x, y, n, i, p, q) {   # is version a older than b?
      sub(/-.*/, "", a); sub(/-.*/, "", b)
      n = split(a, x, "."); if (split(b, y, ".") > n) n = split(b, y, ".")
      for (i = 1; i <= n; i++) { p = x[i] + 0; q = y[i] + 0; if (p < q) return 1; if (p > q) return 0 }
      return 0
    }
    !/^[[:space:]]*#/ && NF >= 2 && older(v, $2) { printf "%s\t%s\t\n", $1, $2; next }
    !/^[[:space:]]*#/ && NF >= 3 && !older(v, $3) { printf "%s\t%s\t%s\n", $1, $2, $3 }' "$APPS_RELEASES"
}
apps_unreleased() { _apps_unreleased_rows | cut -f1 | paste -sd, -; }
# The same split in two: apps that arrive with a NEWER release, and apps this
# release (or an earlier one) took out again.
apps_not_yet() { _apps_unreleased_rows | awk -F'\t' '$3 == "" {print $1}' | paste -sd, -; }
apps_withdrawn() { _apps_unreleased_rows | awk -F'\t' '$3 != "" {print $1}' | paste -sd, -; }

# The sheet without comments: app kind unit needs works_with aliases ram name…
_apps_rows() { awk '!/^[[:space:]]*#/ && NF >= 8' "$APPS_SHEET"; }

# Turn what a person typed into licence names. Unknown words → message on
# stderr, exit status 1. Accepts commas or spaces, any case, and the aliases.
_apps_resolve_names() {
  _apps_rows | awk -v want="$1" '
    { name[$1] = 1; kind[$1] = $2; n = split($6, a, ","); for (i = 1; i <= n; i++) if (a[i] != "-") alias[a[i]] = $1 }
    END {
      gsub(/[ \t]+/, ",", want); n = split(tolower(want), w, ","); out = ""; bad = ""
      for (i = 1; i <= n; i++) {
        x = w[i]; gsub(/-/, "_", x); if (x == "") continue
        if (x in alias) x = alias[x]
        if (!(x in name) || kind[x] == "platform" || kind[x] == "addon") { bad = bad (bad ? ", " : "") w[i]; continue }
        if (!(x in seen)) { seen[x] = 1; out = out (out ? "," : "") x }
      }
      if (bad != "") { print "Unknown app: " bad ". See the list with: ./tarleaks apps" > "/dev/stderr"; exit 1 }
      print out
    }' || return 1
}

apps_resolve() {
  local apps late closure a since gone names="" withdrawn=""
  apps=$(_apps_resolve_names "$1") || return 1
  late=$(_apps_unreleased_rows)
  [ -n "$late" ] || { printf '%s\n' "$apps"; return 0; }
  # Refuse an app whose image this release does not have, or one that needs it.
  closure=$(apps_closure "$apps")
  for a in ${closure//,/ }; do
    since=$(printf '%s\n' "$late" | awk -F'\t' -v a="$a" '$1 == a {print $2}')
    gone=$(printf '%s\n' "$late" | awk -F'\t' -v a="$a" '$1 == a {print $3}')
    if [ -n "$gone" ]; then
      withdrawn="$withdrawn${withdrawn:+, }$(apps_names "$a") (taken out in release $gone while it is rebuilt; it returns in a later release)"
    elif [ -n "$since" ]; then
      names="$names${names:+, }$(apps_names "$a") (from release $since)"
    fi
  done
  if [ -n "$withdrawn" ]; then
    echo "Not in release $APPS_VERSION: $withdrawn. Choose other apps." >&2
    return 1
  fi
  if [ -n "$names" ]; then
    echo "Not in release $APPS_VERSION yet: $names. Choose other apps, or update to that release first." >&2
    return 1
  fi
  printf '%s\n' "$apps"
}

# Everything that must run for the chosen apps: the apps, what they need (all
# the way down) and the base apps. In the sheet's order.
apps_closure() {
  _apps_rows | awk -v want="$1" '
    { order[++rows] = $1; kind[$1] = $2; needs[$1] = $4 }
    END {
      n = split(want, w, ","); top = 0
      for (i = 1; i <= n; i++) if (w[i] != "") stack[++top] = w[i]
      for (r = 1; r <= rows; r++) if (kind[order[r]] == "base") stack[++top] = order[r]
      while (top > 0) {
        a = stack[top--]
        if (a in in_set) continue
        in_set[a] = 1
        if (needs[a] != "-") { m = split(needs[a], d, ","); for (j = 1; j <= m; j++) stack[++top] = d[j] }
      }
      out = ""
      for (r = 1; r <= rows; r++) if ((order[r] in in_set) && kind[order[r]] != "platform" && kind[order[r]] != "addon") out = out (out ? "," : "") order[r]
      print out
    }'
}

# The services to start beyond the always-on ones: one compose profile per unit
# of a chosen (non-base) app.
apps_units() {
  _apps_rows | awk -v set="$1" '
    BEGIN { n = split(set, s, ","); for (i = 1; i <= n; i++) want[s[i]] = 1 }
    ($1 in want) && $2 == "app" && !($3 in seen) { seen[$3] = 1; out = out (out ? "," : "") $3 }
    END { print out }'
}

# Every app a running service serves (HR brings Recruitment: same service).
apps_modules() {
  local units; units=$(apps_units "$1")
  _apps_rows | awk -v units="$units" '
    BEGIN { n = split(units, u, ","); for (i = 1; i <= n; i++) run[u[i]] = 1 }
    $2 == "base" || ($2 == "app" && ($3 in run)) { out = out (out ? "," : "") $1 }
    END { print out }'
}

# Memory to plan for (MB): the platform, the base apps, each running unit once
# and the editors that run with them.
apps_ram_mb() {
  local units; units="$(apps_units "$1"),$(apps_addon_units "$1")"
  _apps_rows | awk -v units="$units" '
    BEGIN { n = split(units, u, ","); for (i = 1; i <= n; i++) run[u[i]] = 1 }
    $2 == "platform" || $2 == "base" || (($2 == "app" || $2 == "addon") && ($3 in run)) { if (!($3 in counted)) { counted[$3] = 1; t += $7 } }
    END { print t + 0 }'
}

# Chosen apps that need `app` (directly or further down), so it cannot go.
apps_needed_by() {
  local target=$1 chosen=$2 a closure out=""
  for a in ${chosen//,/ }; do
    [ "$a" = "$target" ] && continue
    closure=$(apps_closure "$a")
    case ",$closure," in *",$target,"*) out="$out${out:+, }$a" ;; esac
  done
  printf '%s' "$out"
}

# The on-screen name of each app in a list, joined with ", ".
apps_names() {
  _apps_rows | awk -v set="$1" '
    BEGIN { n = split(set, s, ","); for (i = 1; i <= n; i++) pos[s[i]] = i }
    ($1 in pos) { name = $8; for (i = 9; i <= NF; i++) name = name " " $i; nm[pos[$1]] = name }
    END { out = ""; for (i = 1; i <= n; i++) if (i in nm) out = out (out ? ", " : "") nm[i]; print out }'
}

# A table of every app for `./tarleaks apps`: chosen ones marked.
apps_table() {
  local chosen=$1 running=$2
  _apps_rows | awk -v chosen="$chosen" -v running="$running" '
    BEGIN {
      n = split(chosen, c, ","); for (i = 1; i <= n; i++) ch[c[i]] = 1
      n = split(running, r, ","); for (i = 1; i <= n; i++) rn[r[i]] = 1
      printf "  %-3s %-20s %-38s %s\n", "", "APP", "NAME", "NEEDS"
    }
    $2 == "platform" || $2 == "addon" { next }
    {
      name = $8; for (i = 9; i <= NF; i++) name = name " " $i
      mark = ($1 in ch) ? "[x]" : (($1 in rn) ? "(+)" : "[ ]")
      if ($2 == "base") mark = "(b)"
      printf "  %-3s %-20s %-38s %s\n", mark, $1, name, ($4 == "-" ? "" : $4)
    }'
}

# Stop and remove the containers of services no chosen app needs any more
# (compose leaves them running when their profile is switched off). Their data
# stays in the database and the file store; adding the app again brings it back.
apps_stop_unselected() {
  local want svc id project
  want=$(docker compose config --services 2>/dev/null) || return 0
  # The project name (`name:` in docker-compose.yml, or COMPOSE_PROJECT_NAME).
  project=$(docker compose config 2>/dev/null | sed -n 's/^name: *//p' | head -1)
  [ -n "$project" ] || return 0
  for svc in $(docker ps -a --filter "label=com.docker.compose.project=$project" \
                 --format '{{.Label "com.docker.compose.service"}}' | sort -u); do
    printf '%s\n' "$want" | grep -qx "$svc" && continue
    for id in $(docker ps -aq --filter "label=com.docker.compose.project=$project" \
                  --filter "label=com.docker.compose.service=$svc"); do
      docker rm -f "$id" >/dev/null
    done
    printf '  stopped %s (no chosen app needs it; its data is kept)\n' "$svc"
  done
}

# The editors (rows of kind `addon` in config/apps.tsv): the document editor of
# Documents and the diagram editor of Diagrams. They run next to
# the apps that use them. TARLEAKS_EDITORS=off in .env (./tarleaks editors off)
# switches them all off; an editor whose image is newer than the release
# (config/app-releases.tsv) is left out.
apps_editors() {
  local v=${APPS_EDITORS:-}
  [ -n "$v" ] || v=$(grep -E '^TARLEAKS_EDITORS=' .env 2>/dev/null | tail -1 | cut -d= -f2-)
  [ "$v" = off ] && printf off || printf on
}

# The editors to run for a closure: "onlyoffice,drawio" (no leading comma).
apps_addon_units() {
  [ "$(apps_editors)" = off ] && return 0
  local late; late=$(apps_unreleased)
  _apps_rows | awk -v set="$1" -v late="$late" '
    BEGIN {
      n = split(set, s, ","); for (i = 1; i <= n; i++) have[s[i]] = 1
      n = split(late, l, ","); for (i = 1; i <= n; i++) skip[l[i]] = 1
    }
    $2 == "addon" && !($1 in skip) && !($3 in seen) {
      n = split($4, d, ","); for (i = 1; i <= n; i++) if (d[i] in have) { seen[$3] = 1; out = out (out ? "," : "") $3; break }
    }
    END { print out }'
}

# The editors as compose profiles, with a leading comma, so writing
# COMPOSE_PROFILES from the app list adds them: "$(apps_units ...)$(apps_addons ...)".
apps_addons() {
  local u; u=$(apps_addon_units "$1")
  [ -n "$u" ] && printf ',%s' "$u"
  return 0
}

# Write where the editors answer into .env (needs set_env from the caller): the
# address people's browsers use. Empty
# means "no such editor here", which the apps then say plainly. Recomputed on
# every start, so a changed TARLEAKS_URL is followed.
apps_sync_editors() {
  local units base
  units=$(apps_addon_units "$1")
  base=$(grep -E '^TARLEAKS_URL=' .env 2>/dev/null | tail -1 | cut -d= -f2-)
  base=${base%/}
  # The document editor's image: the release's own (Arabic fonts) from 1.2.0;
  # a release before that has none, so it keeps the stock Document Server.
  if [ -n "$APPS_VERSION" ] && _apps_version_older "$APPS_VERSION" "$APPS_ONLYOFFICE_OWN_IMAGE_FROM"; then
    set_env TARLEAKS_ONLYOFFICE_IMAGE "$APPS_ONLYOFFICE_STOCK_IMAGE"
  else
    set_env TARLEAKS_ONLYOFFICE_IMAGE ""
  fi
  case ",$units," in *,onlyoffice,*) set_env TARLEAKS_ONLYOFFICE_URL "$base/onlyoffice" ;; *) set_env TARLEAKS_ONLYOFFICE_URL "" ;; esac
  case ",$units," in *,drawio,*) set_env TARLEAKS_DRAWIO_URL "$base/drawio/" ;; *) set_env TARLEAKS_DRAWIO_URL "" ;; esac
}

# Images the chosen services run that are not on this machine (one per line).
_apps_missing_images() {
  local images img
  images=$(docker compose config --images) || return 2
  for img in $(printf '%s\n' "$images" | sort -u); do
    docker image inspect "$img" >/dev/null 2>&1 || printf '%s\n' "$img"
  done
}

# A pull that failed because the connection dropped (worth trying again), not
# because something refused it (licence, missing release or platform, disk, a
# certificate): then trying again cannot help.
_apps_pull_dropped() {
  grep -qiE 'unauthorized|denied|authentication required|manifest unknown|not found|no matching manifest|does not match the specified platform|no space left on device|x509|certificate|toomanyrequests|rate limit' "$1" && return 1
  grep -qiE 'timeout|timed out|dial tcp|no such host|connection refused|connection reset|network is unreachable|EOF|TLS handshake|broken pipe|503 Service Unavailable|502 Bad Gateway' "$1"
}

# The last thing Docker said about a failed pull, on one line (no secrets: Docker
# prints image names, addresses and the error, never a password).
_apps_pull_reason() {
  grep -v '^[[:space:]]*$' "$1" | tail -1 | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//' | cut -c1-300
}

# Download the images for the services that will run, and turn the usual
# failures into a sentence with the fix. Returns non-zero after printing it:
# 3 when the signature check refused the images (not signed by Tarleaks, or images
# already here that this machine never checked: scripts/lib-signature.sh).
#   apps_pull "./install.sh"     (the command to run again, for the message)
apps_pull() {
  local again=$1 log missing moved
  # An .env from the private preview still names ghcr.io: move it (and the
  # images already here) to the licence-key registry first.
  moved=$(registry_move_off_retired) && [ -n "$moved" ] && echo "$moved"
  # No download (TARLEAKS_NO_DOWNLOAD=1, set by --offline): no download at all; every
  # image must already be here (./tarleaks load-bundle <folder>).
  if [ "${TARLEAKS_NO_DOWNLOAD:-0}" = 1 ]; then
    echo "Offline: using the images already on this machine (no download)."
    missing=$(_apps_missing_images) || { echo "Could not read the list of images from docker-compose.yml." >&2; return 1; }
    # Images already here run only when this machine checked their signature (a signed bundle, an earlier download).
    if [ -z "$missing" ]; then sig_require_verified "$again" || return 3; return 0; fi
    echo "Not on this machine:" >&2; printf '%s\n' "$missing" | sed 's/^/  /' >&2
    echo "Load the offline bundle for this release first (./tarleaks load-bundle <folder>), then run $again --offline again. See docs/faq.md, \"Can I install without internet?\"" >&2
    return 1
  fi
  # The licence key is the download password: sign Docker in first, so a
  # refused key says why before anything is downloaded.
  if ! registry_login "$again"; then
    if missing=$(_apps_missing_images) && [ -z "$missing" ]; then
      echo "Carrying on with the images already on this machine." >&2
      sig_require_verified "$again" || return 3
      return 0
    fi
    return 1
  fi
  log=$(mktemp)
  # A dropped connection halfway through a download (a reset, a timeout, an
  # unexpected EOF from the registry or Docker Hub) is usually gone a few
  # seconds later, and Docker keeps the layers it already has: try again twice
  # before giving up. Refusals (licence, missing release, disk) are not retried.
  local try=1
  while ! docker compose pull --quiet 2>"$log"; do
    if [ "$try" -ge "${TARLEAKS_PULL_TRIES:-3}" ] || ! _apps_pull_dropped "$log"; then try=0; break; fi
    echo "The download was interrupted ($(_apps_pull_reason "$log")). Trying again in ${TARLEAKS_PULL_WAIT:-10} seconds; what is already downloaded is kept." >&2
    sleep "${TARLEAKS_PULL_WAIT:-10}"; try=$((try + 1))
  done
  # Downloaded: run nothing that Tarleaks did not sign (scripts/lib-signature.sh).
  # Exit 3 when the signature check refused them (the caller must not fall back to them).
  [ "$try" = 0 ] || { rm -f "$log"; sig_verify_images "$again" || return 3; return 0; }
  # The download failed, but every image may already be here (an offline
  # bundle was loaded): carry on with those.
  if missing=$(_apps_missing_images) && [ -z "$missing" ]; then
    echo "The download failed, but every image is already on this machine. Carrying on with those." >&2
    rm -f "$log"; sig_require_verified "$again" || return 3; return 0
  fi
  local version=${TARLEAKS_VERSION:-}; [ -n "$version" ] || version=$(grep -E "^TARLEAKS_VERSION=" .env 2>/dev/null | tail -1 | cut -d= -f2-)
  local reg_host; reg_host=$(registry_host)
  if grep -qiE 'unauthorized|denied|authentication required' "$log"; then
    if registry_takes_licence; then
      echo "The registry refused the download with this licence key. Check the licence (Settings, Licence, or ./tarleaks status), then run $again again; if it keeps failing, contact info@tarleaks.com." >&2
    else
      echo "The registry $reg_host refused the download. Sign Docker in to it the way that registry says (docker login $reg_host), then run $again again." >&2
    fi
  elif grep -qiE 'no matching manifest|does not match the specified platform' "$log"; then
    echo "An image is not published for this CPU ($(uname -m)). Tarleaks ERP runs on 64-bit Intel/AMD and 64-bit ARM; check that DOCKER_DEFAULT_PLATFORM is not set (echo \$DOCKER_DEFAULT_PLATFORM must print nothing)." >&2
  elif grep -qiE 'manifest unknown|not found|manifest for .* not found' "$log"; then
    local img; img=$(grep -oiE '[a-z0-9./_-]+:[A-Za-z0-9._-]+' "$log" | grep -i tarleaks | head -1)
    echo "Release ${version:-?} has no image ${img:-for one of the chosen apps}. Check TARLEAKS_VERSION in .env (the release notes list the versions), or remove that app: ./tarleaks apps remove <app>." >&2
  elif grep -qiE 'toomanyrequests|rate limit' "$log" && grep -qF "$reg_host" "$log"; then
    echo "The image registry is busy for this address (too many downloads in a minute). Wait a minute, then run $again again." >&2
  elif grep -qiE 'toomanyrequests|rate limit' "$log"; then
    echo "Docker Hub limits anonymous downloads and this address has reached the limit. Wait a few hours, or sign in with a free Docker account (docker login), then run $again again." >&2
  elif grep -qiE 'no space left on device' "$log"; then
    echo "The disk is full. Free space (docker system df; docker image prune), then run $again again." >&2
  elif grep -qiE 'x509|certificate' "$log"; then
    echo "A certificate was not accepted while downloading: a proxy is probably inspecting HTTPS. Ask your network team to exempt $reg_host and Docker Hub, or set up Docker with your proxy (examples/outbound-proxy), then run $again again." >&2
  elif grep -qiE 'timeout|dial tcp|no such host|connection refused|network is unreachable|i/o timeout|EOF' "$log"; then
    echo "Docker said: $(_apps_pull_reason "$log")" >&2
    echo "The server could not reach the image registries. Allow outbound HTTPS to $reg_host, tarleaks.com, registry-1.docker.io and production.cloudflare.docker.com (behind a company proxy: examples/outbound-proxy), then run $again again." >&2
  else
    cat "$log" >&2
    echo "Downloading the images failed (see above). Check the internet connection and run $again again." >&2
  fi
  rm -f "$log"
  return 1
}
