# =============================================================================
# The Tarleaks release signature (R71). Dot-sourced by install.ps1 and
# tarleaks.ps1 through lib-apps.ps1 (Linux/macOS: scripts/lib-signature.sh).
# The same rules as lib-signature.sh; keep the two in step.
#
# No Tarleaks image runs here unless this computer checked it against the
# release key (config\sigstore\tarleaks-release.pub):
#
#   Confirm-ReleaseImage '<again>'    after `docker compose pull`: cosign checks
#                                     every Tarleaks image by the digest Docker
#                                     downloaded, then records it as checked
#   Register-SigLoadedImage $loaded   after a SIGNED offline bundle was loaded
#   Confirm-ReleaseVerified '<again>' before images already on this computer are
#                                     used: each must be recorded as checked
#
# The record (.tarleaks-verified) holds "<image> <image id>" lines. A refused
# signature stops the install or upgrade before anything starts.
# $env:TARLEAKS_ALLOW_UNSIGNED = '1' is the only way past, for images you built
# yourself. A release number older than $script:SigSignedFrom is not checked.
# cosign: the one on this computer when it is 2.4 or later, otherwise
# Sigstore's own cosign image.
# =============================================================================

$script:SigKitRoot = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $script:SigKitRoot 'docker-compose.yml'))) { $script:SigKitRoot = $PSScriptRoot }
$script:SigPub = Join-Path $script:SigKitRoot 'config/sigstore/tarleaks-release.pub'
$script:SigRoot = Join-Path $script:SigKitRoot 'config/sigstore/trusted_root.json'
$script:SigRecord = Join-Path $script:SigKitRoot '.tarleaks-verified'
# Sigstore's cosign image, multi-arch index digest (ghcr.io/sigstore/cosign/cosign:v3.1.4).
$script:SigCosignImage = if ($env:TARLEAKS_COSIGN_IMAGE) { $env:TARLEAKS_COSIGN_IMAGE } else { 'ghcr.io/sigstore/cosign/cosign:v3.1.4@sha256:0f06154836d2de34f887a5c273506d52ca43edaa1d9e53e6510fa78a48f69c2d' }
# The first release whose images are signed.
$script:SigSignedFrom = '1.2.0-rc.7'
# What cosign prints when an image really has no valid Tarleaks signature; any
# other failure (network, sign-in, a refused mount) means "not checked".
$script:SigVerdict = 'no signatures found|no matching signatures|signature verification failed|invalid signature|none of the verifiers verified|no matching attestations'

# Is release $A at least $B? 1.2.0-rc.7 < 1.2.0-rc.10 < 1.2.0 < 1.2.1.
function Test-SigAtLeast([string] $A, [string] $B) {
  function Split-SigVersion([string] $V) {
    $base, $pre = $V -split '-', 2
    $n = @(($base -split '\.') | ForEach-Object { [int64]("0$_" -replace '\D', '') })
    while ($n.Count -lt 3) { $n += 0 }
    $p = [int64]1000000000
    if ($pre) { $d = ($pre -replace '[^0-9.]', '').Trim('.'); $p = if ($d) { [int64](($d -split '\.')[0]) } else { 0 } }
    return @($n[0], $n[1], $n[2], $p)
  }
  $x = Split-SigVersion $A; $y = Split-SigVersion $B
  for ($i = 0; $i -lt 4; $i++) { if ($x[$i] -gt $y[$i]) { return $true }; if ($x[$i] -lt $y[$i]) { return $false } }
  return $true
}

# The release the images are for, and whether its images must be signed: every
# release from $SigSignedFrom on and anything that is not a release number.
function Get-SigVersion { if ($env:TARLEAKS_VERSION) { return $env:TARLEAKS_VERSION }; return (Get-RegistryEnvValue 'TARLEAKS_VERSION') }
function Test-SigNeeded([string] $Version) {
  if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$') { return $true }
  return (Test-SigAtLeast $Version $script:SigSignedFrom)
}

# The local cosign when it is 2.4 or later (its version), else $null.
function Get-SigLocalCosign {
  if (-not (Get-Command cosign -ErrorAction SilentlyContinue)) { return $null }
  $m = (& cosign version 2>$null) | Select-String '^GitVersion:\s*v?(\S+)' | Select-Object -First 1
  if (-not $m) { return $null }
  $v = $m.Matches[0].Groups[1].Value
  if ($v -match '^(0\.|1\.|2\.[0-3]\.)') { return $null }
  return $v
}

# cosign verify of image references (repository@sha256:...) with the release key
# (the messages of both attempts, with and without the kit's trust root).
# Returns @{ Ok = bool; Said = 'the last line cosign printed'; All = 'everything' }.
function Invoke-SigCosignVerify([string] $ConfigDir, [string[]] $Refs) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $local = Get-SigLocalCosign
    if ($local) {
      $common = @('verify', '--key', $script:SigPub, '--output', 'text')
      if ($local -match '^2\.') { $common += '--new-bundle-format' }
      $out = @(& cosign @common --trusted-root $script:SigRoot @Refs 2>&1)
      if ($LASTEXITCODE -ne 0) { $out += @(& cosign @common @Refs 2>&1) }
    } else {
      $run = @('run', '--rm', '--read-only', '--tmpfs', '/tmp', '-e', 'HOME=/tmp',
               '-v', "$(Split-Path $script:SigPub -Parent):/sigstore:ro")
      if (Get-Command id -ErrorAction SilentlyContinue) { $run += @('--user', "$(id -u):$(id -g)") }
      if ($ConfigDir -and (Test-Path -LiteralPath (Join-Path $ConfigDir 'config.json'))) { $run += @('-v', "${ConfigDir}:/docker:ro", '-e', 'DOCKER_CONFIG=/docker') }
      $common = @($script:SigCosignImage, 'verify', '--key', '/sigstore/tarleaks-release.pub', '--output', 'text')
      $out = @(& docker @run @common --trusted-root /sigstore/trusted_root.json @Refs 2>&1)
      if ($LASTEXITCODE -ne 0) { $out += @(& docker @run @common @Refs 2>&1) }
    }
    $ok = ($LASTEXITCODE -eq 0)
    $lines = @(@($out) | ForEach-Object { "$_" } | Where-Object { $_.Trim() })
    # cosign's verdict when either attempt gave one, else its last words.
    $said = "$($lines | Where-Object { $_ -match $script:SigVerdict } | Select-Object -Last 1)"
    if (-not $said) { $said = "$($lines | Select-Object -Last 1)" }
    if ($said.Length -gt 300) { $said = $said.Substring(0, 300) }
    return @{ Ok = $ok; Said = $said; All = ($lines -join "`n") }
  } finally { $ErrorActionPreference = $old }
}

# A registry sign-in the cosign container can read: the licence key for the
# Tarleaks registry, otherwise only this registry's entry of Docker's config.json.
function New-SigDockerConfig([string] $Dir) {
  $regHost = Get-RegistryHost
  $auth = $null
  if (Test-RegistryTakesLicence) {
    $key = Get-RegistryLicenceKey
    if (-not $key) { return }
    $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($script:RegistryUser):$key"))
  } else {
    $src = if ($env:DOCKER_CONFIG) { Join-Path $env:DOCKER_CONFIG 'config.json' } else { Join-Path $HOME '.docker/config.json' }
    if (-not (Test-Path -LiteralPath $src)) { return }
    try { $entry = (Get-Content -Raw -LiteralPath $src | ConvertFrom-Json).auths.$regHost } catch { return }
    if (-not $entry -or -not $entry.auth) { return }
    $auth = $entry.auth
  }
  $json = '{"auths":{"' + $regHost + '":{"auth":"' + $auth + '"}}}'
  [System.IO.File]::WriteAllText((Join-Path $Dir 'config.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
}

# The Tarleaks images the chosen services run, or $null when the list cannot be
# read or holds no Tarleaks image (the sign-in service always runs one: that is a
# registry setting the check does not read like docker compose, never "nothing to check").
function Get-SigTarleaksImage {
  $images = docker compose config --images 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Host '  [x]  Could not read the list of images from docker-compose.yml, so their Tarleaks signature cannot be checked.' -ForegroundColor Red; return $null }
  $reg = "$(Get-RegistryValue)/"
  $mine = @($images | Sort-Object -Unique | Where-Object { "$_".StartsWith($reg) })
  if (-not $mine.Count) { Write-Host "  [x]  None of the images docker-compose.yml runs comes from $reg (TARLEAKS_REGISTRY), so their Tarleaks signature cannot be checked. Check TARLEAKS_REGISTRY in .env (docker compose config --images lists what it runs)." -ForegroundColor Red; return $null }
  return ,$mine
}

# No download wanted: TARLEAKS_NO_DOWNLOAD=1, or an offline installation (TARLEAKS_OFFLINE true or sealed).
function Test-SigOffline {
  if ($env:TARLEAKS_NO_DOWNLOAD -eq '1') { return $true }
  $o = if ($env:TARLEAKS_OFFLINE) { $env:TARLEAKS_OFFLINE } else { Get-RegistryEnvValue 'TARLEAKS_OFFLINE' }
  return ($o -in 'true', 'sealed')
}
function Get-SigId([string] $Image) { $id = docker image inspect --format '{{.Id}}' $Image 2>$null; if ($LASTEXITCODE -ne 0) { return '' }; return "$id".Trim() }

# Record images as checked on this computer ("<image> <id>", the newest wins),
# through a file beside it. $false, with the fix, when it cannot be written:
# images checked but not recorded would be refused at the next start.
function Add-SigRecord([string[]] $Images) {
  $rec = [ordered]@{}
  $tmp = "$($script:SigRecord).new"
  try {
    if (Test-Path -LiteralPath $script:SigRecord) {
      foreach ($l in Get-Content -LiteralPath $script:SigRecord -ErrorAction Stop) { $p = "$l" -split ' ', 2; if ($p.Count -eq 2) { $rec[$p[0]] = $p[1] } }
    }
    foreach ($img in $Images) { $id = Get-SigId $img; if ($id) { $rec[$img] = $id } }
    $text = ($rec.Keys | ForEach-Object { "$_ $($rec[$_])" }) -join "`n"
    [System.IO.File]::WriteAllText($tmp, "$text`n", (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $script:SigRecord -Force -ErrorAction Stop
    return $true
  } catch {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Write-Host "  [x]  Could not write $($script:SigRecord) ($($_.Exception.Message)). Make sure your user may write to the kit folder, then run the command again." -ForegroundColor Red
    return $false
  }
}

# After load-bundle checked the bundle's signature and loaded it: its Tarleaks
# images (under both their names) count as checked.
function Register-SigLoadedImage([string[]] $LoadOutput) {
  $reg = Get-RegistryValue
  $imgs = @()
  foreach ($line in $LoadOutput) {
    if ("$line" -notmatch '^Loaded image: (.+/tarleaks-erp/(.+:.+))$') { continue }
    $imgs += $Matches[1].Trim(); $imgs += "$reg/$($Matches[2].Trim())"
  }
  if ($imgs.Count) { return (Add-SigRecord $imgs) }
  return $true
}

# Before images already on this computer are used: each Tarleaks image must be
# recorded as checked, with the same content (id) as then.
function Confirm-ReleaseVerified([string] $Again = '.\install.ps1') {
  if ($env:TARLEAKS_ALLOW_UNSIGNED -eq '1') { return $true }
  $version = Get-SigVersion
  if (-not (Test-SigNeeded $version)) { return $true }
  $images = Get-SigTarleaksImage
  if ($null -eq $images) { return $false }
  $lines = @(); if (Test-Path -LiteralPath $script:SigRecord) { $lines = @(Get-Content -LiteralPath $script:SigRecord) }
  $unchecked = @(); $missing = @()
  foreach ($img in $images) {
    $id = Get-SigId $img
    if (-not $id) { $missing += $img } elseif ($lines -cnotcontains "$img $id") { $unchecked += $img }
  }
  if (-not $unchecked.Count -and -not $missing.Count) { return $true }
  # Here but never checked here (a kit older than the check downloaded them, or
  # the record was lost): with internet, check them now, as after a download.
  if ($unchecked.Count -and -not $missing.Count -and -not (Test-SigOffline)) {
    Write-Host "$($unchecked.Count) images on this computer were not checked for the Tarleaks signature yet: checking them now."
    # A local cosign reads the registry sign-in from Docker's own: sign in first, as a download would.
    if ((Get-Command Invoke-RegistryLogin -ErrorAction SilentlyContinue) -and -not (Invoke-RegistryLogin $Again)) {
      Write-Host "  Nothing was started with them. Without internet, load the signed offline bundle (.\tarleaks.ps1 load-bundle <folder>), then run $Again again. (Images you built yourself: `$env:TARLEAKS_ALLOW_UNSIGNED = '1', then $Again)"
      return $false
    }
    return (Confirm-ReleaseImage $Again)
  }
  if ($unchecked.Count) { Write-Host '  [x]  These images were not checked for the Tarleaks signature on this computer:' -ForegroundColor Red; $unchecked | ForEach-Object { Write-Host "  $_" } }
  if ($missing.Count) { Write-Host '  [x]  These images are not on this computer:' -ForegroundColor Red; $missing | ForEach-Object { Write-Host "  $_" } }
  Write-Host "  Nothing was started with them. With internet, run .\tarleaks.ps1 upgrade $(if ($version) { $version } else { '<release>' }): it downloads and checks them. Without internet, load the signed offline bundle (.\tarleaks.ps1 load-bundle <folder>), then run $Again again. (Images you built yourself: `$env:TARLEAKS_ALLOW_UNSIGNED = '1', then $Again)"
  return $false
}

# After a download: every Tarleaks image must carry the release signature.
function Confirm-ReleaseImage([string] $Again = '.\install.ps1') {
  $version = Get-SigVersion
  if ($env:TARLEAKS_ALLOW_UNSIGNED -eq '1') {
    Write-Host '  [!]  The images'' Tarleaks signature was NOT checked (TARLEAKS_ALLOW_UNSIGNED=1). Use this only for images you built or copied yourself.' -ForegroundColor Yellow
    return $true
  }
  if (-not (Test-SigNeeded $version)) {
    Write-Host "Release $version was published before Tarleaks signed its images: no signature to check."
    return $true
  }
  if (-not (Test-Path -LiteralPath $script:SigPub)) {
    Write-Host "  [x]  $($script:SigPub) is missing from this kit, so the images cannot be checked. Update the kit (git pull, or download it again), then run $Again again." -ForegroundColor Red
    return $false
  }
  $images = Get-SigTarleaksImage
  if ($null -eq $images) { return $false }
  $pairs = @(); $unpinned = @()
  foreach ($img in $images) {
    $repo = $img.Substring(0, $img.LastIndexOf(':'))
    $ref = @(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' $img 2>$null | Where-Object { "$_".StartsWith("$repo@") } | Select-Object -First 1)
    if ($ref.Count) { $pairs += @{ Image = $img; Ref = "$($ref[0])".Trim() } } else { $unpinned += $img }
  }
  if ($unpinned.Count) {
    Write-Host '  [x]  These images have no download record, so their Tarleaks signature cannot be checked:' -ForegroundColor Red
    $unpinned | ForEach-Object { Write-Host "  $_" }
    Write-Host "  Remove them (docker image rm <image>), then download and check them: .\tarleaks.ps1 upgrade $(if ($version) { $version } else { '<release>' }) (or load the signed offline bundle: .\tarleaks.ps1 load-bundle <folder>). (Images you built yourself: `$env:TARLEAKS_ALLOW_UNSIGNED = '1', then $Again)"
    return $false
  }
  if (-not $pairs.Count) { return $true }
  if (-not (Get-SigLocalCosign)) {
    docker image inspect $script:SigCosignImage *> $null
    if ($LASTEXITCODE -ne 0) { docker pull -q $script:SigCosignImage *> $null }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  [x]  The images' Tarleaks signature must be checked, and that needs cosign: this computer has no cosign 2.4 or later, and Docker could not download Sigstore's cosign image from ghcr.io. Install cosign (winget install sigstore.cosign), or allow outbound HTTPS to ghcr.io and pkg-containers.githubusercontent.com, then run $Again again." -ForegroundColor Red
      return $false
    }
  }
  $cfg = Join-Path ([System.IO.Path]::GetTempPath()) ("tarleaks-sig-" + [guid]::NewGuid().ToString('N'))
  $unsigned = @(); $unchecked = @()
  try {
    New-Item -ItemType Directory -Path $cfg | Out-Null
    # Only Sigstore's cosign image needs a sign-in file; a local cosign uses Docker's own.
    if (-not (Get-SigLocalCosign)) { New-SigDockerConfig $cfg }
    Write-Host "Checking the Tarleaks signature of $($pairs.Count) images..."
    # One cosign run for all of them; only when it fails, one per image, each with its own messages.
    $r = Invoke-SigCosignVerify $cfg @($pairs | ForEach-Object { $_.Ref })
    if (-not $r.Ok) {
      foreach ($p in $pairs) {
        $one = Invoke-SigCosignVerify $cfg @($p.Ref)
        if ($one.Ok) { continue }
        $item = @{ Image = $p.Image; Ref = $p.Ref; Said = $one.Said }
        if ($one.All -match $script:SigVerdict) { $unsigned += $item } else { $unchecked += $item }
      }
    }
  } finally { Remove-Item -LiteralPath $cfg -Recurse -Force -ErrorAction SilentlyContinue }
  if ($unsigned.Count) {
    Write-Host '  [x]  These images are NOT signed by Tarleaks:' -ForegroundColor Red
    $unsigned | ForEach-Object { Write-Host "  $($_.Ref)" }
    Write-Host "  cosign said: $($unsigned[0].Said)"
    # Remove them: no later run may take them as already downloaded.
    $kept = @(); foreach ($u in $unsigned) { docker image rm $u.Image *> $null; if ($LASTEXITCODE -ne 0) { $kept += $u.Image } }
    if (-not $kept.Count) { Write-Host "  They were removed and nothing was started with them. Do not use them: tell info@tarleaks.com what happened. (Images you built yourself: `$env:TARLEAKS_ALLOW_UNSIGNED = '1', then $Again)" }
    else { Write-Host "  Nothing was started with them. Docker could not remove $($kept -join ' ') (a container still uses it: docker ps -a); remove it with docker image rm. Do not use them: tell info@tarleaks.com what happened. (Images you built yourself: `$env:TARLEAKS_ALLOW_UNSIGNED = '1', then $Again)" }
  }
  if ($unchecked.Count) {
    Write-Host '  [x]  The Tarleaks signature of these images could not be checked:' -ForegroundColor Red
    $unchecked | ForEach-Object { Write-Host "  $($_.Ref)" }
    Write-Host "  cosign said: $($unchecked[0].Said)"
    Write-Host "  Nothing was started with them, and nothing was removed. Fix what cosign names (usually the connection to $(Get-RegistryHost), or ghcr.io when this computer has no cosign; a refused sign-in: check the licence), then run $Again again. Without internet, load the signed offline bundle (.\tarleaks.ps1 load-bundle <folder>)."
  }
  if ($unsigned.Count -or $unchecked.Count) { return $false }
  if (-not (Add-SigRecord @($pairs | ForEach-Object { $_.Image }))) { return $false }
  $hash = (Get-FileHash -LiteralPath $script:SigPub -Algorithm SHA256).Hash.ToLowerInvariant().Substring(0, 12)
  Write-Host "  [ok] Every Tarleaks image is signed by Tarleaks (release key $hash)." -ForegroundColor Green
  return $true
}
