#!/usr/bin/env bash
# =============================================================================
# Tarleaks ERP installer — Linux and macOS (Windows: install.ps1).
#
#   ./install.sh                       # interactive, sensible defaults
#   ./install.sh --yes                 # accept every default (CI, scripts)
#   ./install.sh --host 192.168.1.20   # reachable from the office network
#   ./install.sh --apps hr,crm         # only these apps (+ what they need)
#   ./install.sh --profile small       # a preset: small | standard | full
#   ./install.sh --port 8080           # when port 80 is taken
#   ./install.sh --bind local          # only this computer (network: everyone);
#                                      # without it the installer decides: see below
#   ./install.sh --editors off         # no document/diagram editors (saves ~2 GB)
#   ./install.sh --licence-key nxs1…   # your licence key (none: remove it); it is
#                                      # also the password for downloading
#   ./install.sh --trial you@company.com --company "Name" --accept-terms
#                                      # no key yet: start the 30-day free trial
#   ./install.sh --offline             # no download: use the images already
#                                      # here (./tarleaks load-bundle first)
#   ./install.sh --profile-env local   # local: this computer or the office
#                                      # network over http (the default)
#   ./install.sh --profile-env production --host erp.example.com \
#       --tls letsencrypt --acme-email it@example.com
#                                      # production: a real domain, HTTPS only;
#                                      # --tls letsencrypt | cloudflare | proxy
#                                      # (cloudflare reads CF_DNS_API_TOKEN from
#                                      # the environment; docs/https.md)
#   ./install.sh --no-start            # write .env only
#   COMPOSE_PROJECT_NAME=erp2 ./install.sh --port 8080
#                                      # a SECOND installation on this machine
#                                      # (its own name, data and port)
#
# Safe to run again: an existing .env keeps its keys and passwords; only the
# options you pass change.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

# ---- Output -----------------------------------------------------------------
if [ -t 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=""; G=""; Y=""; R=""; N=""
fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

# ---- Options ----------------------------------------------------------------
PROFILE=auto
APPS=""
HOST=""
PORT=""
VERSION=""
LICENCE=""
BIND=""
EDITORS=""
YES=0
START=1
OFFLINE=0
TRIAL_EMAIL=""
COMPANY=""
ACCEPT_TERMS=0
PROFILE_ENV=""
TLS=""
ACME_EMAIL=""

usage() { sed -n '2,/^# ====/p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
# An option that needs a value: say so plainly when it is missing.
need() { [ $# -ge 2 ] && [ -n "$2" ] || die "$1 needs a value (see ./install.sh --help)"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) need "$@"; PROFILE=$2; shift 2 ;;
    --apps) need "$@"; APPS=$2; shift 2 ;;
    --host) need "$@"; HOST=$2; shift 2 ;;
    --port) need "$@"; PORT=$2; shift 2 ;;
    --bind) need "$@"; BIND=$2; shift 2 ;;
    --editors) need "$@"; EDITORS=$2; shift 2 ;;
    --version) need "$@"; VERSION=$2; shift 2 ;;
    --licence-key|--license-key) need "$@"; LICENCE=$2; shift 2 ;;
    --trial) need "$@"; TRIAL_EMAIL=$2; shift 2 ;;
    --company) need "$@"; COMPANY=$2; shift 2 ;;
    --accept-terms) ACCEPT_TERMS=1; shift ;;
    --yes|-y) YES=1; shift ;;
    --no-start) START=0; shift ;;
    --offline) OFFLINE=1; shift ;;
    --profile-env) need "$@"; PROFILE_ENV=$2; shift 2 ;;
    --tls) need "$@"; TLS=$2; shift 2 ;;
    --acme-email) need "$@"; ACME_EMAIL=$2; shift 2 ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1 (see ./install.sh --help)" ;;
  esac
done
case "$PROFILE" in auto|small|standard|full) ;; *) die "--profile must be small, standard, full or auto" ;; esac
# Check every value before anything is written.
if [ -n "$VERSION" ] && ! printf '%s' "$VERSION" | grep -qE '^[0-9]+[.][0-9]+[.][0-9]+([.-][A-Za-z0-9.-]+)?$'; then
  die "--version \"$VERSION\" is not a release number (like 1.0.0). The release notes list them."
fi
case "$LICENCE" in
  ''|none) ;;
  *) printf '%s' "$LICENCE" | grep -qE '^(tlk1|nxs1)[.][A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)*$' \
       || die "--licence-key does not look like a Tarleaks licence key: it is one line that starts with tlk1. (or nxs1.) and holds only letters, digits, - _ and dots. Copy all of it again, or leave it out and enter it on the setup screen." ;;
esac
if [ -n "$TRIAL_EMAIL" ]; then
  printf '%s' "$TRIAL_EMAIL" | grep -qE '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' \
    || die "--trial needs your e-mail address (for example --trial you@yourcompany.com)."
  [ -z "$LICENCE" ] || [ "$LICENCE" = none ] || die "Give either --licence-key or --trial, not both."
fi
case "$BIND" in
  ''|local|network|office) ;;
  *) printf '%s' "$BIND" | grep -qE '^[0-9]{1,3}([.][0-9]{1,3}){3}$' || die "--bind must be local (this computer only), office (the whole network) or an IP address of this machine" ;;
esac
case "$EDITORS" in ''|on|off) ;; *) die "--editors must be on or off" ;; esac
case "$PROFILE_ENV" in ''|local|production) ;; *) die "--profile-env must be local (this computer or the office network) or production (a real domain over HTTPS)" ;; esac
case "$TLS" in ''|letsencrypt|cloudflare|proxy) ;; *) die "--tls must be letsencrypt, cloudflare or proxy (docs/https.md)" ;; esac
if [ -n "$ACME_EMAIL" ]; then
  printf '%s' "$ACME_EMAIL" | grep -qE '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' || die "--acme-email needs an e-mail address"
fi

# The ERP's containers use the outbound proxy written in .env, never one this
# shell happens to have (a proxy on 127.0.0.1 here is not reachable from inside
# a container). docs/configuration.md#outbound-proxy
shell_proxy=${HTTPS_PROXY:-${https_proxy:-}}
unset HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy ALL_PROXY all_proxy

ask() { # ask "Question" default → answer
  local q="$1" def="$2" a
  if [ "$YES" = 1 ] || [ ! -t 0 ]; then printf '%s' "$def"; return; fi
  read -r -p "$q [$def]: " a </dev/tty || true
  printf '%s' "${a:-$def}"
}

say ""
say "${B}Tarleaks ERP — installer${N}"
say ""

# ---- 1. The machine ---------------------------------------------------------
os=$(uname -s)
case "$os" in Linux|Darwin) ;; *) die "This installer is for Linux and macOS. On Windows run install.ps1 in PowerShell." ;; esac

arch=$(uname -m)
case "$arch" in
  x86_64|amd64) arch_name="amd64 (Intel/AMD)" ;;
  aarch64|arm64) arch_name="arm64 (Apple Silicon, Raspberry Pi 5, Graviton, Ampere)" ;;
  *) die "CPU architecture '$arch' is not supported. Tarleaks ERP runs on 64-bit Intel/AMD (amd64) and 64-bit ARM (arm64). On a Raspberry Pi, install the 64-bit OS." ;;
esac
ok "CPU: $arch_name"

command -v docker >/dev/null 2>&1 || die "Docker is not installed. Install Docker Engine (Linux: https://docs.docker.com/engine/install/) or Docker Desktop (macOS), then run this again."
docker info >/dev/null 2>&1 || die "Docker is installed but not running (or this user may not use it). Start Docker; on Linux add yourself to the docker group: sudo usermod -aG docker \$USER, then log out and in."
# Run with sudo, every file would belong to root and ./tarleaks would then fail
# for the person who runs it. Hand them back at the end (see the trap below).
if [ "$(id -u)" = 0 ] && [ -n "${SUDO_UID:-}" ] && [ "${SUDO_UID}" != 0 ]; then
  warn "Running with sudo: the files this writes are given back to ${SUDO_USER:-uid $SUDO_UID} at the end. Next time, run it without sudo (your user must be in the docker group)."
  trap 'chown "$SUDO_UID:$SUDO_GID" .env 2>/dev/null || true' EXIT
fi
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is missing ('docker compose'). Install the docker-compose-plugin package, or update Docker Desktop."
compose_v=$(docker compose version --short 2>/dev/null || echo "?")
ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?'), Compose $compose_v"

# Memory and CPUs Docker can actually use (on macOS/Windows that is the Docker
# Desktop VM, not the whole machine — the number that matters).
mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
cpus=$(docker info --format '{{.NCPU}}' 2>/dev/null || echo 1)
mem_gb=$(( mem_bytes / 1024 / 1024 / 1024 ))
mem_mb=$(( mem_bytes / 1024 / 1024 ))
ok "Docker can use ${cpus} CPUs and ${mem_gb} GB of memory"
if [ "$mem_mb" -lt 3500 ]; then
  warn "Less than 4 GB of memory for Docker. Tarleaks ERP needs at least 4 GB; it may not start."
  [ "$os" = Darwin ] && warn "Docker Desktop → Settings → Resources → Memory: give it 4 GB or more."
fi

# Free disk where Docker keeps images and data (its data root), not just here.
# Docker Desktop keeps them inside its own virtual disk: ask a container.
desktop=0; docker info --format '{{.OperatingSystem}}' 2>/dev/null | grep -qi 'docker desktop' && desktop=1
root_dir=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)
if [ "$desktop" = 0 ] && [ -n "$root_dir" ] && [ -d "$root_dir" ]; then
  free_kb=$(df -Pk "$root_dir" | awk 'NR==2 {print $4}'); where="for Docker ($root_dir)"
else
  free_kb=$(df -Pk . | awk 'NR==2 {print $4}'); where="here"
  [ "$desktop" = 1 ] && where="here (Docker Desktop's own disk is set in Settings, Resources)"
fi
free_gb=$(( ${free_kb:-0} / 1024 / 1024 ))
if [ "$free_gb" -lt 15 ]; then
  warn "Only ${free_gb} GB of free disk $where. Allow at least 20 GB (images, database, files, backups)."
else
  ok "${free_gb} GB of free disk $where"
fi
if [ "$desktop" = 1 ] && [ "$os" = Linux ]; then
  warn "Docker Desktop on Linux runs everything in a virtual machine (slower, and the address can stop answering after a restart). On a server, install Docker Engine instead: https://docs.docker.com/engine/install/"
fi
# Docker Desktop lets containers use only the folders it shares (your home
# folder by default). The kit's config folder is mounted, so it must be shared.
if [ "$desktop" = 1 ]; then
  case "$PWD/" in
    "$HOME"/*|/Users/*|/Volumes/*|/private/*|/tmp/*) ;;
    *) warn "Docker Desktop may not share $PWD with containers (the start then fails with \"mounts denied … not shared from the host\"). Move the kit under your home folder, or add this folder in Docker Desktop: Settings, Resources, File sharing." ;;
  esac
fi

# ---- 2. Apps ----------------------------------------------------------------
# Only the chosen apps run, plus what they cannot work without (config/apps.tsv
# says what each app needs) and the base apps every workspace holds. Fewer apps
# = fewer containers = less memory.
# shellcheck source=scripts/lib-apps.sh
. scripts/lib-apps.sh
# shellcheck source=scripts/lib-env.sh
. scripts/lib-env.sh
env_now() { [ -f .env ] && grep -E "^$1=" .env | tail -1 | cut -d= -f2- || true; }
env_get() { env_now "$1"; }   # what scripts/lib-env.sh reads
# The release this installation will run: --version, else what .env or the
# example already say. Apps that arrive in a later release are left out.
APPS_VERSION=${VERSION:-$(env_now TARLEAKS_VERSION)}
[ -n "$APPS_VERSION" ] || APPS_VERSION=$(grep -E '^TARLEAKS_VERSION=' .env.example | tail -1 | cut -d= -f2-)
# The migrate image was renamed with the rebrand: nexus-migrate up to 1.1.x,
# tarleaks-migrate from 1.2.0. docker-compose.yml reads TARLEAKS_MIGRATE_IMAGE;
# a name written in .env wins.
use_migrate_image() { # version
  if [ -f .env ] && grep -qE '^TARLEAKS_MIGRATE_IMAGE=.' .env; then return 0; fi
  case "$1" in
    0.*|1.0.*|1.1.*) TARLEAKS_MIGRATE_IMAGE=nexus-migrate ;;
    *) TARLEAKS_MIGRATE_IMAGE=tarleaks-migrate ;;
  esac
  export TARLEAKS_MIGRATE_IMAGE
}
use_migrate_image "$APPS_VERSION"
late=$(apps_unreleased)

# Suggest every app (the trial covers all of them) whenever the machine has the
# memory; otherwise the largest preset that fits, with room to spare.
suggest=small
for p in standard full; do
  need=$(apps_ram_mb "$(apps_closure "$(apps_preset "$p")")")
  [ $(( need + 1024 )) -le "$mem_mb" ] && suggest=$p
done

if [ -n "$APPS" ]; then :
elif [ "$PROFILE" != auto ]; then APPS=$(apps_preset "$PROFILE")
elif [ -n "$(env_now TARLEAKS_APPS)" ]; then APPS=$(env_now TARLEAKS_APPS)   # a re-run keeps the apps
elif [ "$YES" = 1 ] || [ ! -t 0 ]; then APPS=$(apps_preset "$suggest")
else
  say ""
  say "${B}Which apps do you want?${N} Only these run, with what they need."
  say "  1) small     HR, recruitment, attendance, payroll, accounting, CRM, inventory, sales orders, chat"
  say "  2) standard  small + projects, learning, recognition, assets, helpdesk, fleet, correspondence,"
  notyet=$(apps_not_yet); gone=$(apps_withdrawn)
  say "               point of sale, rentals, subscriptions$(case ",$notyet," in *,procurement,*) ;; *) printf ', procurement, construction, contracts' ;; esac)"
  say "  3) full      every app: standard + PDF tools with OCR$(case ",$gone,$notyet," in *,diagrams,*) ;; *) printf ', diagrams' ;; esac), ISO compliance (best for the trial)"
  [ -n "$notyet" ] && say "  (release $APPS_VERSION does not have $(apps_names "$notyet") yet)"
  case ",$gone," in *,diagrams,*) say "  (Diagram Studio is not in release $APPS_VERSION: it is being rebuilt, and returns in a later release)" ;; esac
  say "  4) choose    type the apps you want, for example: hr,crm  (the list: config/apps.tsv)"
  case "$suggest" in small) n=1 ;; standard) n=2 ;; *) n=3 ;; esac
  choice=$(ask "1, 2, 3, 4 or app names" "$n")
  case "$choice" in
    1) APPS=$(apps_preset small) ;;
    2) APPS=$(apps_preset standard) ;;
    3) APPS=$(apps_preset full) ;;
    4) APPS=$(ask "Apps, separated by commas" "hr,crm") ;;
    *) APPS="$choice" ;;
  esac
fi
APPS=$(apps_resolve "$APPS") || die "Fix the app names and run the installer again (./install.sh --apps hr,crm)."
[ -n "$APPS" ] || die "Choose at least one app, for example: ./install.sh --apps hr,crm"

# The editors (New and Edit in Documents; the diagram editor): on, unless asked
# otherwise, or when this machine is too small to carry them (about 2 GB).
cur_editors=$(env_now TARLEAKS_EDITORS)
if [ -n "$EDITORS" ]; then editors_why="you asked for it"
elif [ -n "$cur_editors" ]; then EDITORS=$cur_editors; editors_why="as before"
elif [ "$mem_mb" -lt 5500 ]; then EDITORS=off; editors_why="Docker has only ${mem_gb} GB of memory and the editors need about 2 GB more; turn them on later with ./tarleaks editors on"
else EDITORS=on; editors_why=""; fi
# shellcheck disable=SC2034  # read by scripts/lib-apps.sh
APPS_EDITORS=$EDITORS

closure=$(apps_closure "$APPS")
profiles=$(apps_units "$closure")
modules=$(apps_modules "$closure")
need_mb=$(apps_ram_mb "$closure")
added=""
for a in ${closure//,/ }; do
  case ",$APPS," in *",$a,"*) continue ;; esac
  awk -v a="$a" '$1 == a && $2 == "base" {f=1} END {exit !f}' "$APPS_SHEET" && continue
  added="$added${added:+,}$a"
done
ok "Apps: $(apps_names "$APPS")"
[ -n "$added" ] && ok "Also installed, because those apps need them: $(apps_names "$added")"
ok "Always included: $(apps_names "$(apps_closure "")")"
if [ "$EDITORS" = on ]; then
  ok "Editors: $(apps_names "$(apps_addon_units "$closure")")${editors_why:+ ($editors_why)}"
else
  warn "Editors off ($editors_why): Documents has no New or Edit, and Diagrams no editor. ./tarleaks editors on later."
fi
need_gb=$(awk -v m="$need_mb" 'BEGIN { printf "%.1f", m / 1024 }')
ok "Memory to plan for: about ${need_gb} GB (Docker can use ${mem_gb} GB)"
if [ $(( need_mb + 1024 )) -gt "$mem_mb" ]; then
  warn "These apps need about ${need_gb} GB plus room to work, and Docker has ${mem_gb} GB. Choose fewer apps (./install.sh --apps hr,crm) or give Docker more memory."
fi
# Apps that add to the chosen ones, never installed by themselves.
suggest_apps=$(awk -v set="$modules" '
  BEGIN { n = split(set, s, ","); for (i = 1; i <= n; i++) have[s[i]] = 1 }
  !/^[[:space:]]*#/ && NF >= 8 && ($1 in have) && $5 != "-" { m = split($5, w, ","); for (j = 1; j <= m; j++) if (!(w[j] in have) && !(w[j] in seen)) { seen[w[j]] = 1; out = out (out ? "," : "") w[j] } }
  END { print out }' "$APPS_SHEET")
[ -n "$suggest_apps" ] && say "  Works well with them (add any time: ./tarleaks apps add <app>): $(apps_names "$suggest_apps")"

# Database sized for the services that will connect, and for the memory there is.
units=$(printf '%s' "$profiles" | awk -F, '{print NF}')
pg_conn=$(( 50 + 10 * (units + 7) ))   # + the base apps, auth and the update step
if [ "$mem_mb" -lt 7000 ]; then pg_buf=128MB; pg_cache=512MB
elif [ "$mem_mb" -lt 14000 ]; then pg_buf=256MB; pg_cache=1GB
else pg_buf=512MB; pg_cache=2GB; fi
# The database's memory limit: a quarter of what Docker has, at least 1 GB.
pg_mem=$(( mem_mb / 4 )); [ "$pg_mem" -ge 1024 ] || pg_mem=1024

# ---- 3. Address -------------------------------------------------------------
existing() { [ -f .env ] && grep -E "^$1=" .env | tail -1 | cut -d= -f2- || true; }

lan_ip() {
  if [ "$os" = Darwin ]; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
  else
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true
  fi
}
# The deployment profile: local (this computer or the office network, http)
# or production (a real domain, HTTPS only). Asked once; kept on re-runs.
if [ -z "$PROFILE_ENV" ]; then
  PROFILE_ENV=$(existing TARLEAKS_PROFILE_ENV)
  if [ -z "$PROFILE_ENV" ]; then
    PROFILE_ENV=local
    if [ "$YES" = 0 ] && [ -t 0 ]; then
      say "Where will people use it?"
      say "  1) local       this computer or the office network (http://localhost or http://192.168.x.x)"
      say "  2) production  on the internet at a real domain, HTTPS only (docs/https.md)"
      case "$(ask "1 or 2" 1)" in 2|production) PROFILE_ENV=production ;; esac
    fi
  fi
fi
ok "Profile: $PROFILE_ENV"
if [ -z "$HOST" ]; then
  def_host=$(existing TARLEAKS_HOST); def_host=${def_host:-localhost}
  ip=$(lan_ip)
  [ -n "$ip" ] && [ "$def_host" = localhost ] && say "  This machine's network address is ${B}$ip${N}: use it to reach the ERP from other computers."
  HOST=$(ask "Address people will use (localhost, an IP or a domain)" "$def_host")
fi
case "$HOST" in
  https://*) [ "$PROFILE_ENV" = production ] || warn "The ERP itself speaks plain http on port ${PORT:-80}; for https put a reverse proxy in front (examples/vps-https). Using the name only." ;;
esac
HOST=${HOST#http://}; HOST=${HOST#https://}; HOST=${HOST%%/*}
# A port typed with the address belongs in --port, not in the name.
case "$HOST" in
  *:*) hp=${HOST##*:}; HOST=${HOST%:*}
       case "$hp" in ''|*[!0-9]*) ;; *) warn "Ignoring the port :$hp in the address: the ERP listens on the port from --port (${PORT:-80})." ;; esac ;;
esac
printf '%s' "$HOST" | grep -qE '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' \
  || die "\"$HOST\" is not an address people can type: use localhost, an IP address (192.168.1.20) or a name (erp.example.com), without spaces."
if [ -z "$PORT" ]; then
  PORT=$(existing HTTP_PORT); PORT=${PORT:-80}
fi
case "$PORT" in ''|*[!0-9]*) die "--port must be a number from 1 to 65535" ;; esac
PORT=$((10#$PORT))
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "--port must be a number from 1 to 65535"
if [ "$PORT" = 80 ]; then URL="http://$HOST"; else URL="http://$HOST:$PORT"; fi
# Keep an HTTPS address set up behind a reverse proxy (examples/vps-https,
# examples/behind-nginx): re-running the installer must not undo it.
cur_url=$(existing TARLEAKS_URL)
if [ "${cur_url#https://}" != "$cur_url" ] && [ "$HOST" = "$(existing TARLEAKS_HOST)" ]; then
  URL="$cur_url"
fi
# Production: HTTPS only, on the standard ports. Who holds the certificate:
# this gateway (Let's Encrypt over port 80, or through Cloudflare DNS), or a
# reverse proxy you already run in front of it.
if [ "$PROFILE_ENV" = production ]; then
  [ -n "$TLS" ] || TLS=$(existing TARLEAKS_TLS)
  if [ -z "$TLS" ]; then
    TLS=letsencrypt
    if [ "$YES" = 0 ] && [ -t 0 ]; then
      say "Who holds the HTTPS certificate?"
      say "  1) letsencrypt  this server gets a free certificate (ports 80 and 443 open to the internet)"
      say "  2) cloudflare   the same, proven through Cloudflare DNS (covers <company>.$HOST too)"
      say "  3) proxy        nginx, Caddy or Traefik you already run in front of the ERP"
      case "$(ask "1, 2 or 3" 1)" in 2|cloudflare) TLS=cloudflare ;; 3|proxy) TLS=proxy ;; esac
    fi
  fi
  [ -n "$ACME_EMAIL" ] || ACME_EMAIL=$(existing ACME_EMAIL)
  if [ "$TLS" != proxy ] && [ -z "$ACME_EMAIL" ]; then
    { [ "$YES" = 0 ] && [ -t 0 ]; } || die "--tls $TLS needs --acme-email (Let's Encrypt writes there before a certificate ends)."
    ACME_EMAIL=$(ask "E-mail address for the certificate's expiry notices" "")
  fi
  if [ "$TLS" = cloudflare ] && [ -z "${CF_DNS_API_TOKEN:-}$(existing CF_DNS_API_TOKEN)" ]; then
    { [ "$YES" = 0 ] && [ -t 0 ]; } || die "--tls cloudflare needs CF_DNS_API_TOKEN in the environment (a Cloudflare API token with Zone, DNS, Edit). It is written to .env, never shown."
    printf 'Cloudflare API token (Zone, DNS, Edit; not shown): '; read -rs CF_DNS_API_TOKEN; echo
  fi
  if [ "$TLS" = proxy ]; then
    [ -n "$BIND" ] || BIND=local
  else
    # The gateway itself answers the internet (and Let's Encrypt).
    [ -n "$BIND" ] || BIND=network
    [ -n "$PORT" ] || PORT=80
    [ "$PORT" = 80 ] || [ "$TLS" = cloudflare ] || die "--tls letsencrypt proves the domain over port 80; it cannot use --port $PORT (use --tls cloudflare or --tls proxy)."
  fi
  URL="https://$HOST"
else
  [ "$TLS" != letsencrypt ] && [ "$TLS" != cloudflare ] || die "--tls $TLS needs --profile-env production (a real domain)."
fi
ok "Address: $URL"

port_busy() {
  if command -v ss >/dev/null 2>&1; then ss -ltn "sport = :$1" 2>/dev/null | grep -q LISTEN
  elif command -v lsof >/dev/null 2>&1; then lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else return 1; fi
}
# Busy is fine only when it is this installation's own gateway on that port.
ours=$(docker compose port gateway 80 2>/dev/null | sed 's/.*://' || true)
if port_busy "$PORT" && [ "$ours" != "$PORT" ]; then
  free=""
  for p in 8080 8081 8088 8181 8888 9080; do port_busy "$p" || { free=$p; break; }; done
  die "Port $PORT is already in use by another program. Free it, or use another port${free:+: ./install.sh --port $free}"
fi

# Who may open it: only this computer, or the network too. The installer looks
# at the machine and proposes one, says which and why; --bind always overrides,
# and ./tarleaks network local|office changes it later.
#   a laptop or desktop (a battery, a desktop session, Docker Desktop, macOS)
#     -> only this computer: nobody else on a café or office Wi-Fi can open it
#   a server (none of those) -> the office network, which is what a server is for
#   an address other people type (--host 192.168.1.20) -> the network, always
machine_kind() { # prints "laptop <why>" or "server <why>"
  local why=""
  if [ "$os" = Darwin ]; then echo "laptop this is a Mac"; return; fi
  if [ "$desktop" = 1 ]; then echo "laptop it runs Docker Desktop"; return; fi
  if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then echo "laptop it has a battery"; return; fi
  if [ -n "${XDG_CURRENT_DESKTOP:-}${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then echo "laptop it has a desktop session open"; return; fi
  if command -v systemctl >/dev/null 2>&1 && [ "$(systemctl get-default 2>/dev/null)" = graphical.target ]; then echo "laptop it starts a desktop"; return; fi
  why="no battery and no desktop session"
  echo "server $why"
}
cur_bind=$(existing HTTP_BIND)
bind_why=""
case "$BIND" in
  local) BIND=127.0.0.1; bind_why="you asked for it" ;;
  network|office) BIND=0.0.0.0; bind_why="you asked for it" ;;
  '')
    if [ -n "$cur_bind" ]; then
      def_bind=$cur_bind; bind_why="as before (change it: ./tarleaks network local|office)"
    elif [ "$HOST" != localhost ] && [ "$HOST" != 127.0.0.1 ]; then
      def_bind=0.0.0.0; bind_why="the address is $HOST, which other computers type"
    else
      kind=$(machine_kind); why=${kind#* }; kind=${kind%% *}
      if [ "$kind" = laptop ]; then def_bind=127.0.0.1; bind_why="$why, so this looks like a laptop or desktop"
      else def_bind=0.0.0.0; bind_why="$why, so this looks like a server"; fi
    fi
    BIND=$def_bind
    if [ "$YES" = 0 ] && [ -t 0 ]; then
      say "Who should be able to open it?   (proposed: $([ "$def_bind" = 127.0.0.1 ] && echo "only this computer" || echo "the network too"), because $bind_why)"
      say "  1) only this computer   (other computers cannot connect)"
      say "  2) the network too      (needed for an office server; protect it with your firewall)"
      case "$(ask "1 or 2" "$([ "$def_bind" = 127.0.0.1 ] && echo 1 || echo 2)")" in 1) BIND=127.0.0.1 ;; *) BIND=0.0.0.0 ;; esac
      bind_why="you chose it (proposed from: $bind_why)"
    fi ;;
  *) bind_why="you asked for it" ;;
esac
if [ "$BIND" = 127.0.0.1 ] && [ "$HOST" != localhost ] && [ "$HOST" != 127.0.0.1 ]; then
  warn "Only this computer can connect (HTTP_BIND=127.0.0.1), but the address is $HOST: other computers will not reach it. Fine behind a reverse proxy on this machine (examples/vps-https)."
fi
case "$BIND" in
  127.0.0.1) ok "Who can open it: only this computer ($bind_why). Change it: ./tarleaks network office" ;;
  0.0.0.0) ok "Who can open it: this computer and the network, port $PORT ($bind_why). Change it: ./tarleaks network local" ;;
  *) ok "Listens on $BIND only ($bind_why)" ;;
esac

# ---- 4. Settings and secrets -------------------------------------------------
rand_hex() { # bytes
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex "$1"
  else head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; fi
}
rand_b64() { # bytes
  if command -v openssl >/dev/null 2>&1; then openssl rand -base64 "$1"
  else head -c "$1" /dev/urandom | base64 | tr -d '\n'; fi
}
setup_code() { # XXXX-XXXX-XXXX without look-alike characters
  local alphabet=ABCDEFGHJKLMNPQRSTUVWXYZ23456789 out="" i n
  for i in $(seq 1 12); do
    n=$(( 0x$(rand_hex 1) % ${#alphabet} ))
    out="$out${alphabet:$n:1}"
    if [ "$i" = 4 ] || [ "$i" = 8 ]; then out="$out-"; fi
  done
  printf '%s' "$out"
}

# A new .env next to Docker volumes that already belong to this project name
# would start a second copy of the ERP on another installation's data, with new
# passwords that do not open it. The project name is `name:` in
# docker-compose.yml unless COMPOSE_PROJECT_NAME says otherwise.
env_created=0
if [ ! -f .env ]; then
  project=${COMPOSE_PROJECT_NAME:-$(sed -n 's/^name: *//p' docker-compose.yml | head -1)}
  printf '%s' "$project" | grep -Eq '^[a-z0-9][a-z0-9_-]*$' \
    || die "COMPOSE_PROJECT_NAME '$project' is not a valid name: lowercase letters, digits, - and _ only."
  if [ -n "$(docker volume ls -q --filter "label=com.docker.compose.project=$project")" ]; then
    die "Docker on this machine already holds the data of an installation named '$project', and this folder has no .env. Installing here would attach a second copy to that data. To manage that installation, run ./tarleaks in its own folder. To restore it, put back the .env from its backup first. To install a SEPARATE copy next to it, give this one its own name: COMPOSE_PROJECT_NAME=erp2 ./install.sh (and its own --port). Nothing was changed."
  fi
  cp .env.example .env; chmod 600 .env; env_created=1; ok "Created .env"
fi

# An .env written before the rename has NEXUS_<key> lines. Rename each to
# TARLEAKS_<key> in place, keeping its value (keys are never regenerated). The
# containers get both names, so an image pinned before the rename still starts.
migrate_legacy_keys() {
  grep -qE '^(# ?)?NEXUS_[A-Z0-9_]+=' .env || return 0
  local tmp; tmp=$(mktemp)
  awk '
    function val(line) { return substr(line, index(line, "=") + 1) }
    function key(line) { return substr(line, 1, index(line, "=") - 1) }
    NR == FNR {
      if ($0 ~ /^TARLEAKS_[A-Z0-9_]+=/) { k = key($0); sub(/^TARLEAKS_/, "", k); has[k] = 1 }
      if ($0 ~ /^NEXUS_[A-Z0-9_]+=/)    { k = key($0); sub(/^NEXUS_/, "", k); old[k] = val($0) }
      next
    }
    /^TARLEAKS_[A-Z0-9_]+=/ {
      k = key($0); sub(/^TARLEAKS_/, "", k); v = val($0)
      if ((v == "" || v == "GENERATED") && (k in old) && old[k] != "") v = old[k]
      print "TARLEAKS_" k "=" v; next
    }
    /^NEXUS_[A-Z0-9_]+=/ {
      k = key($0); sub(/^NEXUS_/, "", k)
      if (k in has) next
      print "TARLEAKS_" k "=" val($0); next
    }
    /^# ?NEXUS_[A-Z0-9_]+=/ { sub(/NEXUS_/, "TARLEAKS_"); print; next }
    { print }
  ' .env .env > "$tmp"
  cat "$tmp" > .env && rm -f "$tmp"
  chmod 600 .env
  ok "Renamed the NEXUS_* settings in .env to TARLEAKS_* (values unchanged)"
}
migrate_legacy_keys
# The private-preview image location (ghcr.io, a personal GitHub token) moved to
# registry.tarleaks.com, where the licence key is the password.
moved=$(registry_move_off_retired) && [ -n "$moved" ] && ok "$moved"

set_env() { # key value — replace or append, keep everything else
  local key="$1" val="$2" tmp
  tmp=$(mktemp)
  # Values go through the environment, not awk -v, which would turn a
  # backslash in a value into an escape.
  K="$key" V="$val" awk 'BEGIN{k=ENVIRON["K"]; v=ENVIRON["V"]; done=0} index($0, k "=") == 1 {print k"="v; done=1; next} {print} END{if(!done) print k"="v}' .env > "$tmp"
  cat "$tmp" > .env && rm -f "$tmp"
}
fill() { # key generator — only when missing or still GENERATED
  local cur; cur=$(existing "$1")
  if [ -z "$cur" ] || [ "$cur" = GENERATED ]; then set_env "$1" "$($2)"; fi
}
# The installation's name stays in its .env, always (the default too), so
# ./tarleaks finds its containers and a backup says whose data it holds:
# restore refuses a backup of another installation.
if [ "$env_created" = 1 ]; then
  set_env COMPOSE_PROJECT_NAME "$project"; ok "Installation name: $project"
fi
hex32() { rand_hex 32; }
hex24() { rand_hex 24; }
hex16() { rand_hex 16; }
b64_32() { rand_b64 32; }

fill POSTGRES_PASSWORD hex24
fill RABBITMQ_PASSWORD hex24
fill STORAGE_ACCESS_KEY hex16
fill STORAGE_SECRET_KEY hex32
fill JWT_SECRET hex32
fill CLUSTER_DSN_KEY b64_32
fill INTERNAL_TOKEN hex32
fill PORTAL_JWT_SECRET hex32
fill NOTIFICATIONS_KEK b64_32
fill NOTIFICATIONS_UNSUB_SECRET hex32
fill NOTIFICATIONS_OAUTH_SECRET hex32
fill HELPDESK_TOKEN_KEY b64_32
fill SUBSCRIPTIONS_KEY_SEAL_KEY b64_32
fill MARKETPLACE_TOKEN_KEY b64_32
fill INSIGHTS_SOURCE_KEY b64_32
fill PROCUREMENT_KEK b64_32
fill CONTRACTS_PROVIDER_KEY b64_32
fill ONLYOFFICE_JWT_SECRET hex32
fill TARLEAKS_SETUP_CODE setup_code

set_env TARLEAKS_PROFILE_ENV "$PROFILE_ENV"
set_env TARLEAKS_TLS "$TLS"
[ -z "$ACME_EMAIL" ] || set_env ACME_EMAIL "$ACME_EMAIL"
[ -z "${CF_DNS_API_TOKEN:-}" ] || set_env CF_DNS_API_TOKEN "$CF_DNS_API_TOKEN"
set_env TARLEAKS_HOST "$HOST"
set_env TARLEAKS_URL "$URL"
set_env HTTP_PORT "$PORT"
set_env HTTP_BIND "$BIND"
set_env TARLEAKS_APPS "$APPS"
set_env TARLEAKS_EDITORS "$EDITORS"
set_env COMPOSE_PROFILES "$profiles$(apps_addons "$closure")"
set_env TARLEAKS_AVAILABLE_MODULES "$modules"
apps_sync_editors "$closure"
set_env PG_MAX_CONNECTIONS "$pg_conn"
set_env PG_SHARED_BUFFERS "$pg_buf"
set_env PG_EFFECTIVE_CACHE_SIZE "$pg_cache"
# Kept when set by hand (docs/configuration.md#memory-limits).
[ -n "$(existing PG_MEM_LIMIT)" ] || set_env PG_MEM_LIMIT "${pg_mem}m"
# A version given with --version is written only once its images are here
# (below), so a typo never leaves .env naming a release that does not exist.
[ -n "$VERSION" ] && [ "$START" = 0 ] && set_env TARLEAKS_VERSION "$VERSION"
case "$LICENCE" in
  none) set_env TARLEAKS_LICENSE_KEY ""; ok "Licence key removed from .env" ;;
  ?*) set_env TARLEAKS_LICENSE_KEY "$LICENCE" ;;
esac
sync_compose_files
chmod 600 .env
ok "Settings written to .env (keep a copy somewhere safe)"
# The same checks as ./tarleaks doctor's "Profile and addresses": a mix-up is
# refused here, before anything starts.
env_out=$(env_problems)
printf '%s\n' "$env_out" | sed -n 's/^WARN /  /p' | while IFS= read -r l; do [ -z "$l" ] || warn "$l"; done
if printf '%s\n' "$env_out" | grep -q '^ERROR '; then
  printf '%s\n' "$env_out" | sed -n 's/^ERROR /  /p' >&2
  die "These settings do not fit together (above). Nothing was started; fix them and run ./install.sh again."
fi

[ "$START" = 1 ] || { say "Not starting (--no-start). Run ./tarleaks start when ready."; exit 0; }

# ---- 5. Images ---------------------------------------------------------------
# Every image the chosen profile runs (docker-compose.yml + .env), minus the
# ones already on this machine.
missing_images() {
  local images img
  images=$(docker compose config --images) || return 2
  for img in $(printf '%s\n' "$images" | sort -u); do
    docker image inspect "$img" >/dev/null 2>&1 || printf '%s\n' "$img"
  done
}
# The licence key is also the password for downloading the images. With none
# yet (no --licence-key, none in .env, none in a running installation), start
# the 30-day trial here: the setup screen then continues the same trial when
# you give it the same e-mail address.
# shellcheck disable=SC2034  # read by scripts/lib-registry.sh
REGISTRY_CURL_PROXY=$shell_proxy
if [ "$OFFLINE" = 0 ] && registry_takes_licence && [ -z "$(registry_licence_key)" ]; then
  say ""
  say "${B}A licence key is needed to download Tarleaks ERP${N} (it is also the download password)."
  if [ -z "$TRIAL_EMAIL" ] && [ "$YES" = 0 ] && [ -t 0 ]; then
    say "  1) I have a licence key"
    say "  2) Start the free 30-day trial (your company name and e-mail address)"
    case "$(ask "1 or 2" "2")" in
      1) key=""; read -r -s -p "Paste the licence key (it is not shown): " key </dev/tty || true; say ""
         _reg_plausible_key "$key" || die "That does not look like a Tarleaks licence key: one line that starts with nxs1. Copy all of it again, then run ./install.sh --licence-key <key>."
         set_env TARLEAKS_LICENSE_KEY "$key"; ok "Licence key saved in .env" ;;
      *) TRIAL_EMAIL=$(ask "Your e-mail address" "")
         printf '%s' "$TRIAL_EMAIL" | grep -qE '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' || die "\"$TRIAL_EMAIL\" is not an e-mail address. Run ./install.sh again."
         [ -n "$COMPANY" ] || COMPANY=$(ask "Your company name" "")
         say "  The licence terms are in LICENSE.md next to this installer."
         case "$(ask "Do you accept them? yes/no" "no")" in y|Y|yes|YES|Yes) ACCEPT_TERMS=1 ;; *) die "The trial needs the licence terms accepted (LICENSE.md). Nothing was downloaded." ;; esac ;;
    esac
  fi
  if [ -z "$(registry_licence_key)" ]; then
    [ -n "$TRIAL_EMAIL" ] || die "Give your licence key (./install.sh --licence-key <key>) or start the free trial (./install.sh --trial you@yourcompany.com --company \"Your company\" --accept-terms). Nothing was downloaded."
    [ -n "$COMPANY" ] || die "The trial needs your company name: add --company \"Your company\"."
    [ "$ACCEPT_TERMS" = 1 ] || die "The trial needs the licence terms (LICENSE.md) accepted: add --accept-terms."
    trial_key=$(registry_start_trial "$COMPANY" "$TRIAL_EMAIL") || die "Nothing was downloaded. Fix the above, or give a licence key with ./install.sh --licence-key <key>."
    _reg_plausible_key "$trial_key" || die "tarleaks.com did not send a usable trial key. Run ./install.sh again; if it keeps failing, contact info@tarleaks.com."
    set_env TARLEAKS_DOWNLOAD_KEY "$trial_key"
    chmod 600 .env
    ok "Free trial started for $TRIAL_EMAIL. On the setup screen, choose the free trial with the same e-mail address."
  fi
fi

# Before several GB of downloads: can this machine reach the licence server,
# and is its clock right? (Warnings only: an air-gapped install is allowed.)
if [ "$OFFLINE" = 0 ]; then
  hdrs=$(curl -sSI --max-time 10 ${shell_proxy:+--proxy "$shell_proxy"} https://tarleaks.com 2>/dev/null || true)
  if [ -z "$hdrs" ]; then
    warn "tarleaks.com does not answer from this machine. The trial and the licence check-in need it (outbound HTTPS, port 443; HTTPS_PROXY in .env behind a proxy). Without internet: docs/faq.md, \"Can I install without internet?\""
  else
    ok "tarleaks.com answers"
    remote=$(printf '%s\n' "$hdrs" | awk -F': ' 'tolower($1)=="date" {print $2}' | tr -d '\r')
    if [ -n "$remote" ] && command -v python3 >/dev/null 2>&1; then
      skew=$(python3 -c "import sys,email.utils,time; print(int(abs(time.time()-email.utils.parsedate_to_datetime(sys.argv[1]).timestamp())))" "$remote" 2>/dev/null || echo 0)
      [ "${skew:-0}" -le 600 ] || warn "This machine's clock is ${skew} seconds off. Turn on automatic time (NTP) before the setup: the licence refuses a clock that runs behind."
    fi
  fi
fi
# And can Docker sign in to the image registry with the licence key? This is
# the check that used to fail only after the first downloads.
if [ "$OFFLINE" = 0 ] && registry_takes_licence; then
  registry_login ./install.sh || die "Nothing was downloaded."
  ok "Signed in to $(registry_host) with the licence key"
fi
say ""
say "Downloading the images (the first time takes a few minutes)…"
if [ -n "$VERSION" ]; then
  TARLEAKS_VERSION="$VERSION" TARLEAKS_NO_DOWNLOAD=$OFFLINE apps_pull "./install.sh --version $VERSION" \
    || die "Nothing was started; .env still names $(existing TARLEAKS_VERSION). Check the version number (the release notes list them)."
  set_env TARLEAKS_VERSION "$VERSION"
else
  TARLEAKS_NO_DOWNLOAD=$OFFLINE apps_pull ./install.sh || exit 1
fi
# Offline installs print the no-internet licence note at the end.
if [ "$OFFLINE" = 1 ]; then downloaded=0; ok "Every image is on this machine"; else downloaded=1; ok "Images downloaded"; fi

# ---- 6. Start ----------------------------------------------------------------
# The sign-in token key, once: after the images, so the message-queue image's
# openssl can make it where this machine's cannot (macOS, no openssl).
env_signing_keys_note "$(env_fill_signing_keys)"
docker compose up -d --remove-orphans
apps_stop_unselected
say ""
say "Starting (the first start prepares the database; allow up to 5 minutes)…"
deadline=$(( $(date +%s) + 600 ))
bind=$(existing HTTP_BIND)
case "$bind" in ''|0.0.0.0|'::') bind=127.0.0.1 ;; esac
until curl -fsS -o /dev/null "http://$bind:$PORT/api/auth/installation" 2>/dev/null; do
  if [ "$(date +%s)" -gt "$deadline" ]; then
    warn "Not answering yet after 10 minutes. See: ./tarleaks doctor   and   ./tarleaks logs auth"
    exit 1
  fi
  printf '.'; sleep 5
done
say ""
ok "Tarleaks ERP is running"
# The document editor starts last and takes a minute or two the first time:
# wait for it (at most 4 minutes), so New and Edit work the moment you open Documents.
if [ "$EDITORS" = on ] && case ",$(existing COMPOSE_PROFILES)," in *,onlyoffice,*) true ;; *) false ;; esac; then
  printf 'Starting the document editor (the first start takes a minute or two)'
  editor_deadline=$(( $(date +%s) + 240 )); editor_up=0
  until [ "$(curl -fsS --max-time 5 "http://$bind:$PORT/onlyoffice/healthcheck" 2>/dev/null)" = true ]; do
    [ "$(date +%s)" -gt "$editor_deadline" ] && break
    printf '.'; sleep 5
  done
  [ "$(curl -fsS --max-time 5 "http://$bind:$PORT/onlyoffice/healthcheck" 2>/dev/null)" = true ] && editor_up=1
  say ""
  if [ "$editor_up" = 1 ]; then ok "The document editor is ready"
  else warn "The document editor is still starting. New and Edit in Documents work once it is up. See: ./tarleaks doctor   and   ./tarleaks logs onlyoffice"; fi
fi

code=$(existing TARLEAKS_SETUP_CODE)
say ""
say "${B}Open ${URL} in your browser.${N}"
say "  Setup code: ${B}${code}${N}"
say "  You will name your company, create the first administrator and start the"
if [ "$downloaded" = 1 ]; then
  say "  30-day free trial (or enter a licence key)."
else
  say "  licence: with no internet, enter a licence key (the trial needs internet)."
fi
say ""
say "  E-mail (invitations, password resets): after setup, Settings, Notifications,"
say "  Custom SMTP (your mail server)."
say "  Until it is set, give people their first password yourself."
say ""
say "  ./tarleaks status     what is running"
say "  ./tarleaks stop       stop everything (your data stays)"
say "  ./tarleaks backup     back up the database, files and .env"
say "  ./tarleaks upgrade    move to a newer version"
say ""
if [ "$downloaded" = 1 ]; then
  say "The ERP checks its licence with tarleaks.com about every 6 hours and needs"
  say "to reach it at least once a day. Allow outbound HTTPS to tarleaks.com"
  say "(directly, or through HTTPS_PROXY in .env)."
else
  say "${B}This machine downloaded nothing.${N} If it has no internet at all, it needs a"
  say "licence key made for that: read docs/faq.md, \"Can I install without"
  say "internet?\", before you run the setup."
fi
# A nightly backup, if there is none yet (asked only when someone is at the
# keyboard; examples/scheduled-backups has the systemd timer instead).
if [ "$YES" = 0 ] && [ -t 0 ] && command -v crontab >/dev/null 2>&1 \
   && ! crontab -l 2>/dev/null | grep -qF "$PWD/tarleaks backup"; then
  say ""
  case "$(ask "Back up every night at 02:15 into $PWD/backups (keeps 14 days)? y/n" "y")" in
    y|Y|yes|YES)
      { crontab -l 2>/dev/null || true
        echo "PATH=/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        echo "15 2 * * * cd '$PWD' && ./tarleaks backup >> '$PWD/backups/backup.log' 2>&1"
        echo "0 3 * * * find '$PWD/backups' -mindepth 1 -maxdepth 1 -type d -name '20[0-9]*' -mtime +14 -exec rm -rf {} +"
      } | crontab - && mkdir -p backups && ok "Nightly backup scheduled (crontab -l shows it). Copy the backups off this machine too: docs/backup-restore.md" \
        || warn "Could not add the nightly backup to cron: examples/scheduled-backups shows how." ;;
    *) say "  No nightly backup. Set one up later: examples/scheduled-backups" ;;
  esac
fi
if [ -n "$shell_proxy" ] && [ -z "$(existing HTTPS_PROXY)" ]; then
  say ""
  warn "This shell uses a proxy ($shell_proxy) but .env sets none, so the ERP connects directly. If the ERP needs it too, add HTTPS_PROXY=… to .env and run ./tarleaks restart (docs/configuration.md#outbound-proxy)."
fi
