# shellcheck shell=bash
# =============================================================================
# The deployment profile, HTTPS and offline mode — shared by ./install.sh and
# ./tarleaks. Sourced, never run. Needs env_get (reads one .env value).
#
#   TARLEAKS_PROFILE_ENV  local       this computer or the office network: an
#                                     IP or name over http:// is fine
#                         production  a real domain, HTTPS only (HSTS)
#   TARLEAKS_TLS          letsencrypt the gateway gets a Let's Encrypt
#                                     certificate over port 80 (HTTP-01)
#                         cloudflare  ... through Cloudflare DNS (DNS-01),
#                                     covers *.<host> too
#                         proxy       your own reverse proxy in front holds
#                                     the certificate (nginx, Caddy, Traefik)
#   TARLEAKS_OFFLINE      false | true (no optional outside service) |
#                         sealed (nothing in Docker can leave this machine)
#
# env_problems prints one line per problem, "ERROR <text>" or "WARN <text>";
# ./tarleaks doctor and ./install.sh refuse to go on with an ERROR.
# compose_files prints the COMPOSE_FILE value these settings need.
# =============================================================================

env_is_loopback() { case "$1" in localhost|*.localhost|127.*|::1|'[::1]') return 0 ;; esac; return 1; }
env_is_ip() { printf '%s' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$|:'; }
# scheme://host[:port]/… → host (lower case, no brackets)
env_url_host() { printf '%s' "$1" | sed -E 's#^[A-Za-z]+://##; s#/.*$##; s#^\[([^]]*)\].*$#\1#; s#:[0-9]+$##' | tr '[:upper:]' '[:lower:]'; }
env_url_scheme() { printf '%s' "$1" | sed -nE 's#^([A-Za-z]+)://.*#\1#p' | tr '[:upper:]' '[:lower:]'; }

# The licence key's check-in interval in hours ("" when unknown). The key is
# <prefix>.<base64url JSON>.<signature>; only the JSON is read, never printed.
env_licence_interval() {
  local key="$1" body pad
  body=$(printf '%s' "$key" | cut -d. -f2 | tr '_-' '/+')
  [ -n "$body" ] || return 0
  pad=$(( (4 - ${#body} % 4) % 4 ))
  body="$body$(printf '%*s' "$pad" '' | tr ' ' '=')"
  printf '%s' "$body" | base64 -d 2>/dev/null | tr ',' '\n' \
    | sed -nE 's/.*"heartbeat_interval_hours"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1
}

env_problems() {
  local profile tls offline host url scheme uhost port bind v k h s
  profile=$(env_get TARLEAKS_PROFILE_ENV); profile=${profile:-local}
  tls=$(env_get TARLEAKS_TLS)
  offline=$(env_get TARLEAKS_OFFLINE); offline=${offline:-false}
  host=$(env_get TARLEAKS_HOST); url=$(env_get TARLEAKS_URL)
  port=$(env_get HTTP_PORT); port=${port:-80}
  bind=$(env_get HTTP_BIND); bind=${bind:-0.0.0.0}
  scheme=$(env_url_scheme "$url"); uhost=$(env_url_host "$url")

  case "$profile" in
    local|production) ;;
    *) echo "ERROR TARLEAKS_PROFILE_ENV is '$profile'. Use local (this computer or the office network) or production (a real domain over HTTPS)." ;;
  esac
  case "$scheme" in
    http|https) ;;
    *) echo "ERROR TARLEAKS_URL is '$url'. Write the full address people type, for example http://192.168.1.20 or https://erp.example.com." ;;
  esac
  [ -z "$uhost" ] || [ "$uhost" = "$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')" ] \
    || echo "ERROR TARLEAKS_URL ($url) and TARLEAKS_HOST ($host) name different machines. Set both to the same name: ./install.sh --host <name>."
  case "$tls" in
    ''|letsencrypt|cloudflare|proxy) ;;
    *) echo "ERROR TARLEAKS_TLS is '$tls'. Use letsencrypt, cloudflare or proxy (docs/https.md)." ;;
  esac

  if [ "$profile" = production ]; then
    [ "$scheme" = https ] || echo "ERROR The production profile serves HTTPS only, but TARLEAKS_URL is '$url'. Use https://<your domain>, or the local profile for a computer or office network: ./install.sh --profile-env local."
    if env_is_loopback "$host" || env_is_ip "$host" || [ -z "$host" ]; then
      echo "ERROR The production profile needs a domain name (erp.example.com), not '${host:-nothing}': certificates are issued for names. docs/https.md"
    fi
    case "$tls" in
      '') echo "ERROR The production profile needs TARLEAKS_TLS: letsencrypt (this server gets the certificate), cloudflare (through Cloudflare DNS) or proxy (your reverse proxy has it). docs/https.md" ;;
      letsencrypt|cloudflare)
        [ -n "$(env_get ACME_EMAIL)" ] || echo "ERROR TARLEAKS_TLS=$tls needs ACME_EMAIL: the address Let's Encrypt writes to before a certificate ends."
        [ "$bind" != 127.0.0.1 ] || echo "ERROR TARLEAKS_TLS=$tls but HTTP_BIND=127.0.0.1: nobody outside this machine can reach the gateway. Use ./tarleaks network office."
        if [ "$tls" = letsencrypt ] && [ "$port" != 80 ]; then
          echo "ERROR TARLEAKS_TLS=letsencrypt proves the name over port 80, but HTTP_PORT is $port. Use port 80, or TARLEAKS_TLS=cloudflare (no port 80 needed)."
        fi
        if [ "$tls" = cloudflare ] && [ -z "$(env_get CF_DNS_API_TOKEN)" ]; then
          echo "ERROR TARLEAKS_TLS=cloudflare needs CF_DNS_API_TOKEN (a Cloudflare API token with Zone, DNS, Edit on the domain). docs/https.md"
        fi
        [ "$offline" != sealed ] || echo "ERROR TARLEAKS_OFFLINE=sealed and TARLEAKS_TLS=$tls: Let's Encrypt cannot be reached from a sealed installation. Use TARLEAKS_TLS=proxy with your own certificate." ;;
      proxy)
        [ "$bind" = 127.0.0.1 ] || echo "WARN TARLEAKS_TLS=proxy but the gateway also answers plain http on the network (HTTP_BIND=$bind). If the proxy runs on this machine: ./tarleaks network local." ;;
    esac
  else
    case "$tls" in
      letsencrypt|cloudflare) echo "ERROR TARLEAKS_TLS=$tls is for the production profile (a real domain). Set TARLEAKS_PROFILE_ENV=production, or remove TARLEAKS_TLS." ;;
    esac
    if [ "$scheme" = https ] && [ "$tls" != proxy ]; then
      echo "WARN TARLEAKS_URL is https:// but nothing here serves HTTPS. Fine when a reverse proxy in front holds the certificate (then set TARLEAKS_TLS=proxy); otherwise use http://."
    fi
    if [ "$bind" = 127.0.0.1 ] && ! env_is_loopback "$host"; then
      echo "WARN People open the ERP at $host, but only this computer may connect (HTTP_BIND=127.0.0.1). Fine behind a reverse proxy on this machine; otherwise ./tarleaks network office."
    fi
  fi

  # Addresses handed to browsers must be the one people use.
  for k in TARLEAKS_STORAGE_PRESIGN_ENDPOINT ONLYOFFICE_PUBLIC_URL DRAWIO_URL; do
    v=$(env_get "$k"); [ -n "$v" ] || continue
    h=$(env_url_host "$v"); s=$(env_url_scheme "$v")
    if env_is_loopback "$h" && ! env_is_loopback "$uhost"; then
      echo "ERROR $k is $v, but people open the ERP at $url: their browsers would look on their own computer. Leave $k empty (it follows TARLEAKS_URL)."
    fi
    [ "$scheme" != https ] || [ "$s" != http ] \
      || echo "ERROR $k is $v (http://) inside an https:// ERP: browsers block it. Use https:// or leave it empty."
  done

  case "$offline" in
    false|'') ;;
    true|sealed)
      for k in GROQ_API_KEY OLLAMA_API_KEY OLLAMA_BASE_URL DIAGRAMS_AI_BASE_URL HTTPS_PROXY HTTP_PROXY; do
        [ -z "$(env_get "$k")" ] || echo "ERROR TARLEAKS_OFFLINE=$offline but $k is set: that would reach out. Run ./tarleaks offline $offline again (it clears it)."
      done
      case ",$(env_get COMPOSE_PROFILES)," in
        *,diagrams-engine,*) echo "ERROR TARLEAKS_OFFLINE=$offline but the AI drawing engine (diagrams-engine) is on; it needs an online AI service. ./tarleaks offline $offline switches it off." ;;
      esac
      v=$(env_get TARLEAKS_LICENSE_KEY)
      if [ -n "$v" ]; then
        h=$(env_licence_interval "$v")
        case "$h" in
          0) ;;
          '') echo "WARN Could not read the licence key's check-in interval. An offline installation needs an offline licence key from Tarleaks (docs/offline.md)." ;;
          *) echo "ERROR This licence key checks in with tarleaks.com every $h hours; without internet the ERP stops when its offline allowance runs out. Ask Tarleaks for an offline licence key (docs/offline.md)." ;;
        esac
      else
        echo "WARN No licence key in .env, so the key entered on the setup screen is used. Offline, it must be an offline licence key from Tarleaks (docs/offline.md)."
      fi ;;
    *) echo "ERROR TARLEAKS_OFFLINE is '$offline'. Use false, true or sealed (docs/offline.md)." ;;
  esac
}

# COMPOSE_FILE for these settings ("" = docker compose's own default). A
# docker-compose.override.yml next to docker-compose.yml is kept: Compose
# stops reading it by itself once COMPOSE_FILE is set.
compose_files() {
  local files="" tls offline sep=":"
  tls=$(env_get TARLEAKS_TLS); offline=$(env_get TARLEAKS_OFFLINE)
  case "$(env_get TARLEAKS_PROFILE_ENV):$tls" in
    production:letsencrypt) files="config/https/compose.https-letsencrypt.yml" ;;
    production:cloudflare) files="config/https/compose.https-cloudflare.yml" ;;
  esac
  [ "$offline" != sealed ] || files="$files${files:+$sep}config/offline/compose.sealed.yml"
  [ -n "$files" ] || return 0
  if [ -f docker-compose.override.yml ]; then files="docker-compose.override.yml$sep$files"; fi
  printf 'docker-compose.yml%s%s' "$sep" "$files"
}

# Write (or remove) COMPOSE_FILE in .env. Needs set_env.
sync_compose_files() {
  local want; want=$(compose_files)
  if [ -n "$want" ]; then
    [ "$(env_get COMPOSE_FILE)" = "$want" ] || set_env COMPOSE_FILE "$want"
    # ":" on every system (Compose's own default is ";" on Windows).
    [ "$(env_get COMPOSE_PATH_SEPARATOR)" = ":" ] || set_env COMPOSE_PATH_SEPARATOR ":"
  elif grep -q '^COMPOSE_FILE=' .env 2>/dev/null; then
    local tmp; tmp=$(mktemp)
    grep -Ev '^COMPOSE_(FILE|PATH_SEPARATOR)=' .env > "$tmp" || true
    cat "$tmp" > .env && rm -f "$tmp"
  fi
}

# ---- The token signing key (Ed25519) ----------------------------------------
# Sign-in tokens are signed by the auth service alone with an Ed25519 key; every
# other service checks them with its public half. Two-step confirmation (sealed
# tenders, other actions that ask for the authenticator code again) refuses to
# run without it. The key is made once, like every key in .env, and never
# replaced by a script: a new key signs everyone out.
#
#   JWT_SIGNING_KID      the key's name (tl-<date>-<random>)
#   JWT_SIGNING_KEY_DER  the private key (base64 PKCS#8; only auth reads it)
#   JWT_PUBLIC_KEYS      the public key, as {"<name>": "<PEM>"} (every service)
#
# docker-compose.yml switches auth to Ed25519 only when JWT_SIGNING_KEY_DER is
# set, so an .env without the key keeps working as before.

# The generator, also used by the PowerShell scripts: no quote characters, so it
# passes through any shell unchanged. Prints "<private> <public>" (base64 DER).
ENV_ED25519_SCRIPT='k=$(mktemp) && openssl genpkey -algorithm ed25519 -out $k && echo $(openssl pkey -in $k -outform DER | base64) $(openssl pkey -in $k -pubout -outform DER | base64); rm -f $k'

# "<private> <public>" from this machine's openssl when it knows Ed25519 (macOS'
# LibreSSL does not), else from the openssl inside the message-queue image this
# installation already runs (no internet needed once the images are here).
# Prints nothing when neither works.
env_ed25519_pair() {
  local out img
  out=$(sh -c "$ENV_ED25519_SCRIPT" 2>/dev/null) || out=""
  if ! env_ed25519_valid "$out" && command -v docker >/dev/null 2>&1; then
    img=$(env_get RABBITMQ_IMAGE)
    [ -n "$img" ] || img=$(sed -n 's/^ *image: \${RABBITMQ_IMAGE:-\([^}]*\)}.*/\1/p' docker-compose.yml | head -1)
    # --pull never: no download behind the person's back; without the image
    # the key waits for the next start.
    out=$(docker run --rm --pull never --network none --entrypoint sh "$img" -c "$ENV_ED25519_SCRIPT" 2>/dev/null) || out=""
  fi
  env_ed25519_valid "$out" && printf '%s' "$out"
}
# A PKCS#8 Ed25519 private key is 48 bytes (64 base64 characters), its public
# key 44 bytes (60).
env_ed25519_valid() {
  printf '%s' "$1" | grep -Eq '^MC4CAQAwBQYDK2Vw[A-Za-z0-9+/]{48} MCowBQYDK2VwAyEA[A-Za-z0-9+/]{43}=$'
}

# Writes the three keys when the private key is missing. Needs set_env. Prints
# "added"; "unavailable" when no key could be made (the installation then runs
# as before, without two-step confirmation; the next ./tarleaks start tries
# again); "mismatch" when a private key is there but its name is not among the
# published keys (a hand-edited .env: auth would not start; never repaired by
# replacing the key).
env_fill_signing_keys() {
  local have; have=$(env_get JWT_SIGNING_KEY_DER)
  if [ -n "$have" ]; then
    local kid; kid=$(env_get JWT_SIGNING_KID)
    case "$(env_get JWT_PUBLIC_KEYS)" in
      *"\"$kid\":"*) [ -n "$kid" ] || echo mismatch ;;
      *) echo mismatch ;;
    esac
    return 0
  fi
  local pair priv pub kid
  pair=$(env_ed25519_pair)
  [ -n "$pair" ] || { echo unavailable; return 0; }
  priv=${pair%% *}; pub=${pair#* }
  kid="tl-$(date -u +%Y%m%d)-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  set_env JWT_SIGNING_KID "$kid"
  # Single quotes: Compose keeps the value as it is, and \n stays two
  # characters, which the JSON reader turns into the PEM's line breaks.
  set_env JWT_PUBLIC_KEYS "'{\"$kid\":\"-----BEGIN PUBLIC KEY-----\\n$pub\\n-----END PUBLIC KEY-----\\n\"}'"
  # Last: auth signs with Ed25519 only once the public key is published.
  set_env JWT_SIGNING_KEY_DER "$priv"
  echo added
}

# The message for env_fill_signing_keys' answer (./install.sh and ./tarleaks).
env_signing_keys_note() {
  case "$1" in
    added) ok "Created the sign-in token key (two-step confirmation, sealed tenders)" ;;
    unavailable) warn "Could not create the sign-in token key yet (no openssl with Ed25519 here, and the message-queue image is not on this machine). Everything works except two-step confirmation; ./tarleaks start tries again." ;;
    mismatch) warn "JWT_SIGNING_KEY_DER is set in .env, but JWT_SIGNING_KID is empty or not in JWT_PUBLIC_KEYS: the sign-in service will not start. Put the three JWT_SIGNING_KID, JWT_SIGNING_KEY_DER and JWT_PUBLIC_KEYS lines back from a backup of .env, or delete all three lines to make a new key (everyone signs in again)." ;;
  esac
}
