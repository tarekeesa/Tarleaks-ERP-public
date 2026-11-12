# Confirm-Signature in tarleaks.ps1 (what `.\tarleaks.ps1 load-bundle` runs before it checks or loads anything)
# refuses a checksum list that is not signed with the Tarleaks release key: no signature, another key, a list
# changed after signing, a kit without the public key, no cosign or one too old; -AllowUnsigned (or
# TARLEAKS_ALLOW_UNSIGNED=1) is the only way past. The function is taken from tarleaks.ps1 as it ships; cosign is a
# stub (no network): a stub "signature" is the signing key and the file's sha256, so it verifies exactly when the
# real one would. The same checks for ./tarleaks: scripts/check-bundle-signature.sh. CI runs it.
#   ./scripts/check-bundle-signature.ps1
$ErrorActionPreference = 'Stop'
$kitSrc = Split-Path $PSScriptRoot -Parent
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("tl-sigcheck-" + [guid]::NewGuid().ToString('N'))
$script:KitRoot = Join-Path $work 'kit'
New-Item -ItemType Directory -Path (Join-Path $script:KitRoot 'config/sigstore') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $kitSrc 'config/sigstore/trusted_root.json') -Destination (Join-Path $script:KitRoot 'config/sigstore')
$Key = 'release-key-under-test'
$pubFile = Join-Path $script:KitRoot 'config/sigstore/tarleaks-release.pub'

$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $kitSrc 'tarleaks.ps1'), [ref]$tokens, [ref]$errors)
$fn = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Confirm-Signature' }, $true)
if (-not $fn) { Write-Host 'FAIL Confirm-Signature is not in tarleaks.ps1'; exit 1 }
# the kit folder comes from a variable instead of the script's own folder
Invoke-Expression ($fn.Extent.Text -replace '\$PSScriptRoot', '$script:KitRoot')

$script:said = @(); $script:calls = @(); $script:CosignVersion = '3.1.4'; $AllowUnsigned = $false
function Ok([string] $m) { $script:said += "OK: $m" }
function Warn([string] $m) { $script:said += "WARN: $m" }
function Die([string] $m) { $script:said += "DIE: $m"; throw 'died' }
function Get-Sha([string] $f) { (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash.ToLowerInvariant() }
function Set-Signed([string] $f, [string] $k) { Set-Content -LiteralPath "$f.sigstore.json" -Value "sig:${k}:$(Get-Sha $f)" -NoNewline }
function cosign {
  $script:calls += ($args -join ' ')
  if ($args[0] -eq 'version') { "GitVersion:    v$script:CosignVersion"; $global:LASTEXITCODE = 0; return }
  $k = $null; $b = $null; $f = $null; $i = 1
  while ($i -lt $args.Count) {
    $a = [string] $args[$i]
    if ($a -eq '--key') { $k = $args[$i + 1]; $i += 2 }
    elseif ($a -eq '--bundle') { $b = $args[$i + 1]; $i += 2 }
    elseif ($a -eq '--trusted-root') { if (-not (Test-Path -LiteralPath $args[$i + 1])) { $global:LASTEXITCODE = 1; return 'no trust root' }; $i += 2 }
    elseif ($a -eq '--new-bundle-format') { $i += 1 }
    else { $f = $a; $i += 1 }
  }
  $want = 'sig:' + (Get-Content -Raw -LiteralPath $k).Trim() + ':' + (Get-Sha $f)
  if ((Get-Content -Raw -LiteralPath $b) -eq $want) { $global:LASTEXITCODE = 0; 'Verified OK' }
  else { $global:LASTEXITCODE = 1; 'Error: none of the verifiers verified: invalid signature' }
}

$fails = 0
function Check([string] $name, [string] $file, [string] $want) { # want: "OK: ...", "WARN: ..." or "DIE: ..." (a substring)
  $script:said = @(); $script:calls = @()
  try { Confirm-Signature $file } catch { if ($_.Exception.Message -ne 'died') { $script:said += "ERROR: $($_.Exception.Message)" } }
  if (($script:said -join "`n").Contains($want)) { Write-Host "ok   $name" }
  else { Write-Host "FAIL ${name}: wanted '$want', got:"; $script:said | ForEach-Object { Write-Host "    $_" }; $script:fails++ }
}
function Assert([string] $name, [bool] $cond) {
  if ($cond) { Write-Host "ok   $name" } else { Write-Host "FAIL $name"; $script:fails++ }
}

try {
  Set-Content -LiteralPath $pubFile -Value $Key
  $sums = Join-Path $work 'SHA256SUMS'
  Set-Content -LiteralPath $sums -Value "0000  images/app.tar"
  Set-Signed $sums $Key
  Check 'a list signed with the release key passes' $sums 'OK: Signed by Tarleaks: SHA256SUMS'
  Assert "the kit's trust root is used first (works offline)" ($script:calls[1] -match '--trusted-root')
  Assert 'cosign 3 gets no 2.x flag' (-not (($script:calls -join ' ') -match '--new-bundle-format'))

  $unsigned = Join-Path $work 'unsigned-SHA256SUMS'
  Set-Content -LiteralPath $unsigned -Value "0000  images/app.tar"
  Check 'an unsigned list is refused' $unsigned 'DIE: unsigned-SHA256SUMS.sigstore.json is missing'
  $AllowUnsigned = $true
  Check '-AllowUnsigned lets it through, with a warning' $unsigned 'WARN: Signature of unsigned-SHA256SUMS NOT checked'
  $AllowUnsigned = $false
  $env:TARLEAKS_ALLOW_UNSIGNED = '1'
  Check 'TARLEAKS_ALLOW_UNSIGNED=1 too' $unsigned 'WARN: Signature of unsigned-SHA256SUMS NOT checked'
  Remove-Item Env:TARLEAKS_ALLOW_UNSIGNED

  $other = Join-Path $work 'other-SHA256SUMS'
  Set-Content -LiteralPath $other -Value "0000  images/app.tar"
  Set-Signed $other "someone-else's-key"
  Check 'a list signed with another key is refused' $other 'DIE: The signature of other-SHA256SUMS does not verify'

  $changed = Join-Path $work 'changed-SHA256SUMS'
  Set-Content -LiteralPath $changed -Value "0000  images/app.tar"
  Set-Signed $changed $Key
  Set-Content -LiteralPath $changed -Value "1111  images/app.tar"
  Check 'a list changed after signing is refused' $changed 'DIE: The signature of changed-SHA256SUMS does not verify'

  $script:CosignVersion = '2.2.4'
  Check 'cosign older than 2.4 is refused' $sums 'DIE: cosign 2.2.4 is too old'
  $script:CosignVersion = '2.5.0'
  Check 'cosign 2.5 checks it' $sums 'OK: Signed by Tarleaks'
  Assert 'cosign 2.x gets --new-bundle-format' (($script:calls -join ' ') -match '--new-bundle-format')
  $script:CosignVersion = '3.1.4'

  Remove-Item -LiteralPath $pubFile
  Check 'a kit without the release public key refuses' $sums 'is missing from this kit'
  Set-Content -LiteralPath $pubFile -Value $Key

  Remove-Item Function:cosign
  if (Get-Command cosign -ErrorAction SilentlyContinue) { Write-Host 'skip without cosign: this machine has cosign installed' }
  else { Check 'without cosign it is refused' $sums 'DIE: cosign is needed' }
}
finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fails -gt 0) { Write-Host "$fails check(s) failed"; exit 1 }
Write-Host 'bundle signature (Windows): all checks passed'
exit 0   # the last negative test leaves $LASTEXITCODE at 1; GitHub's pwsh wrapper would exit with it
