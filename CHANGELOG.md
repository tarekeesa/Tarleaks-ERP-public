# Changelog

What changed in each release of the Tarleaks ERP self-hosted kit (this
repository) and what an installation notices. How to move between releases:
[docs/upgrading.md](docs/upgrading.md).

## [Unreleased]

## [1.2.0-rc.7] - 2026-11-01

The seventh **release candidate** of 1.2.0, the first one signed with the Tarleaks release key. The kit installs it
by default. What an installation notices:

### Added

- **Offline bundles are signed, and `load-bundle` checks the signature.** Every bundle and image of a release is
  signed with the Tarleaks release key; `./tarleaks load-bundle` (Windows: `.\tarleaks.ps1 load-bundle`) verifies the
  bundle's signed checksum list with `config/sigstore/tarleaks-release.pub` before it checks or loads anything, also
  without internet (`config/sigstore/trusted_root.json`). It needs cosign 2.4 or later on the server; a bundle you
  built yourself loads with `--allow-unsigned` (`-AllowUnsigned`). Each bundle also carries the release's SBOMs
  (CycloneDX 1.6) under `sbom/`. [config/sigstore/README.md](config/sigstore/README.md). CI proves every refusal
  (no signature, another key, a list changed after signing, no public key, no or too old cosign) for both front ends:
  `scripts/check-bundle-signature.sh` and `scripts/check-bundle-signature.ps1`.
- **Downloaded images are checked for the Tarleaks signature before anything runs them** (releases 1.2.0-rc.7 and
  later). After `./install.sh`, `./tarleaks upgrade`, `./tarleaks update`, `./tarleaks apps add` and
  `./tarleaks editors on` (Windows: the same in `install.ps1` / `tarleaks.ps1`) download images, every Tarleaks image
  is verified with `config/sigstore/tarleaks-release.pub`, by the exact digest Docker downloaded. An image that is not
  signed by Tarleaks is refused, named and removed; an upgrade then stops before its backup and the running release
  keeps running. A signature that cannot be read (no connection) removes nothing. It uses cosign 2.4 or later when the
  server has it, otherwise Sigstore's own cosign image (pinned by digest, read-only, as your user; it needs outbound
  HTTPS to `ghcr.io`, [docs/requirements.md](docs/requirements.md#network)). `TARLEAKS_ALLOW_UNSIGNED=1` is the only
  way past, for images you built yourself. Images already on the server run only when this server checked them
  (recorded in `.tarleaks-verified`, also for a signed offline bundle): `start`, `restart`, `apps remove`,
  `editors off`, `update`, the off-site backup engine, the sign-in restart of `migrate-from-cloud --vendor` and an
  install or upgrade that downloads nothing check an image that was never checked here or changed since (online; a
  kit older than this one downloaded it) and refuse it offline or when missing, saying how to fix it. A record the
  kit cannot write is a refusal that says how to give the folder back to your user. CI proves every case for both front ends: `scripts/check-image-signature.sh` and
  `scripts/check-image-signature.ps1`.

- **Move a company from Tarleaks Cloud to your own server** (needs release 1.2.0-rc.6 or later on the server).
  `./install.sh --from-cloud <code>` (Windows: `.\install.ps1 -FromCloud <code>`) installs the ERP and moves the
  company in one go; on an installed server that is not set up yet, `./tarleaks migrate-from-cloud <code>`. The server
  fetches the company encrypted to its own key, checks every table and file, prints the report and what to connect
  again, and switches over when you say so (`--switch-over`); `--status`, `--resume` and `--cancel` follow, continue
  or stop it. The move code is asked without being shown when it is left out, and neither code is printed or written
  to a file. [docs/move-from-cloud.md](docs/move-from-cloud.md).

### Changed

- **The ERP's containers no longer run as root.** Every app and its jobs run as uid 10001; the update steps run as that user or as the database's own user. They
  have read-only program files and no Linux capabilities, and no program in them can gain rights. They write only
  to `/tmp` and their volumes. The database, cache, message queue and web servers keep only the capabilities their
  start needs. The gateway keeps one: opening ports 80 and 443. A new one-off step, `volume-owner`, gives the HR
  documents volume to that user at every start, so an upgraded installation needs nothing by hand.
  `TARLEAKS_RUN_AS=0:0` in `.env` runs them as root again while a file-ownership problem is fixed (still without
  capabilities).
  [docs/configuration.md#container-security](docs/configuration.md#container-security).
- **Password sign-in has its own guard against guessing:** 300 tries a minute per address (burst 600), like Tarleaks
  Cloud. Before, it shared the general sign-in limit of 60 requests a *second*. Refresh, the sign-in poll, password
  reset and single sign-on keep that general limit, now written out as `period: 1s`. CI (`scripts/check-routes.sh`)
  now fails on a `rateLimit` that leaves `period` out.
- **HTTPS installations accept only TLS 1.2 and 1.3, with forward-secret AEAD cipher suites for TLS 1.2** (no CBC,
  no SHA-1). Every browser and phone of the last eight years connects. Plain-http installations are unchanged.
- **Updated third-party images**, each checked for known vulnerabilities on both CPU types: Redis 7.4.12, Traefik
  3.7.17, the file store (VersityGW) 1.10.0, curl 8.23.0 and draw.io 31.7.0.

### Fixed

- **`./tarleaks migrate-from-cloud` no longer stops with `$2: unbound variable`.** In 1.2.0-rc.6 the command
  stopped at its first progress check, at `--status` and when run without a code, before it asked the ERP anything;
  a move that had started went on in the ERP while the screen showed only the error. A move code can now also be
  piped in from a file (`./tarleaks migrate-from-cloud < move-code.txt`, with `--switch-over` too), so a script need not
  put it on a command line (Linux). [docs/move-from-cloud.md](docs/move-from-cloud.md).

## [1.2.0-rc.6] - 2026-10-30

The sixth **release candidate** of 1.2.0. The kit installs it by default. What an installation notices:

### Fixed

- **The sample company's people use no employee seat.** With the UAE sample loaded, a licence with an employee
  limit counted its 184 people, so a 25-seat trial refused your first own hire. Only your own employees count now.
- **The sample company never bills or messages anyone.** Sample subscriptions are no longer renewed, chased or
  reminded, so a demo never issues an invoice, posts to your books or files an e-invoice. An event about a sample
  record stays in the bell: no e-mail, SMS, push, chat message or webhook goes out for it.
- **Sample data can be removed after days of running.** `./tarleaks sample-data remove` refused once the
  installation had worked on the sample for a while: tasks the project automations created, a subscription
  renewal, scheduled report runs, reminders and alerts. What the system provably made from the sample now goes with
  it. Anything a person made or edited, anything that names your own people, and any posted journal entry or
  e-invoice still stop the removal, with the list of records, and nothing is removed.
- **Every app gets the internal service key.** Only Documents, Contracts and the PDF tools had it, so the rental app
  could not ask Documents to retire customers' ID copies after their retention period (refused every 15 minutes),
  and other apps' internal calls were refused the same way.
- **Every app gets the keys its features need.** The installer now makes, and `./tarleaks upgrade` adds to an
  existing `.env`, the keys these features refused to work without: e-invoicing (ZATCA units and providers could
  not be connected), LMS certificates (none could be issued), mailboxes connected in CRM and Correspondence,
  signing certificates in PDF Tools and Correspondence, Finance's FTA connection and Settings, Integrations (the
  shared sealing key), Accept and Decline links in invitations, Open Badges, and single sign-on secrets. Links in
  invitations and e-mails now use your address instead of `localhost`. The monitoring alert hook now asks for the
  internal key. Back up `.env` after upgrading: what these keys seal cannot be read without them.
- **The kit cannot fall behind the cloud's keys again.** A new check (`scripts/check-service-secrets.sh`, run by CI
  and by every release) compares each app's keys with the cloud's and fails until each difference is given or
  explained.

## [1.2.0-rc.5] - 2026-10-29

The fifth **release candidate** of 1.2.0. The kit installs it by default. What an installation notices:

### Changed

- `LICENSE.md` is version 1.1 of the **Tarleaks ERP Self-Hosted Licence** (licensor TARLEAKS FOR TRADING FZE LLC):
  for business customers only, disputes settled by DIAC arbitration, who controls and who processes personal data,
  withholding tax grossed up, and clearer warranty and force-majeure terms.

### Fixed

- **Sample data loads on a running installation.** `./tarleaks sample-data load` on the UAE company stopped at the
  point-of-sale step (`null value in column "track_serials"`), and `resume` stopped there again. It now loads every
  app. The learning history keeps one enrolment per course and learner, as the app does.
- **Sample data can be removed after the installation has been running.** `./tarleaks sample-data remove` refused
  with `SAMPLE_DATA_IN_USE` once the system had sent notifications to the sample logins (low-stock alerts,
  reminders) or the attendance processor had looked at the sample punches again. Those notifications now go with
  the sample company. The sample punches left for review now give only reasons that stay true, so the
  attendance processor no longer rebuilds sample days from them. Your own users'
  notifications and punches are never touched. Anything a person created on a sample record still stops the
  removal, with the list of records (`--adopt` keeps them).
- **First-run setup continued with a new password.** When setup stopped part-way and the setup screen was filled
  in again with a different password, the new password did not sign in. The administrator now gets the password
  typed the second time, provided they never signed in. Their sessions end, and the change is audited.
- `sample-data load` on a company that already has its own users now names the way on (`--force-nonempty`,
  Windows `-ForceNonempty`).
- **Accounting:** a bill typed by hand for goods received on a purchase order is matched to the order's lines, so
  posting it no longer expenses the goods a second time, and goods received not invoiced clears.
- **Invitations are e-mailed again.** Inviting a colleague told the administrator "sent", but no message went out.
- **PDF tools:** the watermark, page numbers, signatures, initials, stamps and logo were drawn small and mirrored
  in a corner on PDFs printed from Chrome. They are now in place.
- **Sales orders:** with "salespeople see only their own orders" on (the default for a new company), only the
  administrator could start a delivery. The store keeper now starts it from **Sales orders → To deliver**.
- **Payroll (UAE):** the WPS salary file (SIF) follows the Central Bank layout: employee records first, each with the
  employee's own bank and the 14-digit MOHRE person number, and the variable-pay records.
- **Project P&L shows revenue:** a customer invoice can carry its project (see the known limitation below).
- Smaller fixes across contracts, assets, helpdesk, documents, learning, sign-in checks, reports, rental and
  project time logging. Lists show names and yes/no words instead of "—", and reports offer name pickers
  instead of id boxes.

### Known limitation

- **Invoicing a project from its timesheets or milestones (time-and-materials or milestone billing) is not in
  1.2.0.** Workaround: raise the customer invoice in **Accounting → Receivables → New invoice**, type the hours or
  the milestone as invoice lines, and pick the **Project**. **Project → Reports → P&L** then counts the invoice
  as the project's revenue (before VAT, credit notes deducted).

## [1.2.0-rc.4] - 2026-10-28

The fourth **release candidate** of 1.2.0. The kit installs it by default. What an installation notices:

### Changed

- **Installing and updating survive a dropped download.** When the connection to the image registry or Docker Hub
  drops halfway (a reset, a timeout, an unexpected end of the download), `./install.sh`, `./tarleaks update` and
  `apps add` try again twice, 10 seconds apart, keeping what was already downloaded; a refusal (licence, a release
  or app that does not exist, a full disk, a certificate) is still reported at once. When the download does give up,
  the message now ends with what Docker said, so the cause is visible. `TARLEAKS_PULL_TRIES=1` turns the retry off.
- `docs/troubleshooting.md`: when first-run setup stops at the time limit, opening the setup screen again with the
  **same administrator e-mail and password** continues it (the company it already created is kept); it said the
  attempt saved nothing.

### Fixed

- **A contract made from a template can be sent for signature again.** Sending it turned the document into a
  PDF through the document editor, which refused the request (its file name was not a key the editor accepts),
  so the contract never reached the signer.
- **Payroll: the employee's share of pension and social insurance reaches the ledger** (GPSSA, GOSI, SIO, PIFSS,
  SPFL, GRSIA in the six Gulf country packs). Posting payroll left that share on Salaries payable instead of the
  social-insurance payable account, and accepting the salary bank file then booked the same amount as paid from
  the bank. Payroll posted from this release on books it correctly, and the update corrects the installed salary
  rules (each change is kept in the rule's history). Runs posted earlier are not changed: the accountant moves
  the amount from Salaries payable to Social insurance payable, and reverses the extra bank payment if the bank
  file was accepted (the What's new note on the payroll runs page says how).

## [1.2.0-rc.3] - 2026-10-27

The third **release candidate** of 1.2.0. This revision of the kit is the one the
release gate runs for it; once the rc.3 images are published, the kit installs
them by default. What the kit itself changed since 1.2.0-rc.2.1:

### Changed

- `LICENSE.md` is now the **Tarleaks ERP Self-Hosted Licence** (licensor TARLEAKS FOR TRADING FZE LLC,
  governed by the laws of the United Arab Emirates): use with a valid licence or trial key, no
  reverse engineering or redistribution of the binaries, your data stays yours, warranty disclaimer
  and a liability cap.
- The gateway's request time limit follows `HTTP_LONG_REQUEST_TIMEOUT_SECS` (default 300 s), the same
  setting as the services' long requests, so a slow disk can give first-run setup more time with one
  line in `.env` (docs/troubleshooting.md).
- `SECURITY.md`: report vulnerabilities through GitHub private vulnerability reporting
  (**Security**, **Report a vulnerability**), with dev@tarleaks.com as the fallback.

### Added

- Issue forms for bug reports, install or upgrade problems and feature requests. Blank issues are
  off, and the issue chooser points security reports to the private channel.
- **From 1.2.0:** `./tarleaks sample-data status | load | check | remove | resume | modules` fills a new company with a
  fictional one (a UAE or Saudi company with two years of records in every app) and takes it out again exactly; your
  own records are never changed or deleted. `load --install-packs` installs the company's country packs first;
  `remove --yes` (`--adopt` keeps the sample records your own records use). It refuses with a plain message on a
  release that does not have sample data yet. On Windows: `.\tarleaks.ps1 sample-data load -InstallPacks`,
  `remove -Yes [-Adopt]`, `-Company <name>`. [docs/sample-data.md](docs/sample-data.md).
- Off-site copies, encrypted (Linux, macOS and Windows): `./tarleaks backup --offsite`, `./tarleaks cloud backup-key …`,
  `cloud backup target folder <path>`, `cloud backup list | verify | prune | schedule`, `cloud status`, and
  `./tarleaks restore --from-cloud [copy] --recovery-kit <file>`. A copy is encrypted to a key only the recovery kit
  can open, signed, numbered and chained; this release stores it in a folder (a mounted share or a second disk). Needs
  a release whose `migrate` image has the backup engine; older releases say so and change nothing. Not yet: your own
  S3 bucket and Tarleaks storage as targets, the licence check for the off-site service, and the vendor's record of
  each copy that catches an older copy put in place of a newer one; they come with the cloud gateway.
  On Windows: `.\tarleaks.ps1 backup -Offsite`, `cloud …`, `restore -FromCloud -RecoveryKit <file>`, the schedule as a
  Scheduled Task. [docs/backup-restore.md](docs/backup-restore.md#from-130-off-site-copies-encrypted---offsite).

### Changed

- **Diagram Studio is back.** The app sheet (`config/app-releases.tsv`) no longer withdraws the `diagrams` app in
  1.2.0, so the `full` preset, `./tarleaks apps add diagrams` and the release gate include it again, together with the
  diagram editor (draw.io) that runs with it. 1.2.0-rc.1 and rc.2 do not have its image; use rc.3 or later.
  `scripts/check-apps.sh` checks that it is accepted on every release.

### Removed

- **The `diagrams-engine` add-on.** Diagram Studio's rewrite draws with AI inside the `diagrams` app itself, with
  each company's own AI settings (Settings, AI), so there is no separate engine container, image, compose profile or
  `TARLEAKS_DIAGRAMS_ENGINE_URL` / `DIAGRAMS_ENGINE_MEM_LIMIT` / `DIAGRAMS_MODEL_ID` setting any more. No published
  release ran it (it was to arrive in 1.2.0, which left Diagram Studio out while it was rebuilt), so nothing on an
  installation changes.

## [1.2.0-rc.2.1] - 2026-10-21

A **kit revision** for the 1.2.0-rc.2 programs: the installer, `./tarleaks`
and the documentation change; the programs stay 1.2.0-rc.2 (the kit still
installs them by default). Get it with
`git fetch --tags && git checkout v1.2.0-rc.2.1`, then `./tarleaks start`.

### Added

- **Windows: `.\tarleaks.ps1 doctor` and `.\tarleaks.ps1 doctor -Bundle [file]`.** The checks of the Linux and
  macOS doctor that apply on Windows (Docker, containers and their health, leftover containers, memory for the chosen
  apps, the workspace database, messaging, the document editor, the address, the licence server, image downloads, the
  clock, free disk; the profile and addresses check covers what Windows offers — the local profile, or production behind your own HTTPS
  reverse proxy —, and the gateway routes check reads the limit of the WSL 2 engine behind Docker Desktop), and the same support bundle as Linux and macOS, scrubbed by
  `scripts/lib-scrub.ps1` with the same rules (proven in CI by `scripts/check-bundle-scrub.ps1`).
- **`./tarleaks doctor --bundle [file]`**: one support file with the doctor's
  report, versions, containers, the last 2000 log lines of every service,
  database sizes and migration heads, and the names (never the values) of the
  `.env` settings. Passwords and keys from `.env`, licence keys, sign-in tokens,
  passwords in addresses, signed links, private keys, e-mail addresses, IBANs,
  Emirates ID and phone numbers (in the shapes it knows) are taken out before
  anything is packed (`scripts/lib-scrub.sh`, proven in CI by
  `scripts/check-bundle-scrub.sh`). Nothing is sent anywhere.

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
