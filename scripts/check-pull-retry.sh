#!/usr/bin/env bash
# The image download (apps_pull in scripts/lib-apps.sh) tries again after a
# dropped connection, never after a refusal, and shows what Docker said when it
# gives up. Docker is a stub here: no network, no images. CI runs it.
#   bash scripts/check-pull-retry.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib-apps.sh
. scripts/lib-apps.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# Stubs: the registry helpers and docker. STUB_FAILS lines are what each pull
# prints to stderr in turn ("ok" = that pull succeeds).
registry_move_off_retired() { :; }
registry_login() { return 0; }
registry_host() { echo registry.example.com; }
registry_takes_licence() { return 0; }
_apps_missing_images() { echo "example/app:1"; }
sleep() { :; }
# The signature check has its own test (scripts/check-image-signature.sh); here only the download counts.
sig_verify_images() { return 0; }
sig_require_verified() { return 0; }
docker() {
  local n; n=$(($(cat "$work/calls") + 1)); echo "$n" > "$work/calls"
  local said; said=$(sed -n "${n}p" "$work/script")
  [ "$said" = ok ] && return 0
  echo "$said" >&2; return 1
}
fails=0
run() { # name expected-exit expected-calls expected-text  (stdin: one line per pull; never piped in, so the count survives)
  cat > "$work/script"; echo 0 > "$work/calls"
  local rc=0 out; out=$(apps_pull ./install.sh 2>&1) || rc=$?
  local calls; calls=$(cat "$work/calls")
  if [ "$rc" != "$2" ] || [ "$calls" != "$3" ] || { [ -n "$4" ] && ! printf '%s' "$out" | grep -qF -- "$4"; }; then
    echo "FAIL $1: exit $rc (want $2), pulls $calls (want $3), output:"; printf '%s\n' "$out" | sed 's/^/    /'; fails=$((fails + 1))
  else echo "ok   $1"; fi
}
run "a pull that works is not repeated" 0 1 "" < <(printf 'ok\n')
run "an unexpected EOF is tried again" 0 2 "The download was interrupted (Error response from daemon: Get \"https://ghcr.io/v2/\": unexpected EOF)" < <(printf 'Error response from daemon: Get "https://ghcr.io/v2/": unexpected EOF\nok\n')
run "two drops, then it works" 0 3 "Trying again" < <(printf 'net/http: TLS handshake timeout\nread: connection reset by peer\nok\n')
run "three drops: gives up and shows what Docker said" 1 3 "Docker said: dial tcp 1.2.3.4:443: i/o timeout" < <(printf 'unexpected EOF\nunexpected EOF\ndial tcp 1.2.3.4:443: i/o timeout\n')
run "a refused licence is not tried again" 1 1 "refused the download with this licence key" < <(printf 'Error response from daemon: unauthorized: authentication required\nok\n')
run "a missing release is not tried again" 1 1 "has no image" < <(printf 'manifest unknown: example/app:9.9\nok\n')
run "a full disk is not tried again" 1 1 "The disk is full" < <(printf 'write /var/lib/docker/x: no space left on device\nok\n')
TARLEAKS_PULL_TRIES=1 run "TARLEAKS_PULL_TRIES=1 turns the retry off" 1 1 "Docker said: unexpected EOF" <<< 'unexpected EOF'
[ "$fails" = 0 ] || { echo "$fails case(s) failed."; exit 1; }
echo "OK: the image download retries a dropped connection and shows Docker's error."
