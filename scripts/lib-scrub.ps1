# =============================================================================
# lib-scrub.ps1 - take secrets and contact details out of a support file
# (.\tarleaks.ps1 doctor -Bundle). The Windows twin of scripts/lib-scrub.sh:
# the SAME rules, proven by scripts/check-bundle-scrub.ps1 on seeded secrets.
#
#  1. every value in .env that could be a secret (8 characters or more under any
#     key that is not a plain setting, or 4 or more under a key that names a
#     secret) is replaced by [redacted:<KEY>] wherever it appears, longest first;
#  2. known shapes: JWTs, Tarleaks licence/verdict/ticket strings and API
#     tokens, Bearer / Basic credentials, passwords inside addresses, tokens in
#     query strings, private-key blocks, e-mail addresses, IBANs (with or
#     without spaces), Emirates ID numbers and international phone numbers.
# Names of people cannot be recognised by a pattern: the bundle command tells
# the person to look inside before sending.
# =============================================================================

$script:ScrubPlainKeys = '^(TARLEAKS_|NEXUS_)?(VERSION|APPS|PROFILE_ENV|OFFLINE|TLS|URL|HOST|REGISTRY|ENVIRONMENT|AUTO_UPDATE|UPDATE_WINDOW|UPDATE_DAYS)$|^COMPOSE_(FILE|PROFILES|PROJECT_NAME)$|_PORT$|_BIND$|_IMAGE$|_USER$|_DB$|_BUCKET$|_REGION$|_URL$|_ENDPOINT$|_LEVEL$|_MODE$|^RUST_LOG$|^TZ$'
$script:ScrubSecretKeys = 'PASS|SECRET|KEY|TOKEN|CODE|PIN|CREDENTIAL'

# The values of an .env file that count as secrets, longest first.
function Get-ScrubSecret([string] $EnvPath) {
  $found = @()
  foreach ($line in [System.IO.File]::ReadAllLines($EnvPath)) {
    if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { continue }
    $k = $Matches[1]; $v = $Matches[2].TrimEnd("`r")
    if ($v -match '^"(.*)"$' -or $v -match "^'(.*)'$") { $v = $Matches[1] }
    else { $v = ($v -replace '\s+#.*$', '').TrimEnd() }
    if ($v.Length -lt 4 -or $k -cmatch $script:ScrubPlainKeys) { continue }
    if ($v.Length -lt 8 -and $k -cnotmatch $script:ScrubSecretKeys) { continue }
    $found += [pscustomobject]@{ Key = $k; Value = $v }
  }
  return @($found | Sort-Object -Property @{ Expression = { $_.Value.Length }; Descending = $true })
}

# Scrub one text with the given secrets, then the known shapes.
function Invoke-Scrub([string] $Text, $Secrets) {
  foreach ($s in $Secrets) { $Text = $Text.Replace($s.Value, "[redacted:$($s.Key)]") }
  $m = [System.Text.RegularExpressions.RegexOptions]::Multiline
  $rules = @(
    @('eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}', '[redacted:jwt]'),
    @('(nxs1|tlk1|tlc1|nxl1|tll1|nxv1)\.[A-Za-z0-9_-]{16,}(\.[A-Za-z0-9_-]+)?', '[redacted:key]'),
    @('(nxs|tlk)_[A-Za-z0-9]{16,}', '[redacted:api-token]'),
    @('([Bb]earer|[Bb]asic|TarleaksCloud) [A-Za-z0-9._~+/=-]{8,}', '$1 [redacted]'),
    @('://[^/:@ \r\n]+:[^/@ \r\n]+@', '://[redacted]@'),
    @('([?&](access_token|token|key|secret|password|sig|signature|X-Amz-Signature|X-Amz-Credential)=)[^& "\r\n]+', '$1[redacted]'),
    @('-----BEGIN [A-Z ]*PRIVATE KEY-----', '[redacted:private-key]'),
    @('[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[redacted:email]'),
    @('(^|[^A-Za-z0-9])[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}(?=[^A-Za-z0-9]|$)', '$1[redacted:iban]'),
    @('[A-Z]{2}[0-9]{2}( [A-Z0-9]{4}){3,7}( [A-Z0-9]{1,4})?', '[redacted:iban]'),
    @('784-?[0-9]{4}-?[0-9]{7}-?[0-9]', '[redacted:emirates-id]'),
    @('(\+|00)(971|966|973|974|965|968)[0-9]{7,10}', '[redacted:phone]'),
    @('\+[1-9][0-9]{9,14}', '[redacted:phone]')
  )
  # Whole-text replacement with Multiline anchors; no class above crosses a
  # line end, so each rule matches exactly what sed -E matches line by line.
  foreach ($r in $rules) { $Text = [regex]::Replace($Text, $r[0], $r[1], $m) }
  return $Text
}

# Rewrite a file in place, scrubbed (UTF-8 without a byte-order mark).
function Protect-SupportFile([string] $EnvPath, [string] $Path, $Secrets = $null) {
  if ($null -eq $Secrets) { $Secrets = Get-ScrubSecret $EnvPath }
  $text = [System.IO.File]::ReadAllText($Path)
  [System.IO.File]::WriteAllText($Path, (Invoke-Scrub $text $Secrets), (New-Object System.Text.UTF8Encoding($false)))
}

# The names in .env, never the values: which keys are set and which are empty.
function Get-EnvKeyReport([string] $EnvPath) {
  foreach ($line in [System.IO.File]::ReadAllLines($EnvPath)) {
    if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
      if ($Matches[2].Length -gt 0) { "$($Matches[1])=(set)" } else { "$($Matches[1])=(empty)" }
    }
  }
}
