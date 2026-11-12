#!/usr/bin/env bash
# Proves the kit's off-site backup commands (scripts/lib-cloud.sh) against a
# fake `docker` and `crontab`: the engine gets exactly the folders and arguments
# it needs, runs as the kit's owner, its exit codes become the right sentences,
# and a release without the engine changes nothing. Run by CI (scripts job).
# The engine itself is tested in the product repository
# (tarleaks-migrate cloud-backup).
# The checks are strings run by `eval`, so shellcheck cannot see the variables they read.
# shellcheck disable=SC2034
set -euo pipefail
cd "$(dirname "$0")/.."
src=$PWD
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
kit="$work/kit"; mkdir -p "$kit" "$work/bin" "$work/share"
cp -R "$src/tarleaks" "$src/scripts" "$src/config" "$src/docker-compose.yml" "$kit/"
cat > "$kit/.env" <<'ENV'
COMPOSE_PROJECT_NAME=tarleaks
TARLEAKS_VERSION=1.3.0
POSTGRES_USER=tarleaks
POSTGRES_DB=tarleaks
ENV
INST=11111111-2222-3333-4444-555555555555
export FAKE_LOG="$work/docker.log" FAKE_CRON="$work/crontab" INST
# The fake images carry no Tarleaks signature; scripts/check-image-signature.sh proves that check.
export TARLEAKS_ALLOW_UNSIGNED=1

# The fake docker: logs every call; answers the few calls the commands make.
cat > "$work/bin/docker" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
args=("$@")
case "$*" in
  "compose ps --status running --services") [ -n "${FAKE_NO_DB:-}" ] || echo postgres; exit 0 ;;
  "compose exec -T postgres psql"*) echo "$INST"; exit 0 ;;
  "compose exec -T postgres pg_dumpall"*)
    printf 'CREATE DATABASE app;\n-- PostgreSQL database cluster dump complete\n'; exit 0 ;;
  "compose config") echo "name: tarleaks"; exit 0 ;;
esac
[ "${args[0]}" = compose ] && [ "${args[1]}" = run ] || exit 0
# Options must all come before the service name, or Docker passes them to the
# program inside the container instead.
seen_service=0
for a in "${args[@]}"; do
  case "$a" in
    migrate|toolbox) seen_service=1 ;;
    -v|-e|--user|--rm|--no-deps|-T) [ "$seen_service" = 0 ] || { echo "ORDER: $a after the service" >> "$FAKE_LOG"; exit 99; } ;;
  esac
done
# Map container paths to host paths from the -v mounts.
declare -A host
for ((i=0; i<${#args[@]}; i++)); do
  if [ "${args[$i]}" = -v ]; then
    m=${args[$((i+1))]}; h=${m%%:*}; rest=${m#*:}; c=${rest%%:*}; host[$c]=$h
  fi
done
# The toolbox packs the two file volumes into /backup.
if [[ " ${args[*]} " == *" toolbox "* ]]; then
  e=$(mktemp -d); for v in files hrdocs; do tar czf "${host[/backup]}/$v.tar.gz" -C "$e" .; done; rm -rf "$e"; exit 0
fi
# Everything after "cloud-backup".
for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = cloud-backup ] && break; done
sub=${args[$((i+1))]:-}
[ -n "${FAKE_NO_ENGINE:-}" ] && { echo "error: unrecognized subcommand 'cloud-backup'" >&2; exit 2; }
argval() { local k; for ((k=i; k<${#args[@]}; k++)); do [ "${args[$k]}" = "$1" ] && { echo "${args[$((k+1))]}"; return; }; done; }
case "$sub" in
  --help) exit 0 ;;
  keygen|rotate)
    d=${host[$(argval --kit-dir)]}; f="$d/recovery-kit-test-$sub.txt"
    echo "age-identity: AGE-SECRET-KEY-1TEST" > "$f"; echo "kit written" ;;
  verify-kit) touch "${host[/keys]}/kit-verified"; echo "The recovery kit opens this server's backups." ;;
  init-target) [ -n "${FAKE_INIT_RC:-}" ] && { echo "Cannot write in /offsite (backup.target_unreachable)" >&2; exit "$FAKE_INIT_RC"; }
               touch "${host[/offsite]}/.tarleaks-backup-target"
               echo "Off-site copies will be stored in the folder /offsite." ;;
  seal) [ -n "${FAKE_SEAL_RC:-}" ] && { echo "The backup folder /offsite cannot be reached (backup.target_unreachable)" >&2; exit "$FAKE_SEAL_RC"; }
        echo "Off-site copy 1 stored in the folder /offsite (1234 bytes, encrypted to key …AB12)." ;;
  list) [ -n "${FAKE_RC:-}" ] && { echo "The backup folder /offsite cannot be reached (backup.target_unreachable)" >&2; exit "$FAKE_RC"; }
        echo "20261021T020000Z-3fa1c2d9  sequence 1  1234 bytes  key …AB12" ;;
  open)
    into=$(argval --into); d=${host[/backups]}/${into#/backups/}; mkdir -p "$d"
    printf 'CREATE DATABASE app;\n-- PostgreSQL database cluster dump complete\n' | gzip > "$d/database.sql.gz"
    printf 'COMPOSE_PROJECT_NAME=tarleaks\nCLUSTER_DSN_KEY=k\n' > "$d/env"
    echo "opened" ;;
  *) echo "ok" ;;
esac
FAKE
cat > "$work/bin/crontab" <<'FAKE'
#!/usr/bin/env bash
case "${1:-}" in
  -l) [ -f "$FAKE_CRON" ] && cat "$FAKE_CRON" || exit 1 ;;
  -) cat > "$FAKE_CRON" ;;
esac
FAKE
chmod +x "$work/bin/docker" "$work/bin/crontab"
export PATH="$work/bin:$PATH"

fail=0
pass() { printf 'ok   %s\n' "$1"; }
flunk() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then pass "$1"; else flunk "$1"; fi; }
run() { (cd "$kit" && ./tarleaks "$@") ; }

# 1. A release without the engine refuses and changes nothing.
out=$(FAKE_NO_ENGINE=1 run cloud backup-key init 2>&1) && rc=0 || rc=$?
check "no engine: refused" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "no off-site backups yet"'
check "no engine: no keys folder written" '[ ! -e "$kit/.tarleaks/cloud/backup-recipient.txt" ]'

# 1b. With the database stopped there is no installation id: nothing is made.
: > "$FAKE_LOG"
out=$(FAKE_NO_DB=1 run cloud backup-key init 2>&1) && rc=0 || rc=$?
check "no database: init refused" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "database is not running"'
check "no database: the engine was never asked to make keys" '! grep -q "cloud-backup keygen" "$FAKE_LOG"'
check "no database: no kit file" '! ls "$kit"/recovery-kit-*.txt >/dev/null 2>&1'

# 2. backup-key init: the engine runs as the kit's owner with /keys mounted, and
#    the recovery kit lands in the kit folder, mode 600.
: > "$FAKE_LOG"
out=$(run cloud backup-key init 2>&1)
owner=$(ls -nd "$kit" | awk '{print $3":"$4}')
check "init: runs as the kit owner" 'grep -q -- "--user $owner" "$FAKE_LOG"'
check "init: mounts the keys folder at /keys" 'grep -q -- "-v $kit/.tarleaks/cloud:/keys" "$FAKE_LOG"'
check "init: passes the installation id" 'grep -q -- "keygen --keys /keys --kit-dir /keys --installation $INST" "$FAKE_LOG"'
check "init: the kit is moved out of the keys folder" '[ -f "$kit/recovery-kit-test-keygen.txt" ] && [ ! -e "$kit/.tarleaks/cloud/recovery-kit-test-keygen.txt" ]'
check "init: the kit is mode 600" '[ "$(stat -c %a "$kit/recovery-kit-test-keygen.txt" 2>/dev/null || stat -f %Lp "$kit/recovery-kit-test-keygen.txt")" = 600 ]'
check "init: the keys folder is mode 700" '[ "$(stat -c %a "$kit/.tarleaks/cloud" 2>/dev/null || stat -f %Lp "$kit/.tarleaks/cloud")" = 700 ]'
check "init: tells the person to verify and remove the kit" 'printf "%s" "$out" | grep -q "backup-key verify" && printf "%s" "$out" | grep -q "forget-secret"'

# 3. verify mounts the kit file read-only, never the folder around it.
: > "$FAKE_LOG"
run cloud backup-key verify --recovery-kit recovery-kit-test-keygen.txt >/dev/null 2>&1
check "verify: the kit file is mounted read-only" 'grep -q -- "-v $kit/recovery-kit-test-keygen.txt:/kit.txt:ro" "$FAKE_LOG"'

# 3b. forget-secret deletes only the kit copy inside the kit folder.
cp "$kit/recovery-kit-test-keygen.txt" "$work/usb-copy.txt"
out=$(printf 'I HAVE IT\n' | run cloud backup-key forget-secret --recovery-kit "$work/usb-copy.txt" 2>&1) && rc=0 || rc=$?
check "forget-secret: a kit outside the kit folder is refused" '[ "$rc" != 0 ] && [ -f "$work/usb-copy.txt" ] && printf "%s" "$out" | grep -q "somewhere else"'
out=$(printf 'no\n' | run cloud backup-key forget-secret --recovery-kit recovery-kit-test-keygen.txt 2>&1) && rc=0 || rc=$?
check "forget-secret: without I HAVE IT nothing is deleted" '[ "$rc" != 0 ] && [ -f "$kit/recovery-kit-test-keygen.txt" ]'
cp "$kit/recovery-kit-test-keygen.txt" "$kit/second-kit.txt"
printf 'I HAVE IT\n' | run cloud backup-key forget-secret --recovery-kit second-kit.txt >/dev/null 2>&1
check "forget-secret: with I HAVE IT the copy in the kit folder goes" '[ ! -e "$kit/second-kit.txt" ]'

# 4. target folder: refused inside the kit, accepted elsewhere, and only the
#    migrate container sees it.
out=$(run cloud backup target folder "$kit/scripts" 2>&1) && rc=0 || rc=$?
check "target: a folder inside the kit is refused" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "not be inside this kit"'
: > "$FAKE_LOG"
out=$(FAKE_INIT_RC=3 run cloud backup target folder "$work/share" --same-disk 2>&1) && rc=0 || rc=$?
check "target: a first target that fails its set-up leaves no setting" '[ "$rc" = 3 ] && ! grep -q "^TARLEAKS_OFFSITE_FOLDER=" "$kit/.env" && ! grep -q "^TARLEAKS_CLOUD_BACKUP=" "$kit/.env"'
out=$(run cloud backup target folder "$work/share" 2>&1) && rc=0 || rc=$?
check "target: a folder on the same disk is refused without --same-disk" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "same disk" && ! grep -q "^TARLEAKS_OFFSITE_FOLDER=" "$kit/.env"'
: > "$FAKE_LOG"
run cloud backup target folder "$work/share" --same-disk >/dev/null 2>&1
check "target: .env names the folder" 'grep -qx "TARLEAKS_CLOUD_BACKUP=folder" "$kit/.env" && grep -qx "TARLEAKS_OFFSITE_FOLDER=$work/share" "$kit/.env"'
check "target: the share is mounted at /offsite" 'grep -q -- "-v $work/share:/offsite" "$FAKE_LOG" && grep -q -- "-e TARLEAKS_OFFSITE_FOLDER=/offsite" "$FAKE_LOG"'
check "target: init-target runs" 'grep -q "cloud-backup init-target --target folder" "$FAKE_LOG"'
check "target: kept across a restore" 'grep -q "RESTORE_ALWAYS_KEEP=.*TARLEAKS_OFFSITE_FOLDER" "$kit/tarleaks"'
mkdir -p "$work/share2"
out=$(FAKE_INIT_RC=3 run cloud backup target folder "$work/share2" --same-disk 2>&1) && rc=0 || rc=$?
check "target: a folder that fails its set-up is not kept" '[ "$rc" = 3 ] && grep -qx "TARLEAKS_OFFSITE_FOLDER=$work/share" "$kit/.env"'
check "target: no option was put after the service name" '! grep -q "^ORDER" "$FAKE_LOG"'

# 5. Exit code 3 (unreachable) is explained and passed on.
out=$(FAKE_RC=3 run cloud backup list 2>&1) && rc=0 || rc=$?
check "list: exit 3 is passed on" '[ "$rc" = 3 ]'
check "list: exit 3 is explained" 'printf "%s" "$out" | grep -q "could not be reached"'
out=$(run cloud backup list 2>&1)
check "list: shows the copies" 'printf "%s" "$out" | grep -q 20261021T020000Z-3fa1c2d9'

# 6. schedule writes one line for this kit and removes it again, and never
#    touches the line of another kit whose path starts the same.
printf '0 1 * * * cd %s2 && ./tarleaks backup --offsite --scheduled # tarleaks-offsite %s2\n' "$kit" "$kit" > "$FAKE_CRON"
run cloud backup schedule 02:30 >/dev/null 2>&1
check "schedule: one line at 02:30" '[ "$(grep -c "tarleaks-offsite $kit\$" "$FAKE_CRON")" = 1 ] && grep -q "^30 2 \* \* \* " "$FAKE_CRON" && grep -q "backup --offsite --scheduled" "$FAKE_CRON"'
run cloud backup schedule 02:30 >/dev/null 2>&1
check "schedule: no duplicate line" '[ "$(grep -c "tarleaks-offsite $kit\$" "$FAKE_CRON")" = 1 ]'
run cloud backup schedule off >/dev/null 2>&1
check "schedule: off removes it" '[ "$(grep -c "tarleaks-offsite $kit\$" "$FAKE_CRON")" = 0 ]'
check "schedule: the neighbour kit's line survives" 'grep -q "tarleaks-offsite ${kit}2\$" "$FAKE_CRON"'
out=$(run cloud backup schedule 25:00 2>&1) && rc=0 || rc=$?
check "schedule: a bad time is refused" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "HH:MM"'

# 7. restore --from-cloud opens the newest copy into backups/from-cloud-<copy>/
#    and hands it to the ordinary restore, which still asks first.
: > "$FAKE_LOG"
out=$(printf 'no\n' | run restore --from-cloud --recovery-kit recovery-kit-test-keygen.txt 2>&1) && rc=0 || rc=$?
check "restore: the newest copy is opened" 'grep -q "cloud-backup open 20261021T020000Z-3fa1c2d9 --target folder --recovery-kit /kit.txt --into /backups/from-cloud-20261021T020000Z-3fa1c2d9 --release 1.3.0 --keys /keys" "$FAKE_LOG"'
check "restore: the opened folder is checked by the ordinary restore" 'printf "%s" "$out" | grep -q "The backup is complete and readable"'
check "restore: it still asks before replacing anything" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "Cancelled. Nothing was changed"'
out=$(run restore --from-cloud 2>&1) && rc=0 || rc=$?
check "restore: refuses without the kit" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "recovery kit"'
out=$(run restore backups/x --recovery-kit recovery-kit-test-keygen.txt 2>&1) && rc=0 || rc=$?
check "restore: --recovery-kit alone is refused" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "is for --from-cloud"'
out=$(run restore --from-cloud ../etc --recovery-kit recovery-kit-test-keygen.txt 2>&1) && rc=0 || rc=$?
check "restore: a copy name with a path is refused" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "not the name of an off-site copy"'

# 7b. The scheduled clean-up removes only old folders that were sealed off-site.
mkdir -p "$kit/backups/20261001-020000" "$kit/backups/20261002-020000" "$kit/backups/20261020-020000" "$kit/backups/pre-upgrade-20261001"
touch -d "10 days ago" "$kit/backups/20261001-020000/.offsite-sealed"     # old, sealed: removed
touch -d "10 days ago" "$kit/backups/20261002-020000/database.sql.gz"     # old, never sealed: kept
touch "$kit/backups/20261020-020000/.offsite-sealed"                       # sealed, recent: kept
touch -d "10 days ago" "$kit/backups/pre-upgrade-20261001/database.sql.gz" # safety backup: kept
(cd "$kit" && bash -c '. ./tarleaks cloud status >/dev/null; cloud_after_scheduled_seal') >/dev/null 2>&1 || true
check "clean-up: an old sealed backup is removed" '[ ! -e "$kit/backups/20261001-020000" ]'
check "clean-up: an old backup without an off-site copy is kept" '[ -d "$kit/backups/20261002-020000" ]'
check "clean-up: a recent sealed backup is kept" '[ -d "$kit/backups/20261020-020000" ]'
check "clean-up: a safety backup is kept" '[ -d "$kit/backups/pre-upgrade-20261001" ]'
check "clean-up: the restore folder was kept too" '[ -d "$kit/backups/from-cloud-20261021T020000Z-3fa1c2d9" ]'

# 7c. backup --offsite: the local backup, then the seal with the right
#     arguments, then the marker; a failed seal keeps the local backup.
: > "$FAKE_LOG"
out=$(run backup backups/offsite-1 --offsite 2>&1) && rc=0 || rc=$?
check "backup --offsite: succeeds" '[ "$rc" = 0 ] && [ -f "$kit/backups/offsite-1/database.sql.gz" ]'
check "backup --offsite: seals the folder it made" 'grep -q "cloud-backup seal /backups/offsite-1 --target folder --keys /keys --installation $INST --release 1.3.0" "$FAKE_LOG"'
check "backup --offsite: mounts the backups folder, not the kit" 'grep "cloud-backup seal" "$FAKE_LOG" | grep -q -- "-v $kit/backups:/backups"'
check "backup --offsite: marks the folder sealed" '[ -f "$kit/backups/offsite-1/.offsite-sealed" ]'
check "backup --offsite: no option after the service name" '! grep -q "^ORDER" "$FAKE_LOG"'
out=$(FAKE_SEAL_RC=3 run backup backups/offsite-2 --offsite 2>&1) && rc=0 || rc=$?
check "failed seal: exits non-zero and keeps the local backup" '[ "$rc" != 0 ] && [ -f "$kit/backups/offsite-2/database.sql.gz" ] && printf "%s" "$out" | grep -q "only the off-site copy is missing"'
check "failed seal: no marker" '[ ! -e "$kit/backups/offsite-2/.offsite-sealed" ]'
mv "$work/share" "$work/share-unmounted"
out=$(run backup backups/offsite-3 --offsite --scheduled 2>&1) && rc=0 || rc=$?
check "scheduled, share missing: the local backup is still made" '[ -f "$kit/backups/offsite-3/database.sql.gz" ]'
check "scheduled, share missing: says why and fails" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "No off-site copy tonight" && printf "%s" "$out" | grep -q "is not there"'
out=$(run backup backups/offsite-4 --offsite 2>&1) && rc=0 || rc=$?
check "by hand, share missing: refused before the dump" '[ "$rc" != 0 ] && [ ! -e "$kit/backups/offsite-4" ] && printf "%s" "$out" | grep -q "is not there"'
out=$(run cloud backup-key verify --recovery-kit recovery-kit-test-keygen.txt 2>&1) && rc=0 || rc=$?
check "key commands work while the share is down" '[ "$rc" = 0 ]'
# An unmounted mount point: the folder exists, empty, without the marker.
mkdir -p "$work/share"
out=$(run backup backups/offsite-5 --offsite 2>&1) && rc=0 || rc=$?
check "empty mount point: refused before the dump" '[ "$rc" != 0 ] && [ ! -e "$kit/backups/offsite-5" ] && printf "%s" "$out" | grep -q "share is not mounted"'
rmdir "$work/share"
mv "$work/share-unmounted" "$work/share"

# 8. backup --offsite refuses BEFORE any database work when nothing is set up.
sed -i.bak '/^TARLEAKS_CLOUD_BACKUP=/d' "$kit/.env"
: > "$FAKE_LOG"
out=$(run backup --offsite 2>&1) && rc=0 || rc=$?
check "backup --offsite: refused when off" '[ "$rc" != 0 ] && printf "%s" "$out" | grep -q "Off-site copies are off"'
check "backup --offsite: no dump was started" '! grep -q pg_dumpall "$FAKE_LOG"'

[ "$fail" = 0 ] && echo "All off-site backup command checks passed." || { echo "Some checks failed."; exit 1; }
