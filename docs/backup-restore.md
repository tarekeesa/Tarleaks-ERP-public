# Backup and restore

One command backs up everything the ERP stores on this machine:

```bash
./tarleaks backup               # Windows: .\tarleaks.ps1 backup
```

It writes a folder `backups/<year-month-day-time>/`, for example
`backups/20261008-021500/`. The ERP keeps running while it works.

## What is in a backup

| File | What it holds |
|---|---|
| `database.sql.gz` | The whole database server: the installation's own data and your workspace. Made with `pg_dumpall`. |
| `files.tar.gz` | Everything in the Docker volume `files`: documents and attachments kept in the bundled file store, with their details (file type, checksum). It leaves out the app's own nightly backups (below): `database.sql.gz` already holds every database. |
| `hrdocs.tar.gz` | The Docker volume `hrdocs`: HR document templates. |
| `env` | A copy of your `.env`: the passwords and the keys. |
| `backup-info.txt` | When it was made, the release and the apps. |

**A backup is your whole database in readable form.** `database.sql.gz` is plain
SQL: anyone who holds it can read every employee, salary and invoice with
`zcat`, no key needed. Only a few sealed values (saved provider secrets, sealed
bids) also need the keys in `env`. And `env` holds every key and password of the
installation. So:

- Every file is readable by its owner only (folder mode 700, files 600; on
  Windows, only you, Administrators and SYSTEM). Copying with `cp -r` to a share,
  `scp` or a ZIP file can drop that protection: **encrypt a backup before it
  leaves the machine** (below).
- Without `env`, a restored database starts, but sealed values cannot be opened.
  Keep `env` with the backup, and a copy of `.env` somewhere safe.

A backup is written into `<folder>.partial` first and renamed to `<folder>` only
when every step worked and every file was read back. If anything fails, the
`.partial` folder is deleted and the command says so (and stops an upgrade). A
folder **without** `.partial` in its name is a complete backup. To back up
somewhere else, give a folder: `./tarleaks backup /mnt/nas/erp/monday`.

Run as `root` (from cron or systemd), the backup is handed to the owner of the
kit folder, so that person can open and restore it.

### What is not in a backup

| Not included | What to do |
|---|---|
| Files kept in **AWS S3, Cloudflare R2, Wasabi or a NAS** | Use that service's own versioning or replication, or copy the NAS share. `files.tar.gz` only holds the bundled store. |
| `redisdata` (cache) and `rabbitdata` (queued messages) | Not needed. They rebuild themselves. |
| `onlyoffice-data`, `onlyoffice-lib`, `onlyoffice-db` (the document editor's sessions and caches) | Not needed: the documents themselves are in `files`. The editor starts empty after a restore and rebuilds them. Only a document someone had open and unsaved when the machine stopped is lost. |
| HTTPS certificates kept by a Caddy proxy | Re-issued automatically. |
| The operating system, Docker, and the kit | Reinstall them. The kit is the Git repository. |

The database and the files are copied a moment apart, not at the same instant. A
file uploaded during the backup can be in one and not the other (the command then
prints a note). Back up at a quiet hour.

The files are copied with the database image, which is already on the machine,
so a backup needs no download and no internet.

### From 1.2.0: the app's own nightly backup

From release 1.2.0 the app also backs up each company every night by itself
(**Settings, Backups**: the hour and how many to keep). On a server that uses the
bundled file store, these backups are kept in that store, on this machine, and a
week of them is kept. They are for a quick restore from inside the app. They do
not replace `./tarleaks backup`: they are on the same disk as the data, so a
failed disk loses both. Keep scheduling `./tarleaks backup` and copying it off
the machine. `./tarleaks backup` leaves the app's backups out of `files.tar.gz`,
because its own database dump already covers them.

On the bundled file store the app's own backup holds the database only, not the
files: to get documents back after a disk failure you need `./tarleaks backup`
and `./tarleaks restore`. And `./tarleaks backup` copies only the bundled
database: a company that keeps its data in a PostgreSQL of its own
([Use a PostgreSQL on this same machine](../examples/external-postgres/README.md#use-a-postgresql-on-this-same-machine))
must back that database up itself, for example with `pg_dump`.

## Where to keep backups

A backup on the same disk as the ERP is not a backup. Copy each one somewhere
else: another machine, a different site, or cloud storage you control. A sensible
start:

- Daily backups, kept for 14 days.
- One backup a month, kept for a year.
- At least one copy **off the machine** and **encrypted**.

Encrypt a backup before it leaves the machine:

```bash
tar czf - -C backups 20261008-021500 \
  | gpg --symmetric --cipher-algo AES256 -o 20261008-021500.tar.gz.gpg
```

Tools such as `restic` or `borg` encrypt by themselves. Store the passphrase
somewhere that is **not** on the same machine.

Check that a backup is readable (`./tarleaks backup` and `restore` already do
this; this is for a copy you moved):

```bash
gzip -t backups/20261008-021500/database.sql.gz && echo "database ok"
tar tzf backups/20261008-021500/files.tar.gz > /dev/null && echo "files ok"
```

## From 1.3.0: off-site copies, encrypted (`--offsite`)

Linux, macOS and Windows. A release whose `migrate` image does not have the
backup engine yet says so and changes nothing.

`./tarleaks backup --offsite` makes the usual backup, then an **encrypted, signed
copy** of it in a place off this machine. That place is a folder: a share
mounted from another machine (NAS, file server) or a second disk. Your own S3
bucket and Tarleaks storage come later.

The copy is encrypted to a key whose secret half is only in your **recovery
kit**, a text file you print or copy away. Without it, nobody can open the
copies — not you, not Tarleaks. With it, anybody can, so keep it like the keys
to the building.

Set it up once:

```bash
./tarleaks cloud backup-key init                       # writes recovery-kit-….txt here
./tarleaks cloud backup-key verify --recovery-kit recovery-kit-….txt
# print it, or copy it to two USB sticks kept in two places, then:
./tarleaks cloud backup-key forget-secret --recovery-kit recovery-kit-….txt
./tarleaks cloud backup target folder /mnt/backup-share  # mounted first
./tarleaks backup --offsite                            # the first copy
./tarleaks cloud backup schedule 02:30                 # every night
```

- The first copy refuses until the kit has been checked: a kit that does not
  work loses every copy.
- A folder on the same disk as the ERP is refused (an unmounted share looks
  exactly like that). For a second disk that really is meant: add `--same-disk`.
- If the share is not mounted at night (the folder is missing, or it is an empty
  mount point without the marker `target folder` wrote), nothing is written to
  this disk: the scheduled run still makes the local backup, says why there is
  no off-site copy, and ends with an error so the log shows it.
- `./tarleaks cloud backup list` shows the copies (newest first), `verify <copy>`
  checks one without the kit, `prune` thins them (`7d,4w,3m`: the newest of each
  of the last 7 days, 4 weeks and 3 months; change it with
  `TARLEAKS_CLOUD_BACKUP_RETENTION` in `.env`). The scheduled run prunes by
  itself and then removes local backups older than 7 days **that have an
  off-site copy** (a backup whose copy failed is kept).
- Each copy is numbered and chained to the one before, so a copy swapped for an
  older one is noticed.
- `./tarleaks cloud status` says what is set up.

Put a copy back, on this machine or a new one:

```bash
./tarleaks cloud backup-key restore --recovery-kit recovery-kit-….txt   # a new machine only
./tarleaks cloud backup target folder /mnt/backup-share                 # a new machine only
./tarleaks restore --from-cloud --recovery-kit recovery-kit-….txt       # the newest copy
./tarleaks restore --from-cloud 20261021T023000Z-3fa1c2d9 --recovery-kit recovery-kit-….txt
```

The copy is downloaded, its signature and every part checked, then opened into
`backups/from-cloud-<copy>/`; nothing is changed until all of that passed. Then
the ordinary restore runs and asks before replacing anything. That folder holds
your data unencrypted: it is removed when the restore finishes (delete it
yourself if you cancel).

`forget-secret` deletes only the copy of the kit in this kit folder. The recovery
kit, `.tarleaks/` and `logs/` are in `.gitignore`: never put them in a repository.

**Windows** — the same commands with `.\tarleaks.ps1` and switches:

```powershell
.\tarleaks.ps1 cloud backup-key init
.\tarleaks.ps1 cloud backup-key verify -RecoveryKit recovery-kit-....txt
.\tarleaks.ps1 cloud backup-key forget-secret -RecoveryKit recovery-kit-....txt
.\tarleaks.ps1 cloud backup target folder E:\TarleaksCopies     # a second disk
.\tarleaks.ps1 backup -Offsite
.\tarleaks.ps1 cloud backup schedule 02:30                      # a Scheduled Task
.\tarleaks.ps1 restore -FromCloud -RecoveryKit recovery-kit-....txt
```

On Windows the folder must be on a disk Docker Desktop can reach: a second
internal or USB disk. A mapped network drive (`Z:`) is invisible to Docker
Desktop; for a NAS, wait for the S3 target. The scheduled task runs while you are
signed in (a locked screen is fine), because Docker Desktop itself only runs in a
signed-in session. Its log is `logs\offsite-backup.log`.

Change the key with `./tarleaks cloud backup-key rotate`. Copies made before
need the OLD kit, so keep it.

What the copy cannot protect against: someone holding this server can make new,
signed copies and, with the share's own permissions, delete copies in the folder.
Give the share versioning or snapshots if you can.

## Schedule it

Run `./tarleaks backup` every night. Three ways, all with ready-made files in
[examples/scheduled-backups](../examples/scheduled-backups/README.md):

**cron** (Linux, macOS), as a user in the `docker` group:

```text
15 2 * * *  cd /opt/tarleaks-erp && ./tarleaks backup >> "$HOME/tarleaks-backup.log" 2>&1
0 3 * * *   find /opt/tarleaks-erp/backups -mindepth 1 -maxdepth 1 -type d -name '20[0-9]*' -mtime +14 -exec rm -rf {} +
```

The clean-up removes only the dated nightly folders (`20…`). The backups taken
before an upgrade (`pre-upgrade-…`) and before a restore (`pre-restore-…`) stay
until you delete them; so does any backup you rename (for example
`monthly-2026-10`).

**systemd timer** (Linux servers): copy `tarleaks-backup.service` and
`tarleaks-backup.timer` to `/etc/systemd/system/`, then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tarleaks-backup.timer
```

**Windows Task Scheduler**:

```powershell
schtasks /Create /TN "Tarleaks ERP backup" /SC DAILY /ST 02:15 /F `
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Tarleaks-ERP\tarleaks.ps1 backup"
```

A schedule that nobody checks fails quietly. Look at `backups/` once a week.

## Restore

A restore **replaces** the current database and files with the backup. It asks you
to type `RESTORE` first.

```bash
./tarleaks restore backups/20261008-021500       # Windows: .\tarleaks.ps1 restore backups\20261008-021500
```

It does this, in this order, and stops at the first problem:

1. **Checks the backup before touching anything**: every file is read to the end,
   the database dump must hold a database and end with its closing line. A
   damaged or incomplete backup is refused with "Nothing was changed".
   **A backup of another installation is refused too**: the backup's `env` names
   the installation it came from (`COMPOSE_PROJECT_NAME`). Copied over `.env` as
   it is, it would make this folder drive that other installation and replace
   *its* data. To load it into this installation, add `--keep-settings`
   (below). When the backup's address or port differs from this folder's, the
   restore says which one applies afterwards.
2. Asks you to type `RESTORE`.
3. **Backs up what is there now** into `backups/pre-restore-<time>/`, and keeps the
   current settings as `.env.before-restore`. If that safety backup fails, nothing
   is restored. (`--no-safety-backup`, Windows `-NoSafetyBackup`, skips it, for
   when the current data does not matter, for example a new machine.)
4. Stops everything, copies the backup's `env` over `.env` (so the keys match the
   database; the message queue's user and password stay this folder's, because
   the queue is not part of a backup) and starts only the database (at most 5 minutes, or it stops with
   advice).
5. Loads `database.sql.gz`. It **stops at the first error** and says how to go
   back to the safety backup.
6. Unpacks `files.tar.gz` and `hrdocs.tar.gz` next to the current files inside each
   volume, then swaps them in: the current files are removed only once the new
   ones are complete.
7. Starts the ERP.

Then check it: `./tarleaks status` shows your workspace and the licence state. Sign
in and open a document.

### Keep this folder's name, port and address (`--keep-settings`)

```bash
./tarleaks restore backups/20261008-021500 --keep-settings   # Windows: -KeepSettings
```

The keys and the app list still come from the backup (the data was made with
them). This folder keeps its installation name, `HTTP_PORT`, `HTTP_BIND`,
`TARLEAKS_HOST`, `TARLEAKS_URL`, the HTTPS settings and the offline mode. Use it to
load a copy of production into a test installation on the same machine, or on a
new machine with another address. A test copy also carries the licence: keep it
offline ([licensing.md](licensing.md)).

If the restore stops half-way, go back with the command it prints:

```bash
./tarleaks restore backups/pre-restore-<time>
```

Messages queued in RabbitMQ after the backup was made are kept and delivered to
the restored data. A workspace database created after the backup was made is not
deleted (it is no longer used).

### On a new machine

1. Install Docker, get the kit (the installer signs in to the registry with the
   licence key in the restored `.env`), then create the settings
   and stop before starting:

   ```bash
   ./install.sh --no-start            # Windows: .\install.ps1 -NoStart
   ```

2. Copy the backup folder onto the machine (for example into `backups/`).
3. Restore. There is nothing to keep yet, so skip the safety backup:

   ```bash
   ./tarleaks restore backups/20261008-021500 --no-safety-backup
   ```

### Moving to a new machine

Do the restore above on the new machine, and:

- **Check the address.** If the new machine has a different IP or name, install
  it with that address and restore with `--keep-settings`, which keeps the new
  address ([configuration.md](configuration.md#decide-before-the-first-setup)).
  Easiest: give it the old IP, or point the old DNS name at it. An old machine
  that ran under its own installation name (`COMPOSE_PROJECT_NAME`) is restored
  with `--keep-settings`, or installed with the same name.
- **Switch the old one off** (`./tarleaks stop`) before the new one starts.
  The restored installation is the same installation as before and shares its
  licence. See [licensing.md](licensing.md#moving-to-new-hardware).

### Test a restore

A backup you have never restored is a hope, not a backup. Do a full restore test on
a spare machine at least once, and keep that machine off the internet once its
images are downloaded, so it does not check in with your licence. Wipe it when you
are done (`./tarleaks uninstall --purge`).

## Careful with

| Command | What it does |
|---|---|
| `./tarleaks uninstall` | Removes the containers. Your data stays in Docker volumes. |
| `./tarleaks uninstall --purge` | **Deletes all data**: database, files, queues. Type `DELETE` to confirm. Make a backup first. |
| `docker compose down -v` | The same as `--purge`, without the question. |
| `docker volume prune` | After `./tarleaks uninstall` the data volumes are unused, and this deletes them. Do not run it. |
