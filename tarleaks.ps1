<#
.SYNOPSIS
  Everyday commands for a Tarleaks ERP installation on Windows.

.EXAMPLE
  .\tarleaks.ps1 status
  .\tarleaks.ps1 start | stop | restart
  .\tarleaks.ps1 logs auth
  .\tarleaks.ps1 update                  # newest release: check, back up, update (-To 1.2.0, -Check)
  .\tarleaks.ps1 upgrade 1.1.0            # -Offline: no download, images already here
  .\tarleaks.ps1 backup                   # or: backup D:\Backups\erp-monday
  .\tarleaks.ps1 restore backups\20261008-021500   # -KeepSettings: keep this folder's name, port and address
  .\tarleaks.ps1 setup-code
  .\tarleaks.ps1 reset-admin boss@example.com   # -Company <name> -ResetTwoFactor: an administrator who cannot sign in gets a temporary password
  .\tarleaks.ps1 apps
  .\tarleaks.ps1 apps add payroll attendance
  .\tarleaks.ps1 apps remove crm
  .\tarleaks.ps1 profile standard
  .\tarleaks.ps1 editors off             # or on: the document and diagram editors
  .\tarleaks.ps1 network local           # or office: who may open the ERP
  .\tarleaks.ps1 load-bundle D:\tarleaks-1.1.0-linux-amd64
  .\tarleaks.ps1 uninstall               # -Purge: delete the data too
#>
param(
  [Parameter(Position = 0)] [string] $Command = 'help',
  [Parameter(Position = 1)] [string] $Argument = '',
  [Parameter(Position = 2, ValueFromRemainingArguments = $true)] [string[]] $Rest = @(),
  [switch] $Offline,
  [switch] $Force,
  [switch] $Purge,
  [switch] $NoSafetyBackup,
  [string] $To = '',
  [switch] $Check,
  [string] $Company = '',
  [switch] $ResetTwoFactor,
  [switch] $KeepSettings
)
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot
$envPath = Join-Path $PSScriptRoot '.env'
if ($Command -notin 'load-bundle', 'help' -and -not (Test-Path $envPath)) {
  Write-Host 'No .env here. Run .\install.ps1 first.' -ForegroundColor Red; exit 1
}

function Ok($m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [x]  $m" -ForegroundColor Red; exit 1 }

function Get-EnvValue($key) {
  if (-not (Test-Path $envPath)) { return '' }
  $line = Get-Content $envPath | Where-Object { $_ -match "^$([regex]::Escape($key))=" } | Select-Object -Last 1
  if ($line) { return $line.Substring($key.Length + 1) } else { return '' }
}
function Set-EnvValue($key, $value) {
  $lines = [System.Collections.Generic.List[string]]::new([string[]](Get-Content $envPath))
  $found = $false
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^$([regex]::Escape($key))=") { $lines[$i] = "$key=$value"; $found = $true } }
  if (-not $found) { $lines.Add("$key=$value") }
  [System.IO.File]::WriteAllText($envPath, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}
function Remove-EnvValue($key) {
  $lines = @(Get-Content $envPath | Where-Object { $_ -notmatch "^$([regex]::Escape($key))=" })
  [System.IO.File]::WriteAllText($envPath, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}
function Get-EnvFileValue([string] $Path, [string] $Key) {
  $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -Last 1
  if ($line) { return $line.Substring($Key.Length + 1) } else { return '' }
}
# The installation's name in Docker for a settings file: its
# COMPOSE_PROJECT_NAME, else the name in docker-compose.yml.
function Get-EnvProject([string] $Path) {
  $p = (Get-EnvFileValue $Path 'COMPOSE_PROJECT_NAME') -replace "[`"' \r]", ''
  $p = $p.ToLowerInvariant()
  if (-not $p) {
    $m = Select-String -Path (Join-Path $PSScriptRoot 'docker-compose.yml') -Pattern '^name:\s*(\S+)' | Select-Object -First 1
    if ($m) { $p = $m.Matches[0].Groups[1].Value }
  }
  return $p
}
# What `restore -KeepSettings` keeps from this folder: where and how this
# installation runs. Keys and the app list always come from the backup.
$script:RestoreKeepKeys = @('COMPOSE_PROJECT_NAME', 'HTTP_PORT', 'HTTP_BIND', 'TARLEAKS_HOST', 'TARLEAKS_URL', 'TARLEAKS_PROFILE_ENV', 'TARLEAKS_TLS', 'ACME_EMAIL', 'CF_DNS_API_TOKEN', 'TARLEAKS_OFFLINE')
# Kept on EVERY restore: the message queue's account is made once, when this
# folder's queue volume is first created, and a restore does not touch that
# volume. The backup's password would lock every service out of the queue.
$script:RestoreAlwaysKeep = @('RABBITMQ_USER', 'RABBITMQ_PASSWORD')
# Secrets a newer kit needs that an older .env does not have yet (1.0.0 has
# no PROCUREMENT_KEK, for one): without them Compose refuses the whole file.
# Only missing or GENERATED keys are written, as install.ps1 does.
function Add-NewKeys {
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $keys = [ordered]@{
    POSTGRES_PASSWORD = 'hex24'; RABBITMQ_PASSWORD = 'hex24'; STORAGE_ACCESS_KEY = 'hex16'
    STORAGE_SECRET_KEY = 'hex32'; JWT_SECRET = 'hex32'; CLUSTER_DSN_KEY = 'b64'; INTERNAL_TOKEN = 'hex32'
    PORTAL_JWT_SECRET = 'hex32'; NOTIFICATIONS_KEK = 'b64'; NOTIFICATIONS_UNSUB_SECRET = 'hex32'
    NOTIFICATIONS_OAUTH_SECRET = 'hex32'; HELPDESK_TOKEN_KEY = 'b64'; SUBSCRIPTIONS_KEY_SEAL_KEY = 'b64'
    MARKETPLACE_TOKEN_KEY = 'b64'; INSIGHTS_SOURCE_KEY = 'b64'; PROCUREMENT_KEK = 'b64'
    CONTRACTS_PROVIDER_KEY = 'b64'; ONLYOFFICE_JWT_SECRET = 'hex32'
  }
  $n = 0
  foreach ($k in $keys.Keys) {
    $cur = Get-EnvValue $k
    if ($cur -and $cur -ne 'GENERATED') { continue }
    $gen = $keys[$k]
    $len = if ($gen -eq 'b64') { 32 } else { [int]$gen.Substring(3) }
    $b = New-Object byte[] $len; $rng.GetBytes($b)
    $val = if ($gen -eq 'b64') { [Convert]::ToBase64String($b) } else { -join ($b | ForEach-Object { $_.ToString('x2') }) }
    Set-EnvValue $k $val
    $n++
  }
  if ($n) { Ok "Added $n setting(s) this kit needs to .env (new keys only; existing values unchanged)" }
  Write-SigningKeyNote (Add-SigningKey)
}
# An .env written before the rename has NEXUS_<key> lines: rename each to
# TARLEAKS_<key> in place, keeping its value (keys are never regenerated).
function Convert-LegacyKeys {
  $src = @(Get-Content $envPath)
  $old = @{}
  foreach ($l in $src) { if ($l -match '^NEXUS_([A-Z0-9_]+)=(.*)$') { $old[$Matches[1]] = $Matches[2] } }
  $has = @{}
  foreach ($l in $src) { if ($l -match '^TARLEAKS_([A-Z0-9_]+)=') { $has[$Matches[1]] = $true } }
  $out = [System.Collections.Generic.List[string]]::new()
  $changed = $false
  foreach ($l in $src) {
    if ($l -match '^TARLEAKS_([A-Z0-9_]+)=(.*)$') {
      $name = $Matches[1]; $val = $Matches[2]
      if (($val -eq '' -or $val -eq 'GENERATED') -and $old.ContainsKey($name) -and $old[$name] -ne '') { $val = $old[$name]; $changed = $true }
      $out.Add("TARLEAKS_$name=$val")
    }
    elseif ($l -match '^NEXUS_([A-Z0-9_]+)=(.*)$') {
      $changed = $true
      if (-not $has.ContainsKey($Matches[1])) { $out.Add("TARLEAKS_$($Matches[1])=$($Matches[2])") }
    }
    elseif ($l -match '^# ?NEXUS_[A-Z0-9_]+=') { $changed = $true; $out.Add(($l -replace 'NEXUS_', 'TARLEAKS_')) }
    else { $out.Add($l) }
  }
  if ($changed) {
    [System.IO.File]::WriteAllText($envPath, (($out -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'Renamed the NEXUS_* settings in .env to TARLEAKS_* (values unchanged).' -ForegroundColor Green
  }
}
function Port { $p = Get-EnvValue 'HTTP_PORT'; if ($p) { $p } else { '80' } }
. (Join-Path $PSScriptRoot 'scripts/lib-apps.ps1')
. (Join-Path $PSScriptRoot 'scripts/lib-keys.ps1')
$script:AppsVersion = Get-EnvValue 'TARLEAKS_VERSION'
# The migrate image was renamed with the rebrand: nexus-migrate up to 1.1.x,
# tarleaks-migrate from 1.2.0. docker-compose.yml reads TARLEAKS_MIGRATE_IMAGE;
# a name written in .env wins.
function Use-MigrateImage([string] $Version) {
  if (Get-EnvValue 'TARLEAKS_MIGRATE_IMAGE') { return }
  $name = if ($Version -match '^(0|1\.0|1\.1)\.') { 'nexus-migrate' } else { 'tarleaks-migrate' }
  [Environment]::SetEnvironmentVariable('TARLEAKS_MIGRATE_IMAGE', $name, 'Process')
}
Use-MigrateImage $script:AppsVersion
function Die($m) { Write-Host $m -ForegroundColor Red; exit 1 }
# The apps this installation runs. An .env from before apps could be chosen has
# only a hardware profile: read it as that preset.
function Get-CurrentApp {
  $a = Get-EnvValue 'TARLEAKS_APPS'
  if (-not $a) {
    $p = Get-EnvValue 'COMPOSE_PROFILES'
    $a = if ($p -like '*full*') { Get-AppPreset 'full' } elseif ($p -like '*standard*') { Get-AppPreset 'standard' } else { Get-AppPreset 'small' }
  }
  # An app whose image this release does not have (the version was set back)
  # is left out rather than stopping everything.
  $late = @((Get-AppUnreleased).Keys)
  $gone = @(Split-AppList $a | Where-Object { $late -contains $_ })
  if ($gone) {
    Write-Host "Release $($script:AppsVersion) does not have $(Get-AppName ($gone -join ',')); left out, its data kept. On a release that has it again: .\tarleaks.ps1 apps add $($gone -join ' ')" -ForegroundColor Yellow
    $a = Remove-AppFromList $a $late
  }
  return $a
}
# Write the services to run and the apps to show for a list of chosen apps.
function Set-ChosenApp([string] $List) {
  try { $apps = Resolve-App $List } catch { Die $_.Exception.Message }
  if (-not $apps) { Die 'At least one app must stay. To remove everything: docker compose down' }
  $closure = Get-AppClosure $apps
  $hadEditor = ((Get-EnvValue 'COMPOSE_PROFILES') -split ',') -contains 'onlyoffice'
  if (-not (Get-EnvValue 'TARLEAKS_EDITORS')) { Set-EnvValue 'TARLEAKS_EDITORS' 'on' }
  Set-EnvValue 'TARLEAKS_APPS' $apps
  Set-EnvValue 'COMPOSE_PROFILES' ((Get-AppUnit $closure) + (Get-AppAddon $closure))
  Set-EnvValue 'TARLEAKS_AVAILABLE_MODULES' (Get-AppModule $closure)
  $setting = Get-AppEditorSetting $closure (Get-EnvValue 'TARLEAKS_URL')
  foreach ($k in $setting.Keys) { Set-EnvValue $k $setting[$k] }
  # An installation from before the editors existed gets them on its next start.
  if (-not $hadEditor -and ((Split-AppList (Get-AppAddonUnit $closure)) -contains 'onlyoffice')) {
    Warn 'The document editor is now part of this installation (New and Edit in Documents): about 2 GB to download and 2 GB of memory. Not wanted on this computer? .\tarleaks.ps1 editors off'
  }
}
# Recompute from the sheet, so a release that changes what an app needs takes
# effect on the next start.
function Sync-App { Set-ChosenApp (Get-CurrentApp) }
function Gb($mb) { return ('{0:N1}' -f ($mb / 1024)) }
# Compare two releases, candidates included: -1, 0 or 1 for A <, =, > B.
# 1.2.0-rc.1 < 1.2.0-rc.2 < 1.2.0 < 1.2.1; a build tag (-candidate) sorts just
# below the release it is a candidate for.
function Get-ReleaseKey([string] $V) {
  $main = $V; $pre = ''
  if ($V.Contains('-')) { $main = $V.Substring(0, $V.IndexOf('-')); $pre = $V.Substring($V.IndexOf('-') + 1) }
  $p = @($main.Split('.')) + @('0', '0', '0')
  $out = ($p[0..2] | ForEach-Object { '{0:D9}' -f [int]$_ }) -join ''
  if (-not $pre) { return "$out~" }
  $n = if ($pre -match '(\d+)') { [int]$Matches[1] } else { 0 }
  return "$out-" + ('{0:D9}' -f $n) + $(if ($pre -match 'candidate') { 'a' } else { 'b' })
}
function Compare-Release([string] $A, [string] $B) {
  $ka = Get-ReleaseKey $A; $kb = Get-ReleaseKey $B
  if ([string]::CompareOrdinal($ka, $kb) -lt 0) { return -1 } elseif ($ka -eq $kb) { return 0 } else { return 1 }
}
# The newest published release newer than $Current; candidates count only
# when $Current is itself a candidate; build tags (-candidate) never count.
function Select-NewestRelease([string[]] $Tags, [string] $Current) {
  $best = ''
  foreach ($t in $Tags) {
    if ($t -notmatch '^\d+\.\d+\.\d+(-rc\.\d+)?$') { continue }
    if ($t -match '-rc\.' -and $Current -notmatch '-rc\.') { continue }
    if (-not $best -or (Compare-Release $t $best) -eq 1) { $best = $t }
  }
  if ($best -and $Current -and (Compare-Release $best $Current) -ne 1) { $best = $Current }
  return $best
}
function Probe {
  $b = Get-EnvValue 'HTTP_BIND'; if (-not $b -or $b -eq '0.0.0.0') { $b = '127.0.0.1' }
  "http://${b}:$(Port)"
}
function Wait-Ready {
  $deadline = (Get-Date).AddMinutes(10)
  while ($true) {
    try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri "$(Probe)/api/auth/installation" | Out-Null; break }
    catch { if ((Get-Date) -gt $deadline) { Write-Host ''; Write-Host 'Not answering yet: .\tarleaks.ps1 logs auth' -ForegroundColor Yellow; return }
            Write-Host '.' -NoNewline; Start-Sleep -Seconds 5 }
  }
  Write-Host ''; Write-Host "Running at $(Get-EnvValue 'TARLEAKS_URL')" -ForegroundColor Green
}
# The document editor takes a minute or two to start the first time. Waits for
# it (at most 4 minutes) and says plainly when it is not up yet; never fails.
function Wait-Editor {
  if (((Get-EnvValue 'COMPOSE_PROFILES') -split ',') -notcontains 'onlyoffice') { return }
  $deadline = (Get-Date).AddMinutes(4); $shown = $false
  while ($true) {
    try {
      $answer = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri "$(Probe)/onlyoffice/healthcheck").Content
      if ("$answer".Trim() -eq 'true') { break }
    } catch { $answer = '' }
    if ((Get-Date) -gt $deadline) {
      if ($shown) { Write-Host '' }
      Warn 'The document editor is still starting. New and Edit in Documents work once it is up (a minute or two more). See: .\tarleaks.ps1 logs onlyoffice'
      return
    }
    if (-not $shown) { Write-Host 'Starting the document editor (the first start takes a minute or two)' -NoNewline; $shown = $true }
    Write-Host '.' -NoNewline; Start-Sleep -Seconds 5
  }
  if ($shown) { Write-Host '' }
  Ok 'The document editor is ready'
}
# Docker Compose. The ERP's containers use the outbound proxy written in .env,
# never this session's: Compose would take the session's value over .env's, so
# it is hidden from Compose for the call (docs/configuration.md#outbound-proxy).
function Invoke-Compose {
  $names = 'HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY', 'ALL_PROXY'
  $saved = @{}
  foreach ($n in $names) {
    $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process')
    [Environment]::SetEnvironmentVariable($n, $null, 'Process')
  }
  try { docker compose @args } finally {
    foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'Process') }
  }
}
# Every image the installation runs (docker-compose.yml + .env; -Version asks
# about another release), minus the ones already on this computer. $null when
# the list cannot be read.
function Get-MissingImages([string] $Version = '') {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $prev = [Environment]::GetEnvironmentVariable('TARLEAKS_VERSION', 'Process')
  if ($Version) { [Environment]::SetEnvironmentVariable('TARLEAKS_VERSION', $Version, 'Process'); Use-MigrateImage $Version }
  try {
    $images = docker compose config --images 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $missing = @()
    foreach ($img in ($images | Where-Object { $_ } | Sort-Object -Unique)) {
      docker image inspect $img *> $null
      if ($LASTEXITCODE -ne 0) { $missing += $img }
    }
    return , $missing
  } finally {
    [Environment]::SetEnvironmentVariable('TARLEAKS_VERSION', $prev, 'Process')
    $ErrorActionPreference = $old
  }
}
# The Compose project this kit runs as (`name:` in docker-compose.yml, or
# COMPOSE_PROJECT_NAME in .env). Containers and volumes carry it as a label;
# never assume "tarleaks".
function Get-ComposeProject {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $cfg = docker compose config 2>$null } finally { $ErrorActionPreference = $old }
  foreach ($l in $cfg) { if ($l -match '^name:\s*(.+)$') { return $Matches[1].Trim() } }
  return ''
}
function Test-Running([string] $Service) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { return @(docker compose ps --status running --services 2>$null) -contains $Service }
  finally { $ErrorActionPreference = $old }
}
# Stop everything, including services of apps a smaller selection dropped
# (`docker compose stop` only sees the services of the apps chosen now).
function Stop-All {
  docker compose stop
  $p = Get-ComposeProject
  if ($p) {
    $ids = @(docker ps -q --filter "label=com.docker.compose.project=$p" | Where-Object { $_ })
    if ($ids.Count -gt 0) { docker stop @ids | Out-Null }
  }
}
function Remove-AllContainer {
  $p = Get-ComposeProject
  if ($p) {
    $ids = @(docker ps -aq --filter "label=com.docker.compose.project=$p" | Where-Object { $_ })
    if ($ids.Count -gt 0) { docker rm -f @ids | Out-Null }
  }
}
# Runs a docker command and stops with a message when it fails. PowerShell does
# not stop on a failed program by itself, so every step of backup and restore
# goes through this.
function Invoke-Checked([string] $What) {
  & docker @args | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "$What failed (docker exit code $LASTEXITCODE, see above)." }
}
# Owner-only on Windows: this user, Administrators and SYSTEM (Docker Desktop
# writes as you). Elsewhere the folder is made with mode 700 by Docker's tools.
function Protect-Path([string] $Path, [switch] $File) {
  if ($env:OS -ne 'Windows_NT') { & chmod $(if ($File) { '600' } else { '700' }) $Path; return }
  $grant = if ($File) { @("${env:USERNAME}:F", '*S-1-5-32-544:F', '*S-1-5-18:F') }
           else { @("${env:USERNAME}:(OI)(CI)F", '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F') }
  $args2 = @($Path, '/inheritance:r') + ($grant | ForEach-Object { '/grant:r'; $_ })
  icacls @args2 | Out-Null
}
# Waits until the database answers, at most 5 minutes.
function Wait-Database([string] $User) {
  $deadline = (Get-Date).AddMinutes(5)
  while ($true) {
    docker compose exec -T postgres pg_isready -q -h 127.0.0.1 -U $User *> $null
    if ($LASTEXITCODE -eq 0) { return }
    if ((Get-Date) -gt $deadline) { throw 'The database did not start within 5 minutes. See why: .\tarleaks.ps1 logs postgres (a full disk is the usual cause).' }
    Start-Sleep -Seconds 2
  }
}
# A shell script run in the `toolbox` service (the database image), with the
# folder mounted at /backup. Compose finds the volumes of THIS installation, and
# its GNU tar keeps the file store's metadata (extended attributes). The script
# travels base64-encoded in an environment variable: PowerShell would mangle
# quotes on a command line, and the backup folder may be read-only.
function ConvertTo-Step([string] $Script) {
  return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Script -replace "`r`n", "`n")))
}
function Invoke-Toolbox([string] $Folder, [string] $Script) {
  Invoke-Checked 'Copying the files' compose run --rm --no-deps -T -e "TARLEAKS_STEP=$(ConvertTo-Step $Script)" -v "${Folder}:/backup" toolbox 'printenv TARLEAKS_STEP | base64 -d | sh'
}
# Checks a pg_dumpall file (a readable gzip, a database inside, the closing
# line) and each archive, inside the toolbox: Windows has no gzip of its own.
$script:CheckScript = @'
set -eu
cd /backup
found=$(gzip -dc database.sql.gz | awk '/^CREATE DATABASE /{db=1} /^-- PostgreSQL database cluster dump complete/{end=1} END{print (db?"db":"-") (end?"end":"-")}') || { echo "database.sql.gz is damaged (not a readable gzip file)"; exit 1; }
case "$found" in dbend) ;; -*) echo "database.sql.gz holds no database"; exit 1 ;; *) echo "database.sql.gz is incomplete: the dump stopped before the end"; exit 1 ;; esac
for v in files hrdocs; do
  [ -f "$v.tar.gz" ] || continue
  tar -tzf "$v.tar.gz" > /dev/null 2>&1 || { echo "$v.tar.gz is damaged (cannot be read to the end)"; exit 1; }
done
'@
# Writes a complete backup into $Dir, or nothing at all. $true when it worked.
function Invoke-Backup([string] $Dir) {
  $Dir = $Dir.TrimEnd('\', '/')
  if ((Test-Path -LiteralPath $Dir) -and (Get-ChildItem -LiteralPath $Dir -Force | Select-Object -First 1)) {
    Write-Host "  [x]  $Dir already exists and is not empty. Choose a new folder name." -ForegroundColor Red; return $false
  }
  $parent = Split-Path -Parent $Dir; if (-not $parent) { $parent = '.' }
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $full = Join-Path (Resolve-Path -LiteralPath $parent).Path (Split-Path -Leaf $Dir)
  $part = "$full.partial"
  if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Recurse -Force }
  New-Item -ItemType Directory -Path $part | Out-Null
  Protect-Path $part
  $done = $false
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    if (-not (Test-Running 'postgres')) { throw 'The database is not running, so there is nothing to back up. Start it: .\tarleaks.ps1 start' }
    $user = Get-EnvValue 'POSTGRES_USER'; if (-not $user) { $user = 'tarleaks' }
    Write-Host 'Backing up the database...'
    # Dumped inside the container (PowerShell pipelines are text and would
    # corrupt a binary stream), with pipefail so a dump that dies half-way fails.
    Invoke-Checked 'The database dump' compose exec -T postgres bash -o pipefail -c "pg_dumpall -U '$user' --clean --if-exists | gzip > /tmp/tarleaks-dump.sql.gz"
    try { Invoke-Checked 'Copying the database dump' compose cp postgres:/tmp/tarleaks-dump.sql.gz (Join-Path $part 'database.sql.gz') }
    finally { docker compose exec -T postgres rm -f /tmp/tarleaks-dump.sql.gz *> $null }
    Write-Host 'Backing up the files...'
    # The app's own nightly backups (<bucket>/<company>/backups/) are left out:
    # the database dump already holds every database. GNU tar exits 1 when a
    # file changed while it was read (someone uploaded): kept, with a note.
    Invoke-Toolbox $part @'
set -f
for v in files hrdocs; do
  ex=""; [ "$v" = files ] && ex="--exclude=./*/*/backups"
  rc=0; tar --xattrs --xattrs-include="user.*" -czf "/backup/$v.tar.gz" $ex -C "/vol/$v" . || rc=$?
  [ "$rc" -le 1 ] || exit "$rc"
  [ "$rc" = 0 ] || echo "  note: a file in $v changed while it was copied (someone was working); the backup is still usable"
done
'@
    Invoke-Toolbox $part $script:CheckScript
    Copy-Item -LiteralPath $envPath -Destination (Join-Path $part 'env')
    @("made: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')", "version: $(Get-EnvValue 'TARLEAKS_VERSION')",
      "apps: $(Get-EnvValue 'TARLEAKS_APPS')", "project: $(Get-ComposeProject)") |
      Set-Content -LiteralPath (Join-Path $part 'backup-info.txt') -Encoding ascii
    Rename-Item -LiteralPath $part -NewName (Split-Path -Leaf $full)
    $done = $true
    $size = (Get-ChildItem -LiteralPath $full -File | Measure-Object -Sum Length).Sum
    Ok ("Backup written to $full ({0:N1} MB: database, files, settings)." -f ($size / 1MB))
    Warn 'Anyone holding it can read all your data (the database is plain SQL) and has your keys: encrypt it before it leaves this computer (docs\backup-restore.md).'
    return $true
  } catch {
    Write-Host "  [x]  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  [x]  The backup FAILED. Nothing was kept: an incomplete backup is worse than none.' -ForegroundColor Red
    return $false
  } finally {
    $ErrorActionPreference = $old
    if (-not $done -and (Test-Path -LiteralPath $part)) { Remove-Item -LiteralPath $part -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

# Checks every "<sha256>  <file>" line of a checksum file; lists what fails.
function Test-Checksums([string] $Folder, [string] $SumsFile) {
  $good = $true
  foreach ($line in Get-Content $SumsFile) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') { continue }
    $want = $Matches[1]; $file = Join-Path $Folder $Matches[2].Trim()
    if (-not (Test-Path -LiteralPath $file)) { Write-Host "  missing: $($Matches[2])" -ForegroundColor Red; $good = $false; continue }
    $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash
    if ($got -ne $want) { Write-Host "  damaged: $($Matches[2])" -ForegroundColor Red; $good = $false }
  }
  return $good
}
# Refuses a bundle made for another CPU type.
function Assert-Platform([string] $ImagesTxt) {
  $plat = (Select-String -Path $ImagesTxt -Pattern '^# *platform: *(.+)$' | Select-Object -First 1)
  if (-not $plat) { return }
  $want = $plat.Matches[0].Groups[1].Value.Trim()
  $arch = (docker info --format '{{.Architecture}}').Trim()
  $mine = switch ($arch) { { $_ -in 'x86_64', 'amd64' } { 'linux/amd64' } { $_ -in 'aarch64', 'arm64' } { 'linux/arm64' } default { $arch } }
  if ($want -ne $mine) { Die "This bundle is for $want; this computer runs $mine. Get the $mine bundle." }
}

switch ($Command) {
  'start'   { Write-SigningKeyNote (Add-SigningKey); Sync-App; docker compose up -d --remove-orphans; Stop-UnselectedApp; Wait-Ready; Wait-Editor }
  'stop'    { Stop-All; Write-Host 'Stopped. Your data is kept; .\tarleaks.ps1 start brings it back.' -ForegroundColor Green }
  'restart' { Write-SigningKeyNote (Add-SigningKey); Sync-App; docker compose up -d --remove-orphans --force-recreate; Stop-UnselectedApp; Wait-Ready; Wait-Editor }
  'status'  {
    docker compose ps --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
    try {
      $d = Invoke-RestMethod -TimeoutSec 5 -Uri "$(Probe)/api/auth/installation"
      $ws = if ($d.workspace) { $d.workspace.name } else { '(not set up yet - open the address in a browser)' }
      Write-Host "`nWorkspace: $ws"
      if ($d.licence) { $m = if ($d.licence.message) { " - $($d.licence.message)" } else { '' }; Write-Host "Licence:   $($d.licence.state)$m" } else { Write-Host 'Licence:   not configured' }
    } catch { Write-Host "`nThe ERP is not answering on port $(Port)." -ForegroundColor Yellow }
  }
  'logs'    { if ($Argument) { docker compose logs -f --tail=200 $Argument } else { docker compose logs -f --tail=200 } }
  'upgrade' {
    $current = Get-EnvValue 'TARLEAKS_VERSION'
    $v = if ($Argument) { $Argument } else { $current }
    if (-not $v) { Die 'No version given and none in .env. Usage: .\tarleaks.ps1 upgrade 1.2.0' }
    if ($v -notmatch '^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$') { Die "`"$v`" is not a release number (like 1.2.0). The release notes list them." }
    if ($current -and (Compare-Release $v $current) -lt 0) {
      if (-not $Force) { Die "$v is OLDER than the release you run ($current). Going back does not undo the database updates $current made, so the older release may not start. To go back, restore the backup taken before the upgrade (backups\pre-upgrade-*): .\tarleaks.ps1 restore <folder>. (-Force tries anyway.)" }
      Warn "Going back from $current to $v (-Force)."
    }
    if ($v -eq $current) { Write-Host "Already on ${v}: checking its images and the database again." }
    else { Write-Host "Upgrading from $current to $v." }
    # 1. The new images, while the current version keeps running. .env keeps
    #    naming the current version until every image is on this computer.
    Add-NewKeys
    # Only the services the TARGET release runs for these apps: an app it does
    # not have (taken out, like Diagram Studio in 1.2.0, or not there yet) is
    # not downloaded, so it cannot stop the upgrade. .env follows after the
    # backup (Sync-App below), with a message naming what was left out.
    $savedAppsVersion = $script:AppsVersion; $script:AppsVersion = $v
    try {
      $targetClosure = Get-AppClosure (Resolve-App (Get-CurrentApp 6>$null))
      $targetProfiles = (Get-AppUnit $targetClosure) + (Get-AppAddon $targetClosure)
    } catch { $targetProfiles = Get-EnvValue 'COMPOSE_PROFILES' }
    finally { $script:AppsVersion = $savedAppsVersion }
    $prevProfiles = [Environment]::GetEnvironmentVariable('COMPOSE_PROFILES', 'Process')
    [Environment]::SetEnvironmentVariable('COMPOSE_PROFILES', $targetProfiles, 'Process')
    $downloaded = $false
    if (-not $Offline) {
      $prev = [Environment]::GetEnvironmentVariable('TARLEAKS_VERSION', 'Process')
      [Environment]::SetEnvironmentVariable('TARLEAKS_VERSION', $v, 'Process')
      Use-MigrateImage $v
      $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      try { Invoke-Compose pull --quiet; $downloaded = ($LASTEXITCODE -eq 0) }
      finally {
        $ErrorActionPreference = $old
        [Environment]::SetEnvironmentVariable('TARLEAKS_VERSION', $prev, 'Process')
      }
    }
    if ($downloaded) { Ok "Images for $v downloaded" } else {
      $missing = Get-MissingImages -Version $v
      if ($null -eq $missing) { Die 'Could not read the list of images from docker-compose.yml.' }
      if ($missing.Count -gt 0) {
        Write-Host 'Not on this computer:'; $missing | ForEach-Object { Write-Host "  $_" }
        Die "Nothing was changed: .env still names $current. Load the offline bundle for $v (.\tarleaks.ps1 load-bundle <folder>), or fix the download, then run this again."
      }
      Ok "Every image for $v is already on this computer"
    }
    [Environment]::SetEnvironmentVariable('COMPOSE_PROFILES', $prevProfiles, 'Process')
    # 2. Back up while .env still names the release the data belongs to. A
    #    failed backup stops the upgrade: nothing has changed yet.
    Write-Host 'Taking a backup first.'
    $pre = if ($env:TARLEAKS_PRE_UPGRADE_DIR) { $env:TARLEAKS_PRE_UPGRADE_DIR } else { Join-Path 'backups' ("pre-upgrade-$(if ($current) { $current } else { 'unknown' })-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
    if (-not (Invoke-Backup $pre)) { Die 'The backup failed, so the upgrade did not start. Nothing was changed.' }
    Convert-LegacyKeys
    if ($Argument) { Set-EnvValue 'TARLEAKS_VERSION' $Argument }
    $v = Get-EnvValue 'TARLEAKS_VERSION'
    Use-MigrateImage $v
    Write-Host "Upgrading to $v."
    # The editors follow the release now in .env (1.2.0+: its own document
    # editor image), not the one this script started with.
    $script:AppsVersion = $v
    Sync-App
    if ($Offline) { $env:TARLEAKS_NO_DOWNLOAD = '1' }
    if (-not (Invoke-AppPull ".\tarleaks.ps1 upgrade $Argument")) { exit 1 }
    docker compose up -d --remove-orphans
    if ($LASTEXITCODE -ne 0) { Die "Starting $v failed (above). To go back to ${current}: .\tarleaks.ps1 restore $pre" }
    Stop-UnselectedApp
    Wait-Ready
    # 3. Bring the workspace database up to date; the output is kept next to
    #    the backup.
    $log = Join-Path $pre 'migrate.log'
    $pending = $false
    try { $pending = [bool](Invoke-RestMethod -TimeoutSec 10 -Uri "$(Probe)/api/auth/installation").setup_required } catch { }
    if ($pending) { Ok 'No workspace yet (the setup screen has not been used): no database to update.' }
    else {
      $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      docker compose run --rm migrate *> $log
      $rc = $LASTEXITCODE
      $ErrorActionPreference = $old
      if ($rc -eq 0) { Ok 'Database brought up to date' }
      else {
        Write-Host '  [x]  The database update step reported a problem. Its last lines:' -ForegroundColor Red
        Get-Content $log -Tail 15 | ForEach-Object { Write-Host "    $_" }
        Die "The whole output: $log. To go back to ${current}: .\tarleaks.ps1 restore $pre"
      }
    }
    Ok "Upgraded to $v. The backup from before: $pre"
    exit 0
  }
  'update' {
    # One command from one release to the next (docs\upgrading.md): check the
    # release is published and that this kit knows it, back up (and stop if
    # that fails), download, switch, update the database, start, wait, check.
    # Run it again at any time: on the newest release it only checks.
    $to = if ($To) { $To } else { $Argument }
    $lock = Join-Path $PSScriptRoot '.tarleaks-update.lock'
    try { New-Item -ItemType Directory -Path $lock -ErrorAction Stop | Out-Null }
    catch { Die "Another update is running for this installation (or one was interrupted: if none is running, remove the folder $lock and run this again)." }
    try {
      $current = Get-EnvValue 'TARLEAKS_VERSION'
      if (-not $current) { Die '.env names no TARLEAKS_VERSION, so the release you run is unknown. Write it (TARLEAKS_VERSION=<release>) and run this again.' }
      $off = $Offline -or ((Get-EnvValue 'TARLEAKS_OFFLINE') -in 'true', 'sealed')
      $tags = @()
      if (-not $off -and (Test-RegistryTakesLicence)) {
        $tags = Get-RegistryTag 'auth'
        if (-not $tags) { Die "Could not ask $(Get-RegistryHost) which releases exist. Allow outbound HTTPS to it and tarleaks.com, or load the offline bundle and run .\tarleaks.ps1 update -To <release> -Offline. Nothing was changed: still on $current." }
      }
      if (-not $to) {
        if (-not $tags) { Die 'Name the release: .\tarleaks.ps1 update -To <release> (offline, or a registry of your own, cannot list the releases).' }
        $to = Select-NewestRelease $tags $current
      }
      if ($to -notmatch '^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$') { Die "`"$to`" is not a release number (like 1.2.0). The release notes (CHANGELOG.md) list them." }
      if ($to -match '-candidate' -and -not $Force) { Die "$to is a build under test, not a release. Name a release (CHANGELOG.md lists them)." }
      if ($tags -and ($tags -notcontains $to)) { Die "Release $to is not published on $(Get-RegistryHost). Published: $(($tags | Where-Object { $_ -match '^\d+\.\d+\.\d+(-rc\.\d+)?$' }) -join ' '). Nothing was changed." }
      if ((Compare-Release $to $current) -eq -1) { Die "$to is OLDER than the release you run ($current). An update never goes back: restore the backup taken before the update instead (.\tarleaks.ps1 restore backups\pre-update-...)." }
      if ($Check) {
        if ($to -eq $current) { Ok "Up to date: $current is the newest release for this installation." } else { Ok "Release $to is available (you run $current). Update: .\tarleaks.ps1 update -To $to" }
        exit 0
      }
      $known = Test-Path 'CHANGELOG.md' -PathType Leaf
      if ($known) { $known = [bool](Select-String -Path 'CHANGELOG.md' -SimpleMatch "## [$to]" -Quiet) }
      if (-not $known) {
        if ($Force) { Warn "This kit does not list $to in CHANGELOG.md; going on anyway (-Force)." }
        else {
          Write-Host "  [x]  This kit folder does not know release $to (CHANGELOG.md has no section for it): its compose file and scripts are older than the release." -ForegroundColor Red
          Write-Host "  Get the kit of $to first (git fetch --tags; git checkout v$to - a ZIP install: unpack the $to ZIP over this folder; .env and backups stay), then run .\tarleaks.ps1 update again."
          Die "Nothing was changed: still on $current."
        }
      }
      if ($to -eq $current) {
        # Also the way to finish an update that was interrupted after .env was
        # switched: start what is missing and run the (idempotent) database step.
        Write-Host "Already on ${to}: making sure everything runs and the database is up to date."
        Write-SigningKeyNote (Add-SigningKey); Sync-App; docker compose up -d --remove-orphans
        if ($LASTEXITCODE -ne 0) { Die "Starting $to failed (above). See: .\tarleaks.ps1 logs" }
        Stop-UnselectedApp
        Wait-Ready
        try { Invoke-RestMethod -TimeoutSec 10 -Uri "$(Probe)/api/auth/installation" | Out-Null } catch { Die "The ERP does not answer. See: .\tarleaks.ps1 logs auth" }
        $pending = $false
        try { $pending = [bool](Invoke-RestMethod -TimeoutSec 10 -Uri "$(Probe)/api/auth/installation").setup_required } catch { }
        if (-not $pending) {
          $mlog = [System.IO.Path]::GetTempFileName()
          $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
          docker compose run --rm migrate *> $mlog; $mrc = $LASTEXITCODE
          $ErrorActionPreference = $old
          if ($mrc -eq 0) { Ok 'Database is up to date'; Remove-Item $mlog -ErrorAction SilentlyContinue }
          else {
            Write-Host '  [x]  The database update step reported a problem. Its last lines:' -ForegroundColor Red
            Get-Content $mlog -Tail 15 | ForEach-Object { Write-Host "    $_" }
            Remove-Item $mlog -ErrorAction SilentlyContinue
            Die 'Send these lines to info@tarleaks.com.'
          }
        }
        Wait-Editor
        Ok "Up to date: $current is the newest release for this installation."
        exit 0
      }
      $pre = Join-Path 'backups' ("pre-update-$current-to-$to-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
      $rollback = {
        Write-Host ''
        if ((Get-EnvValue 'TARLEAKS_VERSION') -eq $current) {
          Write-Host "Nothing was switched: .env still names $current and your data is as it was. Do NOT restore a backup."
          Write-Host '  If it is not running: .\tarleaks.ps1 start'
          Write-Host "  To try again later: .\tarleaks.ps1 update -To $to"
          return
        }
        Write-Host "How to go back to $current (exactly as it was before the update):"
        if (Test-Path (Join-Path $pre 'database.sql.gz')) {
          Write-Host "  .\tarleaks.ps1 restore $pre      # database, files and the .env that names $current"
          Write-Host '  .\tarleaks.ps1 start'
        } else { Write-Host "  Nothing was changed before it stopped: .\tarleaks.ps1 start brings it back up." }
        Write-Host "  To try again later: .\tarleaks.ps1 update -To $to"
      }
      Write-Host "Updating from $current to $to. A backup is taken first: $pre"
      $env:TARLEAKS_PRE_UPGRADE_DIR = $pre
      $global:LASTEXITCODE = 0; $rc = 1
      try { if ($off) { & $PSCommandPath upgrade $to -Offline } else { & $PSCommandPath upgrade $to } ; $rc = $LASTEXITCODE }
      catch { Write-Host "  [x]  $($_.Exception.Message)" -ForegroundColor Red; $rc = 1 }
      finally { Remove-Item Env:\TARLEAKS_PRE_UPGRADE_DIR -ErrorAction SilentlyContinue }
      if ($rc -ne 0 -or (Get-EnvValue 'TARLEAKS_VERSION') -ne $to) { Write-Host "  [x]  The update to $to did not finish (above)." -ForegroundColor Red; & $rollback; exit 1 }
      Wait-Ready; Wait-Editor
      try { $d = Invoke-RestMethod -TimeoutSec 10 -Uri "$(Probe)/api/auth/installation" } catch { $d = $null }
      if (-not $d) { Write-Host "  [x]  Release $to does not answer after the update." -ForegroundColor Red; & $rollback; exit 1 }
      if ($d.licence) { Write-Host "Licence: $($d.licence.state)" }
      Ok "Updated from $current to $to. The backup from before: $pre (keep it until you have checked your data)."
      exit 0
    } finally { Remove-Item $lock -Recurse -Force -ErrorAction SilentlyContinue }
  }
  'backup'  {
    $dir = if ($Argument) { $Argument } else { Join-Path 'backups' (Get-Date -Format 'yyyyMMdd-HHmmss') }
    if (-not (Invoke-Backup $dir)) { exit 1 }
  }
  'restore' {
    if (-not $Argument) { Die 'usage: .\tarleaks.ps1 restore <backup-folder> [-KeepSettings] [-NoSafetyBackup]   (the backups are in backups\)' }
    if ($Argument -eq '--no-safety-backup') { Die 'usage: .\tarleaks.ps1 restore <backup-folder> -NoSafetyBackup' }
    if ($Rest -contains '--no-safety-backup') { $NoSafetyBackup = $true }
    if ($Rest -contains '--keep-settings') { $KeepSettings = $true }
    if (-not (Test-Path -LiteralPath $Argument -PathType Container)) { Die "$Argument is not a folder. The backups are in backups\: Get-ChildItem backups" }
    if ($Argument -match '\.partial[\\/]?$') { Die "$Argument is an unfinished backup (its name ends in .partial): it cannot be restored." }
    $dir = (Resolve-Path -LiteralPath $Argument).Path
    # 1. Check everything BEFORE anything is touched.
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'database.sql.gz'))) { Die "$dir has no database.sql.gz: not a backup made by .\tarleaks.ps1 backup." }
    Write-Host 'Checking the backup (this reads every file once)...'
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { Invoke-Toolbox $dir $script:CheckScript } catch { Die "The backup is damaged (above). Nothing was changed. Use another backup." }
    finally { $ErrorActionPreference = $old }
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'files.tar.gz'))) { Warn 'This backup has no files.tar.gz: the documents in the file store are left as they are.' }
    $backupEnv = Join-Path $dir 'env'
    if (Test-Path -LiteralPath $backupEnv) {
      if (-not (Get-Content -LiteralPath $backupEnv | Where-Object { $_ -match '^CLUSTER_DSN_KEY=.+' })) { Die "$backupEnv has no CLUSTER_DSN_KEY: it is not a complete settings file. Nothing was changed." }
    } else {
      Warn 'This backup has no env (settings) file: the current .env is kept. Its keys must be the ones the backup was made with.'
    }
    Ok 'The backup is complete and readable.'
    $info = Join-Path $dir 'backup-info.txt'
    if (Test-Path -LiteralPath $info) { Get-Content -LiteralPath $info | ForEach-Object { Write-Host "  $_" } }
    # Whose backup is it? The settings file names the installation (Docker's
    # project): copied over .env as it is, a backup of ANOTHER installation on
    # this computer would make this folder drive that one, and the load below
    # would replace ITS data.
    if (Test-Path -LiteralPath $backupEnv) {
      $here = Get-EnvProject $envPath; $there = Get-EnvProject $backupEnv
      if ($here -ne $there -and -not $KeepSettings) {
        Die "This backup comes from the installation named '$there'; this folder is the installation '$here'. Restored as it is, this folder would take over '$there' and replace ITS data. To load the backup into THIS installation ('$here'), keeping its name, port and address: .\tarleaks.ps1 restore $Argument -KeepSettings. To restore '$there' itself, run the restore in its own folder. Nothing was changed."
      }
      if ($KeepSettings) {
        Ok "Kept from this folder: its name ('$here'), port, address, HTTPS and offline settings. From the backup: its keys and apps."
      } else {
        $bUrl = Get-EnvFileValue $backupEnv 'TARLEAKS_URL'; $bPort = Get-EnvFileValue $backupEnv 'HTTP_PORT'
        $cUrl = Get-EnvValue 'TARLEAKS_URL'; $cPort = Get-EnvValue 'HTTP_PORT'
        if (-not $bPort) { $bPort = '80' }; if (-not $cPort) { $cPort = '80' }
        if ($bUrl -ne $cUrl -or $bPort -ne $cPort) {
          Warn "The backup's settings answer at $bUrl (port $bPort); this folder now answers at $cUrl (port $cPort). After the restore the backup's apply. To keep this folder's: -KeepSettings"
        }
      }
    }
    Write-Host "This REPLACES the current database and files with the backup in $dir." -ForegroundColor White
    if (-not $NoSafetyBackup) { Write-Host 'First a backup of what is there now is made in backups\pre-restore-<time>\, so you can go back.' }
    else { Warn '-NoSafetyBackup: what is there now is NOT backed up first.' }
    $answer = Read-Host 'Type RESTORE to continue'
    if ($answer -cne 'RESTORE') { Die 'Cancelled. Nothing was changed.' }
    # 2. The current data, kept: a backup of it and the current settings.
    $user = Get-EnvValue 'POSTGRES_USER'; if (-not $user) { $user = 'tarleaks' }
    $safety = ''
    $ErrorActionPreference = 'Continue'
    try {
      Invoke-Checked 'Starting the database' compose up -d postgres
      Wait-Database $user
    } catch { Die "$($_.Exception.Message) Nothing was changed." }
    if (-not $NoSafetyBackup) {
      $safety = Join-Path 'backups' ('pre-restore-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
      if (-not (Invoke-Backup $safety)) { Die "The safety backup of the current data failed (above), so nothing was restored. Fix that first, or, if the current data does not matter: .\tarleaks.ps1 restore $Argument -NoSafetyBackup" }
    }
    Copy-Item -LiteralPath $envPath -Destination (Join-Path $PSScriptRoot '.env.before-restore') -Force
    Protect-Path (Join-Path $PSScriptRoot '.env.before-restore') -File
    # 3. Stop everything but the database, then load. From here on, a failure
    #    says how to go back.
    try {
      Stop-All
      if (Test-Path -LiteralPath $backupEnv) {
        Copy-Item -LiteralPath $backupEnv -Destination $envPath -Force
        Protect-Path $envPath -File
        $before = Join-Path $PSScriptRoot '.env.before-restore'
        foreach ($k in $script:RestoreAlwaysKeep) {
          $v = Get-EnvFileValue $before $k
          if ($v) { Set-EnvValue $k $v }
        }
        if ($KeepSettings) {
          foreach ($k in $script:RestoreKeepKeys) {
            $line = Get-Content -LiteralPath $before | Where-Object { $_ -match "^$([regex]::Escape($k))=" } | Select-Object -Last 1
            if ($line) { Set-EnvValue $k $line.Substring($k.Length + 1) } else { Remove-EnvValue $k }
            # A backup from before the rename may carry the old name of the key.
            if ($k -like 'TARLEAKS_*') { Remove-EnvValue ('NEXUS_' + $k.Substring(9)) }
          }
          Ok 'Keys and apps restored from the backup; name, port and address kept (the previous settings: .env.before-restore)'
        } else {
          Ok 'Settings restored from the backup (the previous ones: .env.before-restore)'
        }
      }
      Invoke-Checked 'Starting the database' compose up -d postgres
      Wait-Database $user
      Write-Host 'Loading the database (stops at the first error)...'
      Invoke-Checked 'Copying the dump into the database container' compose cp (Join-Path $dir 'database.sql.gz') postgres:/tmp/tarleaks-restore.sql.gz
      # pg_dumpall --clean drops and re-creates every role, which fails for the
      # role this load runs as: those two lines are left out, and errors in the
      # role section ("already exists") are allowed. Every database after it
      # must load without a single error.
      $load = @'
set -euo pipefail
u=$1
psql -X -q -U "$u" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND datname IS NOT NULL" > /dev/null
rc=0
gzip -dc /tmp/tarleaks-restore.sql.gz | awk -v u="$u" '
  BEGIN { print "\\set ON_ERROR_STOP off"; q = "\"" u "\"" }
  !on && ($0 == "DROP ROLE IF EXISTS " u ";" || $0 == "DROP ROLE IF EXISTS " q ";" || $0 == "CREATE ROLE " u ";" || $0 == "CREATE ROLE " q ";") { next }
  !on && ($0 == "-- Databases" || $0 ~ /^\\connect /) { print "\\set ON_ERROR_STOP on"; on = 1 }
  { print }' | psql -X -q -v ON_ERROR_STOP=1 -U "$u" -d postgres > /dev/null || rc=$?
rm -f /tmp/tarleaks-restore.sql.gz
exit "$rc"
'@
      Invoke-Checked 'Loading the database' compose exec -T -e "TARLEAKS_STEP=$(ConvertTo-Step $load)" postgres bash -c "printenv TARLEAKS_STEP | base64 -d > /tmp/tarleaks-load.sh && bash /tmp/tarleaks-load.sh '$user'"
      Ok 'Database restored'
      # Files: unpacked next to the current ones inside the volume, then
      # swapped in. The current files are removed only after the new ones are
      # complete.
      foreach ($v in 'files', 'hrdocs') {
        if (-not (Test-Path -LiteralPath (Join-Path $dir "$v.tar.gz"))) { continue }
        Write-Host "Restoring $v..."
        Invoke-Toolbox $dir @"
set -e
cd /vol/$v
rm -rf .tarleaks-restore-new .tarleaks-restore-old
mkdir .tarleaks-restore-new .tarleaks-restore-old
tar --xattrs --xattrs-include='user.*' -xzf /backup/$v.tar.gz -C .tarleaks-restore-new
find . -mindepth 1 -maxdepth 1 ! -name .tarleaks-restore-new ! -name .tarleaks-restore-old -exec mv -t .tarleaks-restore-old {} +
find .tarleaks-restore-new -mindepth 1 -maxdepth 1 -exec mv -t . {} +
rm -rf .tarleaks-restore-new .tarleaks-restore-old
"@
      }
      Ok 'Files restored'
    } catch {
      Write-Host "  [x]  $($_.Exception.Message)" -ForegroundColor Red
      Write-Host '  [x]  The restore did NOT finish.' -ForegroundColor Red
      if ($safety) { Write-Host "  Your data from before is in $safety, your settings in .env.before-restore. To go back to it: .\tarleaks.ps1 restore $safety" }
      else { Write-Host '  Your settings from before are in .env.before-restore.' }
      exit 1
    }
    $ErrorActionPreference = $old
    & $PSCommandPath start
    Ok "Restored from $dir"
    if ($safety) { Write-Host "  What was there before is in $safety (delete it when you no longer need it)." }
  }
  'uninstall' {
    $wipe = $Purge -or ($Argument -eq '--purge') -or ($Argument -eq '-Purge')
    if ($Argument -and -not $wipe) { Die 'usage: .\tarleaks.ps1 uninstall [-Purge]' }
    if ($wipe) {
      $answer = Read-Host 'This DELETES all data in Docker (database, files, queues). Type DELETE to continue'
      if ($answer -cne 'DELETE') { Die 'Cancelled.' }
      Stop-All; Remove-AllContainer
      docker compose down -v --remove-orphans
      if ($LASTEXITCODE -ne 0) { Die 'Removing the data volumes failed (above).' }
      Ok 'Removed the containers and the data volumes (database, files, queues).'
      Write-Host 'Still on this computer (not deleted):' -ForegroundColor White
      $nb = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'backups') -Directory -ErrorAction SilentlyContinue).Count
      if ($nb -gt 0) { Write-Host "  backups\      $nb backup(s): each is a full, readable copy of the database plus your keys" }
      Write-Host '  .env          the passwords and keys of this installation (and .env.before-restore, if there is one)'
      Write-Host '  the images    the programs (no data)'
      Write-Host 'To remove those too (from this folder):'
      Write-Host '  Remove-Item -Recurse -Force backups, .env, .env.before-restore'
      Write-Host '  docker image prune -a      (removes every image no container uses, not only Tarleaks'')'
      Write-Host 'Then delete this folder.'
    } else {
      Stop-All; Remove-AllContainer
      docker compose down --remove-orphans
      Ok 'Removed the containers. Your data is kept in Docker volumes (.\tarleaks.ps1 start brings everything back; .\tarleaks.ps1 uninstall -Purge deletes the data).'
    }
  }
  'reset-admin' {
    # The way back for an administrator who forgot the password on a server
    # without outgoing e-mail, or the only administrator whose account was
    # switched off: a temporary password, the account on again, the
    # Administrator role given back, every session ended, an audit row.
    if (-not $Argument) { Die 'Usage: .\tarleaks.ps1 reset-admin <e-mail> [-Company <short name>] [-ResetTwoFactor]' }
    if (-not (Test-Running 'auth')) { Die 'The ERP is not running. Start it first: .\tarleaks.ps1 start' }
    $a = @('compose', 'exec', '-T', 'auth', '/app/service', 'reset-admin', $Argument)
    if ($Company) { $a += @('--company', $Company) }
    if ($ResetTwoFactor) { $a += '--reset-two-factor' }
    & docker @a
    switch ($LASTEXITCODE) {
      0 { }
      2 { Die 'This release does not have reset-admin yet. Upgrade first (.\tarleaks.ps1 upgrade), then run it again.' }
      default { Die 'The password was not reset: see the message above.' }
    }
  }
  'setup-code' {
    $code = Get-EnvValue 'TARLEAKS_SETUP_CODE'
    if (-not $code) { $code = Get-EnvValue 'NEXUS_SETUP_CODE' }   # an .env from before the rename
    Write-Host "Setup code: $code"
  }
  'profile' {
    $preset = Get-AppPreset $Argument
    if (-not $preset) { Die 'usage: .\tarleaks.ps1 profile small|standard|full' }
    Set-ChosenApp $preset
    docker compose up -d --remove-orphans; Stop-UnselectedApp; Wait-Ready; Wait-Editor
  }
  'editors' {
    $sub = if ($Argument) { $Argument } else { 'status' }
    $cur = if ((Get-EnvValue 'TARLEAKS_EDITORS') -eq 'off') { 'off' } else { 'on' }
    switch ($sub) {
      'status' {
        if ($cur -eq 'off') { Write-Host 'The editors are off: Documents has no New or Edit, and Diagrams has no editor.' }
        else { Write-Host "The editors are on: $(Get-AppName (Get-AppAddonUnit (Get-AppClosure (Get-CurrentApp))))." }
        Write-Host 'Switch: .\tarleaks.ps1 editors on | off   (about 2.5 GB of memory when all are on)'
      }
      { $_ -in 'on', 'off' } {
        Set-EnvValue 'TARLEAKS_EDITORS' $sub
        Sync-App
        if ($sub -eq 'on') { if (-not (Invoke-AppPull '.\tarleaks.ps1 editors on')) { exit 1 } }
        docker compose up -d --remove-orphans; Stop-UnselectedApp; Wait-Ready; Wait-Editor
        if ($sub -eq 'on') { Write-Host 'The editors are on. Documents: New and Edit; Diagrams: the editor.' -ForegroundColor Green }
        else { Write-Host 'The editors are off. Your documents and diagrams are kept; .\tarleaks.ps1 editors on brings the editors back.' -ForegroundColor Green }
      }
      default { Die 'usage: .\tarleaks.ps1 editors [status | on | off]' }
    }
  }
  'network' {
    $sub = if ($Argument) { $Argument } else { 'status' }
    $bind = Get-EnvValue 'HTTP_BIND'; if (-not $bind) { $bind = '0.0.0.0' }
    $now = if ($bind -in '127.0.0.1', 'localhost') { "only this computer (HTTP_BIND=$bind)" }
           elseif ($bind -in '0.0.0.0', '::') { "this computer and the whole network (HTTP_BIND=$bind, port $(Port))" }
           else { "the network address $bind only (HTTP_BIND=$bind)" }
    switch ($sub) {
      'status' {
        Write-Host "Who can open the ERP: $now"
        Write-Host 'Change it: .\tarleaks.ps1 network local     only this computer'
        Write-Host '           .\tarleaks.ps1 network office    everyone on the network (protect it with the firewall)'
      }
      { $_ -in 'local', 'office' } {
        $want = if ($sub -eq 'local') { '127.0.0.1' } else { '0.0.0.0' }
        if ($bind -eq $want) { Ok "Already set: $now"; return }
        Set-EnvValue 'HTTP_BIND' $want
        $hostName = Get-EnvValue 'TARLEAKS_HOST'
        if ($sub -eq 'local' -and $hostName -notin 'localhost', '127.0.0.1') {
          Warn "The address is $hostName, but only this computer can connect now: other computers will not reach it. Fine behind a reverse proxy on this computer."
        } elseif ($sub -eq 'office' -and $hostName -eq 'localhost') {
          Warn "Other computers can connect now, but the address is still localhost: links in e-mails and invitations say localhost. Give the ERP its network address: .\install.ps1 -HostName <this computer's address> (docs\network.md)."
        }
        # Only the gateway publishes the port: recreate it, nothing else restarts.
        docker compose up -d --no-deps gateway
        Wait-Ready
        if ($sub -eq 'local') { Ok 'Only this computer can open the ERP now.' }
        else { Ok "Everyone on the network can reach the ERP at port $(Port) now. Allow it in this computer's firewall, and keep it from the internet unless you mean to publish it." }
      }
      default { Die 'usage: .\tarleaks.ps1 network [status | local | office]' }
    }
  }
  'apps' {
    $chosen = Get-CurrentApp
    $sub = if ($Argument) { $Argument } else { 'list' }
    $words = ($Rest -join ',')
    switch ($sub) {
      'list' {
        $closure = Get-AppClosure $chosen
        Write-Host "Chosen apps: $(Get-AppName $chosen)" -ForegroundColor White
        Write-Host ''
        Show-AppTable $chosen (Get-AppModule $closure)
        Write-Host ''
        Write-Host '  [x] chosen   (+) installed because a chosen app needs it or shares its service'
        Write-Host '  (b) part of every installation   [ ] not installed'
        Write-Host ''
        Write-Host "Memory to plan for: about $(Gb (Get-AppRamMb $closure)) GB."
        Write-Host 'Add:    .\tarleaks.ps1 apps add payroll attendance'
        Write-Host 'Remove: .\tarleaks.ps1 apps remove crm'
      }
      'add' {
        if (-not $words) { Die 'usage: .\tarleaks.ps1 apps add <app> [app ...]   (the list: .\tarleaks.ps1 apps)' }
        try { $new = Resolve-App $words; $merged = Resolve-App "$chosen,$new" } catch { Die $_.Exception.Message }
        $before = Get-AppClosure $chosen; $after = Get-AppClosure $merged
        $extra = (Split-AppList $after | Where-Object { (Split-AppList $before) -notcontains $_ }) -join ','
        if (-not $extra) { Write-Host "Already installed: $(Get-AppName $new)" -ForegroundColor Green; return }
        Write-Host "Adding: $(Get-AppName $extra)"
        Write-Host "Memory to plan for: about $(Gb (Get-AppRamMb $before)) GB now, $(Gb (Get-AppRamMb $after)) GB after."
        Set-ChosenApp $merged
        if (-not (Invoke-AppPull ".\tarleaks.ps1 apps add $($Rest -join ' ')")) { exit 1 }
        docker compose up -d --remove-orphans
        Wait-Ready
        Write-Host 'Added. Your licence decides who may use them: Settings > Licence lists the apps it covers.' -ForegroundColor Green
      }
      'remove' {
        if (-not $words) { Die 'usage: .\tarleaks.ps1 apps remove <app> [app ...]' }
        try { $targets = Resolve-App $words } catch { Die $_.Exception.Message }
        $t = Split-AppList $targets
        $remaining = (Split-AppList $chosen | Where-Object { $t -notcontains $_ }) -join ','
        foreach ($x in $t) {
          if (Test-BaseApp $x) { Die "$(Get-AppName $x) is part of every installation and cannot be removed." }
          if ((Split-AppList $chosen) -notcontains $x) {
            $by = Get-AppNeededBy $x $chosen
            if ($by) { Die "$(Get-AppName $x) is installed because $(Get-AppName $by) needs it. Removing that removes it too: .\tarleaks.ps1 apps remove $($by -replace ',', ' ')" }
            Die "$(Get-AppName $x) is not installed."
          }
          $by = Get-AppNeededBy $x $remaining
          if ($by) { Die "Cannot remove $(Get-AppName $x): $(Get-AppName $by) needs it. Remove both: .\tarleaks.ps1 apps remove $x $($by -replace ',', ' ')" }
        }
        Set-ChosenApp $remaining
        docker compose up -d --remove-orphans
        Stop-UnselectedApp
        Wait-Ready
        Write-Host "Removed $(Get-AppName $targets). Its data is kept: .\tarleaks.ps1 apps add $($targets -replace ',', ' ') brings it back." -ForegroundColor Green
      }
      default { Die 'usage: .\tarleaks.ps1 apps [list | add <app>... | remove <app>...]' }
    }
  }
  'load-bundle' {
    if (-not $Argument) { Die 'Usage: .\tarleaks.ps1 load-bundle <bundle folder | .tar file | .tar.part-00 file>' }
    if (-not (Test-Path -LiteralPath $Argument)) { Die "$Argument not found." }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) { Die 'Docker Desktop is not running. Start it, then run this again.' }
    $src = (Resolve-Path -LiteralPath $Argument).Path
    $work = $null
    try {
      if ((Test-Path -LiteralPath $src -PathType Container) -and (Test-Path (Join-Path $src 'images.txt'))) {
        $dir = $src
      } else {
        # An archive: one .tar, or the .tar.part-NN pieces of one.
        if (Test-Path -LiteralPath $src -PathType Container) {
          Get-ChildItem -LiteralPath $src -Filter '*.images.txt' | ForEach-Object { Assert-Platform $_.FullName }
          foreach ($sums in Get-ChildItem -LiteralPath $src -Filter '*.SHA256SUMS') {
            Write-Host "Checking the downloaded files against $($sums.Name)..."
            if (-not (Test-Checksums $src $sums.FullName)) { Die 'A downloaded file is damaged or incomplete (above). Download it again.' }
            Ok 'Downloaded files intact'
          }
          $parts = @(Get-ChildItem -LiteralPath $src | Where-Object { $_.Name -match '\.tar\.part-\d+$' } | Sort-Object Name)
          if ($parts.Count -eq 0) { $parts = @(Get-ChildItem -LiteralPath $src | Where-Object { $_.Name -match '\.tar$' }) }
          if ($parts.Count -eq 0) { Die "No bundle in ${src}: expected images.txt, a .tar file or .tar.part-NN files." }
          if (@($parts | ForEach-Object { $_.Name -replace '\.part-\d+$', '' } | Sort-Object -Unique).Count -gt 1) {
            Die "$src holds more than one bundle. Put each bundle in a folder of its own."
          }
        } elseif ($src -match '\.tar\.part-\d+$') {
          $base = (Split-Path $src -Leaf) -replace '\.part-\d+$', ''
          $parts = @(Get-ChildItem -LiteralPath (Split-Path $src -Parent) | Where-Object { $_.Name -match ('^' + [regex]::Escape($base) + '\.part-\d+$') } | Sort-Object Name)
        } elseif ($src -match '\.tar$') {
          $parts = @(Get-Item -LiteralPath $src)
        } else {
          Die "$src is not a bundle: give the bundle folder, its .tar file or its first .tar.part-NN file."
        }
        # Unpack next to the kit (needs about twice the bundle's size free).
        $work = Join-Path $PSScriptRoot ('.bundle-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $work | Out-Null
        $tarFile = $parts[0].FullName
        if ($parts.Count -gt 1) {
          Write-Host "Joining $($parts.Count) pieces..."
          $tarFile = Join-Path $work 'bundle.tar'
          $out = [System.IO.File]::Create($tarFile)
          try {
            foreach ($part in $parts) {
              $in = [System.IO.File]::OpenRead($part.FullName)
              try { $in.CopyTo($out) } finally { $in.Dispose() }
            }
          } finally { $out.Dispose() }
        }
        Write-Host 'Unpacking...'
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        tar -xf $tarFile -C $work
        $untar = $LASTEXITCODE
        $ErrorActionPreference = $old
        if ($untar -ne 0) { Die 'Could not unpack the bundle: a piece is missing or damaged.' }
        if ($parts.Count -gt 1) { Remove-Item -LiteralPath $tarFile }
        $found = Get-ChildItem -LiteralPath $work -Recurse -Filter 'images.txt' | Select-Object -First 1
        if (-not $found) { Die 'The archive holds no images.txt: not a Tarleaks offline bundle.' }
        $dir = $found.DirectoryName
      }
      $sumsPath = Join-Path $dir 'SHA256SUMS'
      if (-not (Test-Path $sumsPath)) { Die "$sumsPath is missing: the bundle cannot be checked." }
      Assert-Platform (Join-Path $dir 'images.txt')
      Write-Host 'Checking every image file against SHA256SUMS...'
      if (-not (Test-Checksums $dir $sumsPath)) { Die 'The bundle is damaged (above). Copy it again.' }
      Ok 'Bundle intact'
      $n = 0
      foreach ($line in Get-Content $sumsPath) {
        if ($line -notmatch '^[0-9a-fA-F]{64}\s+\*?(images/\S+)$') { continue }
        $file = Join-Path $dir $Matches[1]
        Write-Host "Loading $(Split-Path $file -Leaf)..."
        $loaded = @(docker load -i $file)
        if ($LASTEXITCODE -ne 0) { $loaded | ForEach-Object { Write-Host "  $_" }; Die "Docker could not load $file (above). Check the free disk." }
        $loaded | ForEach-Object { Write-Host "  $_" }
        # A bundle names its images where they were built; give them the name
        # this installation pulls (TARLEAKS_REGISTRY), so nothing is downloaded.
        Register-RegistryLoadedImage $loaded
        $n++
      }
      if ($n -eq 0) { Die 'SHA256SUMS lists no files under images/: nothing to load.' }
      Ok "Loaded $n image file(s)"
      $bver = Select-String -Path (Join-Path $dir 'images.txt') -Pattern '^# *version: *(.+)$' | Select-Object -First 1
      $bver = if ($bver) { $bver.Matches[0].Groups[1].Value.Trim() } else { '' }
      if (-not (Test-Path $envPath)) {
        Write-Host 'Next: .\install.ps1 -Offline'
      } else {
        $missing = Get-MissingImages
        if ($null -eq $missing) { Warn 'Could not compare with docker-compose.yml.' }
        elseif ($missing.Count -eq 0) { Ok 'Every image this installation needs is on this computer.' }
        elseif ($bver -and $bver -ne (Get-EnvValue 'TARLEAKS_VERSION')) {
          Write-Host "This bundle is version $bver; .env names $(Get-EnvValue 'TARLEAKS_VERSION')."
          Write-Host "Next: .\tarleaks.ps1 upgrade $bver -Offline"
        } else {
          Warn 'Still missing for this installation:'; $missing | ForEach-Object { Write-Host "  $_" }
        }
      }
    } finally {
      if ($work -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
    }
  }
  default   { Get-Help $PSCommandPath -Examples }
}
