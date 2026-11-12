#!/usr/bin/env bash
# `./tarleaks load-bundle` refuses a bundle whose checksum list is not signed with the Tarleaks release key: no
# signature, another key, a list changed after signing, a kit without the public key, no cosign or one too old. It
# loads nothing it refused, and --allow-unsigned (or TARLEAKS_ALLOW_UNSIGNED=1) is the only way past. cosign and
# docker are stubs here (no network, no images): a stub "signature" is the signing key and the file's sha256, so
# the stub verifies exactly when the real one would. CI runs it.
#   bash scripts/check-bundle-signature.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
kit="$work/kit"; bin="$work/bin"; mkdir -p "$kit" "$bin"
tar --exclude=.git -cf - . | tar -xf - -C "$kit"
KEY=release-key-under-test
export STUB_LOG="$work/calls.log"

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
sign() { printf 'sig:%s:%s' "$2" "$(sha "$1")" > "$1.sigstore.json"; } # file key

cat > "$bin/cosign" <<'EOF'
#!/usr/bin/env bash
echo "cosign $*" >> "$STUB_LOG"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
case "$1" in
  version) echo "GitVersion:    v${STUB_COSIGN_VERSION:-3.1.4}"; exit 0 ;;
  verify-blob) shift ;;
  *) echo "stub cosign: unexpected command $1" >&2; exit 2 ;;
esac
key="" bundle="" file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --key) key=$2; shift 2 ;;
    --bundle) bundle=$2; shift 2 ;;
    --trusted-root) [ -f "$2" ] || { echo "no trust root $2" >&2; exit 1; }; shift 2 ;;
    --new-bundle-format) shift ;;
    -*) echo "stub cosign: unknown flag $1" >&2; exit 2 ;;
    *) file=$1; shift ;;
  esac
done
[ "$(cat "$bundle")" = "sig:$(cat "$key"):$(sha "$file")" ] \
  || { echo "Error: none of the verifiers verified: invalid signature when validating ASN.1 encoded signature" >&2; exit 1; }
echo "Verified OK" >&2
EOF
cat > "$bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
case "$1 ${2:-}" in
  "info --format") echo x86_64 ;;
  "load -i") echo "Loaded image: example/app:1" ;;
esac
exit 0
EOF
chmod +x "$bin/cosign" "$bin/docker"

bundle() { # folder [signing key] — a one-image bundle; signed when a key is given
  rm -rf "$1"; mkdir -p "$1/images"
  printf '# platform: linux/amd64\nexample/app:1\n' > "$1/images.txt"
  echo "image bytes" > "$1/images/app.tar"
  (cd "$1" && if command -v sha256sum >/dev/null 2>&1; then sha256sum images/app.tar; else shasum -a 256 images/app.tar; fi > SHA256SUMS)
  [ -z "${2:-}" ] || sign "$1/SHA256SUMS" "$2"
}
archive() { # bundle-folder download-folder [outer signing key] — the release's .tar with its own checksum list beside it
  rm -rf "$2"; mkdir -p "$2"
  tar -cf "$2/tarleaks-test.tar" -C "$(dirname "$1")" "$(basename "$1")"
  (cd "$2" && if command -v sha256sum >/dev/null 2>&1; then sha256sum tarleaks-test.tar; else shasum -a 256 tarleaks-test.tar; fi > tarleaks-test.SHA256SUMS)
  [ -z "${3:-}" ] || sign "$2/tarleaks-test.SHA256SUMS" "$3"
}
pub() { mkdir -p "$kit/config/sigstore"; printf '%s\n' "$1" > "$kit/config/sigstore/tarleaks-release.pub"; }

fails=0
check() { # name want-exit want-text loads(yes|no) -- load-bundle arguments; env: STUB_COSIGN_VERSION, TARLEAKS_ALLOW_UNSIGNED, PATHX
  local name=$1 want=$2 text=$3 loads=$4; shift 5
  : > "$STUB_LOG"
  local rc=0 out
  out=$(cd "$kit" && PATH="${PATHX:-$bin:$PATH}" ./tarleaks load-bundle "$@" 2>&1) || rc=$?
  local loaded=no; grep -q '^docker load' "$STUB_LOG" && loaded=yes
  if [ "$rc" != "$want" ] || [ "$loaded" != "$loads" ] || ! printf '%s' "$out" | grep -qF -- "$text"; then
    echo "FAIL $name: exit $rc (want $want), loaded $loaded (want $loads), output:"; printf '%s\n' "$out" | sed 's/^/    /'
    fails=$((fails + 1))
  else echo "ok   $name"; fi
}

pub "$KEY"
bundle "$work/good" "$KEY"
check "a bundle signed with the release key loads" 0 "Signed by Tarleaks: SHA256SUMS" yes -- "$work/good"
grep -q -- "--trusted-root config/sigstore/trusted_root.json" "$STUB_LOG" \
  && echo "ok   the kit's trust root is used first (works offline)" \
  || { echo "FAIL the first check does not use config/sigstore/trusted_root.json"; fails=$((fails + 1)); }
grep -q -- "--new-bundle-format" "$STUB_LOG" \
  && { echo "FAIL cosign 3 was given --new-bundle-format (2.x only)"; fails=$((fails + 1)); } || echo "ok   cosign 3 gets no 2.x flag"

bundle "$work/unsigned"
check "an unsigned bundle is refused" 1 "SHA256SUMS.sigstore.json is missing" no -- "$work/unsigned"
check "--allow-unsigned loads it, with a warning" 0 "NOT checked (--allow-unsigned)" yes -- --allow-unsigned "$work/unsigned"
check "--allow-unsigned also works after the folder" 0 "NOT checked (--allow-unsigned)" yes -- "$work/unsigned" --allow-unsigned
TARLEAKS_ALLOW_UNSIGNED=1 check "TARLEAKS_ALLOW_UNSIGNED=1 loads it too" 0 "NOT checked" yes -- "$work/unsigned"

bundle "$work/other" "someone-else's-key"
check "a bundle signed with another key is refused" 1 "does not verify" no -- "$work/other"

bundle "$work/changed" "$KEY"
echo "other image bytes" > "$work/changed/images/app.tar"
(cd "$work/changed" && if command -v sha256sum >/dev/null 2>&1; then sha256sum images/app.tar; else shasum -a 256 images/app.tar; fi > SHA256SUMS)
check "a checksum list changed after signing is refused" 1 "does not verify" no -- "$work/changed"

bundle "$work/damaged" "$KEY"
echo "damaged" > "$work/damaged/images/app.tar"
check "a signed list with a damaged image is refused" 1 "The bundle is damaged" no -- "$work/damaged"

STUB_COSIGN_VERSION=2.2.4 check "cosign older than 2.4 is refused" 1 "is too old" no -- "$work/good"
STUB_COSIGN_VERSION=2.5.0 check "cosign 2.5 checks it (new bundle format)" 0 "Signed by Tarleaks" yes -- "$work/good"
grep -q -- "--new-bundle-format" "$STUB_LOG" && echo "ok   cosign 2.x gets --new-bundle-format" \
  || { echo "FAIL cosign 2.x was not given --new-bundle-format"; fails=$((fails + 1)); }

nocosign="$work/nocosign"; mkdir -p "$nocosign"; ln -s "$bin/docker" "$nocosign/docker"
if (PATH="$nocosign:/usr/bin:/bin"; command -v cosign >/dev/null 2>&1); then
  echo "skip without cosign: this machine has cosign in /usr/bin or /bin"
else
  PATHX="$nocosign:/usr/bin:/bin" check "without cosign it is refused" 1 "cosign is needed" no -- "$work/good"
fi

rm "$kit/config/sigstore/tarleaks-release.pub"
check "a kit without the release public key refuses" 1 "tarleaks-release.pub is missing from this kit" no -- "$work/good"
pub "$KEY"

archive "$work/good" "$work/dl" "$KEY"
check "a .tar with its signed checksum list loads" 0 "Downloaded files intact" yes -- "$work/dl"
archive "$work/good" "$work/dl" "someone-else's-key"
check "a .tar whose outer list is signed by another key is refused before unpacking" 1 "does not verify" no -- "$work/dl"
case "$(cat "$STUB_LOG")" in *"verify-blob"*"tarleaks-test.SHA256SUMS"*) ;; *) echo "FAIL the outer list was not checked"; fails=$((fails + 1)) ;; esac
archive "$work/unsigned" "$work/dl"
check "a .tar of an unsigned bundle is refused after unpacking" 1 "SHA256SUMS.sigstore.json is missing" no -- "$work/dl"
check "one .tar file given directly is checked the same way" 1 "SHA256SUMS.sigstore.json is missing" no -- "$work/dl/tarleaks-test.tar"
[ -z "$(find "$kit" -maxdepth 1 -name '.bundle-*')" ] && echo "ok   nothing unpacked is left behind" \
  || { echo "FAIL an unpacked bundle was left in the kit folder"; fails=$((fails + 1)); }

[ "$fails" = 0 ] || { echo "$fails check(s) failed"; exit 1; }
echo "bundle signature: all checks passed"
