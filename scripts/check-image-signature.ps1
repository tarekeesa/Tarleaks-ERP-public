# No Tarleaks image runs unless this computer checked it against the release key (scripts\lib-signature.ps1):
#  - after a download (Confirm-ReleaseImage, run by Invoke-AppPull and .\tarleaks.ps1 upgrade): a signed set passes and
#    is recorded; an image cosign calls unsigned is refused, named and removed; any other cosign failure (network, a
#    refused sign-in) refuses WITHOUT removing; each failing image gets its own message, wherever it is in the list;
#  - images already here (Confirm-ReleaseVerified: no download, a failed download or sign-in, start, restart): each must
#    be recorded with the same image id; unrecorded, changed or missing images are refused;
#  - a signed offline bundle's images are recorded (Register-SigLoadedImage);
#  - a kit without the public key, an image with no download digest, an unreadable compose file all refuse;
#    TARLEAKS_ALLOW_UNSIGNED=1 and an older release number pass without cosign; latest/empty are checked;
#  - without a usable cosign, Sigstore's pinned image runs read-only with only the key folder and a licence-key
#    sign-in mounted, removed afterwards; without that image either, it refuses with the fix.
# docker and cosign are stubs (functions, no network): a stub signature is a line "<repository@digest> <release key>".
# The same checks for ./tarleaks: scripts/check-image-signature.sh. CI runs it.
#   ./scripts/check-image-signature.ps1
$ErrorActionPreference = 'Stop'
$kitSrc = Split-Path $PSScriptRoot -Parent
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("tl-imgsig-" + [guid]::NewGuid().ToString('N'))
$kit = Join-Path $work 'kit'
New-Item -ItemType Directory -Path $kit -Force | Out-Null
Get-ChildItem -LiteralPath $kitSrc -Force | Where-Object { $_.Name -notin '.git', '.tarleaks-verified', '.env' } |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $kit -Recurse -Force }
$Key = 'release-key-under-test'
$Reg = 'registry.tarleaks.com/tarleaks-erp'
$pubFile = Join-Path $kit 'config/sigstore/tarleaks-release.pub'
$record = Join-Path $kit '.tarleaks-verified'
. (Join-Path $kit 'scripts/lib-apps.ps1')
function Invoke-RegistryLogin([string] $Again) { return (-not $script:LoginFails) }
function Move-RegistryOffRetired { }

$script:calls = @(); $script:images = @(); $script:digests = @{}; $script:ids = @{}; $script:signed = @()
$script:CosignVersion = '3.1.4'; $script:NetDownFor = @(); $script:UnauthFor = @(); $script:CosignImageHere = $false
$script:PullOk = $true; $script:ComposeFails = $false; $script:PullFails = $false; $script:LoginFails = $false
$script:seenConfig = $null

function Invoke-StubVerify([object[]] $A, [string] $KeyDir) {
  $k = $null; $refs = @(); $i = 0
  while ($i -lt $A.Count) {
    $t = [string] $A[$i]
    if ($t -eq '--key') { $k = $A[$i + 1]; if ($KeyDir) { $k = $k -replace '^/sigstore', $KeyDir }; $i += 2 }
    elseif ($t -in '--trusted-root', '--output') { $i += 2 }
    elseif ($t -eq '--new-bundle-format') { $i += 1 }
    else { $refs += $t; $i += 1 }
  }
  $kv = (Get-Content -Raw -LiteralPath $k).Trim()
  foreach ($r in $refs) {
    if ($script:NetDownFor -contains 'all' -or $script:NetDownFor -contains $r) { $global:LASTEXITCODE = 1; return 'Error: GET https://registry.tarleaks.com/v2/: dial tcp: i/o timeout' }
    if ($script:UnauthFor -contains $r) { $global:LASTEXITCODE = 1; return 'Error: GET https://registry.tarleaks.com/v2/x/manifests/sha256-y.sig: UNAUTHORIZED: authentication required' }
    if ($script:signed -notcontains "$r $kv") { $global:LASTEXITCODE = 1; return "Error: no matching signatures: $r" }
  }
  $global:LASTEXITCODE = 0; 'Verified OK'
}
function cosign {
  $script:calls += 'cosign ' + ($args -join ' ')
  if ($args[0] -eq 'version') { "GitVersion:    v$script:CosignVersion"; $global:LASTEXITCODE = 0; return }
  $rest = [object[]]@($args | Select-Object -Skip 1)
  Invoke-StubVerify -A $rest -KeyDir ''
}
function docker {
  $script:calls += 'docker ' + ($args -join ' ')
  $a = @($args); $global:LASTEXITCODE = 0
  if ($a[0] -eq 'compose' -and $a[1] -eq 'config') { if ($script:ComposeFails) { $global:LASTEXITCODE = 1; return }; return $script:images }
  if ($a[0] -eq 'compose' -and $a[1] -eq 'pull') { if ($script:PullFails) { $global:LASTEXITCODE = 1; return 'Get https://registry.tarleaks.com/v2/: dial tcp 1.2.3.4:443: i/o timeout' }; return }
  if ($a[0] -eq 'compose') { return }
  if ($a[0] -eq 'image' -and $a[1] -eq 'inspect') {
    $img = [string] $a[-1]
    if ($a[2] -eq '--format' -and "$($a[3])" -match 'RepoDigests') { return @($script:digests[$img]) | Where-Object { $_ } }
    if ($a[2] -eq '--format') { if ($script:ids.ContainsKey($img)) { return $script:ids[$img] }; $global:LASTEXITCODE = 1; return }
    if ($img.StartsWith('ghcr.io/sigstore/')) { $global:LASTEXITCODE = $(if ($script:CosignImageHere) { 0 } else { 1 }); return }
    if (-not $script:ids.ContainsKey($img)) { $global:LASTEXITCODE = 1 }
    return
  }
  if ($a[0] -eq 'image' -and $a[1] -eq 'rm') { if ($script:RmFails) { $global:LASTEXITCODE = 1 }; return }
  if ($a[0] -eq 'pull') { $global:LASTEXITCODE = $(if ($script:PullOk) { 0 } else { 1 }); return }
  if ($a[0] -eq 'run') {
    $keyDir = $null; $i = 1
    while ($i -lt $a.Count -and -not "$($a[$i])".StartsWith('ghcr.io/sigstore/')) {
      if ($a[$i] -eq '-v') {
        $m = [string] $a[$i + 1]
        if ($m.EndsWith(':/sigstore:ro')) { $keyDir = $m.Substring(0, $m.Length - ':/sigstore:ro'.Length) }
        if ($m.EndsWith(':/docker:ro')) { $script:seenConfig = Get-Content -Raw -LiteralPath (Join-Path $m.Substring(0, $m.Length - ':/docker:ro'.Length) 'config.json') }
        $i += 2
      } elseif ($a[$i] -in '--rm', '--read-only') { $i += 1 } else { $i += 2 }
    }
    $rest = [object[]]@($a | Select-Object -Skip ($i + 2))
    return (Invoke-StubVerify -A $rest -KeyDir $keyDir)
  }
}

function Reset-Stub {
  $script:images = @('redis:7.4.12-alpine'); $script:digests = @{}; $script:ids = @{ 'redis:7.4.12-alpine' = 'sha256:id-redis' }
  $script:signed = @(); $script:seenConfig = $null; $script:NetDownFor = @(); $script:UnauthFor = @()
  $script:PullOk = $true; $script:CosignVersion = '3.1.4'; $script:ComposeFails = $false; $script:PullFails = $false; $script:LoginFails = $false
  $script:RmFails = $false
  Remove-Item -LiteralPath $record -Force -ErrorAction SilentlyContinue
  Set-Content -LiteralPath (Join-Path $kit '.env') -Value "TARLEAKS_VERSION=1.2.0`nTARLEAKS_LICENSE_KEY=tlk1.test-licence-key"
}
function Add-Image([string] $Unit, [string] $Digest, [string] $SignedWith) {
  $img = "${Reg}/${Unit}:1.2.0"; $script:images += $img; $script:digests[$img] = "${Reg}/${Unit}@sha256:$Digest"
  $script:ids[$img] = "sha256:id-$Digest"
  if ($SignedWith) { $script:signed += "${Reg}/${Unit}@sha256:$Digest $SignedWith" }
}

$fails = 0; $script:lastOut = ''
function Check([string] $Name, [bool] $Want, [string] $Text, [scriptblock] $Run = { Confirm-ReleaseImage '.\install.ps1' }) {
  $script:calls = @()
  $r = @(& $Run 6>&1)
  $got = @($r | Where-Object { $_ -is [bool] })[-1]
  $out = ($r | Where-Object { $_ -isnot [bool] } | ForEach-Object { "$_" }) -join "`n"
  $script:lastOut = $out
  if ($got -eq $Want -and $out.Contains($Text)) { Write-Host "ok   $Name" }
  else { Write-Host "FAIL ${Name}: got $got (want $Want), output:"; $out -split "`n" | ForEach-Object { Write-Host "    $_" }; $script:fails++ }
}
function Assert([string] $Name, [bool] $Cond) { if ($Cond) { Write-Host "ok   $Name" } else { Write-Host "FAIL $Name"; $script:fails++ } }
function Get-Record { if (Test-Path -LiteralPath $record) { return @(Get-Content -LiteralPath $record) }; return @() }
$require = { Confirm-ReleaseVerified '.\install.ps1' }
$pull = { Invoke-AppPull '.\install.ps1' }

Push-Location $kit
try {
  Set-Content -LiteralPath $pubFile -Value $Key
  # --- after a download ---
  Reset-Stub; Add-Image auth aaa1 $Key; Add-Image hr bbb2 $Key
  Check 'every image signed with the release key passes' $true 'Every Tarleaks image is signed by Tarleaks'
  Assert 'one cosign run checks them all, the trust root first' (@($script:calls | Where-Object { $_ -match "^cosign verify .*--trusted-root .*$([regex]::Escape("$Reg/auth@sha256:aaa1 $Reg/hr@sha256:bbb2"))" }).Count -eq 1)
  Assert 'third-party images are not sent to cosign' (-not ($script:calls -match '^cosign verify.*redis'))
  Assert '  ...and both are recorded as checked, with their image ids' ((Get-Record) -contains "$Reg/auth:1.2.0 sha256:id-aaa1" -and (Get-Record) -contains "$Reg/hr:1.2.0 sha256:id-bbb2")

  Reset-Stub; Add-Image auth aaa1 ''; Add-Image hr bbb2 $Key
  Check 'an unsigned image FIRST in the list is refused and named' $false "$Reg/auth@sha256:aaa1"
  Assert '  ...with its own cosign message, not the last image''s' ($script:lastOut.Contains("cosign said: Error: no matching signatures: $Reg/auth@sha256:aaa1"))
  Assert 'the unsigned image is removed' ([bool]($script:calls -match "^docker image rm $([regex]::Escape("$Reg/auth:1.2.0"))"))
  Assert 'the signed one is kept' (-not ($script:calls -match '^docker image rm .*hr'))
  Assert 'nothing is recorded after a refusal' ((Get-Record).Count -eq 0)

  Reset-Stub; Add-Image auth aaa1 'someone-else''s-key'
  Check 'an image signed with another key is refused' $false 'NOT signed by Tarleaks'

  Reset-Stub; Add-Image auth aaa1 $Key; $script:NetDownFor = @('all')
  Check 'a network failure refuses without removing anything' $false 'could not be checked'
  Assert '  ...nothing removed' (-not ($script:calls -match 'image rm'))

  Reset-Stub; Add-Image auth aaa1 $Key; Add-Image hr bbb2 $Key; $script:UnauthFor = @("$Reg/auth@sha256:aaa1")
  Check 'a refused sign-in is "not checked", never "unsigned"' $false 'could not be checked'
  Assert '  ...in cosign''s own words' ($script:lastOut.Contains('UNAUTHORIZED') -and -not $script:lastOut.Contains('NOT signed'))
  Assert '  ...nothing removed' (-not ($script:calls -match 'image rm'))

  Reset-Stub; Add-Image auth aaa1 $Key; Add-Image hr bbb2 ''; $script:NetDownFor = @("$Reg/auth@sha256:aaa1")
  Check 'a network failure on one image and an unsigned other are both named, each for what it is' $false 'NOT signed by Tarleaks'
  Assert '  ...the first not checked and kept, the second removed' ($script:lastOut.Contains('could not be checked') -and [bool]($script:calls -match "^docker image rm $([regex]::Escape("$Reg/hr:1.2.0"))") -and -not ($script:calls -match '^docker image rm .*auth'))

  Reset-Stub; Add-Image auth aaa1 ''; $script:RmFails = $true
  Check 'an unsigned image Docker cannot remove (in use) is refused and says so' $false "Docker could not remove $Reg/auth:1.2.0"
  Assert '  ...never "They were removed"' (-not $script:lastOut.Contains('They were removed'))
  # docker compose reads .env values without quotes: so does the check, which must never find "no Tarleaks image" and pass.
  Reset-Stub; Add-Image auth aaa1 ''
  Set-Content -LiteralPath (Join-Path $kit '.env') -Value "TARLEAKS_VERSION=1.2.0`nTARLEAKS_REGISTRY=`"$Reg`"`nTARLEAKS_LICENSE_KEY=tlk1.test-licence-key"
  Check 'a quoted TARLEAKS_REGISTRY still checks (an unsigned image is refused)' $false 'NOT signed by Tarleaks'
  Reset-Stub; $script:images += 'other.example.com/erp/auth:1.2.0'
  Check 'a compose file with no image from the registry refuses (it never passes unchecked)' $false "None of the images docker-compose.yml runs comes from $Reg/"
  Check '  ...also for images already here' $false 'None of the images' $require
  Reset-Stub; Add-Image auth aaa1 $Key; $script:digests.Clear()
  Check 'an image with no download digest is refused' $false 'no download record'

  Reset-Stub; Add-Image auth aaa1 $Key; $script:ComposeFails = $true
  Check 'a compose file that cannot be read refuses' $false 'Could not read the list of images'

  Reset-Stub; Add-Image auth aaa1 ''; $env:TARLEAKS_ALLOW_UNSIGNED = '1'
  Check 'TARLEAKS_ALLOW_UNSIGNED=1 passes, with a warning' $true 'NOT checked (TARLEAKS_ALLOW_UNSIGNED=1)'
  Assert '  ...and asks cosign nothing' (-not ($script:calls -match 'verify'))
  Check 'TARLEAKS_ALLOW_UNSIGNED=1 also passes images already here' $true '' $require
  $env:TARLEAKS_ALLOW_UNSIGNED = $null

  Reset-Stub; Add-Image auth aaa1 ''; Set-Content -LiteralPath (Join-Path $kit '.env') -Value 'TARLEAKS_VERSION=1.2.0-rc.6'
  Check 'a release from before signing (rc.6) is not checked' $true 'published before Tarleaks signed its images'
  Reset-Stub; Add-Image auth aaa1 ''
  foreach ($v in '1.2.0-rc.10', '1.2.0-rc.7', '1.2.0-rc.7-candidate', 'latest', 'v1.2.0') {
    $env:TARLEAKS_VERSION = $v; Check "$v is checked" $false 'NOT signed by Tarleaks'
  }
  $env:TARLEAKS_VERSION = $null
  Set-Content -LiteralPath (Join-Path $kit '.env') -Value 'TARLEAKS_LICENSE_KEY=tlk1.test-licence-key'
  Check 'no release named at all is checked' $false 'NOT signed by Tarleaks'
  $env:TARLEAKS_VERSION = '1.1.9'; Check '1.1.9 is not' $true 'published before Tarleaks signed'
  Check '  ...nor are its images already here' $true '' $require
  $env:TARLEAKS_VERSION = $null

  Reset-Stub; Add-Image auth aaa1 $Key; Remove-Item -LiteralPath $pubFile
  Check 'a kit without the release public key refuses' $false 'tarleaks-release.pub is missing from this kit'
  Set-Content -LiteralPath $pubFile -Value $Key

  Reset-Stub; Add-Image auth aaa1 $Key; $script:CosignVersion = '2.5.0'
  Check 'cosign 2.5 is used, with --new-bundle-format' $true 'Every Tarleaks image is signed'
  Assert '  ...--new-bundle-format given' ([bool]($script:calls -match '^cosign verify .*--new-bundle-format'))
  Reset-Stub; Add-Image auth aaa1 $Key; $script:CosignVersion = '2.2.4'
  Check 'cosign older than 2.4 is not used (the image is)' $true 'Every Tarleaks image is signed'
  Assert '  ...cosign 2.2 never verifies' (-not ($script:calls -match '^cosign verify'))
  Assert '  ...the image is pinned by digest, read-only' ([bool]($script:calls -match '^docker run --rm --read-only --tmpfs /tmp -e HOME=/tmp -v .*:/sigstore:ro.* ghcr\.io/sigstore/cosign/cosign:v3\.1\.4@sha256:0f06154836d2de34f887a5c273506d52ca43edaa1d9e53e6510fa78a48f69c2d verify'))
  $wantAuth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('licence:tlk1.test-licence-key'))
  Assert '  ...signed in with the licence key' ("$script:seenConfig".Contains("`"registry.tarleaks.com`":{`"auth`":`"$wantAuth`"}"))
  Assert '  ...the sign-in folder is removed afterwards' (@(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter 'tarleaks-sig-*' -ErrorAction SilentlyContinue).Count -eq 0)

  # --- images already on this computer ---
  Reset-Stub; Add-Image auth aaa1 $Key; Add-Image hr bbb2 $Key
  Set-Content -LiteralPath (Join-Path $kit '.env') -Value "TARLEAKS_VERSION=1.2.0`nTARLEAKS_OFFLINE=sealed`nTARLEAKS_LICENSE_KEY=tlk1.test-licence-key"
  Check 'an offline installation (TARLEAKS_OFFLINE=sealed) refuses them, without going online' $false 'load the signed offline bundle' $require
  Assert '  ...cosign is not asked' (-not ($script:calls -match 'verify'))
  Reset-Stub; Add-Image auth aaa1 $Key; Add-Image hr bbb2 $Key; $script:LoginFails = $true
  Check 'online, a refused sign-in refuses them' $false '' $require
  Reset-Stub; Add-Image auth aaa1 $Key; Add-Image hr bbb2 $Key; $env:TARLEAKS_NO_DOWNLOAD = '1'
  Check 'offline, images never checked here are refused' $false 'were not checked for the Tarleaks signature on this computer' $require
  Assert '  ...naming the way out for images built here' ($script:lastOut.Contains('TARLEAKS_ALLOW_UNSIGNED'))
  $env:TARLEAKS_NO_DOWNLOAD = $null
  Check 'online, images never checked here are checked now (a kit older than the check downloaded them)' $true 'checking them now' $require
  Assert '  ...and recorded' ((Get-Record) -contains "$Reg/hr:1.2.0 sha256:id-bbb2")
  Check 'recorded images with the same content pass' $true '' $require
  Assert '  ...without asking cosign' (-not ($script:calls -match 'verify'))
  Reset-Stub; Add-Image auth aaa1 ''
  Check 'online, an unchecked unsigned image here is refused' $false 'NOT signed by Tarleaks' $require
  Reset-Stub; Add-Image auth aaa1 $Key; Add-Image hr bbb2 $Key
  Check '(checked once)' $true 'checking them now' $require
  $script:ids["$Reg/hr:1.2.0"] = 'sha256:id-other'; $script:digests["$Reg/hr:1.2.0"] = "$Reg/hr@sha256:other"
  Check 'an image swapped for another download since it was checked is refused' $false 'NOT signed by Tarleaks' $require
  Assert '  ...named' ($script:lastOut.Contains("$Reg/hr@sha256:other"))
  $script:digests.Remove("$Reg/hr:1.2.0")
  Check 'an image built here under the release''s name (no download digest) is refused' $false 'no download record' $require
  $env:TARLEAKS_NO_DOWNLOAD = '1'
  Check 'offline, a changed image is refused' $false "$Reg/hr:1.2.0" $require
  $env:TARLEAKS_NO_DOWNLOAD = $null
  $script:ids.Remove("$Reg/hr:1.2.0")
  Check 'a missing image is refused (a start would download it unchecked)' $false 'are not on this computer' $require
  $script:ComposeFails = $true
  Check 'a compose file that cannot be read refuses' $false 'Could not read the list of images' $require

  Reset-Stub; Add-Image auth aaa1 $Key; $script:ids['ghcr.io/x/tarleaks-erp/auth:1.2.0'] = 'sha256:id-aaa1'
  Assert 'a signed bundle''s images are recorded' (Register-SigLoadedImage @('Loaded image: ghcr.io/x/tarleaks-erp/auth:1.2.0', 'Loaded image: redis:7.4.12-alpine'))
  Check 'a signed bundle''s images count as checked' $true '' $require
  Assert '  ...under the name it was built with and the one this installation runs, third-party images not' ((Get-Record) -contains 'ghcr.io/x/tarleaks-erp/auth:1.2.0 sha256:id-aaa1' -and (Get-Record) -contains "$Reg/auth:1.2.0 sha256:id-aaa1" -and -not ((Get-Record) -match 'redis'))

  # The record cannot be written (a kit folder the user may not write to): refused with the fix.
  if (($IsLinux -or $IsMacOS) -and "$(& id -u)" -ne '0') {
    Reset-Stub; Add-Image auth aaa1 $Key; & chmod a-w $kit
    try { Check 'a record that cannot be written refuses, saying how to fix it' $false "Could not write" }
    finally { & chmod u+w $kit }
    Assert '  ...and leaves no temporary file' (-not (Test-Path -LiteralPath "$record.new"))
  } else { Write-Host 'skip unwritable record: not a Unix user' }

  # --- Invoke-AppPull: every way to images is checked ---
  $env:TARLEAKS_PULL_TRIES = '1'
  Reset-Stub; Add-Image auth aaa1 $Key
  Check 'Invoke-AppPull: a download of signed images passes' $true 'Every Tarleaks image is signed' $pull
  Reset-Stub; Add-Image auth aaa1 ''
  Check 'Invoke-AppPull: an unsigned download is refused' $false 'NOT signed by Tarleaks' $pull
  Reset-Stub; Add-Image auth aaa1 ''; $script:PullFails = $true
  Check 'Invoke-AppPull: a failed download with unsigned images here is refused' $false 'NOT signed by Tarleaks' $pull
  Reset-Stub; Add-Image auth aaa1 $Key; $script:PullFails = $true; $script:NetDownFor = @('all')
  Check 'Invoke-AppPull: a failed download with unchecked images that cannot be checked is refused' $false 'could not be checked' $pull
  $script:PullFails = $false; $script:NetDownFor = @(); $script:LoginFails = $true; $script:UnauthFor = @("$Reg/auth@sha256:aaa1")
  Check 'Invoke-AppPull: a refused sign-in with unchecked images here is refused (the check signs in first, refused too)' $false 'checking them now' $pull
  $script:LoginFails = $false; $script:UnauthFor = @(); $env:TARLEAKS_NO_DOWNLOAD = '1'
  Check 'Invoke-AppPull: offline with unchecked images is refused' $false 'were not checked' $pull
  $env:TARLEAKS_NO_DOWNLOAD = $null
  Check '(a download checks and records them)' $true 'Every Tarleaks image is signed'
  $script:PullFails = $true
  Check 'Invoke-AppPull: a failed download with checked images here carries on' $true 'Carrying on with those' $pull
  $script:PullFails = $false; $script:LoginFails = $true
  Check 'Invoke-AppPull: a refused sign-in with checked images here carries on' $true 'Carrying on with the images' $pull
  $script:LoginFails = $false; $env:TARLEAKS_NO_DOWNLOAD = '1'
  Check 'Invoke-AppPull: offline with checked images carries on' $true 'Offline' $pull
  $env:TARLEAKS_NO_DOWNLOAD = $null; $env:TARLEAKS_PULL_TRIES = $null

  Remove-Item Function:cosign
  if (Get-Command cosign -ErrorAction SilentlyContinue) { Write-Host 'skip without cosign: this machine has cosign installed' }
  else {
    Reset-Stub; Add-Image auth aaa1 ''
    Check 'without cosign, the image refuses an unsigned image too' $false 'NOT signed by Tarleaks'
    Reset-Stub; Add-Image auth aaa1 $Key; $script:PullOk = $false
    Check 'no cosign and no way to get its image: refused with the fix' $false 'allow outbound HTTPS to ghcr.io'
  }
}
finally {
  Pop-Location
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
$sh = Get-Content -Raw -LiteralPath (Join-Path $kitSrc 'tarleaks.ps1')
Assert '.\tarleaks.ps1 upgrade dies before its backup when the check refuses' ($sh.Contains('if ($downloaded -and -not (Confirm-ReleaseImage'))
Assert '.\tarleaks.ps1 upgrade checks images already here before using them' ($sh.Contains('$checked = Confirm-ReleaseVerified ".\tarleaks.ps1 upgrade $v"'))
Assert '.\tarleaks.ps1 start and restart refuse unchecked images' ($sh.Contains("if (-not (Confirm-ReleaseVerified '.\tarleaks.ps1 start')) { exit 1 }") -and $sh.Contains("if (-not (Confirm-ReleaseVerified '.\tarleaks.ps1 restart')) { exit 1 }"))
Assert '.\tarleaks.ps1 load-bundle records a signed bundle''s images, or stops' ($sh.Contains('if (-not (Register-SigLoadedImage $loaded)) { exit 1 }'))
Assert '.\tarleaks.ps1 upgrade -Offline never checks images online' ($sh.Contains("if (`$Offline) { `$env:TARLEAKS_NO_DOWNLOAD = '1' }"))
$cl = Get-Content -Raw -LiteralPath (Join-Path $kitSrc 'scripts/lib-cloud.ps1')
Assert 'the off-site backup engine runs only checked images' ([regex]::Matches($cl, "Confirm-ReleaseVerified '\.\\tarleaks\.ps1 cloud'").Count -ge 2)
$mv = Get-Content -Raw -LiteralPath (Join-Path $kitSrc 'scripts/lib-move.ps1')
Assert 'a new vendor address restarts the sign-in service only on checked images' ($mv -match 'Confirm-ReleaseVerified[^\n]*-Vendor[\s\S]{0,200}compose up -d --no-deps auth auth-jobs')
if ($fails -gt 0) { Write-Host "$fails check(s) failed"; exit 1 }
Write-Host 'image signature (Windows): all checks passed'
exit 0   # the last negative test leaves $LASTEXITCODE at 1; GitHub's pwsh wrapper would exit with it
