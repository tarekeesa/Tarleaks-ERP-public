#!/usr/bin/env bash
# Proves `./tarleaks migrate-from-cloud` (scripts/lib-move.sh) against a fake
# `docker`: the status check runs under `set -u` without stopping, a move code
# piped in reaches the ERP (the `docker compose exec -T` calls before it would
# otherwise swallow it), and the code never appears on a command line or in the
# output. Run by CI (scripts job). The move itself is tested in the product
# repository (auth cloud_move).
# The checks are strings run by `eval`, so shellcheck cannot see the variables they read.
# shellcheck disable=SC2034
set -euo pipefail
cd "$(dirname "$0")/.."
src=$PWD
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
kit="$work/kit"; mkdir -p "$kit" "$work/bin"
cp -R "$src/tarleaks" "$src/scripts" "$src/config" "$src/docker-compose.yml" "$kit/"
cat > "$kit/.env" <<'ENV'
COMPOSE_PROJECT_NAME=tarleaks
TARLEAKS_VERSION=1.2.0
TARLEAKS_SETUP_CODE=setup-code-for-the-check
ENV
export FAKE_LOG="$work/docker.log" FAKE_BODY="$work/body.log"
# The fake images carry no Tarleaks signature; scripts/check-image-signature.sh proves that check.
export TARLEAKS_ALLOW_UNSIGNED=1

# The fake docker: logs every command line; `exec -T` reads its stdin like the
# real one; the move API answers "no move yet" (GET) or "server too old" (POST).
cat > "$work/bin/docker" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
case "$*" in
  "compose ps --status running --services") echo auth; exit 0 ;;
  # exec -T forwards stdin and swallows what is there; it returns when curl does.
  "compose exec -T auth curl"*/healthz*) timeout 1 cat > /dev/null || true; exit 0 ;;
  "compose exec -T auth curl"*--data-binary*)
    cat >> "$FAKE_BODY"; echo >> "$FAKE_BODY"
    printf '{"error":{"code":"SERVER_TOO_OLD","message":"This server runs Tarleaks 1.2.0, which is older than the cloud."}}\n409'
    exit 0 ;;
  "compose exec -T auth curl"*) cat > /dev/null; printf '{}\n200'; exit 0 ;;
esac
exit 0
FAKE
chmod +x "$work/bin/docker"
export PATH="$work/bin:$PATH"

fails=0
check() { # name  condition
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
run() { # stdin-file  args...  -> $out, $rc
  local in=$1; shift
  rc=0; out=$(cd "$kit" && ./tarleaks migrate-from-cloud "$@" < "$in" 2>&1) || rc=$?
}

# 1. The status check (a GET without a path) no longer stops on 'unbound variable'.
run /dev/null --status
check "--status answers (exit 0)" '[ "$rc" = 0 ]'
check "--status says there is no move" '[[ "$out" == *"There is no move from Tarleaks Cloud"* ]]'
check "no 'unbound variable'" '[[ "$out" != *"unbound variable"* ]]'

# 2. Nothing piped in: the same answer, no hang.
run /dev/null
check "a bare run with nothing piped in says there is no move" '[[ "$out" == *"There is no move from Tarleaks Cloud"* ]]'
check "a bare run exits 1" '[ "$rc" = 1 ]'

# 2b. An open pipe that sends nothing (ssh without -n, cron) does not hang it.
start=$SECONDS
rc=0; out=$(cd "$kit" && ./tarleaks migrate-from-cloud < <(sleep 20 2>/dev/null) 2>&1) || rc=$?
check "an open silent pipe gives up after 5 seconds" '[ $((SECONDS - start)) -lt 15 ]'
check "and says no code came in" '[[ "$out" == *"No move code came in on standard input"* ]]'

# 3. A code piped in reaches the ERP and is never shown or put on a command line.
code=TLM-ABCDE-FGHJK-LMNPQ-RSTUV
printf '\n  \n%s\r\n' "$code" > "$work/code.txt"   # blank lines first, Windows line end
chmod 600 "$work/code.txt"
: > "$FAKE_LOG"; : > "$FAKE_BODY"
run "$work/code.txt"
check "the piped code is sent to the ERP" 'grep -q "\"code\":\"$code\"" "$FAKE_BODY"'
check "the refusal is shown in words" '[[ "$out" == *"SERVER_TOO_OLD"* ]]'
check "the move stops with exit 1" '[ "$rc" = 1 ]'
check "the code is on no command line" '! grep -q "ABCDE" "$FAKE_LOG"'
check "the code is not printed" '[[ "$out" != *"ABCDE"* ]]'

# 3b. A file whose last line has no newline (printf code > file).
printf '%s ' "$code" > "$work/code2.txt"; chmod 600 "$work/code2.txt"
: > "$FAKE_BODY"
run "$work/code2.txt"
check "a code without a final newline is read" 'grep -q "\"code\":\"$code\"" "$FAKE_BODY"'

# 4. The same with --switch-over.
: > "$FAKE_BODY"
run "$work/code.txt" --switch-over
check "--switch-over takes a piped code too" 'grep -q "\"code\":\"$code\"" "$FAKE_BODY"'

if [ "$fails" != 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "migrate-from-cloud: all checks passed"
