# The Windows image download (Invoke-AppPull in scripts/lib-apps.ps1) tries again
# after a dropped connection, never after a refusal, and shows what Docker said
# when it gives up: the twin of scripts/check-pull-retry.sh. Docker is a stub
# here: no network, no images. CI runs it.
#   pwsh ./scripts/check-pull-retry.ps1
$ErrorActionPreference = 'Stop'
$Kit = Split-Path $PSScriptRoot -Parent
Set-Location $Kit
. (Join-Path $PSScriptRoot 'lib-apps.ps1')
function Invoke-RegistryLogin { param($a) return $true }
function Get-AppMissingImage { return @('example/app:1') }
function Get-RegistryHost { return 'registry.example.com' }
function Test-RegistryTakesLicence { return $true }
function Start-Sleep { param([int] $Seconds) }
# The signature check has its own test (scripts/check-image-signature.ps1); here only the download counts.
function Confirm-ReleaseImage { param($a) return $true }
function Confirm-ReleaseVerified { param($a) return $true }
$script:said = @(); $script:calls = 0
function docker { $script:calls++; $s = $script:said[$script:calls - 1]; if ($s -eq 'ok') { $global:LASTEXITCODE = 0; return }; $global:LASTEXITCODE = 1; Write-Output $s }
$fails = 0
function Run($name, $wantOk, $wantCalls, $wantText, [string[]] $lines) {
  $script:said = $lines; $script:calls = 0
  $out = (Invoke-AppPull '.\install.ps1' *>&1 | Out-String)
  $ok = $out.Trim().EndsWith('True')
  if ($ok -ne $wantOk -or $script:calls -ne $wantCalls -or ($wantText -and -not $out.Contains($wantText))) { Write-Host "FAIL $name : ok=$ok calls=$($script:calls)`n$out"; $script:fails++ } else { Write-Host "ok   $name" }
}
Run 'a pull that works is not repeated' $true 1 '' @('ok')
Run 'an unexpected EOF is tried again' $true 2 'The download was interrupted (unexpected EOF)' @('unexpected EOF', 'ok')
Run 'three drops: gives up and shows what Docker said' $false 3 'Docker said: dial tcp 1.2.3.4:443: i/o timeout' @('unexpected EOF', 'unexpected EOF', 'dial tcp 1.2.3.4:443: i/o timeout')
Run 'a refused licence is not tried again' $false 1 'refused the download' @('unauthorized: authentication required', 'ok')
Run 'a full disk is not tried again' $false 1 'The disk is full' @('no space left on device', 'ok')
if ($script:fails) { Write-Host "$($script:fails) case(s) failed"; exit 1 } else { Write-Host 'OK: the Windows image download retries a dropped connection and shows Docker''s error.' }
# The stubbed docker left LASTEXITCODE at 1 (the last case fails on purpose); the CI step exits with it.
exit 0
