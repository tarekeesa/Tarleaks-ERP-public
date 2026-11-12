# =============================================================================
# Which apps run, and what they need — read from config\apps.tsv.
# Dot-sourced by install.ps1 and tarleaks.ps1 (Linux/macOS: scripts/lib-apps.sh).
# The same rules as lib-apps.sh; keep the two in step.
# =============================================================================

# Signing in to the image registry with the licence key (Invoke-AppPull does it).
. (Join-Path $PSScriptRoot 'lib-registry.ps1')
# Checking the Tarleaks signature of what was downloaded (Invoke-AppPull does it).
. (Join-Path $PSScriptRoot 'lib-signature.ps1')

$script:AppsSheet = Join-Path (Split-Path $PSScriptRoot -Parent) 'config/apps.tsv'
if (-not (Test-Path $script:AppsSheet)) { $script:AppsSheet = Join-Path $PSScriptRoot 'config/apps.tsv' }

$script:AppsReleases = Join-Path (Split-Path $script:AppsSheet -Parent) 'app-releases.tsv'
# The release this installation runs (TARLEAKS_VERSION); the caller sets it. An
# app listed in config\app-releases.tsv with a later release is left out of the
# presets and refused by name: its image does not exist yet.
if (-not (Get-Variable -Name AppsVersion -Scope Script -ErrorAction SilentlyContinue)) { $script:AppsVersion = '' }
# 'on' or 'off': the editors (rows of kind addon in apps.tsv). The installer sets
# it for the run; otherwise TARLEAKS_EDITORS in .env says (default on).
if (-not (Get-Variable -Name AppsEditors -Scope Script -ErrorAction SilentlyContinue)) { $script:AppsEditors = '' }

# Is version $A older than version $B? ("1.0.0" vs "1.2.0"; a suffix after - is ignored)
function Test-OlderVersion([string] $A, [string] $B) {
  $x = @(($A -replace '-.*$', '') -split '\.'); $y = @(($B -replace '-.*$', '') -split '\.')
  $n = [Math]::Max($x.Count, $y.Count)
  for ($i = 0; $i -lt $n; $i++) {
    $p = 0; $q = 0
    if ($i -lt $x.Count) { [void][int]::TryParse($x[$i], [ref]$p) }
    if ($i -lt $y.Count) { [void][int]::TryParse($y[$i], [ref]$q) }
    if ($p -lt $q) { return $true }
    if ($p -gt $q) { return $false }
  }
  return $false
}

# Apps whose image $script:AppsVersion does not have, as app -> first release:
# newer than it, or (third column of app-releases.tsv) withdrawn in it or an
# earlier release, as app -> "withdrawn:<release>".
function Get-AppUnreleased {
  $late = [ordered]@{}
  if (-not $script:AppsVersion -or -not (Test-Path $script:AppsReleases)) { return $late }
  foreach ($line in Get-Content $script:AppsReleases) {
    if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
    $f = $line.Trim() -split '\s+'
    if ($f.Count -ge 2 -and (Test-OlderVersion $script:AppsVersion $f[1])) { $late[$f[0]] = $f[1] }
    elseif ($f.Count -ge 3 -and -not (Test-OlderVersion $script:AppsVersion $f[2])) { $late[$f[0]] = "withdrawn:$($f[2])" }
  }
  return $late
}

# The same split in two: apps that arrive with a NEWER release, and apps this
# release (or an earlier one) took out again.
function Get-AppNotYet { $u = Get-AppUnreleased; return @($u.Keys | Where-Object { $u[$_] -notlike 'withdrawn:*' }) }
function Get-AppWithdrawn { $u = Get-AppUnreleased; return @($u.Keys | Where-Object { $u[$_] -like 'withdrawn:*' }) }

# The list without the apps in the second list (order kept).
function Remove-AppFromList([string] $List, [string[]] $Drop) {
  return ((Split-AppList $List | Where-Object { $Drop -notcontains $_ }) -join ',')
}

$script:AppsPresetSmall = 'hr,recruitment,attendance,payroll,accounting,crm,inventory,sales_orders,chat'
$script:AppsPresetStandard = "$script:AppsPresetSmall,project_management,lms,gamification,assets,helpdesk,fleet,correspondence,pos,rental,subscriptions,procurement,construction,contracts"
$script:AppsPresetFull = "$script:AppsPresetStandard,pdftools,diagrams,imtithal,iso42001"

function Get-AppPreset([string] $Name) {
  $list = switch ($Name) {
    'small' { $script:AppsPresetSmall }
    'standard' { $script:AppsPresetStandard }
    'full' { $script:AppsPresetFull }
    default { $null }
  }
  if ($null -eq $list) { return $null }
  return (Remove-AppFromList $list @((Get-AppUnreleased).Keys))
}

# The sheet as objects, in its order.
function Get-AppRow {
  $rows = [System.Collections.Generic.List[object]]::new()
  foreach ($line in Get-Content $script:AppsSheet) {
    if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
    $f = $line.Trim() -split '\s+'
    if ($f.Count -lt 8) { continue }
    $rows.Add([pscustomobject]@{
        App = $f[0]; Kind = $f[1]; Unit = $f[2]
        Needs = @(if ($f[3] -ne '-') { $f[3] -split ',' })
        WorksWith = @(if ($f[4] -ne '-') { $f[4] -split ',' })
        Aliases = @(if ($f[5] -ne '-') { $f[5] -split ',' })
        RamMb = [int]$f[6]
        Name = ($f[7..($f.Count - 1)] -join ' ')
      })
  }
  return $rows
}

function Split-AppList([string] $List) { return @($List -split '[,\s]+' | Where-Object { $_ }) }

# What a person typed → licence names; throws on an unknown word.
function Resolve-App([string] $List) {
  $rows = Get-AppRow
  $byName = @{}; $alias = @{}
  foreach ($r in $rows) { $byName[$r.App] = $r; foreach ($a in $r.Aliases) { $alias[$a] = $r.App } }
  $out = [System.Collections.Generic.List[string]]::new(); $bad = @()
  foreach ($w in (Split-AppList $List)) {
    $x = $w.ToLowerInvariant() -replace '-', '_'
    if ($alias.ContainsKey($x)) { $x = $alias[$x] }
    if (-not $byName.ContainsKey($x) -or $byName[$x].Kind -eq 'platform' -or $byName[$x].Kind -eq 'addon') { $bad += $w; continue }
    if (-not $out.Contains($x)) { $out.Add($x) }
  }
  if ($bad) { throw "Unknown app: $($bad -join ', '). See the list with: .\tarleaks.ps1 apps" }
  $apps = ($out -join ',')
  # Refuse an app whose image this release does not have, or one that needs it.
  $late = Get-AppUnreleased
  if ($late.Count -gt 0) {
    $names = @(); $withdrawn = @()
    foreach ($a in (Split-AppList (Get-AppClosure $apps))) {
      if (-not $late.Contains($a)) { continue }
      if ($late[$a] -like 'withdrawn:*') { $withdrawn += "$(Get-AppName $a) (taken out in release $($late[$a].Substring(10)) while it is rebuilt; it returns in a later release)" }
      else { $names += "$(Get-AppName $a) (from release $($late[$a]))" }
    }
    if ($withdrawn) { throw "Not in release $($script:AppsVersion): $($withdrawn -join ', '). Choose other apps." }
    if ($names) { throw "Not in release $($script:AppsVersion) yet: $($names -join ', '). Choose other apps, or update to that release first." }
  }
  return $apps
}

# Every app that must run: the chosen ones, what they need, and the base apps.
function Get-AppClosure([string] $List) {
  $rows = Get-AppRow
  $needs = @{}; foreach ($r in $rows) { $needs[$r.App] = $r.Needs }
  $set = @{}
  $stack = [System.Collections.Generic.Stack[string]]::new()
  foreach ($a in (Split-AppList $List)) { $stack.Push($a) }
  foreach ($r in $rows) { if ($r.Kind -eq 'base') { $stack.Push($r.App) } }
  while ($stack.Count -gt 0) {
    $a = $stack.Pop()
    if ($set.ContainsKey($a)) { continue }
    $set[$a] = $true
    foreach ($d in $needs[$a]) { $stack.Push($d) }
  }
  return (($rows | Where-Object { $set.ContainsKey($_.App) -and $_.Kind -ne 'platform' -and $_.Kind -ne 'addon' } | ForEach-Object { $_.App }) -join ',')
}

# One compose profile per service of a chosen (non-base) app.
function Get-AppUnit([string] $Closure) {
  $want = @{}; foreach ($a in (Split-AppList $Closure)) { $want[$a] = $true }
  $units = [System.Collections.Generic.List[string]]::new()
  foreach ($r in Get-AppRow) {
    if ($want.ContainsKey($r.App) -and $r.Kind -eq 'app' -and -not $units.Contains($r.Unit)) { $units.Add($r.Unit) }
  }
  return ($units -join ',')
}

# Every app a running service serves (HR brings Recruitment: same service).
function Get-AppModule([string] $Closure) {
  $run = @{}; foreach ($u in (Split-AppList (Get-AppUnit $Closure))) { $run[$u] = $true }
  return ((Get-AppRow | Where-Object { $_.Kind -eq 'base' -or ($_.Kind -eq 'app' -and $run.ContainsKey($_.Unit)) } | ForEach-Object { $_.App }) -join ',')
}

# Memory to plan for (MB): the platform, the base apps, each running unit once
# and the editors that run with them.
function Get-AppRamMb([string] $Closure) {
  $run = @{}
  foreach ($u in (Split-AppList (Get-AppUnit $Closure))) { $run[$u] = $true }
  foreach ($u in (Split-AppList (Get-AppAddonUnit $Closure))) { $run[$u] = $true }
  $seen = @{}; $total = 0
  foreach ($r in Get-AppRow) {
    if ($r.Kind -eq 'platform' -or $r.Kind -eq 'base' -or (($r.Kind -eq 'app' -or $r.Kind -eq 'addon') -and $run.ContainsKey($r.Unit))) {
      if (-not $seen.ContainsKey($r.Unit)) { $seen[$r.Unit] = $true; $total += $r.RamMb }
    }
  }
  return $total
}

# Chosen apps that need $App (directly or further down).
function Get-AppNeededBy([string] $App, [string] $Chosen) {
  $out = @()
  foreach ($a in (Split-AppList $Chosen)) {
    if ($a -eq $App) { continue }
    if ((Split-AppList (Get-AppClosure $a)) -contains $App) { $out += $a }
  }
  return ($out -join ',')
}

function Get-AppName([string] $List) {
  $names = @{}; foreach ($r in Get-AppRow) { $names[$r.App] = $r.Name }
  return ((Split-AppList $List | Where-Object { $names.ContainsKey($_) } | ForEach-Object { $names[$_] }) -join ', ')
}

function Test-BaseApp([string] $App) { return [bool](Get-AppRow | Where-Object { $_.App -eq $App -and $_.Kind -eq 'base' }) }

# Apps that add to the installed ones (never installed by themselves).
function Get-AppSuggestion([string] $Modules) {
  $have = @{}; foreach ($a in (Split-AppList $Modules)) { $have[$a] = $true }
  $out = [System.Collections.Generic.List[string]]::new()
  foreach ($r in Get-AppRow) {
    if (-not $have.ContainsKey($r.App)) { continue }
    foreach ($w in $r.WorksWith) { if (-not $have.ContainsKey($w) -and -not $out.Contains($w)) { $out.Add($w) } }
  }
  return ($out -join ',')
}

function Show-AppTable([string] $Chosen, [string] $Running) {
  $ch = @{}; foreach ($a in (Split-AppList $Chosen)) { $ch[$a] = $true }
  $rn = @{}; foreach ($a in (Split-AppList $Running)) { $rn[$a] = $true }
  Write-Host ('  {0,-3} {1,-20} {2,-38} {3}' -f '', 'APP', 'NAME', 'NEEDS')
  foreach ($r in Get-AppRow) {
    if ($r.Kind -eq 'platform' -or $r.Kind -eq 'addon') { continue }
    $mark = if ($r.Kind -eq 'base') { '(b)' } elseif ($ch.ContainsKey($r.App)) { '[x]' } elseif ($rn.ContainsKey($r.App)) { '(+)' } else { '[ ]' }
    Write-Host ('  {0,-3} {1,-20} {2,-38} {3}' -f $mark, $r.App, $r.Name, ($r.Needs -join ','))
  }
}

# Stop and remove the containers of services no chosen app needs any more.
# Their data stays in the database and the file store.
function Stop-UnselectedApp {
  $want = @(docker compose config --services 2>$null)
  if ($LASTEXITCODE -ne 0) { return }
  # The project name (`name:` in docker-compose.yml, or COMPOSE_PROJECT_NAME).
  $project = ''
  foreach ($l in @(docker compose config 2>$null)) { if ($l -match '^name:\s*(.+)$') { $project = $Matches[1].Trim(); break } }
  if (-not $project) { return }
  $have = @(docker ps -a --filter "label=com.docker.compose.project=$project" --format '{{.Label "com.docker.compose.service"}}' | Sort-Object -Unique)
  foreach ($svc in $have) {
    if (-not $svc -or $want -contains $svc) { continue }
    foreach ($id in @(docker ps -aq --filter "label=com.docker.compose.project=$project" --filter "label=com.docker.compose.service=$svc")) {
      if ($id) { docker rm -f $id | Out-Null }
    }
    Write-Host "  stopped $svc (no chosen app needs it; its data is kept)"
  }
}

# Images the chosen services run that are not on this computer; $null when
# docker-compose.yml cannot be read.
function Get-AppMissingImage {
  $images = docker compose config --images 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  $miss = @()
  foreach ($img in ($images | Sort-Object -Unique)) {
    docker image inspect $img *> $null
    if ($LASTEXITCODE -ne 0) { $miss += $img }
  }
  return ,$miss
}

# The editors (rows of kind addon in config\apps.tsv): the document editor of
# Documents and the diagram editor of Diagrams. They run next to
# the apps that use them. TARLEAKS_EDITORS=off in .env (.\tarleaks.ps1 editors
# off) switches them all off; an editor whose image is newer than the release
# (config\app-releases.tsv) is left out.
function Get-AppEditorsState {
  if ($script:AppsEditors) { return $script:AppsEditors }
  $envFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
  if (Test-Path $envFile) {
    $l = Get-Content $envFile | Where-Object { $_ -match '^TARLEAKS_EDITORS=' } | Select-Object -Last 1
    if ($l -and (($l -replace '^TARLEAKS_EDITORS=', '').Trim() -eq 'off')) { return 'off' }
  }
  return 'on'
}

# The editors to run for a closure: "onlyoffice,drawio" (no leading comma).
function Get-AppAddonUnit([string] $Closure) {
  if ((Get-AppEditorsState) -eq 'off') { return '' }
  $have = @{}; foreach ($a in (Split-AppList $Closure)) { $have[$a] = $true }
  $late = @((Get-AppUnreleased).Keys)
  $units = [System.Collections.Generic.List[string]]::new()
  foreach ($r in Get-AppRow) {
    if ($r.Kind -ne 'addon' -or $late -contains $r.App -or $units.Contains($r.Unit)) { continue }
    foreach ($n in $r.Needs) { if ($have.ContainsKey($n)) { $units.Add($r.Unit); break } }
  }
  return ($units -join ',')
}

# The editors as compose profiles, with a leading comma, so writing
# COMPOSE_PROFILES from the app list adds them.
function Get-AppAddon([string] $Closure) {
  $u = Get-AppAddonUnit $Closure
  if ($u) { return ',' + $u } else { return '' }
}

# Where the editors answer, as .env keys: the address people's browsers use.
# Empty means "no such editor here",
# which the apps then say plainly. Recomputed on every start, so a changed
# TARLEAKS_URL is followed.
function Get-AppEditorSetting([string] $Closure, [string] $BaseUrl) {
  $u = @(Split-AppList (Get-AppAddonUnit $Closure))
  $b = $BaseUrl.TrimEnd('/')
  $office = ''; $draw = ''
  if ($u -contains 'onlyoffice') { $office = "$b/onlyoffice" }
  if ($u -contains 'drawio') { $draw = "$b/drawio/" }
  # The document editor's image: the release's own (Arabic fonts) from 1.2.0; a
  # release before that has none, so it keeps the stock Document Server.
  $officeImage = ''
  if ($script:AppsVersion -and (Test-OlderVersion $script:AppsVersion '1.2.0')) { $officeImage = 'onlyoffice/documentserver:9.4.0.1' }
  return [ordered]@{
    TARLEAKS_ONLYOFFICE_IMAGE = $officeImage
    TARLEAKS_ONLYOFFICE_URL = $office
    TARLEAKS_DRAWIO_URL = $draw
  }
}

# The last thing Docker said about a failed pull, on one line (no secrets: Docker
# prints image names, addresses and the error, never a password).
function Get-AppPullReason($Out) {
  $last = @($Out | ForEach-Object { "$_" -split "`r?`n" } | Where-Object { $_.Trim() }) | Select-Object -Last 1
  $t = ("$last" -replace '\s+', ' ').Trim()
  if ($t.Length -gt 300) { $t = $t.Substring(0, 300) }
  return $t
}

# Download the images for the services that will run, and turn the usual
# failures into a sentence with the fix. Returns $false after printing it.
function Invoke-AppPull([string] $Again) {
  # No download ($env:TARLEAKS_NO_DOWNLOAD = '1', set by -Offline): no download at all;
  # every image must already be here (.\tarleaks.ps1 load-bundle <folder>).
  if ($env:TARLEAKS_NO_DOWNLOAD -eq '1') {
    Write-Host 'Offline: using the images already on this computer (no download).'
    $missing = Get-AppMissingImage
    if ($null -eq $missing) { Write-Host '  [x]  Could not read the list of images from docker-compose.yml.' -ForegroundColor Red; return $false }
    # Images already here run only when this computer checked their signature (a signed bundle, an earlier download).
    if ($missing.Count -eq 0) { return (Confirm-ReleaseVerified $Again) }
    Write-Host 'Not on this computer:'
    $missing | ForEach-Object { Write-Host "  $_" }
    Write-Host "  [x]  Load the offline bundle for this release first (.\tarleaks.ps1 load-bundle <folder>), then run $Again -Offline again. See docs\faq.md, `"Can I install without internet?`"" -ForegroundColor Red
    return $false
  }
  # An .env from the private preview still names ghcr.io: move it (and the
  # images already here) to the licence-key registry first.
  Move-RegistryOffRetired
  # The licence key is the download password: sign Docker in first, so a
  # refused key says why before anything is downloaded.
  if (-not (Invoke-RegistryLogin $Again)) {
    $missing = Get-AppMissingImage
    if ($null -ne $missing -and $missing.Count -eq 0) { Write-Host '  [!]  Carrying on with the images already on this computer.' -ForegroundColor Yellow; return (Confirm-ReleaseVerified $Again) }
    return $false
  }
  # A dropped connection halfway through a download (a reset, a timeout, an
  # unexpected EOF from the registry or Docker Hub) is usually gone a few
  # seconds later, and Docker keeps the layers it already has: try again twice
  # before giving up. Refusals (licence, missing release, disk) are not retried.
  $tries = if ($env:TARLEAKS_PULL_TRIES) { [int]$env:TARLEAKS_PULL_TRIES } else { 3 }
  $wait = if ($env:TARLEAKS_PULL_WAIT) { [int]$env:TARLEAKS_PULL_WAIT } else { 10 }
  for ($try = 1; ; $try++) {
    $out = docker compose pull --quiet 2>&1
    # Downloaded: run nothing that Tarleaks did not sign (scripts\lib-signature.ps1).
    if ($LASTEXITCODE -eq 0) { return (Confirm-ReleaseImage $Again) }
    $text = "$out"
    $refused = $text -match 'unauthorized|denied|authentication required|manifest unknown|not found|no matching manifest|does not match the specified platform|no space left on device|x509|certificate|toomanyrequests|rate limit'
    $dropped = $text -match 'timeout|timed out|dial tcp|no such host|connection refused|connection reset|network is unreachable|EOF|TLS handshake|broken pipe|503 Service Unavailable|502 Bad Gateway'
    if ($try -ge $tries -or $refused -or -not $dropped) { break }
    Write-Host "  [!]  The download was interrupted ($(Get-AppPullReason $out)). Trying again in $wait seconds; what is already downloaded is kept." -ForegroundColor Yellow
    Start-Sleep -Seconds $wait
  }
  # The download failed, but every image may already be here (an offline
  # bundle was loaded): carry on with those.
  $missing = Get-AppMissingImage
  if ($null -ne $missing -and $missing.Count -eq 0) {
    Write-Host '  [!]  The download failed, but every image is already on this computer. Carrying on with those.' -ForegroundColor Yellow
    return (Confirm-ReleaseVerified $Again)
  }
  $log = "$out"
  $version = ''
  $envFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
  if (Test-Path $envFile) { $l = Get-Content $envFile | Where-Object { $_ -match '^TARLEAKS_VERSION=' } | Select-Object -Last 1; if ($l) { $version = $l.Substring(17) } }
  $regHost = Get-RegistryHost
  $msg = if ($log -match 'unauthorized|denied|authentication required') {
    if (Test-RegistryTakesLicence) { "The registry refused the download with this licence key. Check the licence (Settings, Licence, or .\tarleaks.ps1 status), then run $Again again; if it keeps failing, contact info@tarleaks.com." }
    else { "The registry $regHost refused the download. Sign Docker in to it the way that registry says (docker login $regHost), then run $Again again." }
  } elseif ($log -match 'no matching manifest|does not match the specified platform') {
    'An image is not published for this CPU. Tarleaks ERP runs on 64-bit Intel/AMD and 64-bit ARM, with Linux containers.'
  } elseif ($log -match 'manifest unknown|not found') {
    "Release $version has no image for one of the chosen apps. Check TARLEAKS_VERSION in .env (the release notes list the versions), or remove that app: .\tarleaks.ps1 apps remove <app>."
  } elseif ($log -match 'toomanyrequests|rate limit' -and $log.Contains($regHost)) {
    "The image registry is busy for this address (too many downloads in a minute). Wait a minute, then run $Again again."
  } elseif ($log -match 'toomanyrequests|rate limit') {
    "Docker Hub limits anonymous downloads and this address has reached the limit. Wait a few hours, or sign in with a free Docker account (docker login), then run $Again again."
  } elseif ($log -match 'no space left on device') {
    "The disk is full. Free space (docker system df; docker image prune), then run $Again again."
  } elseif ($log -match 'x509|certificate') {
    "A certificate was not accepted while downloading: a proxy is probably inspecting HTTPS. Ask your network team to exempt $regHost and Docker Hub, or set Docker Desktop's proxy (Settings, Resources, Proxies), then run $Again again."
  } elseif ($log -match 'timeout|dial tcp|no such host|connection refused|network is unreachable|EOF') {
    Write-Host "  Docker said: $(Get-AppPullReason $out)"
    "The computer could not reach the image registries. Allow outbound HTTPS to $regHost, tarleaks.com, registry-1.docker.io and production.cloudflare.docker.com, then run $Again again."
  } else {
    Write-Host $log
    "Downloading the images failed (see above). Check the internet connection and run $Again again."
  }
  Write-Host "  [x]  $msg" -ForegroundColor Red
  return $false
}
