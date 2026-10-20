# =============================================================================
# The sign-in token key (Ed25519), dot-sourced by install.ps1 and tarleaks.ps1
# (Linux/macOS: env_fill_signing_keys in scripts/lib-env.sh; keep the two in
# step). Needs the caller's Get-EnvValue and Set-EnvValue.
#
# Windows has no Ed25519 tool of its own, so the key is made by the openssl
# inside the message-queue image this installation already runs (no internet
# needed once the images are on this machine).
# =============================================================================

# No quote characters: passes through PowerShell to docker unchanged. Prints
# "<private> <public>" (base64 DER). The same text as ENV_ED25519_SCRIPT.
$script:Ed25519Script = 'k=$(mktemp) && openssl genpkey -algorithm ed25519 -out $k && echo $(openssl pkey -in $k -outform DER | base64) $(openssl pkey -in $k -pubout -outform DER | base64); rm -f $k'
$script:Ed25519Pattern = '^MC4CAQAwBQYDK2Vw[A-Za-z0-9+/]{48} MCowBQYDK2VwAyEA[A-Za-z0-9+/]{43}=$'

function Get-Ed25519Pair {
  $img = Get-EnvValue 'RABBITMQ_IMAGE'
  if (-not $img) {
    $compose = Join-Path $PSScriptRoot '../docker-compose.yml'
    if (-not (Test-Path $compose)) { $compose = Join-Path $PSScriptRoot 'docker-compose.yml' }
    $m = Select-String -Path $compose -Pattern '^\s*image: \$\{RABBITMQ_IMAGE:-([^}]*)\}' | Select-Object -First 1
    if ($m) { $img = $m.Matches[0].Groups[1].Value }
  }
  if (-not $img) { return $null }
  # Continue: Windows PowerShell turns a native command's stderr into a
  # terminating error under Stop. --pull never: no download behind the
  # person's back; without the image the key waits for the next start.
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = (& docker run --rm --pull never --network none --entrypoint sh $img -c $script:Ed25519Script 2>$null | Out-String).Trim() }
  finally { $ErrorActionPreference = $old }
  if ($out -match $script:Ed25519Pattern) { return $out } else { return $null }
}

# Writes JWT_SIGNING_KID, JWT_PUBLIC_KEYS and JWT_SIGNING_KEY_DER when the
# private key is missing. Returns 'added', 'unavailable', 'mismatch' (a private
# key whose name is not among the published keys: auth would not start; never
# repaired by replacing the key) or $null (already there).
function Add-SigningKey {
  if (Get-EnvValue 'JWT_SIGNING_KEY_DER') {
    $kid = Get-EnvValue 'JWT_SIGNING_KID'
    if (-not $kid -or -not (Get-EnvValue 'JWT_PUBLIC_KEYS').Contains('"' + $kid + '":')) { return 'mismatch' }
    return $null
  }
  $pair = Get-Ed25519Pair
  if (-not $pair) { return 'unavailable' }
  $priv, $pub = $pair -split ' '
  $b = New-Object byte[] 4
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  $kid = 'tl-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd') + '-' + (-join ($b | ForEach-Object { $_.ToString('x2') }))
  Set-EnvValue 'JWT_SIGNING_KID' $kid
  # Single quotes: Compose keeps the value as it is; \n stays two characters,
  # which the JSON reader turns into the PEM's line breaks.
  Set-EnvValue 'JWT_PUBLIC_KEYS' ("'" + '{"' + $kid + '":"-----BEGIN PUBLIC KEY-----\n' + $pub + '\n-----END PUBLIC KEY-----\n"}' + "'")
  # Last: auth signs with Ed25519 only once the public key is published.
  Set-EnvValue 'JWT_SIGNING_KEY_DER' $priv
  return 'added'
}

# The message for Add-SigningKey' answer (install.ps1 and tarleaks.ps1).
function Write-SigningKeyNote($result) {
  switch ($result) {
    'added' { Ok 'Created the sign-in token key (two-step confirmation, sealed tenders)' }
    'unavailable' { Warn 'Could not create the sign-in token key yet (the message-queue image is not on this computer). Everything works except two-step confirmation; .\tarleaks.ps1 start tries again.' }
    'mismatch' { Warn 'JWT_SIGNING_KEY_DER is set in .env, but JWT_SIGNING_KID is empty or not in JWT_PUBLIC_KEYS: the sign-in service will not start. Put the three JWT_SIGNING_KID, JWT_SIGNING_KEY_DER and JWT_PUBLIC_KEYS lines back from a backup of .env, or delete all three lines to make a new key (everyone signs in again).' }
  }
}
