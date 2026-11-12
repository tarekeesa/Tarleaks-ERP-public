# Upgrading

Nothing upgrades by itself. Your installation stays on the release in
`TARLEAKS_VERSION` (in `.env`) until you move it. One command does it:

```bash
./tarleaks update                     # Windows: .\tarleaks.ps1 update
```

## Before you start

1. **Know what you run now.** Sign in and open **Settings, Licence**: the
   **Version** is on that page. From a terminal: `grep ^TARLEAKS_VERSION .env`.
2. **See what is available:** `./tarleaks update --check` asks the image
   registry (with your licence key) and answers "Up to date" or "Release …
   is available". It changes nothing.
3. **Get the kit of that release.** The compose file, gateway routes and
   scripts belong to a release too, and `./tarleaks update` refuses a release
   this folder does not know (its `CHANGELOG.md` has no section for it):

   ```bash
   git fetch --tags && git checkout v<release>
   ```

   Your `.env`, `backups/` and the data in Docker volumes are not in Git, so this
   does not touch them. A ZIP install: unpack the new ZIP over this folder.
4. **Check free disk** (`df -h .`). You need room for the new images and for the
   backup the update takes first.
5. **Pick a quiet time.** The ERP restarts, so it does not answer for a few
   minutes. Allow longer when a release changes the database.

## Update

```bash
./tarleaks update                     # the newest release for this installation
./tarleaks update --to 1.2.0          # or one release by name
```

It does this, in order, and stops at the first problem:

1. **Checks the release.** It must be published on `registry.tarleaks.com`
   (asked with your licence key), be newer than the one you run, and be listed
   in this kit's `CHANGELOG.md`. Release candidates (`1.2.0-rc.2`) are offered
   only to an installation that already runs a candidate.
2. **Downloads** the new images while the current release keeps running. If
   any image is missing it stops here and **changes nothing**.
3. Takes a **backup** into `backups/pre-update-<old>-to-<new>-<date-time>/`
   (database, files, `.env`) while `.env` still names the old release. If the
   backup fails, the update stops here and **changes nothing**.
4. Writes `TARLEAKS_VERSION=<new>` into `.env`, restarts everything on it and
   runs the database update (the `migrate` service). Its output is kept in the
   backup folder as `migrate.log`.
5. **Waits** until the ERP answers and the document editor is up.
6. Runs **`./tarleaks doctor`** and ends with "Updated from … to …" only when
   it finds no problem.

When a step fails, it prints the exact way back, for example:

```text
How to go back to 1.2.0-rc.1 (exactly as it was before the update):
  ./tarleaks restore backups/pre-update-1.2.0-rc.1-to-1.2.0-rc.2-20261020-110512
  ./tarleaks start
```

When it stops before `.env` was switched it says so instead: nothing changed,
and no backup must be restored.

It is safe to run again. On the newest release it makes sure everything runs,
runs the database step (it does nothing when there is nothing to do) and runs
`doctor`; an interrupted update is simply run again (if it says
another update is running and none is, remove the folder
`.tarleaks-update.lock`). It never goes back to an older release (see
[Rolling back](#rolling-back)), and it only touches this installation: the
containers and volumes named by `COMPOSE_PROJECT_NAME` (or `tarleaks`).

On **Windows**, `.\tarleaks.ps1 update` (`-To 1.2.0`, `-Check`) does the same
steps, except `doctor` (there is none on Windows): it ends by checking that the
ERP answers and showing the licence state.

`./tarleaks upgrade <release>` is the inner step (download, backup, switch,
database) without the checks before and after. Use `update`.

### Without internet

Get the new release's offline bundle and kit first (see
[faq.md](faq.md#can-i-install-without-internet)), then:

```bash
./tarleaks load-bundle /media/usb/tarleaks-1.2.0-linux-amd64
./tarleaks update --to 1.2.0 --offline   # Windows: .\tarleaks.ps1 update -To 1.2.0 -Offline
```

Offline the registry cannot be asked, so name the release; `--offline` uses
only the images on the machine.

## After the upgrade

```bash
./tarleaks status
```

- Every service should be `running`, and the licence line should say `active`.
- **Settings, Licence** shows the new **Version**.
- Sign in and open the screens your team uses most.
- If something looks wrong: `./tarleaks doctor`, then `./tarleaks logs auth`.

## Moving to 1.2.0

Release 1.2.0 is in preparation; Tarleaks will tell you when it is out. Release
candidates (`1.2.0-rc.2`) are for evaluation: try them on a server of their
own, not on the one your company works on.

**From 1.0.0** the kit itself is older than `./tarleaks update`, so get the new
kit first, once:

```bash
git fetch --tags && git checkout v1.2.0     # a ZIP install: unpack the 1.2.0 ZIP over this folder (.env stays)
./tarleaks update --to 1.2.0                # Windows: .\tarleaks.ps1 update -To 1.2.0
```

Do not run `./tarleaks upgrade 1.2.0` from the 1.0.0 kit: that would start the
new programs with the old kit's settings. **From a 1.2.0 release candidate**,
get the kit of the next one the same way and run `./tarleaks update`. From then
on `./tarleaks update` is the command for every release.

What else changes for an installation you already run:

- **Nothing to set up.** Your company becomes the first company under its
  existing licence. Users, data, apps and the address stay as they are.
- **Every service checks the licence itself**, not only the gateway. With a
  licence in order you notice nothing.
- **Seats are checked at sign-in.** If more people are active than your licence
  allows, only administrators who manage users can sign in until they switch
  people off or Tarleaks adds seats ([licensing.md](licensing.md#seats)).
- **One running copy per licence.** Stop any copy of this server (a restored
  backup on another machine, a cloned virtual machine) before you update: from
  1.2.0 the copy whose `auth` service started most recently keeps the licence
  and the other is refused.
- **Your own PostgreSQL server** must keep the same time as the ERP (automatic
  time on both), or the ERP locks with "The clocks on this installation
  disagree".
- **More companies on the same server** become possible, each at its own
  address: [companies-and-domains.md](companies-and-domains.md).
- **Diagram Studio** was left out of 1.2.0-rc.1 and rc.2 while it was rebuilt,
  and is back from 1.2.0-rc.3. Its data is kept in every case. It now draws with
  AI by itself, with each company's AI settings (Settings, AI), so the separate
  drawing engine of 1.0.0 is gone. If you ran it on 1.0.0 and your apps list
  still names it, it starts again on the new release. If it was left out in the
  meantime, add it again with `./tarleaks apps add diagrams`.

## If the download fails

| Message | Cause | Fix |
|---|---|---|
| "The image registry did not accept the licence key: …", `unauthorized`, `denied` | The licence cannot download new versions (the sentence says why: ended, withdrawn, suspended) | Renew or fix the licence (Settings, Licence), then run the upgrade again; nothing was changed ([requirements.md](requirements.md#access-to-the-images)) |
| `manifest unknown`, `not found` | There is no such version | Check the version number, then `grep ^TARLEAKS_VERSION .env` |
| `no space left on device` | The disk is full | Free space. `docker image prune` removes unused images |
| Timeouts | No route to `registry.tarleaks.com` or Docker Hub | See [requirements.md](requirements.md#network) (a proxy for Docker), or use the offline bundle |

If the download fails, the old release keeps running and `.env` still names it:
nothing changed. Fix the cause and run `./tarleaks update` again, or load the
release's offline bundle and run `./tarleaks update --to <release> --offline`.

## Rolling back

There is no downgrade command, because a newer release may change the database in
a way an older one cannot read. `./tarleaks upgrade <older release>` is refused
(release candidates count: `1.2.0-rc.1` is older than `1.2.0-rc.2`, which is older
than `1.2.0`). To go back, restore the backup the upgrade took just before it
started; a failed upgrade prints the exact command.

The backup's copy of `.env` still names the version you ran before, so restoring
it brings back both the data and that version:

1. Find the folder: `ls backups/`. The update's backup is named
   `pre-update-<old>-to-<new>-<date-time>` (`pre-upgrade-<old>-<date-time>`
   when it came from `./tarleaks upgrade`).
2. Restore:

   ```bash
   ./tarleaks restore backups/<folder>
   ```

   Type `RESTORE` when asked. This **replaces** the database and the files with
   the backup, so anything entered since the upgrade is lost.

On Windows: `.\tarleaks.ps1 restore backups\<folder>`.

## Good habits

- Upgrade outside working hours, and tell people first.
- Keep a copy of the pre-upgrade backup somewhere else until you are happy with
  the new version.
- Do **not** rehearse an upgrade by restoring your production backup on a second
  machine while production runs. Two copies share one installation ID, so the
  licence server sees one licence checking in from two places. Rehearse on a
  separate trial installation.
- The third-party images (database, cache, message queue, gateway, file store) are
  pinned in `docker-compose.yml`. A new kit release moves those pins, so get the
  release's kit before you update.
- Adding or removing apps is not an upgrade: `./tarleaks apps add …` / `remove …`.
