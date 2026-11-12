# Proves the Windows off-site backup commands (scripts/lib-cloud.ps1) against a
# fake `docker` and `schtasks`, the twin of check-cloud.sh: the engine gets
# exactly the folders and arguments it needs, its exit codes become the right
# sentences, a scheduled run still makes the local backup, and the restore
# still asks first. Run by CI (scripts job, pwsh on Linux).
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("tl-cloud-" + [guid]::NewGuid().ToString('N'))
$kit = Join-Path $work 'kit'; $bin = Join-Path $work 'bin'; $share = Join-Path $work 'share'
New-Item -ItemType Directory -Path $kit, $bin, $share | Out-Null
$failed = $false
try {
  foreach ($f in 'tarleaks.ps1', 'scripts', 'config', 'docker-compose.yml') { Copy-Item -Recurse (Join-Path $src $f) $kit }
  @('COMPOSE_PROJECT_NAME=tarleaks', 'TARLEAKS_VERSION=1.3.0', 'POSTGRES_USER=tarleaks', 'POSTGRES_DB=tarleaks') |
    Set-Content -LiteralPath (Join-Path $kit '.env')
  $inst = '11111111-2222-3333-4444-555555555555'
  $env:FAKE_LOG = Join-Path $work 'docker.log'; $env:FAKE_TASKS = Join-Path $work 'tasks'; $env:INST = $inst
  # The fake images carry no Tarleaks signature; scripts\check-image-signature.ps1 proves that check.
  $env:TARLEAKS_ALLOW_UNSIGNED = '1'
  New-Item -ItemType Directory -Path $env:FAKE_TASKS | Out-Null
  $fakeDocker = @'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
args=("$@")
case "$*" in
  "compose ps --status running --services") [ -n "${FAKE_NO_DB:-}" ] || echo postgres; exit 0 ;;
  "compose exec -T postgres psql"*) echo "$INST"; exit 0 ;;
  "compose exec -T postgres bash"*|"compose exec -T postgres rm"*) exit 0 ;;
  "compose cp postgres:"*) printf 'CREATE DATABASE app;\n-- PostgreSQL database cluster dump complete\n' | gzip > "${args[3]}"; exit 0 ;;
  "compose config") echo "name: tarleaks"; exit 0 ;;
esac
[ "${args[0]}" = compose ] && [ "${args[1]}" = run ] || exit 0
seen_service=0
for a in "${args[@]}"; do
  case "$a" in
    migrate|toolbox) seen_service=1 ;;
    -v|-e|--user|--rm|--no-deps|-T) [ "$seen_service" = 0 ] || { echo "ORDER: $a after the service" >> "$FAKE_LOG"; exit 99; } ;;
  esac
done
declare -A host
for ((i=0; i<${#args[@]}; i++)); do
  if [ "${args[$i]}" = -v ]; then m=${args[$((i+1))]}; h=${m%%:*}; rest=${m#*:}; c=${rest%%:*}; host[$c]=$h; fi
done
if [[ " ${args[*]} " == *" toolbox "* ]]; then
  e=$(mktemp -d); for v in files hrdocs; do tar czf "${host[/backup]}/$v.tar.gz" -C "$e" .; done; rm -rf "$e"; exit 0
fi
for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = cloud-backup ] && break; done
sub=${args[$((i+1))]:-}
[ -n "${FAKE_NO_ENGINE:-}" ] && { echo "error: unrecognized subcommand 'cloud-backup'" >&2; exit 2; }
argval() { local k; for ((k=i; k<${#args[@]}; k++)); do [ "${args[$k]}" = "$1" ] && { echo "${args[$((k+1))]}"; return; }; done; }
case "$sub" in
  --help) exit 0 ;;
  keygen|rotate) d=${host[$(argval --kit-dir)]}; echo "age-identity: AGE-SECRET-KEY-1TEST" > "$d/recovery-kit-test-$sub.txt"; echo "kit written" ;;
  verify-kit) touch "${host[/keys]}/kit-verified"; echo "ok" ;;
  init-target) [ -n "${FAKE_INIT_RC:-}" ] && exit "$FAKE_INIT_RC"
               [ -n "${FAKE_NO_MARKER:-}" ] || touch "${host[/offsite]}/.tarleaks-backup-target"; echo "set up" ;;
  list) [ -n "${FAKE_RC:-}" ] && { echo "cannot be reached (backup.target_unreachable)" >&2; exit "$FAKE_RC"; }
        echo "20261021T020000Z-3fa1c2d9  sequence 1  1234 bytes  key AB12" ;;
  seal) [ -n "${FAKE_SEAL_RC:-}" ] && exit "$FAKE_SEAL_RC"; echo "Off-site copy 1 stored." ;;
  open) into=$(argval --into); d=${host[/backups]}/${into#/backups/}; mkdir -p "$d"
        printf 'CREATE DATABASE app;\n-- PostgreSQL database cluster dump complete\n' | gzip > "$d/database.sql.gz"
        printf 'COMPOSE_PROJECT_NAME=tarleaks\nCLUSTER_DSN_KEY=k\n' > "$d/env"; echo "opened" ;;
  *) echo "ok" ;;
esac
'@
  $fakeTasks = @'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
name=""; for ((i=1; i<=$#; i++)); do [ "${!i}" = /TN ] && { j=$((i+1)); name=${!j}; }; done
f="$FAKE_TASKS/$(printf '%s' "$name" | tr ' /' '__')"
case "$1" in
  /Query) [ -f "$f" ] ;;
  /Create) printf '%s\n' "$*" > "$f" ;;
  /Delete) rm -f "$f" ;;
esac
'@
  Set-Content -LiteralPath (Join-Path $bin 'docker') -Value ($fakeDocker -replace "`r`n", "`n") -NoNewline
  Set-Content -LiteralPath (Join-Path $bin 'schtasks') -Value ($fakeTasks -replace "`r`n", "`n") -NoNewline
  & chmod +x (Join-Path $bin 'docker') (Join-Path $bin 'schtasks')
  $env:PATH = "${bin}:$env:PATH"

  function Pass($m) { Write-Host "ok   $m" }
  function Flunk($m) { Write-Host "FAIL $m"; $script:failed = $true }
  function Check($m, [scriptblock] $Test) { if (& $Test) { Pass $m } else { Flunk $m } }
  # No param block: every word (and -Switch) goes to tarleaks.ps1 as it is.
  # Text for a prompt comes from $script:StdIn.
  $script:StdIn = ''
  function Run {
    $a = @('-NoProfile', '-File', (Join-Path $kit 'tarleaks.ps1')) + $args
    $in = $script:StdIn; $script:StdIn = ''
    $out = if ($in) { $in | & pwsh @a 2>&1 | Out-String } else { & pwsh @a 2>&1 | Out-String }
    return [pscustomobject]@{ Rc = $LASTEXITCODE; Out = $out }
  }
  function Log { return (Get-Content -Raw -LiteralPath $env:FAKE_LOG -ErrorAction SilentlyContinue) + '' }
  function ClearLog { Set-Content -LiteralPath $env:FAKE_LOG -Value '' }
  function EnvText { return Get-Content -Raw -LiteralPath (Join-Path $kit '.env') }

  # 1. A release without the engine refuses and changes nothing.
  $env:FAKE_NO_ENGINE = '1'; $r = Run cloud backup-key init; Remove-Item Env:FAKE_NO_ENGINE
  Check 'no engine: refused' { $r.Rc -ne 0 -and $r.Out -match 'no off-site backups yet' }

  # 2. init: the engine gets /keys and the installation id; the kit lands in the kit folder, owner-only.
  ClearLog; $r = Run cloud backup-key init
  Check 'init: succeeds' { $r.Rc -eq 0 }
  Check 'init: keys folder mounted at /keys' { (Log) -match [regex]::Escape("-v $kit/.tarleaks/cloud:/keys") }
  Check 'init: installation id passed' { (Log) -match [regex]::Escape("keygen --keys /keys --kit-dir /keys --installation $inst") }
  Check 'init: the kit moved to the kit folder' { (Test-Path (Join-Path $kit 'recovery-kit-test-keygen.txt')) -and -not (Test-Path (Join-Path $kit '.tarleaks/cloud/recovery-kit-test-keygen.txt')) }
  Check 'init: the kit is mode 600' { (& stat -c %a (Join-Path $kit 'recovery-kit-test-keygen.txt')) -eq '600' }
  $env:FAKE_NO_DB = '1'; ClearLog; $r = Run cloud backup-key init; Remove-Item Env:FAKE_NO_DB
  Check 'no database: init refused, no keys made' { $r.Rc -ne 0 -and (Log) -notmatch 'cloud-backup keygen' }

  # 3. verify mounts the kit read-only.
  ClearLog; $r = Run cloud backup-key verify -RecoveryKit (Join-Path $kit 'recovery-kit-test-keygen.txt')
  Check 'verify: the kit is mounted read-only' { (Log) -match [regex]::Escape("recovery-kit-test-keygen.txt:/kit.txt:ro") }

  # 3b. forget-secret: only the kit copy inside the kit folder, only after I HAVE IT.
  $usb = Join-Path $work 'usb-copy.txt'; Copy-Item (Join-Path $kit 'recovery-kit-test-keygen.txt') $usb
  $script:StdIn = 'I HAVE IT'; $r = Run cloud backup-key forget-secret -RecoveryKit $usb
  Check 'forget-secret: a kit outside the kit folder is refused' { $r.Rc -ne 0 -and (Test-Path $usb) -and $r.Out -match 'somewhere else' }
  $second = Join-Path $kit 'second-kit.txt'; Copy-Item (Join-Path $kit 'recovery-kit-test-keygen.txt') $second
  $script:StdIn = 'no'; $r = Run cloud backup-key forget-secret -RecoveryKit $second
  Check 'forget-secret: without I HAVE IT nothing is deleted' { $r.Rc -ne 0 -and (Test-Path $second) }
  $script:StdIn = 'I HAVE IT'; $r = Run cloud backup-key forget-secret -RecoveryKit $second
  Check 'forget-secret: with I HAVE IT the kit-folder copy goes' { -not (Test-Path $second) }

  # 4. target: the ERP's own disk is refused without -SameDisk; with it, the folder is set up and mounted.
  $r = Run cloud backup target folder $kit -SameDisk
  Check 'target: the kit folder itself is refused' { $r.Rc -ne 0 -and $r.Out -match 'inside this kit' }
  $env:FAKE_INIT_RC = '3'; $r = Run cloud backup target folder $share -SameDisk; Remove-Item Env:FAKE_INIT_RC
  Check 'target: a first target that fails its set-up leaves no setting' { $r.Rc -eq 3 -and (EnvText) -notmatch 'TARLEAKS_OFFSITE_FOLDER=' -and (EnvText) -notmatch 'TARLEAKS_CLOUD_BACKUP=' }
  $env:FAKE_NO_MARKER = '1'; $r = Run cloud backup target folder $share -SameDisk; Remove-Item Env:FAKE_NO_MARKER
  Check 'target: a folder Docker cannot really write is not kept' { $r.Rc -ne 0 -and $r.Out -match 'cannot write' -and (EnvText) -notmatch 'TARLEAKS_OFFSITE_FOLDER=' }
  $r = Run cloud backup target folder $share
  Check 'target: same disk refused' { $r.Rc -ne 0 -and $r.Out -match 'same disk' -and (EnvText) -notmatch 'TARLEAKS_OFFSITE_FOLDER=' }
  ClearLog; $r = Run cloud backup target folder $share -SameDisk
  Check 'target: set with -SameDisk' { $r.Rc -eq 0 -and (EnvText) -match "TARLEAKS_OFFSITE_FOLDER=$([regex]::Escape($share))" }
  Check 'target: the folder is mounted at /offsite' { (Log) -match [regex]::Escape("-v ${share}:/offsite") }
  Check 'target: no option after the service name' { (Log) -notmatch '(?m)^ORDER' }

  # 5. Exit code 3 is explained and passed on.
  $env:FAKE_RC = '3'; $r = Run cloud backup list; Remove-Item Env:FAKE_RC
  Check 'list: exit 3 passed on' { $r.Rc -eq 3 }
  Check 'list: exit 3 explained' { $r.Out -match 'could not be reached' }
  ClearLog; $r = Run cloud backup verify 20261021T020000Z-3fa1c2d9
  Check 'verify <copy>: the whole name reaches the engine' { (Log) -match [regex]::Escape('cloud-backup verify 20261021T020000Z-3fa1c2d9 --target folder --keys /keys') }

  # 6. schedule: one task for this kit; off removes it.
  ClearLog; $r = Run cloud backup schedule 02:30
  Check 'schedule: a daily task at 02:30' { $r.Rc -eq 0 -and (Log) -match '/Create /TN Tarleaks ERP off-site copy [0-9a-f]{8} /SC DAILY /ST 02:30 /F /TR' -and (Log) -match 'backup -Offsite -Scheduled' }
  $r = Run cloud backup schedule 25:00
  Check 'schedule: a bad time refused' { $r.Rc -ne 0 -and $r.Out -match 'HH:MM' }
  ClearLog; $r = Run cloud backup schedule off
  Check 'schedule: off deletes the task' { $r.Rc -eq 0 -and (Log) -match '/Delete /TN Tarleaks ERP off-site copy' }

  # 7. backup -Offsite: the local backup, the seal, the marker; a failed seal keeps the local backup.
  ClearLog; $r = Run backup (Join-Path $kit 'backups/offsite-1') -Offsite
  Check 'backup -Offsite: succeeds' { $r.Rc -eq 0 -and (Test-Path (Join-Path $kit 'backups/offsite-1/database.sql.gz')) }
  Check 'backup -Offsite: seals the folder it made' { (Log) -match [regex]::Escape("cloud-backup seal /backups/offsite-1 --target folder --keys /keys --installation $inst --release 1.3.0") }
  Check 'backup -Offsite: marks it sealed' { Test-Path (Join-Path $kit 'backups/offsite-1/.offsite-sealed') }
  $env:FAKE_SEAL_RC = '3'; $r = Run backup (Join-Path $kit 'backups/offsite-2') -Offsite; Remove-Item Env:FAKE_SEAL_RC
  Check 'failed seal: fails, local backup kept, no marker' { $r.Rc -ne 0 -and (Test-Path (Join-Path $kit 'backups/offsite-2/database.sql.gz')) -and -not (Test-Path (Join-Path $kit 'backups/offsite-2/.offsite-sealed')) -and $r.Out -match 'only the off-site copy is missing' }
  Rename-Item -LiteralPath $share -NewName 'share-gone'
  $r = Run backup (Join-Path $kit 'backups/offsite-3') -Scheduled
  Check 'scheduled, disk missing: local backup still made' { Test-Path (Join-Path $kit 'backups/offsite-3/database.sql.gz') }
  Check 'scheduled, disk missing: says why and fails' { $r.Rc -ne 0 -and $r.Out -match 'No off-site copy tonight' }
  $r = Run backup (Join-Path $kit 'backups/offsite-4') -Offsite
  Check 'by hand, disk missing: refused before the dump' { $r.Rc -ne 0 -and -not (Test-Path (Join-Path $kit 'backups/offsite-4')) }
  Rename-Item -LiteralPath (Join-Path $work 'share-gone') -NewName 'share'

  # 7b. The scheduled clean-up removes only old folders sealed off-site.
  $b = Join-Path $kit 'backups'
  foreach ($n in '20261001-020000', '20261002-020000', '20261020-020000', 'pre-upgrade-20261001') { New-Item -ItemType Directory -Force -Path (Join-Path $b $n) | Out-Null }
  $old = (Get-Date).AddDays(-10)
  Set-Content (Join-Path $b '20261001-020000/.offsite-sealed') 'x'; (Get-Item -Force (Join-Path $b '20261001-020000/.offsite-sealed')).LastWriteTime = $old
  Set-Content (Join-Path $b '20261020-020000/.offsite-sealed') 'x'
  Set-Content (Join-Path $b 'pre-upgrade-20261001/database.sql.gz') 'x'
  & pwsh -NoProfile -Command "Set-Location '$kit'; . ./scripts/lib-cloud.ps1 2>`$null; function Get-EnvValue(`$k) { (Get-Content .env | Where-Object { `$_ -like ""`$k=*"" } | Select-Object -Last 1) -replace '^[^=]*=', '' }; function Protect-Path { }; function Warn(`$m) { }; Invoke-CloudAfterScheduledSeal" *> $null
  Check 'clean-up: an old sealed backup is removed' { -not (Test-Path (Join-Path $b '20261001-020000')) }
  Check 'clean-up: an old unsealed backup is kept' { Test-Path (Join-Path $b '20261002-020000') }
  Check 'clean-up: a recent sealed backup is kept' { Test-Path (Join-Path $b '20261020-020000') }
  Check 'clean-up: a safety backup is kept' { Test-Path (Join-Path $b 'pre-upgrade-20261001') }

  # 8. restore -FromCloud opens the newest copy and still asks first.
  ClearLog; $script:StdIn = 'no'; $r = Run restore -FromCloud -RecoveryKit (Join-Path $kit 'recovery-kit-test-keygen.txt')
  Check 'restore: the newest copy is opened' { (Log) -match [regex]::Escape('cloud-backup open 20261021T020000Z-3fa1c2d9 --target folder --recovery-kit /kit.txt --into /backups/from-cloud-20261021T020000Z-3fa1c2d9 --release 1.3.0 --keys /keys') }
  Check 'restore: still asks before replacing anything' { $r.Rc -ne 0 -and $r.Out -match 'Cancelled. Nothing was changed' }
  $r = Run restore -FromCloud ../etc -RecoveryKit (Join-Path $kit 'recovery-kit-test-keygen.txt')
  Check 'restore: a copy name with a path is refused' { $r.Rc -ne 0 -and $r.Out -match 'not the name of an off-site copy' }
  $r = Run restore (Join-Path $kit 'backups/offsite-1') -RecoveryKit x.txt
  Check 'restore: -RecoveryKit alone refused' { $r.Rc -ne 0 -and $r.Out -match 'is for -FromCloud' }
} finally {
  Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
}
if ($failed) { Write-Host 'Some checks failed.'; exit 1 }
Write-Host 'All Windows off-site backup command checks passed.'
# Explicit: CI's pwsh step fails on the last native command's exit code,
# and the last one here is a child run that was meant to fail.
exit 0
