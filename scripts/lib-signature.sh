# shellcheck shell=bash
# =============================================================================
# The Tarleaks release signature (R71). Sourced by install.sh and ./tarleaks
# (Windows: scripts/lib-signature.ps1).
#
# Tarleaks signs every image of a release, and every offline bundle's checksum
# list, with its release key (cosign); config/sigstore/tarleaks-release.pub is
# the public half. No Tarleaks image runs here unless this machine checked it:
#
#   sig_verify_images "<again>"    after `docker compose pull`: cosign checks
#                                  every Tarleaks image by the digest Docker
#                                  downloaded, then records it as checked
#   sig_record_loaded              after a SIGNED offline bundle was loaded
#                                  (stdin: docker load's output)
#   sig_require_verified "<again>" before images already on this machine are
#                                  used (no download, a failed download,
#                                  ./tarleaks start): each must be recorded
#
# The record (.tarleaks-verified) holds "<image> <image id>" lines: an image
# whose content changed since it was checked has another id and is refused.
# A refused signature stops the install or upgrade before anything starts (the
# running release keeps running). TARLEAKS_ALLOW_UNSIGNED=1 is the only way
# past, for images you built or copied yourself. Releases published before
# signing began (a release number older than SIG_SIGNED_FROM) are not checked.
#
# cosign: the one on this server when it is 2.4 or later, otherwise Sigstore's
# own cosign image (pinned by digest below), which Docker downloads once.
# =============================================================================

RELEASE_PUBKEY=config/sigstore/tarleaks-release.pub
SIGSTORE_ROOT=config/sigstore/trusted_root.json
SIG_RECORD=.tarleaks-verified
# Sigstore's cosign image, multi-arch index digest (ghcr.io/sigstore/cosign/cosign:v3.1.4).
SIG_COSIGN_IMAGE=${TARLEAKS_COSIGN_IMAGE:-ghcr.io/sigstore/cosign/cosign:v3.1.4@sha256:0f06154836d2de34f887a5c273506d52ca43edaa1d9e53e6510fa78a48f69c2d}
# The first release whose images are signed (the release pipeline cannot publish
# a release unsigned since then).
SIG_SIGNED_FROM=1.2.0-rc.7
# What cosign prints when an image really has no valid Tarleaks signature. Any
# other failure (network, sign-in, a mount Docker refused) means "not checked".
SIG_VERDICT_RE='no signatures found|no matching signatures|signature verification failed|invalid signature|none of the verifiers verified|no matching attestations'

# Is release $1 at least $2? 1.2.0-rc.7 < 1.2.0-rc.10 < 1.2.0 < 1.2.1.
_sig_at_least() {
  awk -v a="$1" -v b="$2" '
    function part(v, out,   n, m, base, pre) {
      base = v; pre = ""
      if ((m = index(v, "-")) > 0) { base = substr(v, 1, m - 1); pre = substr(v, m + 1) }
      n = split(base, out, "."); out[4] = (pre == "") ? 1e9 : 0
      if (pre != "") { gsub(/[^0-9.]/, "", pre); sub(/^[.]+/, "", pre); split(pre, q, "."); out[4] = q[1] + 0 }
    }
    BEGIN { part(a, x); part(b, y)
      for (i = 1; i <= 4; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
      exit 0 }'
}

# The release the images are for: the shell's TARLEAKS_VERSION, else .env's.
_sig_version() { local v=${TARLEAKS_VERSION:-}; [ -n "$v" ] || v=$(_reg_env TARLEAKS_VERSION); printf '%s' "$v"; }

# 0 when the images of this release must carry the signature: every release
# from SIG_SIGNED_FROM on, and anything that is not a release number at all
# (latest, a branch name, an empty value); only an older release number skips.
_sig_needed() {
  local v=$1
  printf '%s' "$v" | grep -qE '^[0-9]+[.][0-9]+[.][0-9]+([.-][A-Za-z0-9.-]+)?$' || return 0
  _sig_at_least "$v" "$SIG_SIGNED_FROM"
}

# The local cosign, when it is 2.4 or later: prints its path, else nothing.
_sig_local_cosign() {
  local v
  command -v cosign >/dev/null 2>&1 || return 0
  v=$(cosign version 2>/dev/null | sed -n 's/^GitVersion: *v\{0,1\}//p' | head -1)
  case "$v" in ''|0.*|1.*|2.[0-3].*) return 0 ;; esac
  command -v cosign
}

# `cosign verify` of image references (repository@sha256:…) with the release key,
# the messages of both attempts (with and without the kit's trust root) into file $2. $1 = a folder holding config.json for the container, or "".
_sig_cosign_verify() {
  local cfg=$1 log=$2 bin; shift 2
  bin=$(_sig_local_cosign)
  if [ -n "$bin" ]; then
    # 2.x needs the flag for the new bundle format; 3.x reads both by itself.
    local sig_extra=()
    case "$("$bin" version 2>/dev/null | sed -n 's/^GitVersion: *v\{0,1\}//p' | head -1)" in 2.*) sig_extra=(--new-bundle-format) ;; esac
    "$bin" verify ${sig_extra[@]+"${sig_extra[@]}"} --key "$RELEASE_PUBKEY" --trusted-root "$SIGSTORE_ROOT" --output text "$@" >/dev/null 2>"$log" \
      || "$bin" verify ${sig_extra[@]+"${sig_extra[@]}"} --key "$RELEASE_PUBKEY" --output text "$@" >/dev/null 2>>"$log"
    return
  fi
  # No usable cosign here: Sigstore's image, as this user, read-only, the kit's
  # key folder and the registry sign-in mounted read-only (:z for SELinux hosts).
  local run=(docker run --rm --user "$(id -u):$(id -g)" --read-only --tmpfs /tmp -e HOME=/tmp
             -v "$PWD/config/sigstore:/sigstore:ro,z")
  [ -z "$cfg" ] || [ ! -f "$cfg/config.json" ] || run+=(-v "$cfg:/docker:ro,z" -e DOCKER_CONFIG=/docker)
  "${run[@]}" "$SIG_COSIGN_IMAGE" verify --key /sigstore/tarleaks-release.pub --trusted-root /sigstore/trusted_root.json \
      --output text "$@" >/dev/null 2>"$log" \
    || "${run[@]}" "$SIG_COSIGN_IMAGE" verify --key /sigstore/tarleaks-release.pub --output text "$@" >/dev/null 2>>"$log"
}

# A registry sign-in the cosign container can read, written into folder $1
# (mode 600): the licence key for the Tarleaks registry, otherwise only this
# registry's entry of Docker's own config.json (never the other registries').
_sig_docker_config() {
  local d=$1 key host src
  host=$(registry_host)
  if registry_takes_licence; then
    key=$(registry_licence_key) || key=""
    [ -n "$key" ] || return 0
    ( umask 077
      printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$host" \
        "$(printf '%s:%s' "$REGISTRY_USER" "$key" | base64 | tr -d '\n')" > "$d/config.json" )
    return 0
  fi
  src="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
  [ -f "$src" ] && command -v python3 >/dev/null 2>&1 || return 0
  ( umask 077
    python3 - "$src" "$host" > "$d/config.json" 2>/dev/null <<'PY' || rm -f "$d/config.json"
import json, sys
a = json.load(open(sys.argv[1])).get("auths", {}).get(sys.argv[2])
if not a or not a.get("auth"): sys.exit(1)
print(json.dumps({"auths": {sys.argv[2]: {"auth": a["auth"]}}}))
PY
  )
  return 0
}

# The Tarleaks images the chosen services run (one per line); exit 2 when the
# list cannot be read, 3 (with the reason) when it holds no Tarleaks image: the
# sign-in service always runs one, so that is a registry setting the check does
# not read like docker compose, never "nothing to check".
_sig_tarleaks_images() {
  local images reg out
  images=$(docker compose config --images 2>/dev/null) || return 2
  reg="$(registry_value)/"
  out=$(printf '%s\n' "$images" | sort -u | awk -v r="$reg" 'index($0, r) == 1')
  if [ -z "$out" ]; then
    echo "None of the images docker-compose.yml runs comes from $reg (TARLEAKS_REGISTRY), so their Tarleaks signature cannot be checked. Check TARLEAKS_REGISTRY in .env (docker compose config --images lists what it runs)." >&2
    return 3
  fi
  printf '%s\n' "$out"
}

# No download wanted: TARLEAKS_NO_DOWNLOAD=1, or an offline installation (TARLEAKS_OFFLINE true or sealed).
_sig_offline() {
  [ "${TARLEAKS_NO_DOWNLOAD:-0}" = 1 ] && return 0
  case "${TARLEAKS_OFFLINE:-$(_reg_env TARLEAKS_OFFLINE)}" in true|sealed) return 0 ;; esac
  return 1
}

_sig_id() { docker image inspect --format '{{.Id}}' "$1" 2>/dev/null; }

# Record images as checked on this machine: "<image> <id>", one line each, the
# newest wins. Written to a file beside it, then moved over it (a record left
# owned by root by a `sudo ./install.sh` is replaced, as the folder is yours).
# Returns 1, with the fix, when it cannot be written: images checked but not
# recorded would be refused at the next start.
_sig_record() { # image...
  local img id tmp="$SIG_RECORD.new.$$"
  if { { [ ! -f "$SIG_RECORD" ] || cat "$SIG_RECORD"
         for img in "$@"; do id=$(_sig_id "$img") && [ -n "$id" ] && printf '%s %s\n' "$img" "$id"; done
       } | awk '{ last[$1] = $2; if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 } } END { for (i = 1; i <= n; i++) print order[i], last[order[i]] }' > "$tmp"; } 2>/dev/null \
     && mv -f "$tmp" "$SIG_RECORD" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  echo "Could not write $SIG_RECORD in $PWD (who owns this folder? ls -ld $PWD). Give the kit folder back to your user (sudo chown -R \"\$(id -u):\$(id -g)\" $PWD), then run the command again." >&2
  return 1
}

# After `./tarleaks load-bundle` checked the bundle's signature and loaded it:
# the Tarleaks images it loaded (under both their names) count as checked.
sig_record_loaded() { # stdin: the output of docker load
  local line img rest reg sig_imgs=()
  reg=$(registry_value)
  while IFS= read -r line; do
    img=${line#Loaded image: }
    [ "$img" != "$line" ] || continue
    case "$img" in */tarleaks-erp/*:*) ;; *) continue ;; esac
    rest=${img##*/tarleaks-erp/}
    sig_imgs+=("$img" "$reg/$rest")
  done
  [ "${#sig_imgs[@]}" = 0 ] || _sig_record "${sig_imgs[@]}"
}

# Before images already on this machine are used: each Tarleaks image must be
# recorded as checked, with the same content (id) as when it was checked.
sig_require_verified() {
  local again=${1:-./install.sh} version images img id r unchecked=() missing=()
  version=$(_sig_version)
  [ "${TARLEAKS_ALLOW_UNSIGNED:-}" != 1 ] || return 0
  _sig_needed "$version" || return 0
  images=$(_sig_tarleaks_images) || { r=$?; [ "$r" = 3 ] || echo "Could not read the list of images from docker-compose.yml, so their Tarleaks signature cannot be checked." >&2; return 1; }
  while IFS= read -r img; do
    [ -n "$img" ] || continue
    id=$(_sig_id "$img") || id=""
    if [ -z "$id" ]; then missing+=("$img")
    elif ! grep -qxF "$img $id" "$SIG_RECORD" 2>/dev/null; then unchecked+=("$img"); fi
  done <<< "$images"
  # Here but never checked here (a kit older than the check downloaded them, or the
  # record was lost): with internet, check them now, as after a download.
  if [ "${#unchecked[@]}" -gt 0 ] && [ "${#missing[@]}" = 0 ] && ! _sig_offline; then
    echo "${#unchecked[@]} images on this machine were not checked for the Tarleaks signature yet: checking them now." >&2
    # A local cosign reads the registry sign-in from Docker's own: sign in first, as a download would.
    if declare -F registry_login >/dev/null && ! registry_login "$again"; then
      echo "Nothing was started with them. Without internet, load the signed offline bundle (./tarleaks load-bundle <folder>), then run $again again. (Images you built yourself: TARLEAKS_ALLOW_UNSIGNED=1 $again)" >&2
      return 1
    fi
    sig_verify_images "$again"
    return
  fi
  if [ "${#unchecked[@]}" -gt 0 ] || [ "${#missing[@]}" -gt 0 ]; then
    [ "${#unchecked[@]}" = 0 ] || { echo "These images were not checked for the Tarleaks signature on this machine:" >&2; printf '  %s\n' "${unchecked[@]}" >&2; }
    [ "${#missing[@]}" = 0 ] || { echo "These images are not on this machine:" >&2; printf '  %s\n' "${missing[@]}" >&2; }
    echo "Nothing was started with them. With internet, run ./tarleaks upgrade ${version:-<release>}: it downloads and checks them. Without internet, load the signed offline bundle (./tarleaks load-bundle <folder>), then run $again again. (Images you built yourself: TARLEAKS_ALLOW_UNSIGNED=1 $again)" >&2
    return 1
  fi
  return 0
}

# After a download: every Tarleaks image must carry the release signature.
#   sig_verify_images "./install.sh"
sig_verify_images() {
  local again=${1:-./install.sh} version images img d r refs=() sig_imgs=() unpinned=() unsigned=() unchecked=() kept=() said="" tmp ref i
  version=$(_sig_version)
  if [ "${TARLEAKS_ALLOW_UNSIGNED:-}" = 1 ]; then
    echo "! The images' Tarleaks signature was NOT checked (TARLEAKS_ALLOW_UNSIGNED=1). Use this only for images you built or copied yourself." >&2
    return 0
  fi
  if ! _sig_needed "$version"; then
    echo "Release $version was published before Tarleaks signed its images: no signature to check." >&2
    return 0
  fi
  if [ ! -f "$RELEASE_PUBKEY" ]; then
    echo "$RELEASE_PUBKEY is missing from this kit, so the images cannot be checked. Update the kit (git pull, or download it again), then run $again again." >&2
    return 1
  fi
  images=$(_sig_tarleaks_images) || { r=$?; [ "$r" = 3 ] || echo "Could not read the list of images from docker-compose.yml, so their Tarleaks signature cannot be checked." >&2; return 1; }
  while IFS= read -r img; do
    [ -n "$img" ] || continue
    d=$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$img" 2>/dev/null \
          | awk -v r="${img%:*}@" 'index($0, r) == 1 {print; exit}')
    if [ -n "$d" ]; then refs+=("$d"); sig_imgs+=("$img"); else unpinned+=("$img"); fi
  done <<< "$images"
  if [ "${#unpinned[@]}" -gt 0 ]; then
    echo "These images have no download record, so their Tarleaks signature cannot be checked:" >&2
    printf '  %s\n' "${unpinned[@]}" >&2
    echo "Remove them (docker image rm <image>), then download and check them: ./tarleaks upgrade ${version:-<release>} (or load the signed offline bundle: ./tarleaks load-bundle <folder>). (Images you built yourself: TARLEAKS_ALLOW_UNSIGNED=1 $again)" >&2
    return 1
  fi
  [ "${#refs[@]}" -gt 0 ] || return 0
  if [ -z "$(_sig_local_cosign)" ] && ! docker image inspect "$SIG_COSIGN_IMAGE" >/dev/null 2>&1 \
     && ! docker pull -q "$SIG_COSIGN_IMAGE" >/dev/null 2>&1; then
    echo "The images' Tarleaks signature must be checked, and that needs cosign: this server has no cosign 2.4 or later, and Docker could not download Sigstore's cosign image from ghcr.io. Install cosign (one file: https://github.com/sigstore/cosign/releases), or allow outbound HTTPS to ghcr.io and pkg-containers.githubusercontent.com, then run $again again." >&2
    return 1
  fi
  tmp=$(mktemp -d) || { echo "Could not make a temporary folder (is the disk full?), so the signatures cannot be checked." >&2; return 1; }
  # The folder may hold the licence key: gone on every way out, Ctrl-C and a
  # dropped connection included (which then end the run); the caller's own
  # traps for those signals come back afterwards.
  local traps; traps=$(trap -p INT TERM HUP)
  # shellcheck disable=SC2064 # expand now: the folder name
  trap "rm -rf '$tmp'; exit 130" INT
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'; exit 143" TERM
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'; exit 129" HUP
  # Only Sigstore's cosign image needs a sign-in file; a local cosign uses Docker's own.
  [ -n "$(_sig_local_cosign)" ] || _sig_docker_config "$tmp"
  echo "Checking the Tarleaks signature of ${#refs[@]} images…" >&2
  # One cosign run for all of them; only when it fails, one per image, each with
  # its own messages: cosign's verdict means unsigned, anything else not checked.
  if ! _sig_cosign_verify "$tmp" "$tmp/all.log" "${refs[@]}"; then
    for i in "${!refs[@]}"; do
      ref=${refs[$i]}
      _sig_cosign_verify "$tmp" "$tmp/one.log" "$ref" && continue
      # cosign's verdict when either attempt gave one, else its last words.
      said=$(grep -iE "$SIG_VERDICT_RE" "$tmp/one.log" | tail -1 | cut -c1-300) || said=""
      [ -n "$said" ] || said=$(grep -v '^[[:space:]]*$' "$tmp/one.log" | tail -1 | cut -c1-300) || said=""
      if grep -qiE "$SIG_VERDICT_RE" "$tmp/one.log"; then unsigned+=("$ref|${sig_imgs[$i]}|$said"); else unchecked+=("$ref|$said"); fi
    done
  fi
  rm -rf "$tmp"; trap - INT TERM HUP; eval "$traps"
  if [ "${#unsigned[@]}" -gt 0 ]; then
    echo "These images are NOT signed by Tarleaks:" >&2
    for ref in "${unsigned[@]}"; do echo "  ${ref%%|*}" >&2; done
    said=${unsigned[0]#*|}; echo "cosign said: ${said#*|}" >&2
    # Remove them: no later run may take them as already downloaded.
    for ref in "${unsigned[@]}"; do img=${ref#*|}; img=${img%%|*}; docker image rm "$img" >/dev/null 2>&1 || kept+=("$img"); done
    if [ "${#kept[@]}" = 0 ]; then
      echo "They were removed and nothing was started with them. Do not use them: tell info@tarleaks.com what happened. (Images you built yourself: TARLEAKS_ALLOW_UNSIGNED=1 $again)" >&2
    else
      echo "Nothing was started with them. Docker could not remove ${kept[*]} (a container still uses it: docker ps -a); remove it with docker image rm. Do not use them: tell info@tarleaks.com what happened. (Images you built yourself: TARLEAKS_ALLOW_UNSIGNED=1 $again)" >&2
    fi
  fi
  if [ "${#unchecked[@]}" -gt 0 ]; then
    echo "The Tarleaks signature of these images could not be checked:" >&2
    for ref in "${unchecked[@]}"; do echo "  ${ref%%|*}" >&2; done
    echo "cosign said: ${unchecked[0]#*|}" >&2
    echo "Nothing was started with them, and nothing was removed. Fix what cosign names (usually the connection to $(registry_host), or ghcr.io when this server has no cosign; a refused sign-in: check the licence), then run $again again. Without internet, load the signed offline bundle (./tarleaks load-bundle <folder>)." >&2
  fi
  [ "${#unsigned[@]}" = 0 ] && [ "${#unchecked[@]}" = 0 ] || return 1
  _sig_record "${sig_imgs[@]}" || return 1
  echo "✓ Every Tarleaks image is signed by Tarleaks (release key $(_sig_key_id))." >&2
  return 0
}

# A short id of the release key (sha256 of the public key file), for the message.
_sig_key_id() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$RELEASE_PUBKEY"; else shasum -a 256 "$RELEASE_PUBKEY"; fi | cut -c1-12
}
