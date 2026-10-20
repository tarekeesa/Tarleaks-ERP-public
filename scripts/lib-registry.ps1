# =============================================================================
# Signing Docker in to the Tarleaks image registry with the licence key.
# Dot-sourced by scripts/lib-apps.ps1 (so by install.ps1 and tarleaks.ps1);
# Linux/macOS: scripts/lib-registry.sh. The same rules; keep the two in step.
#
# The images are at registry.tarleaks.com/tarleaks-erp/<unit>:<version>. The
# user name is `licence` and the password is the licence key, so nobody types
# `docker login`: every download signs in first, with the key from
#   1. TARLEAKS_LICENSE_KEY in .env (or the older NEXUS_LICENSE_KEY),
#   2. the key the installation holds in its database (setup screen or
#      Settings, Licence), when the database is running,
#   3. TARLEAKS_DOWNLOAD_KEY in .env: the trial the installer started.
# The key goes to Docker on stdin and to curl in a config file in your own
# temp folder: never on a command line, never printed. A registry you run yourself is left alone.
# =============================================================================

$script:RegistryDefault = 'registry.tarleaks.com/tarleaks-erp'
# The private-preview location (1.0.x): the same images behind a personal
# GitHub token. An .env that still names it is moved to the default.
$script:RegistryRetired = 'ghcr.io/tarekeesa/tarleaks-erp'
$script:RegistryLicenceHosts = @('registry.tarleaks.com')
$script:RegistryUser = 'licence'
$script:RegistrySignedIn = ''
$script:RegistryKitRoot = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $script:RegistryKitRoot 'docker-compose.yml'))) { $script:RegistryKitRoot = $PSScriptRoot }

function Get-RegistryEnvFile { return (Join-Path $script:RegistryKitRoot '.env') }

function Get-RegistryEnvValue([string] $Key) {
  $f = Get-RegistryEnvFile
  if (-not (Test-Path $f)) { return '' }
  $l = Get-Content $f | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -Last 1
  if ($l) { return $l.Substring($Key.Length + 1) } else { return '' }
}

function Set-RegistryEnvValue([string] $Key, [string] $Value) {
  $f = Get-RegistryEnvFile
  $lines = [System.Collections.Generic.List[string]]::new([string[]](Get-Content $f))
  $done = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^$([regex]::Escape($Key))=") { $lines[$i] = "$Key=$Value"; $done = $true; break }
  }
  if (-not $done) { $lines.Add("$Key=$Value") }
  # UTF-8 without a byte-order mark, LF endings: what Docker Compose reads.
  [System.IO.File]::WriteAllText($f, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

function Get-RegistryValue {
  # The session's value wins over .env, exactly as for docker compose.
  $v = [Environment]::GetEnvironmentVariable('TARLEAKS_REGISTRY', 'Process')
  if (-not $v) { $v = Get-RegistryEnvValue 'TARLEAKS_REGISTRY' }
  $v = "$v".Trim().TrimEnd('/')
  if ($v) { return $v } else { return $script:RegistryDefault }
}

function Get-RegistryHost { return ((Get-RegistryValue) -split '/')[0] }

function Test-RegistryTakesLicence {
  $extra = @("$env:TARLEAKS_REGISTRY_LICENCE_HOSTS" -split '\s+' | Where-Object { $_ })
  return (@($script:RegistryLicenceHosts + $extra) -contains (Get-RegistryHost))
}

function Test-LicenceKeyShape([string] $Key) {
  return ($Key -match '^(tlk1|nxs1)\.[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$')
}

function Get-RegistryLicenceKey {
  $k = Get-RegistryEnvValue 'TARLEAKS_LICENSE_KEY'
  if (-not $k) { $k = Get-RegistryEnvValue 'NEXUS_LICENSE_KEY' }
  if (-not $k -and (Get-Command docker -ErrorAction SilentlyContinue)) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
      $running = @(docker compose ps --status running --services 2>$null)
      if ($running -contains 'postgres') {
        $user = Get-RegistryEnvValue 'POSTGRES_USER'; if (-not $user) { $user = 'tarleaks' }
        $db = Get-RegistryEnvValue 'POSTGRES_DB'; if (-not $db) { $db = 'tarleaks' }
        $k = "$(docker compose exec -T postgres psql -X -q -At -U $user -d $db -c 'SELECT token FROM auth.installation_state WHERE id AND token IS NOT NULL' 2>$null | Select-Object -First 1)".Trim()
        if ($LASTEXITCODE -ne 0) { $k = '' }
      }
    } finally { $ErrorActionPreference = $old }
  }
  if (-not $k) { $k = Get-RegistryEnvValue 'TARLEAKS_DOWNLOAD_KEY' }
  return "$k".Trim()
}

# Ask the registry's sign-in service directly: its refusal is a sentence that
# `docker login` would bury. 0 accepted, 1 refused (message printed), 2 could
# not ask (no curl.exe, no answer).
function Test-RegistryKey([string] $RegHost, [string] $Key) {
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (-not $curl) { return 2 }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $hdr = & $curl.Source -sS -I --max-time 15 "https://$RegHost/v2/" 2>$null
    if ($LASTEXITCODE -ne 0) { return 2 }
    $auth = $hdr | Where-Object { $_ -match '^www-authenticate:\s*Bearer\s' } | Select-Object -First 1
    if (-not $auth -or $auth -notmatch 'realm="(https://[^"]+)"') { return 2 }
    $realm = $Matches[1]
    $service = if ($auth -match 'service="([^"]+)"') { $Matches[1] } else { $RegHost }
    $body = [System.IO.Path]::GetTempFileName()
    # The key travels in a curl config file in your own temp folder (deleted at
    # once), never on the command line, where other users could read it.
    $cfg = [System.IO.Path]::GetTempFileName()
    try {
      [System.IO.File]::WriteAllText($cfg, "user = `"$($script:RegistryUser):$Key`"`n", (New-Object System.Text.UTF8Encoding($false)))
      $code = & $curl.Source -sS -K $cfg -G --max-time 20 -o $body -w '%{http_code}' --data-urlencode "service=$service" $realm 2>$null
      if ($LASTEXITCODE -ne 0) { $code = '000' }
    } finally { Remove-Item $cfg -ErrorAction SilentlyContinue }
    $msg = ''
    try { $j = Get-Content $body -Raw | ConvertFrom-Json; $msg = "$($j.error_description)" } catch { $msg = '' }
    Remove-Item $body -ErrorAction SilentlyContinue
    switch -Regex ("$code") {
      '^200$' { return 0 }
      '^000$' { return 2 }
      '^429$' { Write-Host "  [x]  The image registry is busy for this address: $(if ($msg) { $msg } else { 'too many sign-ins' }). Wait a minute and run it again." -ForegroundColor Red; return 1 }
      '^5' { Write-Host "  [x]  The image registry cannot check licence keys right now$(if ($msg) { ": $msg" }). Try again in a few minutes; if it lasts, contact info@tarleaks.com." -ForegroundColor Red; return 1 }
      default { Write-Host "  [x]  The image registry did not accept the licence key: $(if ($msg) { $msg } else { "it was refused (HTTP $code)" })" -ForegroundColor Red; return 1 }
    }
  } finally { $ErrorActionPreference = $old }
}

# The tags of registry.tarleaks.com/tarleaks-erp/<Unit>: the releases
# .\tarleaks.ps1 update can move to. A read token comes from the registry's
# sign-in service with the licence key (in a curl config file, never on a
# command line); $null when the list cannot be read (the reason is printed).
function Get-RegistryTag([string] $Unit) {
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (-not $curl -or -not (Test-RegistryTakesLicence)) { return $null }
  $regHost = Get-RegistryHost
  $repo = (Get-RegistryValue) -replace '^[^/]+/', ''
  $key = Get-RegistryLicenceKey
  if (-not (Test-LicenceKeyShape $key)) { Write-Host '  [x]  No usable licence key in .env or in the installation, so the list of releases cannot be read.' -ForegroundColor Red; return $null }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $cfg = [System.IO.Path]::GetTempFileName(); $body = [System.IO.Path]::GetTempFileName()
  try {
    $hdr = & $curl.Source -sS -I --max-time 15 "https://$regHost/v2/" 2>$null
    $auth = $hdr | Where-Object { $_ -match '^www-authenticate:\s*Bearer\s' } | Select-Object -First 1
    if (-not $auth -or $auth -notmatch 'realm="(https://[^"]+)"') { return $null }
    $realm = $Matches[1]
    $service = if ($auth -match 'service="([^"]+)"') { $Matches[1] } else { $regHost }
    [System.IO.File]::WriteAllText($cfg, "user = `"$($script:RegistryUser):$key`"`n", (New-Object System.Text.UTF8Encoding($false)))
    $code = & $curl.Source -sS -K $cfg -G --max-time 20 -o $body -w '%{http_code}' --data-urlencode "service=$service" --data-urlencode "scope=repository:$repo/${Unit}:pull" $realm 2>$null
    if ("$code" -ne '200') { Write-Host "  [x]  The image registry did not accept the licence key (HTTP $code), so the list of releases cannot be read." -ForegroundColor Red; return $null }
    $j = Get-Content $body -Raw | ConvertFrom-Json
    $tok = if ($j.token) { $j.token } else { $j.access_token }
    if (-not $tok) { return $null }
    [System.IO.File]::WriteAllText($cfg, "header = `"Authorization: Bearer $tok`"`n", (New-Object System.Text.UTF8Encoding($false)))
    $code = & $curl.Source -sS -K $cfg --max-time 20 -o $body -w '%{http_code}' "https://$regHost/v2/$repo/$Unit/tags/list?n=1000" 2>$null
    if ("$code" -ne '200') { Write-Host "  [x]  The image registry answered HTTP $code for the list of releases." -ForegroundColor Red; return $null }
    return @((Get-Content $body -Raw | ConvertFrom-Json).tags)
  } catch { return $null }
  finally {
    Remove-Item $cfg, $body -ErrorAction SilentlyContinue
    $ErrorActionPreference = $old
  }
}

# Sign Docker in; $false after printing what to do.
function Invoke-RegistryLogin([string] $Again = '.\install.ps1') {
  if ($env:TARLEAKS_NO_DOWNLOAD -eq '1') { return $true }
  if (-not (Test-RegistryTakesLicence)) { return $true }
  $regHost = Get-RegistryHost
  if ($script:RegistrySignedIn -eq $regHost) { return $true }
  $key = Get-RegistryLicenceKey
  if (-not $key) {
    Write-Host "  [x]  Downloading Tarleaks ERP needs a licence key: it is also the download password. Give it with .\install.ps1 -LicenceKey <key>, or start a free trial: .\install.ps1 -Trial you@yourcompany.com -Company `"Your company`" -AcceptTerms. Then run $Again again." -ForegroundColor Red
    return $false
  }
  if (-not (Test-LicenceKeyShape $key)) {
    Write-Host '  [x]  The licence key in .env (or in the installation) is damaged: it must be one line that starts with nxs1. or tlk1. Paste it again with .\install.ps1 -LicenceKey <key>.' -ForegroundColor Red
    return $false
  }
  if ((Test-RegistryKey $regHost $key) -eq 1) {
    Write-Host "  [x]  Nothing was downloaded. Fix the licence (Settings, Licence, or .\install.ps1 -LicenceKey <key>), then run $Again again." -ForegroundColor Red
    return $false
  }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $out = "$($key | docker login $regHost --username $script:RegistryUser --password-stdin 2>&1)"
    $failed = ($LASTEXITCODE -ne 0)
  } finally { $ErrorActionPreference = $old }
  if ($failed) {
    $msg = if ($out -match 'timeout|dial tcp|no such host|connection refused|network is unreachable|EOF') {
      "Docker could not reach $regHost. Allow outbound HTTPS to $regHost and tarleaks.com (behind a proxy: Docker Desktop, Settings, Resources, Proxies), then run $Again again."
    } elseif ($out -match 'x509|certificate') {
      "Docker did not accept the certificate of ${regHost}: a proxy is probably inspecting HTTPS. Ask your network team to exempt $regHost and tarleaks.com, then run $Again again."
    } else {
      Write-Host $out
      "Docker could not sign in to $regHost with the licence key (above). Run $Again again; if it keeps failing, send this message to info@tarleaks.com."
    }
    Write-Host "  [x]  $msg" -ForegroundColor Red
    return $false
  }
  $script:RegistrySignedIn = $regHost
  return $true
}

# A trial key from tarleaks.com; $null after printing why not.
function Start-RegistryTrial([string] $Company, [string] $Email) {
  $vendor = Get-RegistryEnvValue 'TARLEAKS_VENDOR_URL'
  if (-not $vendor) { $vendor = 'https://tarleaks.com' }
  $vendor = $vendor.TrimEnd('/')
  # Only for the vendor's records until the installation itself checks in: its
  # first check-in moves the trial to the installation's own identity.
  $b = New-Object byte[] 16
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  $fp = -join ($b | ForEach-Object { $_.ToString('x2') })
  $body = @{
    company      = $Company
    email        = $Email
    fingerprint  = $fp
    version      = (Get-RegistryEnvValue 'TARLEAKS_VERSION')
    arch         = "$env:PROCESSOR_ARCHITECTURE"
    accept_terms = $true
  } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Method Post -Uri "$vendor/api/activation/trial" -ContentType 'application/json' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30
    return "$($r.token)"
  } catch {
    $msg = ''
    try { $msg = "$((($_.ErrorDetails.Message) | ConvertFrom-Json).error.message)" } catch { $msg = '' }
    if ($msg) { Write-Host "  [x]  The trial was not started: $msg" -ForegroundColor Red }
    else { Write-Host "  [x]  Could not reach $vendor to start the trial. Allow outbound HTTPS to tarleaks.com, or ask info@tarleaks.com for a licence key." -ForegroundColor Red }
    return $null
  }
}

# The images already here under the retired name get the new name too, so
# nothing is downloaded again and an installation without internet still starts.
function Copy-RegistryRetiredTag {
  $n = 0
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $imgs = @(docker images --format '{{.Repository}}:{{.Tag}}' 2>$null | Where-Object { $_.StartsWith("$script:RegistryRetired/") -and $_ -notmatch ':<none>$' })
    foreach ($img in $imgs) {
      docker tag $img ("$script:RegistryDefault/" + $img.Substring($script:RegistryRetired.Length + 1)) 2>$null
      if ($LASTEXITCODE -eq 0) { $n++ }
    }
  } finally { $ErrorActionPreference = $old }
  return $n
}

# .env still names the private-preview registry: switch it (in the file).
function Move-RegistryOffRetired {
  if ((Get-RegistryEnvValue 'TARLEAKS_REGISTRY').Trim().TrimEnd('/') -ne $script:RegistryRetired) { return }
  # TARLEAKS_REGISTRY_KEEP=1 keeps the address as written (a test machine that
  # reads the private-preview location with its own sign-in).
  $keep = $env:TARLEAKS_REGISTRY_KEEP
  if (-not $keep) { $keep = Get-RegistryEnvValue 'TARLEAKS_REGISTRY_KEEP' }
  if ("$keep".Trim() -eq '1') { return }
  Set-RegistryEnvValue 'TARLEAKS_REGISTRY' $script:RegistryDefault
  $n = Copy-RegistryRetiredTag
  $note = if ($n -gt 0) { "; $n image name(s) here moved over" } else { '' }
  Write-Host "  [ok] Images now come from $script:RegistryDefault, signed in with the licence key (no docker login any more)$note." -ForegroundColor Green
}

# The output of `docker load`: tag each Tarleaks image under TARLEAKS_REGISTRY.
function Register-RegistryLoadedImage([string[]] $LoadOutput) {
  $reg = Get-RegistryValue
  $n = 0
  foreach ($line in $LoadOutput) {
    if ("$line" -notmatch '^Loaded image: (.+/tarleaks-erp/(.+:.+))$') { continue }
    $img = $Matches[1]; $rest = $Matches[2]
    if ($img -eq "$reg/$rest") { continue }
    docker tag $img "$reg/$rest"
    if ($LASTEXITCODE -eq 0) { $n++ }
  }
  if ($n -gt 0) { Write-Host "  [ok] Named $n image(s) for $reg (TARLEAKS_REGISTRY)." -ForegroundColor Green }
}
