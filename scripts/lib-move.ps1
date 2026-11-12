# lib-move.ps1 - move a company from Tarleaks Cloud to this installation, on
# Windows (from 1.2.0). The twin of scripts/lib-move.sh: the ERP does the work
# (its own key pair, the encrypted copy, the checks, the switch over); this
# file asks the installation's API, shows the progress on one line, prints the
# verification report and asks before the switch over. docs\move-from-cloud.md
#
#   POST /api/auth/installation/cloud-move          start {code}, go on {resume}
#   GET  /api/auth/installation/cloud-move          where it stands
#   POST /api/auth/installation/cloud-move/switch   Switch over (when ready)
#   POST /api/auth/installation/cloud-move/cancel   stop, remove the copy here
#
# Every call carries the setup code (TARLEAKS_SETUP_CODE in .env) in a header
# or the request body, never on a command line; neither the setup code nor the
# move code is printed or written to a file.
#
# Needs, from tarleaks.ps1: Get-EnvValue, Set-EnvValue, Remove-EnvValue, Probe,
# Wait-Ready, Test-Running, Ok, Warn, Die.

$script:MoveCmd = '.\tarleaks.ps1 migrate-from-cloud'
$script:MoveUsage = 'Usage: .\tarleaks.ps1 migrate-from-cloud [<code>] [-SwitchOver] | -Status | -Resume | -Cancel   (docs\move-from-cloud.md)'
$script:MoveSetupCode = ''
$script:MoveLineOpen = $false
$script:MoveReportShown = $false
$script:MoveTimingWords = [ordered]@{
  handshake = 'connecting'; schema = 'database layout'; data = 'data'; people = 'people and settings'
  files = 'files'; indexes = 'indexes and keys'; verify = 'checks'; final_changes = 'last changes'; switch = 'switch over'
}

# A move code: TLM-XXXXX-XXXXX-XXXXX-XXXXX, made in the cloud workspace. Case,
# spaces and dashes as typed; the TLM in front may be left out.
function Test-MoveCode([string] $Code) {
  $c = ($Code -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
  if ($c.Length -eq 23 -and $c.StartsWith('TLM')) { $c = $c.Substring(3) }
  return ($c -cmatch '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{20}$')
}

# -Vendor: another Tarleaks platform, only for tests (default goes back).
function Test-MoveVendor([string] $Url) {
  return ($Url -eq 'default' -or $Url -match '^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?$')
}

function Write-MoveBad($m) { Write-Host "  [x]  $m" -ForegroundColor Red }
function Close-MoveLine { if ($script:MoveLineOpen) { Write-Host ''; $script:MoveLineOpen = $false } }
function Get-MoveNumber($v) { if ($null -eq $v -or "$v" -eq '') { return [int64]0 } else { return [int64]$v } }
function Test-MoveOk($a) { return ($a.Http -ge 200 -and $a.Http -lt 300) }
# Someone at the keyboard (install.ps1 -Yes sets TARLEAKS_NO_PROMPT: ask nothing).
function Test-MoveInteractive {
  return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and $env:TARLEAKS_NO_PROMPT -ne '1')
}

function Format-MoveSize($Bytes) {
  $b = [double](Get-MoveNumber $Bytes)
  if ($b -ge 1GB) { return ('{0:N1} GB' -f ($b / 1GB)) } else { return ('{0:N1} MB' -f ($b / 1MB)) }
}
function Format-MoveDuration($Ms) {
  $s = [int64][math]::Round([double](Get-MoveNumber $Ms) / 1000)
  if ($s -lt 60) { return "$s s" }
  if ($s -lt 3600) { return ('{0} min {1} s' -f [math]::Floor($s / 60), ($s % 60)) }
  return ('{0} h {1} min' -f [math]::Floor($s / 3600), [math]::Floor(($s % 3600) / 60))
}
# "connecting 2 s, data 3 min 10 s, ..." in the order the move runs.
function Format-MoveTimings($Timings) {
  if ($null -eq $Timings) { return '' }
  $names = @($Timings.PSObject.Properties | ForEach-Object { $_.Name })
  $out = @()
  foreach ($k in $script:MoveTimingWords.Keys) {
    if ($names -contains $k) { $out += "$($script:MoveTimingWords[$k]) $(Format-MoveDuration $Timings.$k)" }
  }
  foreach ($k in $names) {
    if (-not $script:MoveTimingWords.Contains($k)) { $out += "$k $(Format-MoveDuration $Timings.$k)" }
  }
  return ($out -join ', ')
}

function Get-MoveStepWords([string] $State, [string] $Step) {
  switch -Wildcard ("${State}:${Step}") {
    'connecting:*' { return 'Connecting to Tarleaks Cloud' }
    'copying:schema' { return 'Copying the database layout' }
    'copying:data' { return 'Copying the data' }
    'copying:people' { return 'Copying people, roles and settings' }
    'copying:files' { return 'Copying the files' }
    'copying:indexes' { return 'Rebuilding indexes and keys' }
    'copying:*' { return 'Copying' }
    'verifying:*' { return 'Checking every table and file against the cloud' }
    'ready:*' { return 'Copied and checked, ready to switch over' }
    'switching:read_only' { return 'Switching over: making the cloud workspace read-only' }
    'switching:final_changes' { return 'Switching over: copying the last changes' }
    'switching:finishing' { return 'Switching over: putting the company in place' }
    'switching:confirming' { return 'Switching over: telling Tarleaks Cloud' }
    'switching:*' { return 'Switching over' }
    'live:*' { return 'Live on this server' }
  }
  return $State
}

# The progress line (without the clock): the step in words, and its numbers.
function Get-MoveLine($M) {
  $state = "$($M.state)"; $step = "$($M.step)"; $p = $M.progress
  $s = Get-MoveStepWords $state $step
  if ($state -eq 'copying' -and $step -eq 'files') {
    $s += ": $(Get-MoveNumber $p.files_copied) copied ($(Format-MoveSize $p.files_bytes))"
    $fh = Get-MoveNumber $p.files_already_here
    if ($fh -gt 0) { $s += ", $fh already here" }
  } elseif ($state -eq 'copying') {
    $bt = Get-MoveNumber $p.batches_total
    if ($bt -gt 0) { $s += ": batch $(Get-MoveNumber $p.batches_done) of $bt, $(Format-MoveSize $p.bytes_done) of $(Format-MoveSize $p.bytes_total)" }
  }
  return $s
}

# One call to the installation's API through the gateway on this computer.
# Answers @{ Http = <status, 0: no answer>; Body = <the answer, or $null> }.
function Invoke-MoveApi([string] $Method, [string] $Path = '', [hashtable] $Extra = @{}) {
  $req = @{ UseBasicParsing = $true; Method = $Method; Uri = "$(Probe)/api/auth/installation/cloud-move$Path"; TimeoutSec = 60 }
  if ($Method -eq 'GET') {
    $req.Headers = @{ 'X-Setup-Code' = $script:MoveSetupCode }
    $req.TimeoutSec = 30
  } else {
    $b = @{ setup_code = $script:MoveSetupCode }
    foreach ($k in $Extra.Keys) { $b[$k] = $Extra[$k] }
    $req.ContentType = 'application/json'
    $req.Body = [System.Text.Encoding]::UTF8.GetBytes(($b | ConvertTo-Json -Compress))
  }
  $http = 0; $text = ''
  try {
    $r = Invoke-WebRequest @req
    $http = [int]$r.StatusCode
    $text = [System.Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
  } catch {
    $err = $_
    $resp = $err.Exception.Response
    if ($resp) {
      try { $http = [int]$resp.StatusCode } catch { $http = 0 }
      $text = "$($err.ErrorDetails.Message)"
    }
  }
  $body = $null
  if ($text.Trim()) { try { $body = $text | ConvertFrom-Json } catch { $body = $null } }
  return @{ Http = $http; Body = $body }
}

# The same, waiting up to 2 minutes while the ERP does not answer (it may still
# be starting).
function Invoke-MoveApiPatient([string] $Method, [string] $Path = '', [hashtable] $Extra = @{}) {
  for ($i = 0; ; $i++) {
    $a = Invoke-MoveApi $Method $Path $Extra
    if ((Test-MoveOk $a) -or $a.Http -notin 0, 502, 503, 504 -or $i -ge 23) { return $a }
    Start-Sleep -Seconds 5
  }
}

# Why a call was refused, in words, with what to do.
function Write-MoveRefusal($a) {
  $code = "$($a.Body.error.code)"; $msg = "$($a.Body.error.message)"
  if ($a.Http -in 0, 502, 503, 504) {
    $why = if ($msg) { " ($msg)" } else { '' }
    Write-MoveBad "The ERP's sign-in service does not answer$why. See: .\tarleaks.ps1 status   and   .\tarleaks.ps1 logs auth"
    return
  }
  if ($a.Http -eq 404) {
    Write-MoveBad "This release ($(Get-EnvValue 'TARLEAKS_VERSION')) cannot take a company from Tarleaks Cloud: that comes with release 1.2.0-rc.6. Update first (.\tarleaks.ps1 update), then run this again."
    return
  }
  $text = if ($msg) { $msg } else { "The ERP answered HTTP $($a.Http)." }
  if ($code) { $text += " ($code)" }
  Write-MoveBad $text
  switch ($code) {
    'SETUP_CODE_INVALID' { Write-Host '  The kit sends TARLEAKS_SETUP_CODE from .env. If it was changed there, apply it first: .\tarleaks.ps1 restart' }
    'SERVER_HAS_WORKSPACE' { Write-Host '  Install a fresh copy for the move: on another computer, or in a second copy of this folder with its own name and port (docs\move-from-cloud.md).' }
    'MOVE_NOT_READY' { Write-Host "  Watch it until it is ready: $script:MoveCmd -Status" }
    'MOVE_ALMOST_DONE' { Write-Host "  Finish the switch over: $script:MoveCmd -Resume" }
    'CLOUD_MOVE_IN_PROGRESS' { Write-Host "  Watch it: $script:MoveCmd -Status" }
  }
}

function Write-MoveFingerprint($M) {
  $who = "$($M.company)"
  if ($M.slug) { $who = "$who ($($M.slug))".Trim() }
  if ($who) { Ok "Connected to Tarleaks Cloud: $who" } else { Ok 'Connected to Tarleaks Cloud' }
  Write-Host "  This server's key fingerprint: $($M.fingerprint)" -ForegroundColor White
  Write-Host '  The cloud workspace shows the fingerprint of the server that used the code (Settings >'
  Write-Host '  Move to your own server). It must be the same. If it is not, cancel the move there at once.'
}

function Write-MoveReport($M) {
  $r = $M.report
  if ($null -eq $r) { return }
  $script:MoveReportShown = $true
  Write-Host ''
  Write-Host 'Verification report' -ForegroundColor White
  if ($r.all_green -eq $true) { Ok 'Everything matches the cloud: every table and every file was checked.' }
  else { Write-MoveBad 'Not everything matches the cloud (below).' }
  Write-Host "  Tables:  $(Get-MoveNumber $r.tables), each checked by its row count and checksum"
  $failed = @($r.tables_failed | Where-Object { $_ } | ForEach-Object { $_.table })
  if ($failed.Count -gt 0) { Write-Host "           different: $($failed -join ', ')" }
  Write-Host "  Rows:    $(Get-MoveNumber $r.rows), and $(Get-MoveNumber $r.platform_rows) of people, roles and settings ($(Get-MoveNumber $r.platform_tables) tables)"
  $pp = $r.people
  Write-Host "  People:  $(Get-MoveNumber $pp.people) ($(Get-MoveNumber $pp.active) active, $(Get-MoveNumber $pp.two_step) with two-step sign-in), $(Get-MoveNumber $pp.settings) settings"
  $f = $r.files
  if ("$($f.mode)" -eq 'keep_own_bucket') { Write-Host "  Files:   stay in the company's own storage bucket (not copied)" }
  else { Write-Host "  Files:   $(Get-MoveNumber $f.copied) copied, $(Get-MoveNumber $f.already_here) already here, $(Format-MoveSize $f.bytes), $(Get-MoveNumber $f.failed) failed; each checked by size and SHA-256" }
  $t = Format-MoveTimings $r.timings_ms
  if ($t) { Write-Host "  Time:    $t" }
  $again = @($r.reconnect | Where-Object { $_ })
  if ($again.Count -gt 0) {
    Write-Host '  To reconnect after the switch over (secrets sealed in the cloud do not move):' -ForegroundColor White
    foreach ($x in $again) {
      $what = if ("$($x.action)" -eq 'removed') { 'removed, set it up again' } else { 'cleared, enter it again' }
      Write-Host "    - $($x.table) ($($x.column)): $($x.rows) record(s), $what"
    }
  }
  $secrets = @($r.secret_settings | Where-Object { $_ })
  if ($secrets.Count -gt 0) { Write-Host "  Settings to type again: $($secrets -join ', ')" }
  if ($null -ne $r.stays) {
    $byReason = [ordered]@{}
    foreach ($prop in $r.stays.PSObject.Properties) {
      $why = "$($prop.Value)"
      if ($byReason.Contains($why)) { $byReason[$why] = "$($byReason[$why]), $($prop.Name)" } else { $byReason[$why] = $prop.Name }
    }
    if ($byReason.Count -gt 0) {
      Write-Host '  Stays in Tarleaks Cloud:'
      foreach ($why in $byReason.Keys) { Write-Host "    - $why ($($byReason[$why]))" }
    }
  }
}

function Write-MoveLive($M) {
  if (-not $script:MoveReportShown) { Write-MoveReport $M }
  Write-Host ''
  $company = if ($M.company) { "$($M.company)" } else { 'the company' }
  Ok "Moved: $company now runs on this server."
  Write-Host "  Open $(Get-EnvValue 'TARLEAKS_URL') and sign in as in the cloud: the same e-mail addresses, passwords and two-step sign-in."
  $t = Format-MoveTimings $M.progress.timings_ms
  if ($t) { Write-Host "  Time: $t" }
  if (@($M.report.reconnect | Where-Object { $_ }).Count -gt 0 -or @($M.report.secret_settings | Where-Object { $_ }).Count -gt 0) {
    Write-Host '  Reconnect what the report lists (mail server, storage, integrations): those secrets do not move.'
  }
  Write-Host '  Tell your people the new address, and take a first backup: .\tarleaks.ps1 backup'
  if ($M.certificate) {
    Ok 'The cloud copy is destroyed: the deletion certificate, signed by Tarleaks, is in Settings > Move to your own server.'
  } else {
    Write-Host '  The copy in Tarleaks Cloud stays read-only for the retention period set there (30 days unless'
    Write-Host '  changed), then it is destroyed. The deletion certificate, signed by Tarleaks, then appears on this'
    Write-Host '  server in Settings > Move to your own server.'
  }
  if (Get-EnvValue 'TARLEAKS_LICENSE_KEY') {
    Warn 'TARLEAKS_LICENSE_KEY in .env holds a licence key, and a key set there wins over the company''s own licence that came with the move. Unless it is the key you want, remove that line from .env and run .\tarleaks.ps1 restart.'
  }
}

function Write-MoveFailed($M) {
  if ($null -ne $M.report -and -not $script:MoveReportShown) { Write-MoveReport $M }
  Write-Host ''
  $msg = "$($M.error.message)"
  if (-not $msg) { $msg = 'no reason was given (see .\tarleaks.ps1 logs auth)' }
  Write-MoveBad "The move stopped: $msg"
  $st = "$($M.error.state)"
  if ($st) { Write-Host "  While: $(Get-MoveStepWords $st "$($M.error.step)")" }
  if ($st -eq 'connecting') {
    Write-Host "  Nothing was copied. Run it again with the code: $script:MoveCmd <code>"
    Write-Host '  A code works once and for 24 hours: if the message says it is used or expired, make a new one in'
    Write-Host '  the cloud workspace (Settings > Move to your own server).'
  } else {
    if ($st -eq 'switching') {
      Write-Host '  The cloud workspace stays read-only until the switch over finishes. If this server stays silent'
      Write-Host '  for 6 hours, the cloud workspace becomes writable again by itself.'
    }
    Write-Host "  Go on from where it stopped: $script:MoveCmd -Resume"
    Write-Host "  Or stop and remove the copy here (the cloud workspace keeps working): $script:MoveCmd -Cancel"
  }
  Write-Host '  The details: .\tarleaks.ps1 logs auth'
}

function Write-MoveNotSwitched {
  Ok 'Copied and checked. Not switched over: the cloud workspace keeps working as before; what changes there until the switch over is copied then.'
  Write-Host "  Switch over when you are ready (a few minutes of read-only in the cloud): $script:MoveCmd -SwitchOver"
  Write-Host "  Or stop and remove the copy here: $script:MoveCmd -Cancel"
}

# Follow the move until it is live, stopped, or ready and not switched over.
# Answers the exit code. $Auto: switch over at ready without asking.
function Watch-Move($M, [bool] $Auto) {
  $started = Get-Date; $shown = ''; $fp = $false; $switched = $false; $misses = 0
  $tty = -not [Console]::IsOutputRedirected
  $width = 80
  if ($tty) { try { $width = [Console]::WindowWidth } catch { $width = 80 } }
  if ($width -lt 20) { $width = 80 }
  while ($true) {
    $state = "$($M.state)"
    if (-not $fp -and $M.fingerprint -and ($M.company -or $state -ne 'connecting')) {
      Close-MoveLine; Write-MoveFingerprint $M; $fp = $true
    }
    if ($state -eq 'ready' -and -not $switched) {
      Close-MoveLine
      Write-MoveReport $M
      Write-Host ''
      $go = $false
      if ($Auto) { Write-Host 'Switching over now (-SwitchOver).'; $go = $true }
      elseif (Test-MoveInteractive) {
        $answer = Read-Host 'Switch over now? The cloud workspace becomes read-only from now on; the last changes come over in a few minutes, then this server opens. [y/N]'
        $go = ("$answer".Trim() -match '^(y|yes)$')
      }
      if (-not $go) { Write-MoveNotSwitched; return 0 }
      $a = Invoke-MoveApi 'POST' '/switch'
      if (-not (Test-MoveOk $a)) { Write-MoveRefusal $a; return 1 }
      $M = $a.Body; $switched = $true
      continue
    }
    if ($state -eq 'live') { Close-MoveLine; Write-MoveLive $M; return 0 }
    if ($state -eq 'failed') { Close-MoveLine; Write-MoveFailed $M; return 1 }
    if ($state -eq 'cancelled') {
      Close-MoveLine
      Write-MoveBad 'The move was cancelled (on this server or in the cloud workspace). The cloud workspace keeps working as before.'
      Write-Host "  To move later, make a new code in the cloud workspace (Settings > Move to your own server), then: $script:MoveCmd <code>"
      return 1
    }
    if (-not $state) { Close-MoveLine; Write-MoveBad 'There is no move from Tarleaks Cloud on this server.'; return 1 }
    if ($state -ne 'ready') {
      $e = (Get-Date) - $started
      $clock = '[{0:D2}:{1:D2}]' -f [int][math]::Floor($e.TotalMinutes), $e.Seconds
      $line = Get-MoveLine $M
      if ($misses -gt 0) { $line += ' (the ERP does not answer, trying again)' }
      if ($tty) {
        $text = "$clock $line"
        if ($text.Length -gt $width - 1) { $text = $text.Substring(0, $width - 1) }
        Write-Host ("`r" + $text.PadRight($width - 1)) -NoNewline
        $script:MoveLineOpen = $true
      } elseif ($line -ne $shown) {
        Write-Host "$clock $line"
        $shown = $line
      }
    }
    Start-Sleep -Seconds 5
    $a = Invoke-MoveApi 'GET'
    if (Test-MoveOk $a) { $M = $a.Body; $misses = 0 }
    elseif ($a.Http -in 0, 502, 503, 504) {
      # The ERP restarting: keep the last answer; 5 minutes stop the watching, not the move.
      $misses++
      if ($misses -ge 60) {
        Close-MoveLine
        Write-MoveBad 'The ERP has not answered for 5 minutes. See why: .\tarleaks.ps1 doctor   and   .\tarleaks.ps1 logs auth'
        Write-Host "  The move goes on by itself once the ERP is back. Watch it again: $script:MoveCmd -Status"
        return 1
      }
    } else { Close-MoveLine; Write-MoveRefusal $a; return 1 }
  }
}

function Invoke-MoveCancel {
  $a = Invoke-MoveApiPatient 'GET'
  if (-not (Test-MoveOk $a)) { Write-MoveRefusal $a; return 1 }
  $st = "$($a.Body.state)"
  if (-not $st) { Ok 'There is no move from Tarleaks Cloud on this server.'; return 0 }
  if ($st -eq 'cancelled') { Ok 'The move is already cancelled.'; return 0 }
  if ($st -eq 'live') { Ok 'Nothing to cancel: the move is finished and the company runs on this server.'; return 0 }
  if (Test-MoveInteractive) {
    $answer = Read-Host 'Cancel the move? The copy on this server is removed, and the cloud workspace keeps working as before. [y/N]'
    if ("$answer".Trim() -notmatch '^(y|yes)$') { Write-Host 'Not cancelled.'; return 0 }
  }
  $a = Invoke-MoveApi 'POST' '/cancel'
  if (-not (Test-MoveOk $a)) { Write-MoveRefusal $a; return 1 }
  Ok 'Cancelled. The copy on this server is removed; the cloud workspace is writable and works as before.'
  Write-Host '  The code is used up. To move later, make a new one in the cloud workspace (Settings > Move to'
  Write-Host "  your own server), then: $script:MoveCmd <code>"
  return 0
}

# -Vendor: the Tarleaks platform the move (and a trial) talks to, only for
# tests. The sign-in service reads it at start, so it is started again.
function Set-MoveVendor([string] $Url) {
  $want = if ($Url -eq 'default') { '' } else { $Url.TrimEnd('/') }
  if ($want -eq (Get-EnvValue 'TARLEAKS_VENDOR_URL')) { return }
  if ($want) {
    Set-EnvValue 'TARLEAKS_VENDOR_URL' $want
    Warn "Tarleaks Cloud is $want for this installation (TARLEAKS_VENDOR_URL in .env), for tests only. Back to normal: -Vendor default"
  } else {
    Remove-EnvValue 'TARLEAKS_VENDOR_URL'
    Ok 'Tarleaks Cloud is https://tarleaks.com again (TARLEAKS_VENDOR_URL removed from .env).'
  }
  if (-not (Confirm-ReleaseVerified "$script:MoveCmd -Vendor $Url")) { Die 'Nothing was started; TARLEAKS_VENDOR_URL is changed in .env and takes effect at the next start.' }
  Write-Host 'Starting the sign-in service again to use it...'
  docker compose up -d --no-deps auth auth-jobs | Out-Host
  if ($LASTEXITCODE -ne 0) { Die 'The sign-in service did not start again (above). See: .\tarleaks.ps1 logs auth' }
  Write-Host 'Waiting for the ERP to answer' -NoNewline
  Wait-Ready
}

# The code typed or pasted, not shown.
function Read-MoveCode {
  $secure = Read-Host 'Move code from the cloud workspace (Settings > Move to your own server; not shown)' -AsSecureString
  $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# .\tarleaks.ps1 migrate-from-cloud [<code>] [-SwitchOver] [-Status | -Resume | -Cancel] [-Vendor <url>]
# The Linux spellings (--switch-over, --status, ...) are taken too. Ends the
# script with its exit code.
function Invoke-MoveFromCloud([string[]] $Words = @(), [switch] $SwitchOver, [switch] $Resume, [switch] $Cancel, [switch] $Status, [string] $Vendor = '') {
  $code = ''
  $list = @($Words | Where-Object { $_ })
  for ($i = 0; $i -lt $list.Count; $i++) {
    $w = "$($list[$i])"
    if ($w -match '^--?switch-?over$') { $SwitchOver = $true }
    elseif ($w -match '^--?resume$') { $Resume = $true }
    elseif ($w -match '^--?cancel$') { $Cancel = $true }
    elseif ($w -match '^--?status$') { $Status = $true }
    elseif ($w -match '^--?vendor=(.+)$') { $Vendor = $Matches[1] }
    elseif ($w -match '^--?vendor$') {
      if ($i + 1 -ge $list.Count) { Die '-Vendor needs an address (only to test against another Tarleaks platform; leave it out otherwise)' }
      $i++; $Vendor = "$($list[$i])"
    }
    elseif ($w -match '^(-h|--help|-\?)$') { Write-Host $script:MoveUsage; exit 0 }
    elseif ($w.StartsWith('-')) { Die "Unknown option: $w. $script:MoveUsage" }
    elseif ($code) { Die $script:MoveUsage }
    else { $code = $w }
  }
  $modes = [int][bool]$Resume + [int][bool]$Cancel + [int][bool]$Status
  if ($modes -gt 1) { Die 'Give only one of -Status, -Resume and -Cancel.' }
  if ($code -and $modes -gt 0) { Die 'A move code starts a new move: leave out -Status, -Resume and -Cancel.' }
  if ($Cancel -and $SwitchOver) { Die '-Cancel and -SwitchOver do not go together.' }
  $notCode = 'That is not a move code. It looks like TLM-XXXXX-XXXXX-XXXXX-XXXXX: make one in the cloud workspace, Settings > Move to your own server.'
  if ($code -and -not (Test-MoveCode $code)) { Die $notCode }
  if ($Vendor -and -not (Test-MoveVendor $Vendor)) { Die '-Vendor must be an address such as https://tarleaks.com (or default).' }
  if (-not (Test-Running 'auth')) { Die 'The ERP is not running. Start it first: .\tarleaks.ps1 start' }
  $script:MoveSetupCode = Get-EnvValue 'TARLEAKS_SETUP_CODE'
  if (-not $script:MoveSetupCode) { $script:MoveSetupCode = Get-EnvValue 'NEXUS_SETUP_CODE' }   # an .env from before the rename
  if (-not $script:MoveSetupCode -or $script:MoveSetupCode -eq 'GENERATED') { Die 'There is no setup code in .env (TARLEAKS_SETUP_CODE). Run .\install.ps1 again: it makes one.' }
  if ($Vendor) { Set-MoveVendor $Vendor }
  # The ERP answers before it is asked anything (the kit's own wait otherwise).
  try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Uri "$(Probe)/api/auth/installation" | Out-Null }
  catch { Write-Host 'Waiting for the ERP to answer' -NoNewline; Wait-Ready }

  if ($Cancel) { exit (Invoke-MoveCancel) }
  if ($code) {
    Write-Host 'Asking Tarleaks Cloud for the company (the code works once)...'
    $a = Invoke-MoveApiPatient 'POST' '' @{ code = $code }
  } elseif ($Resume) {
    Write-Host 'Going on with the move...'
    $a = Invoke-MoveApiPatient 'POST' '' @{ resume = $true }
  } else {
    $a = Invoke-MoveApiPatient 'GET'
    $st = "$($a.Body.state)"
    if ((Test-MoveOk $a) -and (-not $st -or ($st -eq 'cancelled' -and -not $Status -and -not $SwitchOver))) {
      if (-not $Status -and -not $SwitchOver -and (Test-MoveInteractive)) {
        if ($st -eq 'cancelled') { Write-Host 'The last move was cancelled. Starting a new one.' }
        $code = Read-MoveCode
        if (-not (Test-MoveCode $code)) { Die $notCode }
        Write-Host 'Asking Tarleaks Cloud for the company (the code works once)...'
        $a = Invoke-MoveApiPatient 'POST' '' @{ code = $code }
      } else {
        if ($st -eq 'cancelled') { Ok 'The last move from Tarleaks Cloud was cancelled.' }
        else { Ok 'There is no move from Tarleaks Cloud on this server.' }
        Write-Host '  Start one with the code from the cloud workspace (Settings > Move to your own server):'
        Write-Host "    $script:MoveCmd TLM-XXXXX-XXXXX-XXXXX-XXXXX"
        if ($Status) { exit 0 } else { exit 1 }
      }
    }
  }
  if (-not (Test-MoveOk $a)) { Write-MoveRefusal $a; exit 1 }
  # Ctrl+C stops the watching only: the move goes on in the ERP. [Console] and
  # not Write-Host, which may not print while the script is being stopped.
  $done = $false; $rc = 1
  try { $rc = Watch-Move $a.Body ([bool]$SwitchOver); $done = $true }
  finally {
    if (-not $done) {
      if ($script:MoveLineOpen) { [Console]::WriteLine() }
      [Console]::WriteLine()
      [Console]::WriteLine('  [!]  Stopped watching. The move goes on by itself on this server.')
      [Console]::WriteLine("  Watch it again: $script:MoveCmd -Status")
      [Console]::WriteLine("  When it is ready, switch over: $script:MoveCmd -SwitchOver")
    }
  }
  exit $rc
}
