# Proves scripts/lib-scrub.ps1 on seeded secrets (the same seeds as
# check-bundle-scrub.sh): none may survive, and the plain settings support
# needs must. Run by CI (scripts job, pwsh).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib-scrub.ps1')
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("tl-scrub-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  # Secret-shaped fixtures are put together at run time, so that no token, key
  # or JWT sits in this file for a secret scanner (gitleaks in CI) to find.
  $H = 'eyJ'
  $JWT = "${H}hbGciOiJFZERTQSJ9.${H}zdWIiOiIxMjM0NTY3ODkwIn0.c2lnbmF0dXJlZm9yand0"
  $LIC = "nxs1.${H}pbnN0YWxsYXRpb25faWQiOiIxIn0.c2lnbmF0dXJlc2lnbmF0dXJl"
  $TIC = "tlc1.${H}0eXAiOiJjbG91ZF90aWNrZXQifQ.c2lnbmF0dXJlc2lnbmF0dXJl"
  $PEM = '-----BEGIN PRIVATE' + ' KEY-----'
  $BASIC = 'dXNlcjpw' + 'YXNzd29yZA=='
  $BEARER = 'abcdefghij' + 'klmnop.qrstuvwx'
  $APITOK = 'nxs' + '_0123456789abcdef0123'
  $SEALVAL = 'b64keymaterial' + 'ABCDEFGHIJKLMNOP=='
  $envText = @"
TARLEAKS_VERSION=1.2.0-rc.2
TARLEAKS_APPS=hr,payroll,accounting
POSTGRES_USER=tarleaks
RABBITMQ_USER=tarleaks-mq
STORAGE_BUCKET=tarleaks-files
DATABASE_URL=postgres://app:Url-Pass-Secret-9@postgres:5432/app
POSTGRES_PASSWORD=Pg-Very-Secret-42
CLUSTER_DSN_KEY="$SEALVAL"
TARLEAKS_SETUP_CODE=K7QF2M9DXR4P
TARLEAKS_ENTITLEMENT_TOKEN=$LIC
SHORTVAL=abc
LOG_LEVEL=info
FEATURE_FLAG=true
SHORT_PASS=q7Zp
LONG_SECRET=prefix-secret-and-more
PREFIX_SECRET=prefix-secret
HAND_EDITED=hand-value-77   # a comment
WEIRD=redacted-loop-value
"@
  $logText = @"
auth | connecting with password Pg-Very-Secret-42 to postgres
auth | sealing with $SEALVAL
auth | setup code K7QF2M9DXR4P printed
auth | token $LIC
auth | cloud ticket $TIC
auth | Authorization: Bearer $BEARER
auth | jwt $JWT
hr   | sent payslip to someone.payroll@example.com
hr   | IBAN AE070331234567890123456 saved
db   | dsn postgres://app:hunter2secret@postgres:5432/app
key  | $PEM
odd  | value redacted-loop-value seen
short| pass q7Zp used
lvl  | info: started with feature true
pre  | prefix-secret-and-more and prefix-secret
hand | hand-value-77 kept by mistake
s3   | GET https://bucket.example/file?X-Amz-Signature=abcdef0123456789
nxt  | the next line survives a token at the end of the line above
basic| Authorization: Basic $BASIC
tok  | api token $APITOK
iban | AE070331234567890123456 AE070331234567890123457
ibsp | printed as AE07 0331 2345 6789 0123 458 on the slip
eid  | Emirates ID 784-1990-1234567-1 checked
tel  | call +971501234567 or 00966512345678
ver  | running release 1.2.0-rc.2 with apps hr,payroll,accounting as tarleaks
mq   | connected to tarleaks-mq, bucket tarleaks-files
db   | url postgres://app:Url-Pass-Secret-9@postgres:5432/app
"@
  $envPath = Join-Path $work 'env'; $logPath = Join-Path $work 'log'
  [System.IO.File]::WriteAllText($envPath, ($envText -replace "`r", ''))
  [System.IO.File]::WriteAllText($logPath, ($logText -replace "`r", ''))
  Protect-SupportFile $envPath $logPath
  $out = [System.IO.File]::ReadAllText($logPath)
  $fail = $false
  $mustGo = @('Pg-Very-Secret-42', $SEALVAL.TrimEnd('='), 'K7QF2M9DXR4P', 'c2lnbmF0dXJlc2lnbmF0dXJl', $BEARER,
    ($JWT -split '\.')[0], 'someone.payroll@example.com', 'AE070331234567890123456', 'hunter2secret', $PEM.Substring(5),
    'redacted-loop-value', 'Url-Pass-Secret-9', 'q7Zp', 'prefix-secret', 'and-more', 'hand-value-77', 'abcdef0123456789',
    $BASIC, $APITOK, '6789 0123 458', '1234567-1', '501234567', '512345678', 'AE070331234567890123457')
  foreach ($s in $mustGo) { if ($out.Contains($s)) { Write-Host "LEAK: $s survived"; $fail = $true } }
  $kept = @('nxt  | the next line survives', '1.2.0-rc.2', 'hr,payroll,accounting', 'as tarleaks', 'postgres:5432/app', '[redacted:POSTGRES_PASSWORD]',
    'connected to tarleaks-mq, bucket tarleaks-files', 'info: started with feature true')
  foreach ($k in $kept) { if (-not $out.Contains($k)) { Write-Host "LOST: '$k' should stay"; $fail = $true } }
  $report = @(Get-EnvKeyReport $envPath)
  if (($report -join "`n").Contains('Pg-Very-Secret-42')) { Write-Host 'LEAK: the key report printed a value'; $fail = $true }
  if ($report -notcontains 'POSTGRES_PASSWORD=(set)') { Write-Host 'key report: missing POSTGRES_PASSWORD=(set)'; $fail = $true }
  # The same .env and log with Windows line ends (CRLF), as an editor on Windows
  # or Windows PowerShell's own output would leave them.
  [System.IO.File]::WriteAllText($envPath, (($envText -replace "`r", '') -replace "`n", "`r`n"))
  [System.IO.File]::WriteAllText($logPath, (($logText -replace "`r", '') -replace "`n", "`r`n"))
  Protect-SupportFile $envPath $logPath
  $crlf = [System.IO.File]::ReadAllText($logPath)
  foreach ($s in @('Pg-Very-Secret-42', 'hand-value-77', 'K7QF2M9DXR4P', 'abcdef0123456789', 'hunter2secret')) {
    if ($crlf.Contains($s)) { Write-Host "LEAK (CRLF): $s survived"; $fail = $true }
  }
  if (-not $crlf.Contains("bucket tarleaks-files`r`n")) { Write-Host 'LOST (CRLF): a line end was eaten'; $fail = $true }
  if ($fail) { Write-Host '--- scrubbed file ---'; Write-Host $out; exit 1 }
  Write-Host 'OK: every seeded secret was removed and the plain settings stayed.'
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
