# lib-cloud.ps1 - off-site encrypted backups on Windows. The twin of scripts/lib-cloud.sh: the work is done by the backup
# engine in the `migrate` image (`tarleaks-migrate cloud-backup`); this file
# runs it with exactly the folders it needs and turns its refusal codes into
# plain sentences.
#
#   .tarleaks\cloud\        the server's half of the keys (never the secret
#                           that decrypts: that is only in the recovery kit)
#   TARLEAKS_CLOUD_BACKUP   off | folder   (S3 and Tarleaks storage come later)
#   TARLEAKS_OFFSITE_FOLDER the folder target: a second disk Docker Desktop can
#                           reach (a mapped network drive is invisible to it)
#
# Engine exit codes: 0 ok, 2 refused (nothing changed), 3 the target could not
# be reached (retry later), anything else an error.

$script:CloudDir = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) '.tarleaks') 'cloud'
$script:CloudMarker = '.tarleaks-backup-target'

function Get-CloudTarget {
  $t = Get-EnvValue 'TARLEAKS_CLOUD_BACKUP'
  if ($t) { return $t } else { return 'off' }
}

# The installation's identity at the vendor (auth.installation_state.instance_id).
function Get-CloudInstallationId {
  if (-not (Test-Running 'postgres')) { Die 'The database is not running. Start the ERP first: .\tarleaks.ps1 start' }
  $user = Get-EnvValue 'POSTGRES_USER'; if (-not $user) { $user = 'tarleaks' }
  $db = Get-EnvValue 'POSTGRES_DB'; if (-not $db) { $db = 'tarleaks' }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $id = docker compose exec -T postgres psql -X -q -At -U $user -d $db -c 'SELECT instance_id FROM auth.installation_state WHERE id' 2>$null |
      Select-Object -First 1
  } finally { $ErrorActionPreference = $old }
  if (-not $id -or -not "$id".Trim()) { Die 'This installation has no identity yet (it is made at the first start). Start the ERP once, then try again.' }
  return "$id".Trim()
}

function Test-CloudEngine {
  # The engine is the release's migrate image: it runs only when this computer checked it (scripts\lib-signature.ps1).
  if (-not (Confirm-ReleaseVerified '.\tarleaks.ps1 cloud')) { exit 1 }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { docker compose run --rm --no-deps -T migrate cloud-backup --help *> $null; return ($LASTEXITCODE -eq 0) }
  finally { $ErrorActionPreference = $old }
}

function Assert-CloudEngine {
  if (-not (Test-CloudEngine)) { Die 'This release has no off-site backups yet. Update to a release that has them: .\tarleaks.ps1 update' }
}

# The docker arguments that run the engine. -Mounts: "host:container[:ro]".
# -NoTarget: the key commands never touch the off-site folder, so they work
# while the disk is not there.
function Get-CloudEngineArgs([string[]] $Mounts = @(), [string[]] $EngineArgs = @(), [switch] $NoTarget) {
  New-Item -ItemType Directory -Force -Path $script:CloudDir | Out-Null
  Protect-Path (Split-Path -Parent $script:CloudDir)
  Protect-Path $script:CloudDir
  $a = @('compose', 'run', '--rm', '--no-deps', '-T')
  if ($env:OS -ne 'Windows_NT') { $a += @('--user', "$(& id -u):$(& id -g)") }
  $a += @('-v', "$($script:CloudDir):/keys")
  foreach ($m in $Mounts) { $a += @('-v', $m) }
  if (-not $NoTarget -and (Get-CloudTarget) -eq 'folder') {
    $f = Get-EnvValue 'TARLEAKS_OFFSITE_FOLDER'
    if (-not $f) { Die 'The off-site folder is not set. Set it: .\tarleaks.ps1 cloud backup target folder <path>' }
    # Never let Docker create a missing host folder.
    if (-not (Test-Path -LiteralPath $f -PathType Container)) { Die "The off-site folder $f is not there (is the disk plugged in?). Nothing was changed." }
    $a += @('-v', "${f}:/offsite", '-e', 'TARLEAKS_OFFSITE_FOLDER=/offsite')
  }
  return $a + @('migrate', 'cloud-backup') + $EngineArgs
}

function Write-CloudFailure([int] $Code) {
  switch ($Code) {
    0 { }
    2 { Write-Host '  [x]  Nothing was changed (the reason is above).' -ForegroundColor Red }
    3 { Write-Host '  [x]  The off-site place could not be reached (above). Nothing is lost; it is tried again next time.' -ForegroundColor Red }
    default { Write-Host '  [x]  The off-site backup engine failed (above).' -ForegroundColor Red }
  }
}

# Run the engine, show its output, explain a failure; returns the exit code.
function Invoke-CloudEngine([string[]] $Mounts = @(), [string[]] $EngineArgs = @(), [switch] $NoTarget) {
  if (-not (Confirm-ReleaseVerified '.\tarleaks.ps1 cloud')) { exit 1 }
  $a = Get-CloudEngineArgs -Mounts $Mounts -EngineArgs $EngineArgs -NoTarget:$NoTarget
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & docker @a | Out-Host; $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
  Write-CloudFailure $rc
  return $rc
}

# The file-system path (never a PowerShell provider path such as
# "Microsoft.PowerShell.Core\FileSystem::\\nas\share").
function Get-FullPath([string] $Path) { return (Resolve-Path -LiteralPath $Path).ProviderPath }

# The kit folder itself, or anything in it.
function Test-InsideKit([string] $Full) {
  $sep = [System.IO.Path]::DirectorySeparatorChar
  $root = ($PSScriptRoot | Split-Path -Parent).TrimEnd('\', '/') + $sep
  return ($Full.TrimEnd('\', '/') + $sep).StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
}

# .\tarleaks.ps1 cloud backup-key init|verify|forget-secret|restore|rotate
function Invoke-CloudBackupKey([string] $Sub, [string] $KitFile) {
  Assert-CloudEngine
  $root = Split-Path -Parent $PSScriptRoot
  switch ($Sub) {
    { $_ -in 'init', 'rotate' } {
      $inst = Get-CloudInstallationId
      $before = @(Get-ChildItem -LiteralPath $script:CloudDir -Filter 'recovery-kit-*.txt' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
      $verb = if ($Sub -eq 'init') { 'keygen' } else { 'rotate' }
      $rc = Invoke-CloudEngine -NoTarget -EngineArgs @($verb, '--keys', '/keys', '--kit-dir', '/keys', '--installation', $inst)
      if ($rc -ne 0) { exit $rc }
      $new = @(Get-ChildItem -LiteralPath $script:CloudDir -Filter 'recovery-kit-*.txt' | Where-Object { $before -notcontains $_.Name } | Select-Object -First 1)
      if ($new.Count -eq 0) { Die 'The recovery kit was not written.' }
      $kit = Join-Path $root $new[0].Name
      Move-Item -LiteralPath $new[0].FullName -Destination $kit
      Protect-Path $kit -File
      Write-Host ''
      Write-Host "Your recovery kit is $($new[0].Name)" -ForegroundColor White
      Write-Host 'Without it, NO off-site copy can be opened - not by you, not by Tarleaks.'
      Write-Host '1. Print it, or copy it to two USB sticks kept in two places.'
      Write-Host "2. Check it:   .\tarleaks.ps1 cloud backup-key verify -RecoveryKit $($new[0].Name)"
      Write-Host "3. Remove it from this computer:   .\tarleaks.ps1 cloud backup-key forget-secret -RecoveryKit $($new[0].Name)"
      if ($Sub -eq 'rotate') { Warn 'Copies made before today still need the OLD recovery kit. Keep it.' }
    }
    'verify' {
      if (-not $KitFile) { Die 'usage: .\tarleaks.ps1 cloud backup-key verify -RecoveryKit <file>' }
      if (-not (Test-Path -LiteralPath $KitFile -PathType Leaf)) { Die "$KitFile is not a file." }
      $rc = Invoke-CloudEngine -NoTarget -Mounts @("$(Get-FullPath $KitFile):/kit.txt:ro") -EngineArgs @('verify-kit', '--keys', '/keys', '--recovery-kit', '/kit.txt')
      if ($rc -ne 0) { exit $rc }
      Ok "This recovery kit opens this computer's off-site copies."
    }
    'forget-secret' {
      if (-not $KitFile) { Die 'usage: .\tarleaks.ps1 cloud backup-key forget-secret -RecoveryKit <file>' }
      if (-not (Test-Path -LiteralPath $KitFile -PathType Leaf)) { Die "$KitFile is not a file." }
      $full = Get-FullPath $KitFile
      if (-not (Test-InsideKit $full)) { Die "forget-secret removes the copy of the kit kept in this kit folder, and only that one. $full is somewhere else (a USB stick?): keep it." }
      $rc = Invoke-CloudEngine -NoTarget -Mounts @("${full}:/kit.txt:ro") -EngineArgs @('verify-kit', '--keys', '/keys', '--recovery-kit', '/kit.txt')
      if ($rc -ne 0) { exit $rc }
      $answer = Read-Host "This deletes $full from this computer. Type I HAVE IT once it is printed or copied away"
      if ($answer -cne 'I HAVE IT') { Die 'Cancelled. The file is still here.' }
      Remove-Item -LiteralPath $full -Force
      Ok 'Removed. Keep the printed or copied kit safe: it is the only way to open the copies.'
    }
    'restore' {
      if (-not $KitFile) { Die 'usage: .\tarleaks.ps1 cloud backup-key restore -RecoveryKit <file>' }
      if (-not (Test-Path -LiteralPath $KitFile -PathType Leaf)) { Die "$KitFile is not a file." }
      $rc = Invoke-CloudEngine -NoTarget -Mounts @("$(Get-FullPath $KitFile):/kit.txt:ro") -EngineArgs @('restore-keys', '--keys', '/keys', '--recovery-kit', '/kit.txt')
      if ($rc -ne 0) { exit $rc }
      Ok 'The backup keys are back on this computer; new copies continue the same chain.'
    }
    default { Die 'usage: .\tarleaks.ps1 cloud backup-key init | verify | forget-secret | restore | rotate' }
  }
}

# .\tarleaks.ps1 cloud backup target folder <path> [-SameDisk] | off
function Set-CloudTarget([string[]] $Words, [switch] $SameDisk) {
  $kind = if ($Words.Count -gt 0) { $Words[0] } else { '' }
  switch ($kind) {
    'folder' {
      if ($Words.Count -lt 2) { Die 'usage: .\tarleaks.ps1 cloud backup target folder <path> [-SameDisk]' }
      $path = $Words[1]
      if (-not (Test-Path -LiteralPath $path -PathType Container)) { Die "$path is not a folder on this computer. Plug in the disk first." }
      $full = Get-FullPath $path
      # A whole drive (E:\) as a Docker mount source is unreliable: use a
      # folder on it, which also keeps the copies apart from anything else.
      if ($full.TrimEnd('\', '/') -match '^[A-Za-z]:$' -or $full -eq '/') { Die "Use a folder on that disk, not the whole disk: for example $($full.TrimEnd('\', '/'))\TarleaksCopies (create it first)." }
      if (Test-InsideKit $full) { Die 'The off-site folder must not be inside this kit folder: a copy on the same disk is not off-site.' }
      # On the kit's own drive, a copy does not survive a failed disk: refuse
      # unless the person says it is meant.
      $kitRoot = Split-Path -Parent $PSScriptRoot
      if (-not $SameDisk -and [System.IO.Path]::GetPathRoot($full) -eq [System.IO.Path]::GetPathRoot($kitRoot)) {
        Die "$full is on the same disk as this computer's ERP data: a copy there does not survive a failed disk or a theft. Use a second disk. To use this folder anyway: .\tarleaks.ps1 cloud backup target folder `"$full`" -SameDisk"
      }
      Assert-CloudEngine
      $oldTarget = Get-EnvValue 'TARLEAKS_CLOUD_BACKUP'; $oldFolder = Get-EnvValue 'TARLEAKS_OFFSITE_FOLDER'
      Set-EnvValue 'TARLEAKS_CLOUD_BACKUP' 'folder'
      Set-EnvValue 'TARLEAKS_OFFSITE_FOLDER' $full
      $rc = Invoke-CloudEngine -EngineArgs @('init-target', '--target', 'folder')
      # Docker Desktop cannot see some folders (a mapped network drive) and
      # quietly gives the container an empty one inside its own disk: the
      # marker must be on THIS computer's folder, or nothing is set up.
      if ($rc -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $full $script:CloudMarker) -PathType Leaf)) {
        Write-Host "  [x]  Docker Desktop cannot write to $full (a mapped network drive is invisible to it). Use a local or USB disk." -ForegroundColor Red
        $rc = 3
      }
      if ($rc -ne 0) {
        # A target that failed its set-up must not become the nightly one.
        if ($oldTarget) { Set-EnvValue 'TARLEAKS_CLOUD_BACKUP' $oldTarget } else { Remove-EnvValue 'TARLEAKS_CLOUD_BACKUP' }
        if ($oldFolder) { Set-EnvValue 'TARLEAKS_OFFSITE_FOLDER' $oldFolder } else { Remove-EnvValue 'TARLEAKS_OFFSITE_FOLDER' }
        exit $rc
      }
      Ok "Off-site copies will go to $full. Make one now: .\tarleaks.ps1 backup -Offsite"
    }
    'off' {
      Set-EnvValue 'TARLEAKS_CLOUD_BACKUP' 'off'
      Ok 'Off-site copies are off. Copies already made are left where they are.'
      if (Test-CloudSchedule) { Warn 'A nightly off-site copy is still scheduled: it now makes the local backup and reports an error every night. To stop it: .\tarleaks.ps1 cloud backup schedule off' }
    }
    { $_ -in 's3', 'tarleaks' } { Die 'Copies to your own S3 bucket and to Tarleaks storage come with a later release. Use a second disk for now.' }
    default { Die 'usage: .\tarleaks.ps1 cloud backup target folder <path> [-SameDisk] | off' }
  }
}

# Throws (never exits) when off-site copies cannot be made now, so a scheduled
# run can still make the local backup.
function Test-CloudReady {
  if ((Get-CloudTarget) -eq 'off') { throw 'Off-site copies are off. Choose where they go first: .\tarleaks.ps1 cloud backup target folder <path>' }
  if ((Get-CloudTarget) -eq 'folder') {
    $f = Get-EnvValue 'TARLEAKS_OFFSITE_FOLDER'
    if (-not $f) { throw 'The off-site folder is not set. Set it: .\tarleaks.ps1 cloud backup target folder <path>' }
    if (-not (Test-Path -LiteralPath $f -PathType Container)) { throw "The off-site folder $f is not there (is the disk plugged in?)." }
    if (-not (Test-Path -LiteralPath (Join-Path $f $script:CloudMarker) -PathType Leaf)) { throw "The off-site folder $f is empty: the disk is not the one that was set up, or the folder was never set up (.\tarleaks.ps1 cloud backup target folder $f)." }
  }
  if (-not (Test-CloudEngine)) { throw 'This release has no off-site backups yet. Update to a release that has them: .\tarleaks.ps1 update' }
}

function Assert-CloudReady { try { Test-CloudReady } catch { Die $_.Exception.Message } }

# Seal one finished backup folder; a sealed folder gets a marker, so the
# scheduled clean-up removes only local backups that have an off-site copy.
function Invoke-CloudSeal([string] $Dir) {
  try { Test-CloudReady } catch { Write-Host "  [x]  $($_.Exception.Message)" -ForegroundColor Red; return 3 }
  $full = Get-FullPath $Dir
  $parent = Split-Path -Parent $full; $name = Split-Path -Leaf $full
  $inst = Get-CloudInstallationId
  $rc = Invoke-CloudEngine -Mounts @("${parent}:/backups") -EngineArgs @('seal', "/backups/$name", '--target', (Get-CloudTarget), '--keys', '/keys', '--installation', $inst, '--release', (Get-EnvValue 'TARLEAKS_VERSION'))
  if ($rc -eq 0) { Set-Content -LiteralPath (Join-Path $full '.offsite-sealed') -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') -Encoding ascii }
  return $rc
}

# After a scheduled, sealed backup: thin the off-site copies, then drop local
# backups older than 7 days that were sealed off-site (never one whose copy
# failed, one made without -Offsite, or a safety backup).
function Invoke-CloudAfterScheduledSeal {
  $keep = Get-EnvValue 'TARLEAKS_CLOUD_BACKUP_RETENTION'; if (-not $keep) { $keep = '7d,4w,3m' }
  $rc = Invoke-CloudEngine -EngineArgs @('prune', '--target', (Get-CloudTarget), '--keys', '/keys', '--retention', $keep)
  if ($rc -ne 0) { Warn 'Older off-site copies were not thinned this time (above).' }
  $backups = Join-Path (Split-Path -Parent $PSScriptRoot) 'backups'
  if (-not (Test-Path -LiteralPath $backups)) { return }
  foreach ($d in Get-ChildItem -LiteralPath $backups -Directory) {
    $marker = Join-Path $d.FullName '.offsite-sealed'
    if ((Test-Path -LiteralPath $marker) -and (Get-Item -Force -LiteralPath $marker).LastWriteTime -lt (Get-Date).AddDays(-7)) {
      Remove-Item -LiteralPath $d.FullName -Recurse -Force
    }
  }
}

# One scheduled task per kit folder (its name carries a hash of the path).
function Get-CloudTaskName {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $root = Split-Path -Parent $PSScriptRoot
  $h = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))[0..3] | ForEach-Object { $_.ToString('x2') })
  return "Tarleaks ERP off-site copy $h"
}
# Windows: the ScheduledTasks cmdlets (no command line to quote, no length
# limit). schtasks.exe is the fallback where they are missing.
function Test-ScheduledTaskCmdlet { return [bool](Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) }
function Test-CloudSchedule {
  if (Test-ScheduledTaskCmdlet) { return [bool](Get-ScheduledTask -TaskName (Get-CloudTaskName) -ErrorAction SilentlyContinue) }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { schtasks /Query /TN (Get-CloudTaskName) *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false }
  finally { $ErrorActionPreference = $old }
}

# .\tarleaks.ps1 cloud backup schedule HH:MM | off
function Set-CloudSchedule([string] $When) {
  $name = Get-CloudTaskName
  if ($When -eq 'off') {
    if (Test-CloudSchedule) {
      if (Test-ScheduledTaskCmdlet) { Unregister-ScheduledTask -TaskName $name -Confirm:$false }
      else {
        schtasks /Delete /TN $name /F | Out-Null
        if ($LASTEXITCODE -ne 0) { Die "Could not remove the scheduled task '$name'." }
      }
    }
    Ok 'The scheduled off-site copy is off.'
    return
  }
  if ($When -notmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$') { Die 'usage: .\tarleaks.ps1 cloud backup schedule HH:MM (00:00 to 23:59) | off' }
  Assert-CloudReady
  $root = Split-Path -Parent $PSScriptRoot
  $script = Join-Path $root 'tarleaks.ps1'
  $taskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" backup -Offsite -Scheduled"
  if (Test-ScheduledTaskCmdlet) {
    # The arguments travel as one string to the Task Scheduler, never through
    # a command line, so a path with spaces (C:\Users\Jane Doe\...) is safe.
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs -WorkingDirectory $root
    $trigger = New-ScheduledTaskTrigger -Daily -At $When
    # A laptop on battery still runs it, and a night the computer was off is
    # caught up when it is next on.
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    try { Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Force -ErrorAction Stop | Out-Null }
    catch { Die "Could not create the scheduled task '$name': $($_.Exception.Message)" }
  } else {
    $tr = "powershell.exe $taskArgs"
    if ($tr.Length -gt 261) { Die "The kit's path is too long for the task scheduler (its command may be 261 characters). Move the kit to a shorter path." }
    schtasks /Create /TN $name /SC DAILY /ST $When /F /TR $tr | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "Could not create the scheduled task '$name' (above)." }
  }
  Ok "Every night at $When a backup is made and copied off-site; local backups older than 7 days that have an off-site copy are then removed. Log: logs\offsite-backup.log"
  Write-Host '  It runs while you are signed in (a locked screen is fine): Docker Desktop itself only runs in a signed-in session.'
}

# Opens a copy into backups\from-cloud-<copy>\ for the ordinary restore.
function Open-CloudCopyForRestore([string] $Id, [string] $KitFile) {
  Assert-CloudReady
  if (-not $KitFile) { Die 'An off-site copy opens only with its recovery kit: .\tarleaks.ps1 restore -FromCloud [copy] -RecoveryKit <file>' }
  if (-not (Test-Path -LiteralPath $KitFile -PathType Leaf)) { Die "$KitFile is not a file." }
  if (-not $Id) {
    $a = Get-CloudEngineArgs -EngineArgs @('list', '--target', (Get-CloudTarget))
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $listing = @(& docker @a); $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
    if ($rc -eq 3) { Die 'The off-site place could not be reached (above). Plug in the disk, then try again.' }
    if ($rc -ne 0) { Die 'The off-site copies could not be listed (above).' }
    $first = $listing | Where-Object { $_ } | Select-Object -First 1
    if (-not $first) { Die "There is no off-site copy in $(Get-EnvValue 'TARLEAKS_OFFSITE_FOLDER')." }
    $Id = ($first -split '\s+')[0]
    Write-Host "The newest off-site copy is $Id. (Another one: .\tarleaks.ps1 cloud backup list, then .\tarleaks.ps1 restore -FromCloud <copy> -RecoveryKit <file>.)"
  }
  # The name ends up in a folder this command later removes.
  if ($Id -match '[\\/]' -or $Id.StartsWith('.')) { Die "`"$Id`" is not the name of an off-site copy (see .\tarleaks.ps1 cloud backup list)." }
  $backups = Join-Path (Split-Path -Parent $PSScriptRoot) 'backups'
  New-Item -ItemType Directory -Force -Path $backups | Out-Null
  # The opened copy is the whole database and every key, unencrypted: born
  # owner-only (the engine's 0700 means nothing on NTFS through Docker Desktop).
  Protect-Path $backups
  $into = Join-Path $backups "from-cloud-$Id"
  if (Test-Path -LiteralPath $into) { Die "$into already exists. Restore it directly: .\tarleaks.ps1 restore `"$into`"" }
  $rc = Invoke-CloudEngine -Mounts @("$((Resolve-Path -LiteralPath $backups).Path):/backups", "$(Get-FullPath $KitFile):/kit.txt:ro") `
    -EngineArgs @('open', $Id, '--target', (Get-CloudTarget), '--recovery-kit', '/kit.txt', '--into', "/backups/from-cloud-$Id", '--release', (Get-EnvValue 'TARLEAKS_VERSION'), '--keys', '/keys')
  if ($rc -ne 0) { exit $rc }
  Protect-Path $into
  return $into
}

# .\tarleaks.ps1 cloud backup-key ... | backup ... | status
function Invoke-CloudCommand([string] $Area, [string[]] $Words, [string] $KitFile, [switch] $SameDisk) {
  switch ($Area) {
    'backup-key' { Invoke-CloudBackupKey ($(if ($Words.Count -gt 0) { $Words[0] } else { '' })) $KitFile }
    'backup' {
      $sub = if ($Words.Count -gt 0) { $Words[0] } else { '' }
      # @(): a one-element slice is a plain string, and [0] of a string is its first letter.
      $restWords = @(if ($Words.Count -gt 1) { $Words[1..($Words.Count - 1)] })
      switch ($sub) {
        'target' { Set-CloudTarget $restWords -SameDisk:$SameDisk }
        'list' { Assert-CloudReady; $rc = Invoke-CloudEngine -EngineArgs @('list', '--target', (Get-CloudTarget)); if ($rc -ne 0) { exit $rc } }
        'verify' {
          if ($restWords.Count -lt 1) { Die 'usage: .\tarleaks.ps1 cloud backup verify <copy>   (the copies: .\tarleaks.ps1 cloud backup list)' }
          Assert-CloudReady
          $rc = Invoke-CloudEngine -EngineArgs @('verify', $restWords[0], '--target', (Get-CloudTarget), '--keys', '/keys'); if ($rc -ne 0) { exit $rc }
        }
        'prune' {
          Assert-CloudReady
          $keep = Get-EnvValue 'TARLEAKS_CLOUD_BACKUP_RETENTION'; if (-not $keep) { $keep = '7d,4w,3m' }
          $rc = Invoke-CloudEngine -EngineArgs @('prune', '--target', (Get-CloudTarget), '--keys', '/keys', '--retention', $keep); if ($rc -ne 0) { exit $rc }
        }
        'schedule' { Set-CloudSchedule ($(if ($restWords.Count -gt 0) { $restWords[0] } else { '' })) }
        default { Die 'usage: .\tarleaks.ps1 cloud backup target | list | verify <copy> | prune | schedule <HH:MM|off>' }
      }
    }
    'status' {
      $t = Get-CloudTarget
      $where = if ($t -eq 'folder') { " -> $(Get-EnvValue 'TARLEAKS_OFFSITE_FOLDER')" } else { '' }
      Write-Host "Off-site copies: $t$where"
      if (Test-Path -LiteralPath (Join-Path $script:CloudDir 'backup-recipient.txt')) { Write-Host 'Backup key: made' } else { Write-Host 'Backup key: not made (.\tarleaks.ps1 cloud backup-key init)' }
      if (Test-Path -LiteralPath (Join-Path $script:CloudDir 'kit-verified')) { Write-Host 'Recovery kit: checked' } else { Write-Host 'Recovery kit: not checked yet (.\tarleaks.ps1 cloud backup-key verify -RecoveryKit <file>)' }
      $last = Join-Path $script:CloudDir 'last_sequence'
      if (Test-Path -LiteralPath $last) { Write-Host "Last off-site copy: number $(((Get-Content -LiteralPath $last -TotalCount 1) -split ' ')[0])" }
      Write-Host "Scheduled nightly copy: $(if (Test-CloudSchedule) { 'yes' } else { 'no' })"
    }
    default { Die 'usage: .\tarleaks.ps1 cloud backup-key ... | backup ... | status' }
  }
}
