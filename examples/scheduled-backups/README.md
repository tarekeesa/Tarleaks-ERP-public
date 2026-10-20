# Scheduled backups

Run `./tarleaks backup` every night, keep two weeks of backups, and copy them off
the machine.

Time: 10 minutes. Works with every other example.

## What it backs up

`./tarleaks backup` writes `backups/<date-time>/` with the database, the bundled
file store and a copy of `.env`. The ERP keeps running while it works. What is and is
not included, and how to restore: [backup and restore](../../docs/backup-restore.md).

A backup on the same disk is not a backup. Copy it to another machine, and encrypt it
before it leaves ([how](../../docs/backup-restore.md#where-to-keep-backups)). It holds
your keys.

## Files in this folder

| File | What it is |
|---|---|
| [crontab.example](crontab.example) | Three cron lines: back up, clean up, copy off the machine |
| [tarleaks-backup.service](tarleaks-backup.service) | A systemd unit that runs one backup and cleans up |
| [tarleaks-backup.timer](tarleaks-backup.timer) | A systemd timer that runs the unit every night |

Use **one** method: cron, or systemd, or Task Scheduler on Windows.

## Try it by hand first

```bash
cd /opt/tarleaks-erp
./tarleaks backup
ls -lh backups/
```

You should see a folder with `database.sql.gz`, `files.tar.gz`, `hrdocs.tar.gz`,
`env` and `backup-info.txt`. It uses the database image, which is already on the
machine, so the backup needs no internet. A folder whose name ends in `.partial`
is a backup that is still running (or failed and was not cleaned up): never
restore it.

## Option A: cron (Linux, macOS)

Use the account that owns the kit and is in the `docker` group.

```bash
crontab -e
```

Paste the lines from [crontab.example](crontab.example), and change the path if the
kit is not in `/opt/tarleaks-erp`:

```text
PATH=/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
15 2 * * *  cd /opt/tarleaks-erp && ./tarleaks backup >> "$HOME/tarleaks-backup.log" 2>&1
0 3 * * *   find /opt/tarleaks-erp/backups -mindepth 1 -maxdepth 1 -type d -name '20[0-9]*' -mtime +14 -exec rm -rf {} +
```

- The `PATH` line lets cron find `docker` (on macOS it is in `/usr/local/bin` or
  `/opt/homebrew/bin`, which cron does not search by itself).
- The next line backs up at 02:15 every night, and logs to `~/tarleaks-backup.log`.
- The next removes nightly backups older than 14 days. Only the dated folders:
  the backups taken before an upgrade or a restore, and any folder you rename
  (for example `monthly-2026-10`), are kept.
- The third (commented out in the file) copies the backups to another machine with
  `rsync`. Edit the destination and remove the `#`.

Check it ran the next morning: `ls -lh /opt/tarleaks-erp/backups/` and
`tail ~/tarleaks-backup.log`.

## Option B: systemd timer (Linux servers)

```bash
cd /opt/tarleaks-erp/examples/scheduled-backups
sudo cp tarleaks-backup.service tarleaks-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tarleaks-backup.timer
```

Test it now, without waiting for the night:

```bash
sudo systemctl start tarleaks-backup.service
journalctl -u tarleaks-backup.service -n 30 --no-pager
```

See when it will run next:

```bash
systemctl list-timers tarleaks-backup.timer
```

What is in the files:

- The service runs `./tarleaks backup` once, then deletes nightly backups older
  than 14 days. It runs as `User=tarleaks`: **change it to the account that owns
  the kit folder** (that account must be in the `docker` group), so the backups
  belong to the person who reads and restores them. Run as root instead (delete
  the `User=` and `Group=` lines) and each backup is handed to the kit folder's
  owner anyway.
- The timer runs it every day at 02:15 and, because of `Persistent=true`, runs it
  when the machine next starts if it was off at 02:15.
- To copy backups off the machine, uncomment the `rsync` line in the service and
  edit the destination.

Change the schedule by editing `OnCalendar=` in the timer, then
`sudo systemctl daemon-reload && sudo systemctl restart tarleaks-backup.timer`.

## Option C: Windows Task Scheduler

`.\tarleaks.ps1 backup` does the same on Windows. In PowerShell, create a task that
runs every night at 02:15 (adjust the kit's path):

```powershell
schtasks /Create /TN "Tarleaks ERP backup" /SC DAILY /ST 02:15 /F `
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Tarleaks-ERP\tarleaks.ps1 backup"
```

And one that removes backups older than 14 days, at 03:00:

```powershell
schtasks /Create /TN "Tarleaks ERP backup cleanup" /SC DAILY /ST 03:00 /F `
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command Get-ChildItem C:\Tarleaks-ERP\backups -Directory -Filter 20* | Where-Object LastWriteTime -lt (Get-Date).AddDays(-14) | Remove-Item -Recurse -Force"
```

Test it now:

```powershell
schtasks /Run /TN "Tarleaks ERP backup"
Get-ChildItem C:\Tarleaks-ERP\backups
```

Things to know on Windows:

- The task runs as **you**, and only while you are signed in. That is when Docker
  Desktop is running. Make sure Docker Desktop starts when you sign in.
- The PC must be on at 02:15. If it often is not, pick a time when it is.
- To copy the backups off the machine, add a third task that runs `robocopy`
  to a network share or a drive that is not the PC's own.

## Check your backups

A backup nobody checks is a hope.

- **Weekly:** look at the newest folder. The five files should exist and
  `database.sql.gz` should be more than a few kilobytes. `./tarleaks backup`
  checks each file before it renames the folder, so a folder without `.partial`
  was complete when it was made.
- **Monthly:** `gzip -t backups/<folder>/database.sql.gz` and
  `tar tzf backups/<folder>/files.tar.gz > /dev/null`.
- **Once, then once a year:** do a full restore on a spare machine
  ([how](../../docs/backup-restore.md#test-a-restore)).

## Problems

| Symptom | Fix |
|---|---|
| Nothing in `backups/` | `./tarleaks backup` by hand shows the error. Cron runs with a small environment: check the log. |
| `permission denied` talking to Docker | The user is not in the `docker` group, or run it as root |
| The disk fills up | Lower the 14 days, or copy off and delete sooner. `du -sh backups/*` |
| Backups have an old `.env` | `.env` is copied each time; edit it, not an old backup |
