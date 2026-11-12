<#
.SYNOPSIS
  Tarleaks ERP installer for Windows (Docker Desktop with the WSL 2 engine).

.EXAMPLE
  .\install.ps1
  .\install.ps1 -Yes
  .\install.ps1 -Apps hr,crm
  .\install.ps1 -HostName 192.168.1.20 -Profile standard
  .\install.ps1 -Port 8080
  .\install.ps1 -LicenceKey nxs1....     # your licence key, also the download
                                         # password (-LicenceKey none removes it)
  .\install.ps1 -Trial you@company.com -Company "Name" -AcceptTerms
                                         # no key yet: start the 30-day trial
  .\install.ps1 -Bind local              # only this computer (office: everyone);
                                         # without it the installer decides: see below
  .\install.ps1 -Editors off             # no document/diagram editors (saves ~2 GB)
  .\install.ps1 -Offline     # no download: use the images already here
                             # (load them first: .\tarleaks.ps1 load-bundle <folder>)
  .\install.ps1 -FromCloud TLM-XXXXX-XXXXX-XXXXX-XXXXX
                                         # From 1.2.0: move a company from Tarleaks
                                         # Cloud to this new computer instead of the
                                         # setup screen (code: Settings > Move
                                         # to your own server; docs\move-from-cloud.md)
  .\install.ps1 -FromCloud <code> -SwitchOver
                                         # the same, and switch over without asking
                                         # once everything is copied and checked
  .\install.ps1 -Vendor https://...      # only to test against another Tarleaks
                                         # platform (default: tarleaks.com)

.NOTES
  Safe to run again: an existing .env keeps its keys and passwords.
  If scripts are blocked:  Set-ExecutionPolicy -Scope Process Bypass
#>
[CmdletBinding()]
param(
  [Alias('Profile')] [ValidateSet('auto', 'small', 'standard', 'full')] [string] $HardwareProfile = 'auto',
  [string] $Apps = '',
  [string] $HostName = '',
  [int] $Port = 0,
  [string] $Version = '',
  [Alias('LicenseKey')] [string] $LicenceKey = '',
  [string] $Trial = '',
  [string] $Company = '',
  [switch] $AcceptTerms,
  [string] $Bind = '',
  [string] $Editors = '',
  [switch] $Yes,
  [switch] $NoStart,
  [switch] $Offline,
  # local: this computer or the office network (http). production: a real
  # domain behind your own HTTPS reverse proxy (docs/https.md); a Windows
  # machine does not get the certificate itself, use a Linux server for that.
  [ValidateSet('', 'local', 'production')] [string] $ProfileEnv = '',
  # From 1.2.0: the move code from the cloud workspace (docs\move-from-cloud.md).
  [string] $FromCloud = '',
  [switch] $SwitchOver,
  # Only to test against another Tarleaks platform; empty = tarleaks.com.
  [string] $Vendor = ''
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

function Ok($m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [x]  $m" -ForegroundColor Red; exit 1 }
function Ask($q, $def) {
  if ($Yes) { return $def }
  $a = Read-Host "$q [$def]"
  if ([string]::IsNullOrWhiteSpace($a)) { return $def } else { return $a.Trim() }
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
# Every image the chosen profile runs (docker-compose.yml + .env), minus the
# ones already on this computer. $null when the list cannot be read.
function Get-MissingImages {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $images = docker compose config --images 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $missing = @()
    foreach ($img in ($images | Where-Object { $_ } | Sort-Object -Unique)) {
      docker image inspect $img *> $null
      if ($LASTEXITCODE -ne 0) { $missing += $img }
    }
    return , $missing
  } finally { $ErrorActionPreference = $old }
}

# Check every value before anything is written.
if ($Version -and $Version -notmatch '^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$') { Write-Host "  [x]  -Version `"$Version`" is not a release number (like 1.0.0). The release notes list them." -ForegroundColor Red; exit 1 }
if ($LicenceKey -and $LicenceKey -ne 'none' -and $LicenceKey -notmatch '^(tlk1|nxs1)\.[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$') {
  Write-Host '  [x]  -LicenceKey does not look like a Tarleaks licence key: it is one line that starts with tlk1. (or nxs1.) and holds only letters, digits, - _ and dots. Copy all of it again, or leave it out and enter it on the setup screen.' -ForegroundColor Red; exit 1
}
if ($Trial -and $Trial -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { Write-Host '  [x]  -Trial needs your e-mail address (for example -Trial you@yourcompany.com).' -ForegroundColor Red; exit 1 }
if ($Trial -and $LicenceKey -and $LicenceKey -ne 'none') { Write-Host '  [x]  Give either -LicenceKey or -Trial, not both.' -ForegroundColor Red; exit 1 }
if ($Bind -and $Bind -notin 'local', 'network', 'office' -and $Bind -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { Write-Host '  [x]  -Bind must be local (this computer only), office (the whole network) or an IP address of this computer' -ForegroundColor Red; exit 1 }
if ($Editors -and $Editors -notin 'on', 'off') { Write-Host '  [x]  -Editors must be on or off' -ForegroundColor Red; exit 1 }
if ($Port -lt 0 -or $Port -gt 65535) { Write-Host '  [x]  -Port must be a number from 1 to 65535' -ForegroundColor Red; exit 1 }
# A move from Tarleaks Cloud (docs\move-from-cloud.md).
. (Join-Path $PSScriptRoot 'scripts/lib-move.ps1')
if ($FromCloud -and -not (Test-MoveCode $FromCloud)) { Write-Host '  [x]  -FromCloud needs the move code, which looks like TLM-XXXXX-XXXXX-XXXXX-XXXXX: make it in the cloud workspace, Settings > Move to your own server.' -ForegroundColor Red; exit 1 }
if ($SwitchOver -and -not $FromCloud) { Write-Host '  [x]  -SwitchOver goes with -FromCloud <code> (on an installed computer: .\tarleaks.ps1 migrate-from-cloud -SwitchOver)' -ForegroundColor Red; exit 1 }
if ($Vendor -and -not (Test-MoveVendor $Vendor)) { Write-Host '  [x]  -Vendor must be an address such as https://tarleaks.com (or default).' -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host 'Tarleaks ERP - installer' -ForegroundColor White
if ($FromCloud) {
  Write-Host 'Moving a company from Tarleaks Cloud: this sets up the computer, then moves the company in'
  Write-Host '(no setup screen). docs\move-from-cloud.md'
}
Write-Host ''

# ---- 1. The machine ---------------------------------------------------------
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -notin @('AMD64', 'ARM64')) { Die "CPU architecture '$arch' is not supported (64-bit Intel/AMD or ARM only)." }
Ok "CPU: $arch"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Die 'Docker Desktop is not installed. Install it from https://www.docker.com/products/docker-desktop/ (use the WSL 2 engine), start it, then run this again.'
}
docker info *> $null
if ($LASTEXITCODE -ne 0) { Die 'Docker Desktop is not running. Start it and wait until it says "Engine running", then run this again.' }
docker compose version *> $null
if ($LASTEXITCODE -ne 0) { Die 'Docker Compose v2 is missing. Update Docker Desktop.' }
$osType = (docker info --format '{{.OSType}}').Trim()
if ($osType -ne 'linux') { Die 'Docker is in Windows-containers mode. Right-click the Docker icon > "Switch to Linux containers", then run this again.' }
Ok "Docker $((docker version --format '{{.Server.Version}}').Trim())"

$memBytes = [int64]((docker info --format '{{.MemTotal}}').Trim())
$cpus = (docker info --format '{{.NCPU}}').Trim()
$memMb = [int]($memBytes / 1MB)
Ok ("Docker can use {0} CPUs and {1:N1} GB of memory" -f $cpus, ($memBytes / 1GB))
if ($memMb -lt 3500) {
  Warn 'Docker has less than 4 GB of memory. Give WSL more: create %UserProfile%\.wslconfig with [wsl2] memory=8GB, run "wsl --shutdown", restart Docker Desktop.'
}

$drive = (Get-Item .).PSDrive
$freeGb = [int]($drive.Free / 1GB)
if ($freeGb -lt 15) { Warn "Only $freeGb GB free on drive $($drive.Name):. Allow at least 20 GB." } else { Ok "$freeGb GB of free disk" }

# ---- 2. Apps ----------------------------------------------------------------
# Only the chosen apps run, plus what they cannot work without (config\apps.tsv
# says what each app needs) and the base apps every workspace holds.
. (Join-Path $PSScriptRoot 'scripts/lib-apps.ps1')
. (Join-Path $PSScriptRoot 'scripts/lib-keys.ps1')
$prevApps = ''
$prevEditors = ''
if (Test-Path (Join-Path $PSScriptRoot '.env')) {
  $l = Get-Content (Join-Path $PSScriptRoot '.env') | Where-Object { $_ -match '^TARLEAKS_APPS=' } | Select-Object -Last 1
  if ($l) { $prevApps = $l.Substring('TARLEAKS_APPS='.Length) }
  $l = Get-Content (Join-Path $PSScriptRoot '.env') | Where-Object { $_ -match '^TARLEAKS_EDITORS=' } | Select-Object -Last 1
  if ($l) { $prevEditors = ($l -replace '^TARLEAKS_EDITORS=', '').Trim() }
}
# The release this installation will run: -Version, else what .env or the
# example already say. Apps that arrive in a later release are left out.
function Get-KitVersion([string] $File) {
  if (-not (Test-Path $File)) { return '' }
  $l = Get-Content $File | Where-Object { $_ -match '^TARLEAKS_VERSION=' } | Select-Object -Last 1
  if ($l) { return $l.Substring('TARLEAKS_VERSION='.Length) } else { return '' }
}
$script:AppsVersion = if ($Version) { $Version } else { Get-KitVersion (Join-Path $PSScriptRoot '.env') }
if (-not $script:AppsVersion) { $script:AppsVersion = Get-KitVersion (Join-Path $PSScriptRoot '.env.example') }
# The migrate image was renamed with the rebrand: nexus-migrate up to 1.1.x,
# tarleaks-migrate from 1.2.0. docker-compose.yml reads TARLEAKS_MIGRATE_IMAGE;
# a name written in .env wins.
function Use-MigrateImage([string] $Version) {
  $envFile = Join-Path $PSScriptRoot '.env'
  if ((Test-Path $envFile) -and (Select-String -Path $envFile -Pattern '^TARLEAKS_MIGRATE_IMAGE=.' -Quiet)) { return }
  $name = if ($Version -match '^(0|1\.0|1\.1)\.') { 'nexus-migrate' } else { 'tarleaks-migrate' }
  [Environment]::SetEnvironmentVariable('TARLEAKS_MIGRATE_IMAGE', $name, 'Process')
}
Use-MigrateImage $script:AppsVersion
$late = Get-AppUnreleased
# Suggest every app (the trial covers all of them) whenever the machine has the
# memory; otherwise the largest preset that fits, with room to spare.
$suggest = 'small'
foreach ($p in 'standard', 'full') {
  $need = Get-AppRamMb (Get-AppClosure (Get-AppPreset $p))
  if (($need + 1024) -le $memMb) { $suggest = $p }
}
if ($Apps) { }
elseif ($HardwareProfile -ne 'auto') { $Apps = Get-AppPreset $HardwareProfile }
elseif ($prevApps) { $Apps = $prevApps }   # a re-run keeps the apps
elseif ($Yes) { $Apps = Get-AppPreset $suggest }
else {
  Write-Host ''
  Write-Host 'Which apps do you want? Only these run, with what they need.' -ForegroundColor White
  if ($FromCloud) {
    Write-Host '  Choose at least the apps the company uses in Tarleaks Cloud. The data of an app left out'
    Write-Host '  is moved too and kept; add the app later with .\tarleaks.ps1 apps add <app>.'
  }
  Write-Host '  1) small     HR, recruitment, attendance, payroll, accounting, CRM, inventory, sales orders, chat'
  Write-Host '  2) standard  small + projects, learning, recognition, assets, helpdesk, fleet, correspondence,'
  $notYet = Get-AppNotYet; $gone = Get-AppWithdrawn
  if ($notYet -notcontains 'procurement') { Write-Host '               point of sale, rentals, subscriptions, procurement, construction, contracts' }
  else { Write-Host '               point of sale, rentals, subscriptions' }
  if ($gone -contains 'diagrams' -or $notYet -contains 'diagrams') { Write-Host '  3) full      every app: standard + PDF tools with OCR, ISO compliance (best for the trial)' }
  else { Write-Host '  3) full      every app: standard + PDF tools with OCR, diagrams, ISO compliance (best for the trial)' }
  if ($notYet.Count -gt 0) { Write-Host "  (release $($script:AppsVersion) does not have $(Get-AppName ($notYet -join ',')) yet)" }
  if ($gone -contains 'diagrams') { Write-Host "  (Diagram Studio is not in release $($script:AppsVersion): it is being rebuilt, and returns in a later release)" }
  Write-Host '  4) choose    type the apps you want, for example: hr,crm  (the list: config\apps.tsv)'
  $n = switch ($suggest) { 'small' { '1' } 'standard' { '2' } default { '3' } }
  $choice = Ask '1, 2, 3, 4 or app names' $n
  switch ($choice) {
    '1' { $Apps = Get-AppPreset 'small' }
    '2' { $Apps = Get-AppPreset 'standard' }
    '3' { $Apps = Get-AppPreset 'full' }
    '4' { $Apps = Ask 'Apps, separated by commas' 'hr,crm' }
    default { $Apps = $choice }
  }
}
try { $Apps = Resolve-App $Apps } catch { Die "$($_.Exception.Message) Fix the app names and run the installer again (.\install.ps1 -Apps hr,crm)." }
if (-not $Apps) { Die 'Choose at least one app, for example: .\install.ps1 -Apps hr,crm' }

# The editors (New and Edit in Documents; the diagram editor): on, unless asked
# otherwise, or when this computer is too small to carry them (about 2 GB).
$editorsWhy = ''
if ($Editors) { $editorsWhy = 'you asked for it' }
elseif ($prevEditors) { $Editors = $prevEditors; $editorsWhy = 'as before' }
elseif ($memMb -lt 5500) {
  $Editors = 'off'
  $editorsWhy = ('Docker has only {0:N0} GB of memory and the editors need about 2 GB more; turn them on later with .\tarleaks.ps1 editors on' -f ($memBytes / 1GB))
}
else { $Editors = 'on' }
$script:AppsEditors = $Editors   # read by scripts/lib-apps.ps1

$closure = Get-AppClosure $Apps
$profiles = Get-AppUnit $closure
$modules = Get-AppModule $closure
$needMb = Get-AppRamMb $closure
$chosenList = Split-AppList $Apps
$added = (Split-AppList $closure | Where-Object { $chosenList -notcontains $_ -and -not (Test-BaseApp $_) }) -join ','
Ok "Apps: $(Get-AppName $Apps)"
if ($added) { Ok "Also installed, because those apps need them: $(Get-AppName $added)" }
Ok "Always included: $(Get-AppName (Get-AppClosure ''))"
if ($Editors -eq 'on') {
  $why = if ($editorsWhy) { " ($editorsWhy)" } else { '' }
  Ok "Editors: $(Get-AppName (Get-AppAddonUnit $closure))$why"
} else { Warn "Editors off ($editorsWhy): Documents has no New or Edit, and Diagrams no editor. .\tarleaks.ps1 editors on later." }
Ok ("Memory to plan for: about {0:N1} GB (Docker can use {1:N1} GB)" -f ($needMb / 1024), ($memBytes / 1GB))
if (($needMb + 1024) -gt $memMb) {
  Warn ("These apps need about {0:N1} GB plus room to work. Choose fewer apps (.\install.ps1 -Apps hr,crm) or give Docker more memory (see examples\windows)." -f ($needMb / 1024))
}
$more = Get-AppSuggestion $modules
if ($more) { Write-Host "  Works well with them (add any time: .\tarleaks.ps1 apps add <app>): $(Get-AppName $more)" }

# Database sized for the services that will connect, and for the memory there is.
$units = @(Split-AppList $profiles).Count
$pg = @((50 + 10 * ($units + 7)), '128MB', '512MB')
if ($memMb -ge 14000) { $pg[1] = '512MB'; $pg[2] = '2GB' } elseif ($memMb -ge 7000) { $pg[1] = '256MB'; $pg[2] = '1GB' }
# The database's memory limit: a quarter of what Docker has, at least 1 GB.
$pgMem = [Math]::Max(1024, [int]($memMb / 4))

# ---- 3. Settings file -------------------------------------------------------
$envPath = Join-Path $PSScriptRoot '.env'
# A new .env next to Docker volumes that already belong to this project name
# would start a second copy of the ERP on another installation's data, with new
# passwords that do not open it. The project name is `name:` in
# docker-compose.yml unless COMPOSE_PROJECT_NAME says otherwise.
$envCreated = $false
if (-not (Test-Path $envPath)) {
  $project = $env:COMPOSE_PROJECT_NAME
  if (-not $project) {
    $project = (Get-Content (Join-Path $PSScriptRoot 'docker-compose.yml') | Where-Object { $_ -match '^name:\s*(\S+)' } | Select-Object -First 1) -replace '^name:\s*', ''
  }
  if ($project -cnotmatch '^[a-z0-9][a-z0-9_-]*$') { Die "COMPOSE_PROJECT_NAME '$project' is not a valid name: lowercase letters, digits, - and _ only." }
  $existing = docker volume ls -q --filter "label=com.docker.compose.project=$project"
  if ($existing) {
    Die "Docker on this machine already holds the data of an installation named '$project', and this folder has no .env. Installing here would attach a second copy to that data. To manage that installation, run .\tarleaks.ps1 in its own folder. To restore it, put back the .env from its backup first. To install a SEPARATE copy next to it, give this one its own name: `$env:COMPOSE_PROJECT_NAME='erp2'; .\install.ps1 (and its own -Port). Nothing was changed."
  }
  Copy-Item .env.example $envPath; $envCreated = $true; Ok 'Created .env'
}
$lines = [System.Collections.Generic.List[string]]::new([string[]](Get-Content $envPath))
$shellProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process')

function Get-EnvValue($key) {
  foreach ($l in $lines) { if ($l -match "^$([regex]::Escape($key))=(.*)$") { return $Matches[1] } }
  return ''
}
function Set-EnvValue($key, $value) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^$([regex]::Escape($key))=") { $lines[$i] = "$key=$value"; return }
  }
  $lines.Add("$key=$value")
}
# The installation's name stays in its .env, always (the default too), so
# .\tarleaks.ps1 finds its containers and a backup says whose data it holds:
# restore refuses a backup of another installation.
if ($envCreated) {
  Set-EnvValue 'COMPOSE_PROJECT_NAME' $project; Ok "Installation name: $project"
}
# An .env written before the rename has NEXUS_<key> lines: rename each to
# TARLEAKS_<key> in place, keeping its value (keys are never regenerated).
# Returns $true when anything changed.
function Convert-LegacyKeys {
  $src = @($lines)
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
  $script:lines = $out
  return $changed
}
if (Convert-LegacyKeys) { Ok 'Renamed the NEXUS_* settings in .env to TARLEAKS_* (values unchanged)' }
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
function RandBytes($n) { $b = New-Object byte[] $n; $rng.GetBytes($b); return ,$b }
function Hex($n) { return (-join ((RandBytes $n) | ForEach-Object { $_.ToString('x2') })) }
function B64($n) { return [Convert]::ToBase64String((RandBytes $n)) }
function SetupCode {
  $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  $bytes = RandBytes 12
  $chars = for ($i = 0; $i -lt 12; $i++) { $alphabet[$bytes[$i] % $alphabet.Length] }
  $s = -join $chars
  return "$($s.Substring(0,4))-$($s.Substring(4,4))-$($s.Substring(8,4))"
}
function Fill($key, [scriptblock] $gen) {
  $cur = Get-EnvValue $key
  if ([string]::IsNullOrEmpty($cur) -or $cur -eq 'GENERATED') { Set-EnvValue $key (& $gen) }
}

Fill 'POSTGRES_PASSWORD' { Hex 24 }
Fill 'RABBITMQ_PASSWORD' { Hex 24 }
Fill 'STORAGE_ACCESS_KEY' { Hex 16 }
Fill 'STORAGE_SECRET_KEY' { Hex 32 }
Fill 'JWT_SECRET' { Hex 32 }
Fill 'CLUSTER_DSN_KEY' { B64 32 }
Fill 'INTERNAL_TOKEN' { Hex 32 }
Fill 'PORTAL_JWT_SECRET' { Hex 32 }
Fill 'NOTIFICATIONS_KEK' { B64 32 }
Fill 'NOTIFICATIONS_UNSUB_SECRET' { Hex 32 }
Fill 'NOTIFICATIONS_OAUTH_SECRET' { Hex 32 }
Fill 'HELPDESK_TOKEN_KEY' { B64 32 }
Fill 'SUBSCRIPTIONS_KEY_SEAL_KEY' { B64 32 }
Fill 'MARKETPLACE_TOKEN_KEY' { B64 32 }
Fill 'INSIGHTS_SOURCE_KEY' { B64 32 }
Fill 'INSIGHTS_VISITOR_HASH_KEY' { Hex 32 }
Fill 'PROCUREMENT_KEK' { B64 32 }
Fill 'CONTRACTS_PROVIDER_KEY' { B64 32 }
Fill 'ACTIVITIES_INVITE_SECRET' { Hex 32 }
Fill 'CORRESPONDENCE_MAILBOX_KEY' { B64 32 }
Fill 'CRM_EMAIL_TOKEN_KEY' { B64 32 }
Fill 'EINVOICE_SEAL_KEY' { B64 32 }
Fill 'PDFTOOLS_SIGN_KEY' { B64 32 }
Fill 'SOCIAL_TOKEN_KEY' { B64 32 }
Fill 'SSO_CREDENTIAL_KEY' { Hex 32 }
Fill 'ONLYOFFICE_JWT_SECRET' { Hex 32 }
Fill 'TARLEAKS_SETUP_CODE' { SetupCode }

# ---- 4. Address -------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($HostName)) {
  $def = Get-EnvValue 'TARLEAKS_HOST'; if (-not $def) { $def = 'localhost' }
  $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
         Where-Object { $_.PrefixOrigin -in 'Dhcp', 'Manual' -and $_.IPAddress -notlike '169.254.*' } |
         Select-Object -First 1).IPAddress
  if ($ip -and $def -eq 'localhost') { Write-Host "  This computer's network address is $ip - use it to reach the ERP from other computers." }
  $HostName = Ask 'Address people will use (localhost, an IP or a domain)' $def
}
if ($HostName -match '^https://') { Warn 'The ERP itself speaks plain http; for https put a reverse proxy in front (examples\vps-https). Using the name only.' }
$HostName = ($HostName.Trim() -replace '^https?://', '') -replace '/.*$', ''
if ($HostName -match '^(.+):(\d+)$') { Warn "Ignoring the port :$($Matches[2]) in the address: the ERP listens on the port from -Port."; $HostName = $Matches[1] }
if ($HostName -notmatch '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$') { Die "`"$HostName`" is not an address people can type: use localhost, an IP address (192.168.1.20) or a name (erp.example.com), without spaces." }
if ($Port -eq 0) { $p = Get-EnvValue 'HTTP_PORT'; if ($p) { $Port = [int]$p } else { $Port = 80 } }
$url = if ($Port -eq 80) { "http://$HostName" } else { "http://${HostName}:$Port" }
# Keep an HTTPS address set up behind a reverse proxy: re-running must not undo it.
$curUrl = Get-EnvValue 'TARLEAKS_URL'
if ($curUrl -like 'https://*' -and $HostName -eq (Get-EnvValue 'TARLEAKS_HOST')) { $url = $curUrl }
Ok "Address: $url"

function Test-PortBusy([int] $P) {
  if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) { return [bool](Get-NetTCPConnection -LocalPort $P -State Listen -ErrorAction SilentlyContinue) }
  return $false
}
# Busy is fine only when it is this installation's own gateway on that port.
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$oursLine = docker compose port gateway 80 2>$null
$ErrorActionPreference = $old
$ours = if ($oursLine -match ':(\d+)\s*$') { [int]$Matches[1] } else { 0 }
if ((Test-PortBusy $Port) -and $ours -ne $Port) {
  $free = @(8080, 8081, 8088, 8181, 8888, 9080) | Where-Object { -not (Test-PortBusy $_) } | Select-Object -First 1
  Die "Port $Port is already in use (often IIS or Skype). Free it, or use another port: .\install.ps1 -Port $free"
}
# Who may open it: only this computer, or the network too. The installer looks
# at the computer and proposes one, says which and why; -Bind always overrides,
# and .\tarleaks.ps1 network local|office changes it later.
#   a laptop or desktop (a battery, or Windows 10/11 rather than Windows Server)
#     -> only this computer: nobody else on a cafe or office Wi-Fi can open it
#   a server (Windows Server, no battery) -> the office network
#   an address other people type (-HostName 192.168.1.20) -> the network, always
function Get-MachineKind {
  $battery = $null; $os = $null
  try { $battery = Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1 } catch { $battery = $null }
  try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $os = $null }
  if ($battery) { return @('laptop', 'it has a battery') }
  if ($os -and $os.ProductType -eq 1) { return @('laptop', 'it runs Windows 10 or 11, not Windows Server') }
  if ($os) { return @('server', 'it runs Windows Server and has no battery') }
  return @('laptop', 'the kind of computer could not be read, so the safer choice is made')
}
$curBind = Get-EnvValue 'HTTP_BIND'
$bindWhy = ''
switch ($Bind) {
  'local' { $Bind = '127.0.0.1'; $bindWhy = 'you asked for it' }
  { $_ -in 'network', 'office' } { $Bind = '0.0.0.0'; $bindWhy = 'you asked for it' }
  '' {
    if ($curBind) { $defBind = $curBind; $bindWhy = 'as before (change it: .\tarleaks.ps1 network local|office)' }
    elseif ($HostName -notin 'localhost', '127.0.0.1') { $defBind = '0.0.0.0'; $bindWhy = "the address is $HostName, which other computers type" }
    else {
      $kind = Get-MachineKind
      if ($kind[0] -eq 'laptop') { $defBind = '127.0.0.1'; $bindWhy = "$($kind[1]), so this looks like a laptop or desktop" }
      else { $defBind = '0.0.0.0'; $bindWhy = "$($kind[1]), so this looks like a server" }
    }
    $Bind = $defBind
    if (-not $Yes) {
      $proposed = if ($defBind -eq '127.0.0.1') { 'only this computer' } else { 'the network too' }
      Write-Host "Who should be able to open it?   (proposed: $proposed, because $bindWhy)"
      Write-Host '  1) only this computer   (other computers cannot connect)'
      Write-Host '  2) the network too      (needed for an office server; protect it with the firewall)'
      $Bind = if ((Ask '1 or 2' $(if ($defBind -eq '127.0.0.1') { '1' } else { '2' })) -eq '1') { '127.0.0.1' } else { '0.0.0.0' }
      $bindWhy = "you chose it (proposed from: $bindWhy)"
    }
  }
  default { $bindWhy = 'you asked for it' }
}
if ($Bind -eq '127.0.0.1' -and $HostName -notin 'localhost', '127.0.0.1') { Warn "Only this computer can connect, but the address is ${HostName}: other computers will not reach it." }
Ok $(if ($Bind -eq '127.0.0.1') { "Who can open it: only this computer ($bindWhy). Change it: .\tarleaks.ps1 network office" } elseif ($Bind -eq '0.0.0.0') { "Who can open it: this computer and the network, port $Port ($bindWhy). Change it: .\tarleaks.ps1 network local" } else { "Listens on $Bind only ($bindWhy)" })

if (-not $ProfileEnv) { $ProfileEnv = Get-EnvValue 'TARLEAKS_PROFILE_ENV' }
if (-not $ProfileEnv) { $ProfileEnv = 'local' }
if ($ProfileEnv -eq 'production') {
  if ($HostName -match '^(localhost|127\.|\d+\.\d+\.\d+\.\d+$)' -or $HostName -match ':') {
    Die "The production profile needs a domain name (erp.example.com), not '$HostName'. docs/https.md"
  }
  $url = "https://$HostName"
  Set-EnvValue 'TARLEAKS_TLS' 'proxy'
  Warn "Production on Windows: put your HTTPS reverse proxy in front of port $Port (docs/https.md, 'Behind a reverse proxy you already run')."
} else {
  Set-EnvValue 'TARLEAKS_TLS' ''
}
Set-EnvValue 'TARLEAKS_PROFILE_ENV' $ProfileEnv
Ok "Profile: $ProfileEnv"
Set-EnvValue 'TARLEAKS_HOST' $HostName
Set-EnvValue 'TARLEAKS_URL' $url
Set-EnvValue 'HTTP_PORT' $Port
Set-EnvValue 'HTTP_BIND' $Bind
Set-EnvValue 'TARLEAKS_APPS' $Apps
Set-EnvValue 'TARLEAKS_EDITORS' $Editors
Set-EnvValue 'COMPOSE_PROFILES' ($profiles + (Get-AppAddon $closure))
Set-EnvValue 'TARLEAKS_AVAILABLE_MODULES' $modules
$editorSetting = Get-AppEditorSetting $closure $url
foreach ($k in $editorSetting.Keys) { Set-EnvValue $k $editorSetting[$k] }
Set-EnvValue 'PG_MAX_CONNECTIONS' $pg[0]
Set-EnvValue 'PG_SHARED_BUFFERS' $pg[1]
Set-EnvValue 'PG_EFFECTIVE_CACHE_SIZE' $pg[2]
# Kept when set by hand (docs\configuration.md#memory-limits).
if (-not (Get-EnvValue 'PG_MEM_LIMIT')) { Set-EnvValue 'PG_MEM_LIMIT' "${pgMem}m" }
# A version given with -Version is written only once its images are here, so
# a typo never leaves .env naming a release that does not exist.
if ($Version -and $NoStart) { Set-EnvValue 'TARLEAKS_VERSION' $Version }
if ($LicenceKey -eq 'none') { Set-EnvValue 'TARLEAKS_LICENSE_KEY' ''; Ok 'Licence key removed from .env' }
# A move brings the company's own licence, and a key in TARLEAKS_LICENSE_KEY
# would win over it: this one is only the download password.
elseif ($LicenceKey -and $FromCloud) { Set-EnvValue 'TARLEAKS_DOWNLOAD_KEY' $LicenceKey }
elseif ($LicenceKey) { Set-EnvValue 'TARLEAKS_LICENSE_KEY' $LicenceKey }
# Only to test against another Tarleaks platform; empty = tarleaks.com.
if ($Vendor -eq 'default') {
  if (Get-EnvValue 'TARLEAKS_VENDOR_URL') { Set-EnvValue 'TARLEAKS_VENDOR_URL' ''; Ok 'Tarleaks Cloud is https://tarleaks.com again' }
} elseif ($Vendor) {
  Set-EnvValue 'TARLEAKS_VENDOR_URL' $Vendor.TrimEnd('/')
  Warn "Tarleaks Cloud is $($Vendor.TrimEnd('/')) for this installation (TARLEAKS_VENDOR_URL in .env), for tests only."
}
# The private-preview image location (ghcr.io, a personal GitHub token) moved to
# registry.tarleaks.com, where the licence key is the password. The images
# already here get the new name too, so nothing downloads again.
if ((Get-EnvValue 'TARLEAKS_REGISTRY').Trim().TrimEnd('/') -eq $script:RegistryRetired) {
  Set-EnvValue 'TARLEAKS_REGISTRY' $script:RegistryDefault
  $moved = Copy-RegistryRetiredTag
  Ok ("Images now come from $script:RegistryDefault, signed in with the licence key (no docker login any more)" + $(if ($moved -gt 0) { "; $moved image name(s) here moved over." } else { '.' }))
}

# UTF-8 WITHOUT a byte-order mark and with LF endings: Docker Compose reads the
# first key wrong otherwise.
[System.IO.File]::WriteAllText($envPath, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
# Readable by you, Administrators and SYSTEM only: a folder like C:\Tarleaks-ERP
# otherwise lets every signed-in user of this computer read the keys.
if ($env:OS -eq 'Windows_NT') {
  icacls $envPath /inheritance:r /grant:r "${env:USERNAME}:F" '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Null
  if ($LASTEXITCODE -ne 0) { Warn 'Could not limit who may read .env (icacls failed). Check its permissions: only you and Administrators should read it.' }
}
Ok 'Settings written to .env (keep a copy somewhere safe)'

if ($NoStart) {
  Write-Host 'Not starting (-NoStart). Run .\tarleaks.ps1 start when ready.'
  if ($FromCloud) { Write-Host 'Then move the company in with the same code: .\tarleaks.ps1 migrate-from-cloud <code>' }
  exit 0
}

# ---- 5. Images ---------------------------------------------------------------
if ($Offline) { $env:TARLEAKS_NO_DOWNLOAD = '1' }
function Save-Env { [System.IO.File]::WriteAllText($envPath, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false))) }
$emailPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
# The licence key is also the password for downloading the images. With none
# yet (no -LicenceKey, none in .env, none in a running installation), start the
# 30-day trial here: the setup screen then continues the same trial when you
# give it the same e-mail address.
if (-not $Offline -and (Test-RegistryTakesLicence) -and -not (Get-RegistryLicenceKey)) {
  Write-Host ''
  Write-Host 'A licence key is needed to download Tarleaks ERP (it is also the download password).' -ForegroundColor White
  if ($FromCloud) { Write-Host "  The company's own licence comes with the move: the key or trial here is only used to download." }
  if (-not $Trial -and -not $Yes) {
    Write-Host '  1) I have a licence key'
    Write-Host '  2) Start the free 30-day trial (your company name and e-mail address)'
    if ((Ask '1 or 2' '2') -eq '1') {
      $secure = Read-Host 'Paste the licence key (it is not shown)' -AsSecureString
      $key = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)).Trim()
      if (-not (Test-LicenceKeyShape $key)) { Die 'That does not look like a Tarleaks licence key: one line that starts with nxs1. Copy all of it again, then run .\install.ps1 -LicenceKey <key>.' }
      if ($FromCloud) { Set-EnvValue 'TARLEAKS_DOWNLOAD_KEY' $key; Save-Env; Ok 'Download key saved in .env' }
      else { Set-EnvValue 'TARLEAKS_LICENSE_KEY' $key; Save-Env; Ok 'Licence key saved in .env' }
    } else {
      $Trial = Ask 'Your e-mail address' ''
      if ($Trial -notmatch $emailPattern) { Die "`"$Trial`" is not an e-mail address. Run .\install.ps1 again." }
      if (-not $Company) { $Company = Ask 'Your company name' '' }
      Write-Host '  The licence terms are in LICENSE.md next to this installer.'
      if ((Ask 'Do you accept them? yes/no' 'no') -notmatch '^(y|yes)$') { Die 'The trial needs the licence terms accepted (LICENSE.md). Nothing was downloaded.' }
      $AcceptTerms = [switch]::Present
    }
  }
  if (-not (Get-RegistryLicenceKey)) {
    if (-not $Trial) { Die 'Give your licence key (.\install.ps1 -LicenceKey <key>) or start the free trial (.\install.ps1 -Trial you@yourcompany.com -Company "Your company" -AcceptTerms). Nothing was downloaded.' }
    if (-not $Company) { Die 'The trial needs your company name: add -Company "Your company".' }
    if (-not $AcceptTerms) { Die 'The trial needs the licence terms (LICENSE.md) accepted: add -AcceptTerms.' }
    $trialKey = Start-RegistryTrial $Company $Trial
    if (-not $trialKey) { Die 'Nothing was downloaded. Fix the above, or give a licence key with .\install.ps1 -LicenceKey <key>.' }
    if (-not (Test-LicenceKeyShape $trialKey)) { Die 'tarleaks.com did not send a usable trial key. Run .\install.ps1 again; if it keeps failing, contact info@tarleaks.com.' }
    Set-EnvValue 'TARLEAKS_DOWNLOAD_KEY' $trialKey; Save-Env
    if ($FromCloud) { Ok "Free trial started for $Trial, to download. The company keeps its own licence." }
    else { Ok "Free trial started for $Trial. On the setup screen, choose the free trial with the same e-mail address." }
  }
}
# Before several GB of downloads: can this computer reach the licence server,
# is its clock right, and does the registry take the licence key?
if (-not $Offline) {
  $remote = $null; $answered = $false
  try {
    $r = Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec 10 -Uri 'https://tarleaks.com'
    $answered = $true; $remote = "$($r.Headers['Date'])"
  } catch {
    # An HTTP error is still an answer; only no answer at all is a problem.
    if ($_.Exception.Response) { $answered = $true; try { $remote = "$($_.Exception.Response.Headers['Date'])" } catch { $remote = $null } }
  }
  if ($answered) {
    Ok 'tarleaks.com answers'
    try {
      $then = [datetimeoffset]::ParseExact($remote.Trim(), 'r', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).UtcDateTime
      $skew = [math]::Abs(([datetime]::UtcNow - $then).TotalSeconds)
      if ($skew -gt 600) { Warn ("This computer's clock is {0:N0} seconds off. Turn on 'Set time automatically' (Settings, Time and language) before the setup: the licence refuses a clock that runs behind." -f $skew) }
    } catch { $skew = $null }
  } else {
    Warn 'tarleaks.com does not answer from this computer. The trial and the licence check-in need it (outbound HTTPS, port 443). Without internet: docs\faq.md, "Can I install without internet?"'
  }
  if (Test-RegistryTakesLicence) {
    if (-not (Invoke-RegistryLogin '.\install.ps1')) { Die 'Nothing was downloaded.' }
    Ok "Signed in to $(Get-RegistryHost) with the licence key"
  }
}
Write-Host ''
Write-Host 'Downloading the images (the first time takes a few minutes)...'
if ($Version) {
  [Environment]::SetEnvironmentVariable('TARLEAKS_VERSION', $Version, 'Process')
  $pulled = Invoke-AppPull ".\install.ps1 -Version $Version"
  [Environment]::SetEnvironmentVariable('TARLEAKS_VERSION', $null, 'Process')
  if (-not $pulled) { Die "Nothing was started; .env still names $(Get-EnvValue 'TARLEAKS_VERSION'). Fix what is named above (a release number that does not exist: the release notes list them)." }
  Set-EnvValue 'TARLEAKS_VERSION' $Version
  [System.IO.File]::WriteAllText($envPath, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
} elseif (-not (Invoke-AppPull '.\install.ps1')) { exit 1 }
$downloaded = -not $Offline
if ($downloaded) { Ok 'Images downloaded' } else { Ok 'Every image is on this computer' }
# The sign-in token key, once: after the images, whose openssl makes it.
Write-SigningKeyNote (Add-SigningKey)
Write-AppSigningKeyNote (Add-AppSigningKey)
[System.IO.File]::WriteAllText($envPath, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
docker compose up -d --remove-orphans
if ($LASTEXITCODE -ne 0) { Die 'Starting failed. See: docker compose logs' }
Stop-UnselectedApp

Write-Host ''
Write-Host 'Starting (the first start prepares the database; allow up to 5 minutes)' -NoNewline
$deadline = (Get-Date).AddMinutes(10)
while ($true) {
  try {
    $bind = Get-EnvValue 'HTTP_BIND'; if (-not $bind -or $bind -eq '0.0.0.0') { $bind = '127.0.0.1' }
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri "http://${bind}:$Port/api/auth/installation" | Out-Null
    break
  } catch {
    if ((Get-Date) -gt $deadline) { Write-Host ''; Warn 'Not answering after 10 minutes. See: docker compose ps   and   docker compose logs auth'; exit 1 }
    Write-Host '.' -NoNewline; Start-Sleep -Seconds 5
  }
}
Write-Host ''
Ok 'Tarleaks ERP is running'
# The document editor starts last and takes a minute or two the first time:
# wait for it (at most 4 minutes), so New and Edit work the moment you open Documents.
if ($Editors -eq 'on' -and ((Get-EnvValue 'COMPOSE_PROFILES') -split ',') -contains 'onlyoffice') {
  Write-Host 'Starting the document editor (the first start takes a minute or two)' -NoNewline
  $editorDeadline = (Get-Date).AddMinutes(4); $editorUp = $false
  while ($true) {
    try {
      $answer = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri "http://${bind}:$Port/onlyoffice/healthcheck").Content
      if ("$answer".Trim() -eq 'true') { $editorUp = $true; break }
    } catch { $answer = '' }
    if ((Get-Date) -gt $editorDeadline) { break }
    Write-Host '.' -NoNewline; Start-Sleep -Seconds 5
  }
  Write-Host ''
  if ($editorUp) { Ok 'The document editor is ready' }
  else { Warn 'The document editor is still starting. New and Edit in Documents work once it is up. See: docker compose logs onlyoffice' }
}
if ($FromCloud) {
  # No setup screen: the company, its people and settings come from the cloud.
  # .\tarleaks.ps1 does the move, so it can be watched again or resumed there.
  if ($shellProxy -and -not (Get-EnvValue 'HTTPS_PROXY')) {
    Write-Host ''
    Warn "This session uses a proxy ($shellProxy) but .env sets none, so the ERP reaches Tarleaks Cloud directly. If it needs the proxy, add HTTPS_PROXY=... to .env, run .\tarleaks.ps1 restart, then .\tarleaks.ps1 migrate-from-cloud <code> (docs\configuration.md#outbound-proxy)."
  }
  Write-Host ''
  Write-Host 'Moving the company from Tarleaks Cloud' -ForegroundColor White
  if ($Yes) { $env:TARLEAKS_NO_PROMPT = '1' }   # -Yes asks nothing: the switch over then waits for -SwitchOver
  try { & (Join-Path $PSScriptRoot 'tarleaks.ps1') migrate-from-cloud $FromCloud -SwitchOver:$SwitchOver }
  finally { Remove-Item Env:TARLEAKS_NO_PROMPT -ErrorAction SilentlyContinue }
  $moveExit = $LASTEXITCODE
  if ($moveExit -ne 0) {
    Write-Host ''
    Warn 'Tarleaks ERP is installed and running, but the move did not finish (above). Nothing needs installing again; .\tarleaks.ps1 migrate-from-cloud -Status shows where it stands.'
    exit $moveExit
  }
  Write-Host ''
} else {
  Write-Host ''
  Write-Host "Open $url in your browser." -ForegroundColor White
  Write-Host "  Setup code: $(Get-EnvValue 'TARLEAKS_SETUP_CODE')" -ForegroundColor White
  Write-Host '  Name your company, create the first administrator and start the'
  if ($downloaded) { Write-Host '  30-day free trial (or enter a licence key).' }
  else { Write-Host '  licence: with no internet, enter a licence key (the trial needs internet).' }
  Write-Host ''
}
Write-Host '  .\tarleaks.ps1 status | stop | start | logs | backup | upgrade'
Write-Host ''
if ($downloaded -or $FromCloud) {
  Write-Host 'The ERP checks its licence with tarleaks.com about every 6 hours and needs'
  Write-Host 'to reach it at least once a day. Allow outbound HTTPS to tarleaks.com'
  Write-Host '(directly, or through HTTPS_PROXY in .env).'
} else {
  Write-Host 'This computer downloaded nothing. If it has no internet at all, it needs a' -ForegroundColor White
  Write-Host 'licence key made for that: read docs\faq.md, "Can I install without'
  Write-Host 'internet?", before you run the setup.'
}
if (-not $FromCloud -and $shellProxy -and -not (Get-EnvValue 'HTTPS_PROXY')) {
  Write-Host ''
  Warn "This session uses a proxy ($shellProxy) but .env sets none, so the ERP connects directly. If the ERP needs it too, add HTTPS_PROXY=... to .env and run .\tarleaks.ps1 restart (docs\configuration.md#outbound-proxy)."
}
