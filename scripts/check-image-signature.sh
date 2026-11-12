#!/usr/bin/env bash
# No Tarleaks image runs unless this machine checked it against the release key (scripts/lib-signature.sh):
#  - after a download (sig_verify_images, called by apps_pull): a signed set passes and is recorded; an image cosign
#    calls unsigned is refused, named and removed; any other cosign failure (network, refused sign-in, a mount Docker
#    refused) refuses WITHOUT removing; each failing image gets its own message, wherever it is in the list;
#  - images already here (sig_require_verified: no download, a failed download, a failed sign-in, ./tarleaks start):
#    each must be recorded with the same image id; unrecorded, changed or missing images are refused;
#  - a signed offline bundle's images are recorded (sig_record_loaded);
#  - a kit without the public key, an image Docker keeps no digest for, an unreadable compose file all refuse;
#    TARLEAKS_ALLOW_UNSIGNED=1 and an older release number pass without cosign; latest/empty are checked;
#  - without a usable cosign, Sigstore's pinned image runs read-only as this user with only the key folder and a mode
#    600 licence-key sign-in mounted, removed afterwards; without that image either, it refuses with the fix;
#  - apps_pull answers 3 on every refusal and ./tarleaks upgrade then stops before its backup with .env unchanged.
# docker and cosign are stubs (no network, no images): a stub signature is a line "<repository@digest> <release key>".
# CI runs it; the same checks for Windows: scripts/check-image-signature.ps1.
#   bash scripts/check-image-signature.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
kit="$work/kit"; bin="$work/bin"; mkdir -p "$kit" "$bin"
tar --exclude=.git -cf - . | tar -xf - -C "$kit"
rm -f "$kit/.tarleaks-verified"
KEY=release-key-under-test
REG=registry.tarleaks.com/tarleaks-erp
export STUB_LOG="$work/calls.log" STUB_SIGNED="$work/signed.txt" STUB_DIGESTS="$work/digests.txt" STUB_IMAGES="$work/images.txt" \
  STUB_IDS="$work/ids.txt" STUB_SEEN_CONFIG="$work/seen-config.json" STUB_COSIGN="$bin/cosign"

cat > "$bin/cosign" <<'EOF'
#!/usr/bin/env bash
echo "cosign $*" >> "$STUB_LOG"
case "$1" in
  version) echo "GitVersion:    v${STUB_COSIGN_VERSION:-3.1.4}"; exit 0 ;;
  verify) shift ;;
  *) echo "stub cosign: unexpected command $1" >&2; exit 2 ;;
esac
key="" refs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --key) key=$2; shift 2 ;;
    --trusted-root) [ -f "$2" ] || { echo "no trust root $2" >&2; exit 1; }; shift 2 ;;
    --output) shift 2 ;;
    --new-bundle-format) shift ;;
    -*) echo "stub cosign: unknown flag $1" >&2; exit 2 ;;
    *) refs+=("$1"); shift ;;
  esac
done
for r in "${refs[@]}"; do
  case " ${STUB_NET_DOWN_FOR:-} " in *" $r "*|*" all "*) echo "Error: GET https://registry.tarleaks.com/v2/: dial tcp: i/o timeout" >&2; exit 1 ;; esac
  case " ${STUB_UNAUTH_FOR:-} " in *" $r "*) echo "Error: GET https://registry.tarleaks.com/v2/x/manifests/sha256-y.sig: UNAUTHORIZED: authentication required" >&2; exit 1 ;; esac
  grep -qxF "$r $(cat "$key")" "$STUB_SIGNED" 2>/dev/null || { echo "Error: no matching signatures: $r" >&2; exit 1; }
done
echo "Verification for ${refs[*]} -- the signatures were verified against the specified public key" >&2
EOF
cat > "$bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
case "$1 ${2:-}" in
  "compose config") [ "${STUB_COMPOSE_FAIL:-0}" = 1 ] && { echo "invalid compose file" >&2; exit 1; }; cat "$STUB_IMAGES"; exit 0 ;;
  "compose pull") [ "${STUB_PULL_FAIL:-0}" = 1 ] && { echo "Get https://registry.tarleaks.com/v2/: dial tcp 1.2.3.4:443: i/o timeout" >&2; exit 1; }; exit 0 ;;
  "compose "*) exit 0 ;;
  "image inspect")
    img=${!#}
    case "${4:-}" in
      *RepoDigests*) awk -v i="$img" '$1 == i {print $2}' "$STUB_DIGESTS"; exit 0 ;;
      *.Id*) awk -v i="$img" '$1 == i {print $2; f=1} END {exit !f}' "$STUB_IDS"; exit ;;
    esac
    case "$img" in ghcr.io/sigstore/*) [ "${STUB_COSIGN_IMAGE_HERE:-0}" = 1 ] && exit 0; exit 1 ;; esac
    awk -v i="$img" '$1 == i {f=1} END {exit !f}' "$STUB_IDS"; exit ;;
  "image rm") [ "${STUB_RM_FAIL:-0}" = 1 ] && { echo "Error response from daemon: conflict: unable to remove repository reference (must force) - container abc is using its referenced image" >&2; exit 1; }; exit 0 ;;
  "pull -q") [ "${STUB_PULL_OK:-1}" = 1 ] && exit 0; echo "Error response from daemon: Get https://ghcr.io/v2/: dial tcp: i/o timeout" >&2; exit 1 ;;
  "run --rm")
    # the cosign image: map the mounted key folder back to this machine and run the stub cosign on it
    shift 2; keydir="" cfgdir="" args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        -v) case "$2" in *:/sigstore:ro,z) keydir=${2%:/sigstore:ro,z} ;; *:/docker:ro,z) cfgdir=${2%:/docker:ro,z} ;; esac; shift 2 ;;
        -e|--user|--tmpfs) shift 2 ;;
        --read-only) shift ;;
        ghcr.io/sigstore/*) shift; break ;;
        *) echo "stub docker run: unexpected $1" >&2; exit 2 ;;
      esac
    done
    [ -n "$cfgdir" ] && [ -f "$cfgdir/config.json" ] && cp "$cfgdir/config.json" "$STUB_SEEN_CONFIG" \
      && ls -l "$cfgdir/config.json" | cut -c1-10 >> "$STUB_SEEN_CONFIG.mode"
    for a in "$@"; do args+=("${a//\/sigstore/$keydir}"); done
    exec "$STUB_COSIGN" "${args[@]}" ;;
esac
exit 0
EOF
# no network in a test: the licence pre-check finds no registry and leaves the answer to (stub) docker login
printf '#!/bin/sh\nexit 7\n' > "$bin/curl"
chmod +x "$bin/cosign" "$bin/docker" "$bin/curl"

pub() { mkdir -p "$kit/config/sigstore"; printf '%s\n' "$1" > "$kit/config/sigstore/tarleaks-release.pub"; }
image() { # unit digest [signed-with-key]
  echo "$REG/$1:1.2.0" >> "$STUB_IMAGES"
  echo "$REG/$1:1.2.0 $REG/$1@sha256:$2" >> "$STUB_DIGESTS"
  echo "$REG/$1:1.2.0 sha256:id-$2" >> "$STUB_IDS"
  [ -z "${3:-}" ] || echo "$REG/$1@sha256:$2 $3" >> "$STUB_SIGNED"
}
reset() {
  : > "$STUB_IMAGES"; : > "$STUB_DIGESTS"; : > "$STUB_SIGNED"; : > "$STUB_IDS"; rm -f "$STUB_SEEN_CONFIG" "$STUB_SEEN_CONFIG.mode" "$kit/.tarleaks-verified"
  # third-party: not checked here (pinned by digest and scanned by the release)
  echo "redis:7.4.12-alpine" >> "$STUB_IMAGES"; echo "redis:7.4.12-alpine sha256:id-redis" >> "$STUB_IDS"
  printf 'TARLEAKS_VERSION=1.2.0\nTARLEAKS_LICENSE_KEY=tlk1.test-licence-key\n' > "$kit/.env"
}

fails=0 LAST_OUT=""
check() { # name want-exit want-text shell-code -- environment assignments (VAR=value ...)
  local name=$1 want=$2 text=$3 fn=$4; shift 5
  : > "$STUB_LOG"; rm -rf "$work/tmp"; mkdir -p "$work/tmp"
  local rc=0 out
  out=$(cd "$kit" && env "$@" TMPDIR="$work/tmp" PATH="${PATHX:-$bin:$PATH}" bash -c ". scripts/lib-apps.sh; registry_login() { return 0; }; $fn ./install.sh" 2>&1) || rc=$?
  if [ "$rc" != "$want" ] || { [ -n "$text" ] && ! printf '%s' "$out" | grep -qF -- "$text"; }; then
    echo "FAIL $name: exit $rc (want $want), output:"; printf '%s\n' "$out" | sed 's/^/    /'
    fails=$((fails + 1))
  else echo "ok   $name"; fi
  LAST_OUT=$out
}
verify() { check "$1" "$2" "$3" sig_verify_images "${@:4}"; }
require() { check "$1" "$2" "$3" sig_require_verified "${@:4}"; }
expect_log() { # name pattern [absent]
  if grep -qE -- "$2" "$STUB_LOG"; then
    [ "${3:-}" = absent ] && { echo "FAIL $1"; fails=$((fails + 1)); return; }
  else
    [ "${3:-}" = absent ] || { echo "FAIL $1"; fails=$((fails + 1)); return; }
  fi
  echo "ok   $1"
}
assert() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
said() { printf '%s' "$LAST_OUT" | grep -qF -- "$1"; }

pub "$KEY"
# --- after a download ---
reset; image auth aaa1 "$KEY"; image hr bbb2 "$KEY"
verify "every image signed with the release key passes" 0 "Every Tarleaks image is signed by Tarleaks" -- X=1
expect_log "one cosign run checks them all, the kit's trust root first" "cosign verify --key config/sigstore/tarleaks-release.pub --trusted-root config/sigstore/trusted_root.json --output text $REG/auth@sha256:aaa1 $REG/hr@sha256:bbb2"
expect_log "third-party images are not sent to cosign" "verify.*redis" absent
assert "  ...and both are recorded as checked, with their image ids" "grep -qx '$REG/auth:1.2.0 sha256:id-aaa1' '$kit/.tarleaks-verified' && grep -qx '$REG/hr:1.2.0 sha256:id-bbb2' '$kit/.tarleaks-verified'"

reset; image auth aaa1; image hr bbb2 "$KEY"
verify "an unsigned image FIRST in the list is refused and named" 1 "$REG/auth@sha256:aaa1" -- X=1
assert "  ...with its own cosign message, not the last image's" "said 'cosign said: Error: no matching signatures: $REG/auth@sha256:aaa1'"
expect_log "the unsigned image is removed, so no later run takes it as downloaded" "docker image rm $REG/auth:1.2.0"
expect_log "the signed one is kept" "docker image rm $REG/hr" absent
assert "nothing is recorded after a refusal" "[ ! -s '$kit/.tarleaks-verified' ]"

reset; image auth aaa1 "someone-else's-key"
verify "an image signed with another key is refused" 1 "NOT signed by Tarleaks" -- X=1

reset; image auth aaa1 "$KEY"
verify "a network failure refuses without removing anything" 1 "could not be checked" -- STUB_NET_DOWN_FOR=all
expect_log "  ...nothing removed" "image rm" absent

reset; image auth aaa1 "$KEY"; image hr bbb2 "$KEY"
verify "a refused sign-in is 'not checked', never 'unsigned'" 1 "could not be checked" -- "STUB_UNAUTH_FOR=$REG/auth@sha256:aaa1"
assert "  ...in cosign's own words" "said UNAUTHORIZED && ! said 'NOT signed'"
expect_log "  ...nothing removed" "image rm" absent

reset; image auth aaa1 "$KEY"; image hr bbb2
verify "a network failure on one image and an unsigned other are both named, each for what it is" 1 "NOT signed by Tarleaks" -- "STUB_NET_DOWN_FOR=$REG/auth@sha256:aaa1"
assert "  ...the first not checked and kept, the second removed" "said 'could not be checked' && grep -q 'docker image rm $REG/hr:1.2.0' '$STUB_LOG' && ! grep -q 'docker image rm $REG/auth' '$STUB_LOG'"

reset; image auth aaa1 "$KEY"; sed -i.bak '/auth/d' "$STUB_DIGESTS"
verify "an image with no download digest is refused" 1 "no download record" -- X=1
assert "  ...naming the way out for images built here" "said 'TARLEAKS_ALLOW_UNSIGNED=1 ./install.sh'"

reset; image auth aaa1
verify "an unsigned image Docker cannot remove (in use) is refused and says so" 1 "Docker could not remove $REG/auth:1.2.0" -- STUB_RM_FAIL=1
assert "  ...never 'They were removed'" "! said 'They were removed'"

# docker compose reads .env values without quotes and carriage returns: so does the check, which
# must never find "no Tarleaks image" and pass.
reset; image auth aaa1
printf 'TARLEAKS_VERSION=1.2.0\r\nTARLEAKS_REGISTRY="%s"\r\nTARLEAKS_LICENSE_KEY=tlk1.test-licence-key\r\n' "$REG" > "$kit/.env"
verify "a quoted TARLEAKS_REGISTRY in a CRLF .env still checks (an unsigned image is refused)" 1 "NOT signed by Tarleaks" -- X=1
reset; : > "$STUB_IMAGES"; echo "redis:7.4.12-alpine" >> "$STUB_IMAGES"; echo "other.example.com/erp/auth:1.2.0" >> "$STUB_IMAGES"
verify "a compose file with no image from the registry refuses (it never passes unchecked)" 1 "None of the images docker-compose.yml runs comes from $REG/" -- X=1
require "  ...also for images already here" 1 "None of the images" -- X=1

reset; image auth aaa1 "$KEY"
verify "a compose file that cannot be read refuses" 1 "Could not read the list of images" -- STUB_COMPOSE_FAIL=1

reset; image auth aaa1
verify "TARLEAKS_ALLOW_UNSIGNED=1 passes, with a warning" 0 "NOT checked (TARLEAKS_ALLOW_UNSIGNED=1)" -- TARLEAKS_ALLOW_UNSIGNED=1
expect_log "  ...and asks cosign nothing" "verify" absent

reset; image auth aaa1; printf 'TARLEAKS_VERSION=1.2.0-rc.6\n' > "$kit/.env"
verify "a release from before signing (rc.6) is not checked" 0 "published before Tarleaks signed its images" -- X=1
reset; image auth aaa1
for v in 1.2.0-rc.10 1.2.0-rc.7 1.2.0-rc.7-candidate latest v1.2.0; do
  verify "$v is checked" 1 "NOT signed by Tarleaks" -- "TARLEAKS_VERSION=$v"
done
printf 'TARLEAKS_LICENSE_KEY=tlk1.test-licence-key\n' > "$kit/.env"
verify "no release named at all is checked" 1 "NOT signed by Tarleaks" -- X=1
verify "1.1.9 is not" 0 "published before Tarleaks signed" -- TARLEAKS_VERSION=1.1.9

reset; image auth aaa1 "$KEY"; rm "$kit/config/sigstore/tarleaks-release.pub"
verify "a kit without the release public key refuses" 1 "tarleaks-release.pub is missing from this kit" -- X=1
pub "$KEY"

# --- without a usable cosign: Sigstore's pinned image ---
nocosign="$work/nocosign"; mkdir -p "$nocosign"; ln -s "$bin/docker" "$nocosign/docker"
if (PATH="$nocosign:/usr/bin:/bin"; command -v cosign >/dev/null 2>&1); then
  echo "skip without cosign: this machine has cosign in /usr/bin or /bin"
else
  reset; image auth aaa1 "$KEY"; image hr bbb2 "$KEY"
  PATHX="$nocosign:/usr/bin:/bin" verify "without cosign, Sigstore's cosign image checks them" 0 "Every Tarleaks image is signed" -- STUB_PULL_OK=1
  expect_log "  ...pinned by digest, read-only, as this user" "docker run --rm --user [0-9]+:[0-9]+ --read-only --tmpfs /tmp -e HOME=/tmp -v $kit/config/sigstore:/sigstore:ro,z -v [^ ]+:/docker:ro,z -e DOCKER_CONFIG=/docker ghcr.io/sigstore/cosign/cosign:v3.1.4@sha256:0f06154836d2de34f887a5c273506d52ca43edaa1d9e53e6510fa78a48f69c2d verify"
  want_auth=$(printf 'licence:tlk1.test-licence-key' | base64 | tr -d '\n')
  assert "  ...signed in with the licence key" "grep -qF '\"registry.tarleaks.com\":{\"auth\":\"$want_auth\"}' '$STUB_SEEN_CONFIG'"
  assert "  ...through a mode 600 file" "grep -q '^-rw-------' '$STUB_SEEN_CONFIG.mode'"
  assert "  ...removed afterwards with cosign's messages" "[ -z \"\$(ls -A '$work/tmp')\" ]"
  reset; image auth aaa1
  PATHX="$nocosign:/usr/bin:/bin" verify "the image path refuses an unsigned image too" 1 "NOT signed by Tarleaks" -- STUB_PULL_OK=1
  reset; image auth aaa1 "$KEY"
  PATHX="$nocosign:/usr/bin:/bin" verify "no cosign and no way to get its image: refused with the fix" 1 "allow outbound HTTPS to ghcr.io" -- STUB_PULL_OK=0
  # Another registry: only its own entry of Docker's config.json goes into the container.
  if command -v python3 >/dev/null 2>&1; then
    reset; mkdir -p "$work/dc"; ( umask 077; printf '{"auths":{"mirror.example.com":{"auth":"bWlycm9y"},"other.example.com":{"auth":"b3RoZXI="}}}' > "$work/dc/config.json" )
    M=mirror.example.com/tarleaks-erp
    { echo "$M/auth:1.2.0"; } >> "$STUB_IMAGES"
    echo "$M/auth:1.2.0 $M/auth@sha256:ccc3" >> "$STUB_DIGESTS"
    echo "$M/auth:1.2.0 sha256:id-ccc3" >> "$STUB_IDS"
    echo "$M/auth@sha256:ccc3 $KEY" >> "$STUB_SIGNED"
    PATHX="$nocosign:$(dirname "$(command -v python3)"):/usr/bin:/bin" verify "a mirror registry gets only its own sign-in" 0 "Every Tarleaks image is signed" -- TARLEAKS_REGISTRY=$M "DOCKER_CONFIG=$work/dc"
    assert "  ...never the other registries' passwords" "grep -q 'mirror.example.com' '$STUB_SEEN_CONFIG' && ! grep -q 'other.example.com' '$STUB_SEEN_CONFIG'"
  fi
fi
reset; image auth aaa1 "$KEY"
verify "cosign older than 2.4 is not used (the image is)" 0 "Every Tarleaks image is signed" -- STUB_COSIGN_VERSION=2.2.4
expect_log "  ...cosign 2.2 never verifies" "^cosign verify --key config/" absent
verify "cosign 2.5 is used, with --new-bundle-format" 0 "Every Tarleaks image is signed" -- STUB_COSIGN_VERSION=2.5.0
expect_log "  ...--new-bundle-format given" "^cosign verify --new-bundle-format --key config/"

# --- images already on this machine ---
reset; image auth aaa1 "$KEY"; image hr bbb2 "$KEY"
require "offline, images never checked here are refused" 1 "were not checked for the Tarleaks signature on this machine" -- TARLEAKS_NO_DOWNLOAD=1
assert "  ...naming the way out for images built here" "said 'TARLEAKS_ALLOW_UNSIGNED=1 ./install.sh'"
printf 'TARLEAKS_VERSION=1.2.0\nTARLEAKS_OFFLINE=sealed\nTARLEAKS_LICENSE_KEY=tlk1.test-licence-key\n' > "$kit/.env"
require "an offline installation (TARLEAKS_OFFLINE=sealed) refuses them, without going online" 1 "load the signed offline bundle" -- X=1
expect_log "  ...cosign is not asked" "verify" absent
reset; image auth aaa1 "$KEY"; image hr bbb2 "$KEY"
check "online, a refused sign-in refuses them" 1 "" "registry_login() { echo 'sign-in refused' >&2; return 1; }; sig_require_verified" -- X=1
require "online, images never checked here are checked now (a kit older than the check downloaded them)" 0 "checking them now" -- X=1
assert "  ...and recorded" "grep -qx '$REG/hr:1.2.0 sha256:id-bbb2' '$kit/.tarleaks-verified'"
require "recorded images with the same content pass" 0 "" -- X=1
expect_log "  ...without asking cosign" "verify" absent
reset; image auth aaa1
require "online, an unchecked unsigned image here is refused" 1 "NOT signed by Tarleaks" -- X=1
reset; image auth aaa1 "$KEY"; image hr bbb2 "$KEY"
require "(checked once)" 0 "checking them now" -- X=1
sed -i.bak -e "s#^$REG/hr:1.2.0 .*#$REG/hr:1.2.0 sha256:id-other#" "$STUB_IDS"
sed -i.bak -e "s#^$REG/hr:1.2.0 .*#$REG/hr:1.2.0 $REG/hr@sha256:other#" "$STUB_DIGESTS"
require "an image swapped for another download since it was checked is refused" 1 "NOT signed by Tarleaks" -- X=1
assert "  ...named" "said '$REG/hr@sha256:other'"
sed -i.bak "/hr:1.2.0/d" "$STUB_DIGESTS"
require "an image built here under the release's name (no download digest) is refused" 1 "no download record" -- X=1
require "offline, a changed image is refused" 1 "$REG/hr:1.2.0" -- TARLEAKS_NO_DOWNLOAD=1
sed -i.bak "/hr:1.2.0/d" "$STUB_IDS"
require "a missing image is refused (a start would download it unchecked)" 1 "are not on this machine" -- X=1
require "TARLEAKS_ALLOW_UNSIGNED=1 passes" 0 "" -- TARLEAKS_ALLOW_UNSIGNED=1
require "an older release number passes" 0 "" -- TARLEAKS_VERSION=1.2.0-rc.5
require "a compose file that cannot be read refuses" 1 "Could not read the list of images" -- STUB_COMPOSE_FAIL=1

reset; image auth aaa1 "$KEY"
echo "ghcr.io/x/tarleaks-erp/auth:1.2.0 sha256:id-aaa1" >> "$STUB_IDS"
check "a signed bundle's images are recorded" 0 "" "printf 'Loaded image: ghcr.io/x/tarleaks-erp/auth:1.2.0\nLoaded image: redis:7.4.12-alpine\n' | sig_record_loaded; sig_require_verified" -- X=1
assert "  ...under the name it was built with and the one this installation runs, third-party images not" "grep -qx 'ghcr.io/x/tarleaks-erp/auth:1.2.0 sha256:id-aaa1' '$kit/.tarleaks-verified' && grep -qx '$REG/auth:1.2.0 sha256:id-aaa1' '$kit/.tarleaks-verified' && ! grep -q redis '$kit/.tarleaks-verified'"

# The record cannot be written (a kit folder left to root by sudo): refused with the fix, never "checked" and then
# refused at the next start.
if [ "$(id -u)" != 0 ]; then
  reset; image auth aaa1 "$KEY"; chmod a-w "$kit"
  verify "a record that cannot be written refuses, saying how to fix the folder" 1 "Could not write .tarleaks-verified in" -- X=1
  assert "  ...and leaves no temporary file" "[ -z \"\$(ls -A '$kit' | grep 'tarleaks-verified.new')\" ]"
  chmod u+w "$kit"
else echo "skip unwritable record: running as root"; fi

# --- apps_pull: every way to images is checked; a refusal is exit 3, never a fallback ---
reset; image auth aaa1 "$KEY"
check "apps_pull: a download of signed images passes" 0 "Every Tarleaks image is signed" apps_pull -- X=1
reset; image auth aaa1
check "apps_pull: an unsigned download is exit 3" 3 "NOT signed by Tarleaks" apps_pull -- X=1
reset; image auth aaa1
check "apps_pull: a failed download with unsigned images here is exit 3" 3 "NOT signed by Tarleaks" apps_pull -- STUB_PULL_FAIL=1 TARLEAKS_PULL_TRIES=1
reset; image auth aaa1 "$KEY"
check "apps_pull: a failed download with unchecked images that cannot be checked is exit 3" 3 "could not be checked" apps_pull -- STUB_PULL_FAIL=1 TARLEAKS_PULL_TRIES=1 STUB_NET_DOWN_FOR=all
check "apps_pull: a refused sign-in with unchecked images here is exit 3 (the check signs in first, refused too)" 3 "checking them now" "registry_login() { return 1; }; apps_pull" -- X=1
check "apps_pull: offline with unchecked images is exit 3" 3 "were not checked" apps_pull -- TARLEAKS_NO_DOWNLOAD=1
check "(a download checks and records them)" 0 "Every Tarleaks image is signed" sig_verify_images -- X=1
check "apps_pull: a failed download with checked images here carries on" 0 "Carrying on with those" apps_pull -- STUB_PULL_FAIL=1 TARLEAKS_PULL_TRIES=1
check "apps_pull: a refused sign-in with checked images here carries on" 0 "Carrying on with the images" "registry_login() { return 1; }; apps_pull" -- X=1
check "apps_pull: offline with checked images carries on" 0 "Offline" apps_pull -- TARLEAKS_NO_DOWNLOAD=1

# --- ./tarleaks upgrade: a refused download stops it before the backup, .env unchanged ---
reset; image auth aaa1
printf 'TARLEAKS_VERSION=1.2.0-rc.9\nTARLEAKS_LICENSE_KEY=tlk1.test-licence-key\n' > "$kit/.env"
: > "$STUB_LOG"; rc=0
up=$(cd "$kit" && TMPDIR="$work/tmp" PATH="$bin:$PATH" TARLEAKS_PULL_TRIES=1 ./tarleaks upgrade 1.2.0 2>&1) || rc=$?
if [ "$rc" = 1 ] && printf '%s' "$up" | grep -q 'NOT signed by Tarleaks' && printf '%s' "$up" | grep -q 'Nothing was changed: .env still names 1.2.0-rc.9' \
   && ! printf '%s' "$up" | grep -q 'Taking a backup' && grep -qx 'TARLEAKS_VERSION=1.2.0-rc.9' "$kit/.env"; then
  echo "ok   ./tarleaks upgrade refuses an unsigned download before its backup, .env unchanged"
else
  echo "FAIL ./tarleaks upgrade with an unsigned download: exit $rc, output:"; printf '%s\n' "$up" | tail -15 | sed 's/^/    /'; fails=$((fails + 1))
fi
# Every command that starts the Tarleaks services first downloads-and-checks or checks what is here: a
# `docker compose up` with neither nearby could download (and start) an image nobody checked.
for f in tarleaks:4 tarleaks.ps1:4 install.sh:16 install.ps1:16; do
  bad=$(awk -v W="${f#*:}" '{ l[NR] = $0 } /compose up -d --remove-orphans/ && !/^ *#/ {
      ok = 0; for (i = NR - W; i <= NR; i++) if (l[i] ~ /sig_require_verified|apps_pull|Confirm-ReleaseVerified|Confirm-ReleaseImage|Invoke-AppPull/) ok = 1
      if (!ok) print FILENAME ":" NR }' "$kit/${f%%:*}")
  if [ -z "$bad" ]; then echo "ok   every start in ${f%%:*} checks the images first"
  else echo "FAIL a start with no signature check before it: $bad"; fails=$((fails + 1)); fi
done
# The other ways a Tarleaks image runs: the off-site backup engine and a restarted sign-in service.
for g in "scripts/lib-cloud.sh:cloud_engine_available() {:sig_require_verified" "scripts/lib-cloud.sh:cloud_engine() {:sig_require_verified" \
         "scripts/lib-cloud.ps1:function Test-CloudEngine {:Confirm-ReleaseVerified" "scripts/lib-cloud.ps1:function Invoke-CloudEngine(:Confirm-ReleaseVerified" \
         "scripts/lib-move.sh:docker compose up -d --no-deps auth auth-jobs:sig_require_verified" \
         "scripts/lib-move.ps1:docker compose up -d --no-deps auth auth-jobs:Confirm-ReleaseVerified"; do
  IFS=: read -r gf gat gneed <<< "$g"
  if awk -v A="$gat" -v N="$gneed" '{ l[NR] = $0 } index($0, A) && !s { s = NR }
       END { if (!s) exit 1; for (i = s - 4; i <= s + 4; i++) if (index(l[i], N)) exit 0; exit 1 }' "$kit/$gf"; then
    echo "ok   $gf: '$gat' checks the images"
  else echo "FAIL $gf: no $gneed next to '$gat'"; fails=$((fails + 1)); fi
done
grep -qF 'nd=1' "$kit/tarleaks" && grep -qF 'TARLEAKS_NO_DOWNLOAD=$nd COMPOSE_PROFILES' "$kit/tarleaks" \
  && echo "ok   ./tarleaks upgrade --offline never checks images online" \
  || { echo "FAIL ./tarleaks upgrade --offline would check images online"; fails=$((fails + 1)); }
grep -qF 'sig_require_verified "./tarleaks offline $mode" || die' "$kit/tarleaks" \
  && echo "ok   ./tarleaks offline checks the images before it changes anything" \
  || { echo "FAIL ./tarleaks offline restarts on images it did not check"; fails=$((fails + 1)); }
grep -q 'export TARLEAKS_ALLOW_UNSIGNED=1' "$kit/scripts/release-gate.sh" \
  && echo "ok   the release gate (candidates, signed only after it) switches the check off explicitly" \
  || { echo "FAIL the release gate would refuse the unsigned candidates"; fails=$((fails + 1)); }

[ "$fails" = 0 ] || { echo "$fails check(s) failed"; exit 1; }
echo "image signature: all checks passed"
