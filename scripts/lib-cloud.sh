# shellcheck shell=bash
# =============================================================================
# lib-cloud.sh — off-site encrypted backups.
#
# The work is done by the backup engine in the `migrate` image
# (`tarleaks-migrate cloud-backup`); this file is the kit's side: it runs the
# engine with exactly the folders it needs, as the owner of this kit folder (so
# the recovery kit and the keys belong to the person, not to root), and turns
# its refusal codes into plain sentences.
#
#   .tarleaks/cloud/        the server's half of the keys (never the secret that
#                           decrypts: that is only in the recovery kit)
#   TARLEAKS_CLOUD_BACKUP   off | folder   (s3 and tarleaks storage come later)
#   TARLEAKS_OFFSITE_FOLDER the folder target: a mounted share or second disk
#
# Engine exit codes: 0 ok, 2 refused (nothing changed), 3 the target could not
# be reached (retry later), anything else an error.
# =============================================================================

CLOUD_DIR=.tarleaks/cloud

cloud_target() { local t; t=$(env_get TARLEAKS_CLOUD_BACKUP); printf '%s' "${t:-off}"; }

# The installation's identity at the vendor (auth.installation_state.instance_id).
cloud_installation_id() {
  local user db id
  user=$(env_get POSTGRES_USER); db=$(env_get POSTGRES_DB)
  is_running postgres || die "The database is not running. Start the ERP first: ./tarleaks start"
  id=$(docker compose exec -T postgres psql -X -q -At -U "${user:-tarleaks}" -d "${db:-tarleaks}" \
         -c "SELECT instance_id FROM auth.installation_state WHERE id" 2>/dev/null | head -1 | tr -d '\r') || id=""
  [ -n "$id" ] || die "This installation has no identity yet (it is made at the first start). Start the ERP once, then try again."
  printf '%s' "$id"
}

# Does this release's engine know `cloud-backup`?
cloud_engine_available() {
  # The engine is the release's migrate image: it runs only when this machine checked it (scripts/lib-signature.sh).
  sig_require_verified "./tarleaks cloud" || exit 1
  docker compose run --rm --no-deps -T migrate cloud-backup --help >/dev/null 2>&1
}

cloud_require_engine() {
  cloud_engine_available || die "This release has no off-site backups yet. Update to a release that has them: ./tarleaks update"
}

# cloud_engine <mount…> -- <engine args…>
# Mounts are "host-path:container-path[:ro]". The keys folder is always /keys.
cloud_engine() {
  local mounts=() a
  sig_require_verified "./tarleaks cloud" || exit 1
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do mounts+=(-v "$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  mkdir -p "$CLOUD_DIR"
  chmod 700 .tarleaks "$CLOUD_DIR" 2>/dev/null || true
  if [ "$(id -u)" = 0 ] && [ "$(kit_owner)" != "0:0" ]; then chown "$(kit_owner)" .tarleaks "$CLOUD_DIR"; fi
  local target_env=()
  # The key commands never touch the off-site folder: they work while the
  # share is down (CLOUD_WITH_TARGET=0).
  if [ "${CLOUD_WITH_TARGET:-1}" = 1 ] && [ "$(cloud_target)" = folder ]; then
    a=$(env_get TARLEAKS_OFFSITE_FOLDER)
    [ -n "$a" ] || die "The off-site folder is not set. Set it: ./tarleaks cloud backup target folder <path>"
    # Never let Docker create a missing host folder (as root, on this disk).
    [ -d "$a" ] || die "The off-site folder $a is not there (is the share mounted?). Nothing was changed."
    mounts+=(-v "$a:/offsite")
    target_env=(-e TARLEAKS_OFFSITE_FOLDER=/offsite)
  fi
  # ${a[@]+"${a[@]}"}: an empty array under `set -u` on macOS's bash 3.2.
  docker compose run --rm --no-deps -T --user "$(kit_owner)" \
    -v "$PWD/$CLOUD_DIR:/keys" ${mounts[@]+"${mounts[@]}"} ${target_env[@]+"${target_env[@]}"} \
    migrate cloud-backup "$@"
}

# Run the engine and explain a failure. Returns the engine's exit code.
cloud_run() {
  local rc=0
  cloud_engine "$@" || rc=$?
  case "$rc" in
    0) ;;
    2) bad "Nothing was changed (the reason is above)." ;;
    3) bad "The off-site place could not be reached (above). Nothing is lost; it is tried again next time." ;;
    *) bad "The off-site backup engine failed (above)." ;;
  esac
  return "$rc"
}

cloud_abs() { # path → absolute path (the file or folder must exist)
  if [ -d "$1" ]; then (cd "$1" && pwd); else printf '%s/%s' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"; fi
}

# ./tarleaks cloud backup-key init|verify|forget-secret|restore|rotate
cloud_backup_key() {
  local sub=${1:-} kit
  shift || true
  local CLOUD_WITH_TARGET=0
  cloud_require_engine
  case "$sub" in
    init|rotate)
      [ $# -eq 0 ] || die "usage: ./tarleaks cloud backup-key $sub"
      local before after inst
      # Not inside the argument list: a `die` in $(…) there would only end the
      # subshell, and the keys would be made with an empty installation.
      inst=$(cloud_installation_id) || exit 1
      before=$(ls "$CLOUD_DIR"/recovery-kit-*.txt 2>/dev/null | sort || true)
      cloud_run -- "$( [ "$sub" = init ] && echo keygen || echo rotate)" \
        --keys /keys --kit-dir /keys --installation "$inst" || exit $?
      after=$(ls "$CLOUD_DIR"/recovery-kit-*.txt 2>/dev/null | sort || true)
      kit=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)
      [ -n "$kit" ] || die "The recovery kit was not written."
      mv "$kit" .
      kit=$(basename "$kit")
      chmod 600 "$kit"
      echo
      printf '%sYour recovery kit is %s%s\n' "$B" "$kit" "$N"
      echo "Without it, NO off-site copy can be opened — not by you, not by Tarleaks."
      echo "1. Print it, or copy it to two USB sticks kept in two places."
      echo "2. Check it:   ./tarleaks cloud backup-key verify --recovery-kit $kit"
      echo "3. Remove it from this server:   ./tarleaks cloud backup-key forget-secret --recovery-kit $kit"
      if [ "$sub" = rotate ]; then warn "Copies made before today still need the OLD recovery kit. Keep it."; fi ;;
    verify)
      [ "${1:-}" = --recovery-kit ] && [ -n "${2:-}" ] || die "usage: ./tarleaks cloud backup-key verify --recovery-kit <file>"
      [ -f "$2" ] || die "$2 is not a file."
      cloud_run "$(cloud_abs "$2"):/kit.txt:ro" -- verify-kit --keys /keys --recovery-kit /kit.txt || exit $?
      ok "This recovery kit opens this server's off-site copies." ;;
    forget-secret)
      [ "${1:-}" = --recovery-kit ] && [ -n "${2:-}" ] || die "usage: ./tarleaks cloud backup-key forget-secret --recovery-kit <file>"
      [ -f "$2" ] || die "$2 is not a file."
      local abs; abs=$(cloud_abs "$2")
      case "$abs" in
        "$PWD"/*) ;;
        *) die "forget-secret removes the copy of the kit kept in this kit folder, and only that one. $abs is somewhere else (a USB stick?): keep it." ;;
      esac
      cloud_run "$abs:/kit.txt:ro" -- verify-kit --keys /keys --recovery-kit /kit.txt || exit $?
      printf 'This deletes %s from this server. Type I HAVE IT once it is printed or copied away: ' "$abs"
      read -r answer || true
      [ "$answer" = "I HAVE IT" ] || die "Cancelled. The file is still here."
      rm -f "$2"
      ok "Removed. Keep the printed or copied kit safe: it is the only way to open the copies." ;;
    restore)
      [ "${1:-}" = --recovery-kit ] && [ -n "${2:-}" ] || die "usage: ./tarleaks cloud backup-key restore --recovery-kit <file>"
      [ -f "$2" ] || die "$2 is not a file."
      cloud_run "$(cloud_abs "$2"):/kit.txt:ro" -- restore-keys --keys /keys --recovery-kit /kit.txt || exit $?
      ok "The backup keys are back on this server; new copies continue the same chain." ;;
    *) die "usage: ./tarleaks cloud backup-key init | verify | forget-secret | restore | rotate" ;;
  esac
}

# ./tarleaks cloud backup target folder <path> | off
cloud_backup_target() {
  case "${1:-}" in
    folder)
      [ -n "${2:-}" ] || die "usage: ./tarleaks cloud backup target folder <path> [--same-disk]"
      [ -d "$2" ] || die "$2 is not a folder on this server. Mount the share or plug in the disk first."
      local abs same_disk=0 old_target old_folder rc=0
      [ "${3:-}" = --same-disk ] && same_disk=1
      abs=$(cloud_abs "$2")
      case "$abs/" in
        "$PWD"/*) die "The off-site folder must not be inside this kit folder: a copy on the same disk is not off-site." ;;
      esac
      # An unmounted share is an empty folder on THIS disk: refuse a folder on
      # the same file system as the kit unless the person says it is meant.
      if [ "$same_disk" = 0 ] && [ "$(df -P "$abs" | awk 'NR==2{print $1}')" = "$(df -P . | awk 'NR==2{print $1}')" ]; then
        die "$abs is on the same disk as this server's data: if it is a share, it is not mounted now; if it is a plain folder, a copy there does not survive a failed disk or a fire. Mount the share, or use a second disk. To use this folder anyway: ./tarleaks cloud backup target folder $abs --same-disk"
      fi
      cloud_require_engine
      old_target=$(env_get TARLEAKS_CLOUD_BACKUP); old_folder=$(env_get TARLEAKS_OFFSITE_FOLDER)
      set_env TARLEAKS_CLOUD_BACKUP folder
      set_env TARLEAKS_OFFSITE_FOLDER "$abs"
      cloud_run -- init-target --target folder || rc=$?
      if [ "$rc" != 0 ]; then
        # Put the previous choice back: a target that failed its set-up must
        # not become the one the nightly run uses.
        if [ -n "$old_target" ]; then set_env TARLEAKS_CLOUD_BACKUP "$old_target"; else env_del TARLEAKS_CLOUD_BACKUP; fi
        if [ -n "$old_folder" ]; then set_env TARLEAKS_OFFSITE_FOLDER "$old_folder"; else env_del TARLEAKS_OFFSITE_FOLDER; fi
        exit "$rc"
      fi
      ok "Off-site copies will go to $abs. Make one now: ./tarleaks backup --offsite" ;;
    off)
      set_env TARLEAKS_CLOUD_BACKUP off
      ok "Off-site copies are off. Copies already made are left where they are."
      if crontab -l 2>/dev/null | grep -qF "# tarleaks-offsite $PWD"; then
        warn "A nightly off-site copy is still scheduled: it now makes the local backup and reports an error every night. To stop it: ./tarleaks cloud backup schedule off"
      fi ;;
    s3|tarleaks)
      die "Copies to your own S3 bucket and to Tarleaks storage come with a later release. Use a folder (a mounted share or a second disk) for now." ;;
    *) die "usage: ./tarleaks cloud backup target folder <path> [--same-disk] | off" ;;
  esac
}

# Seal one finished backup folder into the off-site target.
# A sealed folder gets a marker, so the scheduled clean-up removes only local
# backups that really have an off-site copy.
cloud_seal() { # backup-folder
  local dir parent name inst
  dir=$(cloud_abs "$1"); parent=$(dirname "$dir"); name=$(basename "$dir")
  # The share may have gone since the check before the dump: say so here, so
  # the caller's "the local backup is kept" message is printed.
  (cloud_offsite_ready) || return 3
  inst=$(cloud_installation_id) || return 1
  cloud_run "$parent:/backups" -- seal "/backups/$name" --target "$(cloud_target)" --keys /keys \
    --installation "$inst" --release "$(env_get TARLEAKS_VERSION)" || return $?
  date '+%Y-%m-%d %H:%M:%S %z' > "$dir/.offsite-sealed"
}

cloud_offsite_ready() {
  [ "$(cloud_target)" != off ] || die "Off-site copies are off. Choose where they go first: ./tarleaks cloud backup target folder <path>"
  if [ "$(cloud_target)" = folder ]; then
    local f; f=$(env_get TARLEAKS_OFFSITE_FOLDER)
    [ -n "$f" ] || die "The off-site folder is not set. Set it: ./tarleaks cloud backup target folder <path>"
    [ -d "$f" ] || die "The off-site folder $f is not there (is the share mounted?)."
    # An unmounted mount point is an empty folder: the marker init-target
    # wrote is only there when the share really is.
    [ -f "$f/.tarleaks-backup-target" ] || die "The off-site folder $f is empty: the share is not mounted, or the folder was never set up (./tarleaks cloud backup target folder $f)."
  fi
  cloud_require_engine
}

# ./tarleaks cloud backup list|verify <id>|prune|schedule …
cloud_backup() {
  local sub=${1:-}
  shift || true
  case "$sub" in
    target) cloud_backup_target "$@" ;;
    list)
      cloud_offsite_ready
      cloud_run -- list --target "$(cloud_target)" || exit $? ;;
    verify)
      [ -n "${1:-}" ] || die "usage: ./tarleaks cloud backup verify <copy>   (the copies: ./tarleaks cloud backup list)"
      cloud_offsite_ready
      cloud_run -- verify "$1" --target "$(cloud_target)" --keys /keys || exit $? ;;
    prune)
      cloud_offsite_ready
      local keep; keep=$(env_get TARLEAKS_CLOUD_BACKUP_RETENTION)
      cloud_run -- prune --target "$(cloud_target)" --keys /keys --retention "${keep:-7d,4w,3m}" || exit $? ;;
    schedule) cloud_backup_schedule "$@" ;;
    *) die "usage: ./tarleaks cloud backup target | list | verify <copy> | prune | schedule <HH:MM|off>" ;;
  esac
}

# ./tarleaks cloud backup schedule HH:MM | off — one cron line for this kit.
cloud_backup_schedule() {
  command -v crontab >/dev/null 2>&1 || die "crontab is not installed. Schedule './tarleaks backup --offsite --scheduled' with your system's scheduler (docs/backup-restore.md)."
  # The tag ends the line, and only a line ending EXACTLY with it is this
  # kit's: /opt/tarleaks must never remove /opt/tarleaks2's line.
  local tag="# tarleaks-offsite $PWD" current listing
  # cron turns % into a new line, so a path holding one cannot be scheduled.
  case "$PWD$PATH" in *%*) die "This folder's path (or PATH) contains %, which cron cannot run. Move the kit, or schedule './tarleaks backup --offsite --scheduled' with your system's scheduler." ;; esac
  # "no crontab for <user>" is an empty list; any other failure must stop
  # here, or the line below would replace the person's whole crontab.
  local errf; errf=$(mktemp)
  if ! listing=$(crontab -l 2>"$errf"); then
    local err; err=$(cat "$errf"); rm -f "$errf"
    case "$err" in
      *"no crontab"*) listing="" ;;
      *) die "Could not read this account's crontab: $err" ;;
    esac
  fi
  rm -f "$errf"
  current=$(printf '%s\n' "$listing" | T="$tag" awk 'BEGIN { t = ENVIRON["T"] } length($0) < length(t) || substr($0, length($0) - length(t) + 1) != t' || true)
  case "${1:-}" in
    off)
      printf '%s\n' "$current" | sed '/^$/d' | crontab -
      ok "The scheduled off-site copy is off." ;;
    [0-2][0-9]:[0-5][0-9])
      local h=${1%%:*} m=${1##*:}
      [ "$((10#$h))" -le 23 ] || die "usage: ./tarleaks cloud backup schedule HH:MM (00:00 to 23:59) | off"
      cloud_offsite_ready
      mkdir -p logs
      { printf '%s\n' "$current" | sed '/^$/d'
        printf '%s %s * * * cd %q && PATH=%q ./tarleaks backup --offsite --scheduled >> logs/offsite-backup.log 2>&1 %s\n' \
          "$((10#$m))" "$((10#$h))" "$PWD" "$PATH" "$tag"
      } | crontab -
      ok "Every night at $1 a backup is made and copied off-site; local backups older than 7 days are then removed. Log: logs/offsite-backup.log" ;;
    *) die "usage: ./tarleaks cloud backup schedule HH:MM | off" ;;
  esac
}

# After a scheduled, sealed backup: thin the off-site copies and drop local
# backups older than 7 days (the off-site copies are the history now).
cloud_after_scheduled_seal() {
  ( cloud_backup prune ) || warn "Older off-site copies were not thinned this time (above)."
  # Only folders that were sealed off-site (their marker is there) and older
  # than 7 days; a backup whose copy failed, one made without --offsite or a
  # safety backup before an upgrade or restore is never removed here.
  local d
  for d in backups/*/; do
    d=${d%/}
    [ -f "$d/.offsite-sealed" ] || continue
    [ -n "$(find "$d/.offsite-sealed" -mtime +7 2>/dev/null)" ] || continue
    rm -rf "$d"
  done
}

# ./tarleaks restore --from-cloud [copy] --recovery-kit <file> [restore options]
# Opens the copy into backups/from-cloud-<copy>/ and hands that folder to the
# ordinary restore, which checks it again and asks before replacing anything.
cloud_open_for_restore() { # copy kit-file → prints the opened folder
  local id=$1 kit=$2 into
  cloud_offsite_ready
  [ -f "$kit" ] || die "$kit is not a file."
  if [ -z "$id" ]; then
    local listing rc=0
    listing=$(cloud_engine -- list --target "$(cloud_target)") || rc=$?
    case "$rc" in
      0) ;;
      3) die "The off-site place could not be reached (above). Mount the share, then try again." ;;
      *) die "The off-site copies could not be listed (above)." ;;
    esac
    id=$(printf '%s\n' "$listing" | awk 'NR==1{print $1}')
    [ -n "$id" ] || die "There is no off-site copy in $(env_get TARLEAKS_OFFSITE_FOLDER)."
    # The name ends up in a folder this command later removes: check it like a
    # typed one, whatever the share holds.
    case "$id" in */*|.*) die "The off-site folder lists a copy named \"$id\", which is not a copy name. Nothing was changed." ;; esac
    echo "The newest off-site copy is $id. (Another one: ./tarleaks cloud backup list, then ./tarleaks restore --from-cloud <copy> --recovery-kit <file>.)" >&2
  fi
  mkdir -p backups
  into="backups/from-cloud-$id"
  [ ! -e "$into" ] || die "$into already exists. Restore it directly: ./tarleaks restore $into"
  cloud_run "$(cloud_abs backups):/backups" "$(cloud_abs "$kit"):/kit.txt:ro" -- \
    open "$id" --target "$(cloud_target)" --recovery-kit /kit.txt --into "/backups/from-cloud-$id" \
    --release "$(env_get TARLEAKS_VERSION)" --keys /keys >&2 || exit $?
  printf '%s' "$into"
}

cloud_main() {
  local area=${1:-}
  shift || true
  case "$area" in
    backup-key) cloud_backup_key "$@" ;;
    backup) cloud_backup "$@" ;;
    status)
      echo "Off-site copies: $(cloud_target)$( [ "$(cloud_target)" = folder ] && printf ' → %s' "$(env_get TARLEAKS_OFFSITE_FOLDER)")"
      if [ -f "$CLOUD_DIR/backup-recipient.txt" ]; then echo "Backup key: made"; else echo "Backup key: not made (./tarleaks cloud backup-key init)"; fi
      if [ -f "$CLOUD_DIR/kit-verified" ]; then echo "Recovery kit: checked"; else echo "Recovery kit: not checked yet (./tarleaks cloud backup-key verify --recovery-kit <file>)"; fi
      if [ -f "$CLOUD_DIR/last_sequence" ]; then echo "Last off-site copy: number $(awk '{print $1}' "$CLOUD_DIR/last_sequence")"; fi ;;
    *) die "usage: ./tarleaks cloud backup-key … | backup … | status" ;;
  esac
}
