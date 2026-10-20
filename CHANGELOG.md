# Changelog

What changed in each release of the Tarleaks ERP self-hosted kit (this
repository) and what an installation notices. How to move between releases:
[docs/upgrading.md](docs/upgrading.md).

## [Unreleased]

### Added

- **`./tarleaks doctor --bundle [file]`**: one support file with the doctor's
  report, versions, containers, the last 2000 log lines of every service,
  database sizes and migration heads, and the names (never the values) of the
  `.env` settings. Passwords and keys from `.env`, licence keys, sign-in tokens,
  passwords in addresses, signed links, private keys, e-mail addresses, IBANs,
  Emirates ID and phone numbers (in the shapes it knows) are taken out before
  anything is packed (`scripts/lib-scrub.sh`, proven in CI by
  `scripts/check-bundle-scrub.sh`). Nothing is sent anywhere. (Tarleaks Hybrid
  R39, slice 8.)

- **`./tarleaks update`** (Windows: `.\tarleaks.ps1 update`): one command to the
  newest release, or `--to <release>`. It checks the release is published and
  that this kit knows it, backs up first (and stops if that fails), downloads,
  updates the database, starts the new release, waits for it and runs
  `./tarleaks doctor` (Windows: checks it answers and the licence state). When a step fails it prints the exact way back; run
  again, it only checks. `--check` tells you whether a release is available.
  [docs/upgrading.md](docs/upgrading.md).
- `./tarleaks doctor` warns when the machine is short of inotify instances
  (the gateway would start without its routes and every page answer 404), and
  says so plainly when it has happened.
- `./tarleaks reset-admin <e-mail>` (Windows `.\tarleaks.ps1 reset-admin`):
  an administrator who cannot sign in gets a temporary password on a server
  without outgoing e-mail, with the account switched on and the Administrator
  role given back ([docs/troubleshooting.md](docs/troubleshooting.md#somebody-cannot-sign-in)).
  Needs a release that has the command; an older one says so.

### Fixed

- `./tarleaks restore` refuses a backup of another installation on the same
  machine (it would have taken over that installation and replaced its data);
  `--keep-settings` (Windows `-KeepSettings`) loads a backup into this
  installation keeping its name, port, address, HTTPS and offline settings, for
  a test copy or a new machine with another address. When the backup's address
  differs, the restore says which one applies.
- The installer writes the installation's name (`COMPOSE_PROJECT_NAME`) into a
  new `.env` every time, so a backup always says whose data it holds.
- `./tarleaks upgrade` refuses an older release candidate (`1.2.0-rc.1` on
  `1.2.0-rc.2`, or a candidate on its final release) like any older release;
  when the new release does not start, it prints the restore command that goes
  back.
- Sealed tenders can be opened: the installer (and, for an existing
  installation, `./tarleaks start` or `restart` once the message-queue image is
  on the machine) creates the sign-in token key that two-step confirmation
  needs, and says so. Sessions signed in before stay valid.
- A fresh install no longer stops at random with "service postgres-prepare
  didn't complete successfully": the database counts as ready only once it
  takes network connections, not while its first-start initialisation runs.
- Contracts and Construction find the document editor's server, so a contract
  drafted from a template and a payment certificate get their PDF when the
  editors are on.

## [1.2.0-rc.2] - 2026-10-20

The second **release candidate** of 1.2.0, for evaluation on a fresh server.
The kit installs it by default.

### Changed

- New images. The self-hosted web application has no platform console, the
  web server no longer names its version, Diagram Studio is left out, and the
  programs carry no source code, source maps or names of real companies.
- The installer refuses to create a new installation on top of the data of
  another one: when Docker already holds volumes for the installation's name
  and the folder has no `.env`, it stops and explains (before, it silently
  reused that data). A second installation on the same machine takes its own
  name: `COMPOSE_PROJECT_NAME=erp2 ./install.sh --port 8080`.

## [1.2.0-rc.1] - 2026-10-20

A **release candidate** of 1.2.0, for evaluation. Do not run it in production;
the final 1.2.0 replaces it.

### Added

- **Procurement & Tenders, Construction and Contracts** apps
  ([docs/apps.md](docs/apps.md)).
- **HTTPS by the gateway** on your own domain, with a Let's Encrypt or
  Cloudflare certificate ([docs/https.md](docs/https.md)).
- **Offline installation and upgrade** from an offline bundle
  (`./tarleaks load-bundle`, `--offline`), and an offline mode that keeps the
  ERP off the internet ([docs/offline.md](docs/offline.md)).
- **Choose your apps** instead of a hardware profile: `--apps`,
  `./tarleaks apps add` / `remove` ([docs/apps.md](docs/apps.md)).
- `./tarleaks network local` / `office`: who may open the ERP.
- Clock-in machines (fingerprint, face and card readers) reach the ERP through
  the gateway ([docs/attendance-machines.md](docs/attendance-machines.md)).
- Optional database access for a reporting tool, on `127.0.0.1` only
  ([examples/database-access](examples/database-access)).
- An outbound proxy for servers that reach the internet through one
  ([examples/outbound-proxy](examples/outbound-proxy)).

### Changed

- **Images come from `registry.tarleaks.com`, and your licence key is the
  download password.** No `docker login`; the installer signs Docker in. An
  `.env` from the private preview is moved to the new address by itself.
- What 1.2.0 changes for an installation you already run (licence checks,
  seats, one server per licence, more companies per server):
  [docs/upgrading.md](docs/upgrading.md#moving-to-120).
- Upgrading from 1.0.0 adds the settings a newer kit needs to `.env` and keeps
  every existing value.
- **Security:** only the gateway publishes a port; every other service is
  reachable only inside Docker.
- No telemetry and no version check.

### Removed

- **Diagram Studio** is not in 1.2.0. It is being rebuilt and returns in a
  later release. An installation that runs it on 1.0.0 keeps its data; the app
  simply does not start on 1.2.0.

### Known limitations of this candidate

- `./tarleaks update` was not in this candidate's kit (it came after rc.2).
  Install a fresh evaluation server with `./install.sh` instead of moving a
  1.0.0 installation.
- Activation with no internet connection at all is not available yet: a
  licence needs one connection to `tarleaks.com`
  ([docs/faq.md](docs/faq.md#can-i-install-without-internet)).

## [1.0.0]

The first release, as a private preview: HR, payroll, accounting, CRM,
inventory, sales and the other apps on one server, installed with
`./install.sh` (Linux, macOS) or `.\install.ps1` (Windows).
