# Tarleaks ERP — self-hosted

Run the whole Tarleaks ERP on your own computer or server: HR and payroll,
accounting, CRM, inventory, sales, projects, helpdesk, learning, commerce and
more, in one workspace that you own.

This repository holds **only what you need to install it**: a Docker Compose
file, an installer for Linux, macOS and Windows, settings, examples and
documentation. The software itself comes as pre-built images for Intel/AMD
(`amd64`) and ARM (`arm64`) machines. No source code is included or needed.

> **Your licence key is the download password.** The installer signs Docker in
> to `registry.tarleaks.com` with it (no `docker login`), or starts the free
> 30-day trial when you have no key yet.

## Install in three steps

**Linux or macOS**

```bash
git clone https://github.com/tarekeesa/Tarleaks-ERP.git
cd Tarleaks-ERP
./install.sh
```

**Windows 10/11** (Docker Desktop with WSL 2, in PowerShell)

```powershell
git clone https://github.com/tarekeesa/Tarleaks-ERP.git
cd Tarleaks-ERP
.\install.ps1
```

The installer checks Docker, memory, disk and CPU type. It asks which apps to
run (or takes `--apps`), writes `.env` with freshly generated passwords and keys, downloads the
images and starts everything. At the end it prints the **address** and a
**setup code**.

Open the address in a browser. Then:

1. Type the setup code.
2. Enter your company name and country, and create the first administrator.
3. Choose **Start a 30-day free trial**, or paste a licence key.
4. Sign in.

## Choose your apps

Install only what you use. Each app brings the apps it cannot work without, and
nothing else runs:

```bash
./install.sh --apps hr,crm          # Windows: .\install.ps1 -Apps hr,crm
```

HR and CRM run 22 containers in about 2 GB of memory, plus about 2 GB for the
editors (New and Edit in Documents, the diagram editor; `./tarleaks editors off`
gives it back): a 2-core, 8 GB server, or 4 GB with the editors off. Without `--apps` the installer offers three presets (`small`,
`standard`, `full`) or lets you type the apps. Change your mind any time:
`./tarleaks apps add payroll`, `./tarleaks apps remove crm`.

What each app needs and costs: [docs/apps.md](docs/apps.md).
Step by step for your kind of machine: **[docs/setup-guide.md](docs/setup-guide.md)**.

| You run | CPU | Memory | Disk |
|---|---|---|---|
| HR and CRM | 2 | 8 GB (4 GB with the editors off) | 20 GB |
| `small` preset (HR, payroll, accounting, CRM, inventory, sales, chat …) | 2 | 8 GB (4 GB with the editors off) | 20 GB |
| `standard` preset (+ projects, helpdesk, assets, fleet, learning, commerce …; procurement, construction and contracts from release 1.2.0) | 4 | 8 GB | 40 GB |
| `full` (+ PDF tools with OCR, ISO compliance; diagrams on 1.0.0 only) | 8 | 16 GB | 80 GB |

It runs on:

- Linux servers: Ubuntu 22.04/24.04, Debian 12, RHEL, Rocky and Alma 9, on
  Intel/AMD or ARM (AWS Graviton, Ampere, Hetzner ARM).
- Macs (Intel or Apple Silicon) with Docker Desktop.
- Windows 10/11 with Docker Desktop and WSL 2.
- Raspberry Pi 5 with 8 GB and the 64-bit OS.

Details: [docs/requirements.md](docs/requirements.md).

## Examples

| You want to… | Example |
|---|---|
| Try it on your own computer | [examples/laptop](examples/laptop) |
| Run it for the office on a local server | [examples/office-server](examples/office-server) |
| Put it on the internet with HTTPS | [docs/https.md](docs/https.md) (or Caddy: [examples/vps-https](examples/vps-https)) |
| Use a Raspberry Pi 5 | [examples/raspberry-pi](examples/raspberry-pi) |
| Run it behind your existing nginx | [examples/behind-nginx](examples/behind-nginx) |
| Keep files in AWS S3, Cloudflare R2 or Wasabi | [examples/s3-storage](examples/s3-storage) |
| Use your own PostgreSQL server (advanced) | [examples/external-postgres](examples/external-postgres) |
| Install on Windows | [examples/windows](examples/windows) |
| Back up every night | [examples/scheduled-backups](examples/scheduled-backups) |

## Everyday commands

| Linux / macOS | Windows | What it does |
|---|---|---|
| `./tarleaks status` | `.\tarleaks.ps1 status` | What is running, and the licence state |
| `./tarleaks apps` | `.\tarleaks.ps1 apps` | Which apps run, what each needs; `add` / `remove` apps |
| `./tarleaks editors on` / `off` | `.\tarleaks.ps1 editors on` / `off` | The document and diagram editors (about 2 GB) |
| `./tarleaks network local` / `office` | `.\tarleaks.ps1 network local` / `office` | Who may open the ERP: only this computer, or the whole network |
| `./tarleaks stop` / `start` | `.\tarleaks.ps1 stop` / `start` | Stop and start. Your data stays. |
| `./tarleaks logs auth` | `.\tarleaks.ps1 logs auth` | Follow one service's log |
| `./tarleaks backup` | `.\tarleaks.ps1 backup` | Database, files and settings into `backups/` |
| `./tarleaks restore <folder>` | `.\tarleaks.ps1 restore <folder>` | Put a backup back (checks it first, keeps what was there) |
| `./tarleaks update` | `.\tarleaks.ps1 update` | Move to the newest release: check, back up, update, start, check again (`--to <release>`, `--check`) |
| `./tarleaks doctor` | — | Check the installation and explain what is wrong |
| `./tarleaks doctor --bundle` | — | The same, plus logs and versions, in one file for support, with passwords, keys and contact details in known shapes taken out ([docs/troubleshooting.md](docs/troubleshooting.md#still-stuck)) |
| `./tarleaks setup-code` | `.\tarleaks.ps1 setup-code` | Show the setup code again |
| `./tarleaks load-bundle <folder>` | `.\tarleaks.ps1 load-bundle <folder>` | Load the images of an offline bundle (no internet needed) |
| `./tarleaks uninstall` | `.\tarleaks.ps1 uninstall` | Remove the containers (`--purge` / `-Purge`: the data too) |

## Upgrade

```bash
./tarleaks update                     # Windows: .\tarleaks.ps1 update
```

It checks the release is published and that this kit knows it, backs up
first, downloads the new images, updates the database, starts the new release
and runs `./tarleaks doctor`; your data and `.env` stay. If a step fails it
prints the exact way back. What changed in each release:
[CHANGELOG.md](CHANGELOG.md). Step by step, including the one-time move to
1.2.0: [docs/upgrading.md](docs/upgrading.md). A release candidate such as
`1.2.0-rc.2` is for evaluation on a fresh server, not for upgrading a running
installation.

## No internet on the server

Install and upgrade from an **offline bundle**: every image of one release on a
USB disk, loaded with `./tarleaks load-bundle <folder>`, then
`./install.sh --offline` (or `./tarleaks update --to <release> --offline`).
`./tarleaks offline on` keeps a running installation off the internet
altogether. Details: [docs/offline.md](docs/offline.md) and
[docs/faq.md](docs/faq.md#can-i-install-without-internet).

## HTTPS on your own domain

Point a DNS name (for example `erp.example.com`) at the server, open ports 80
and 443, and let the gateway get a free Let's Encrypt certificate
(`--tls cloudflare` gets one through Cloudflare DNS instead):

```bash
./install.sh --profile-env production --host erp.example.com \
  --tls letsencrypt --acme-email it@example.com
```

Behind your own nginx, Caddy or load balancer instead:
[examples/behind-nginx](examples/behind-nginx), [examples/vps-https](examples/vps-https).
Every option, step by step: [docs/https.md](docs/https.md).

## Licence and the daily check-in

Each installation is licensed, either as a trial or with a key from Tarleaks.
The ERP checks its licence with `tarleaks.com` about every **6 hours** and has
to reach it **at least once a day**. If it cannot reach it for 30 hours, it
stops serving until a check-in succeeds. It retries every two minutes on its
own, and **Check again** on the screen retries at once.

A check-in sends only the licence ID, the installation ID, the version, the
CPU type and the number of active users. **Your business data never leaves
your server.**

Allow outbound HTTPS (port 443) to `tarleaks.com` (directly or through a proxy
set in `.env`), and keep the server's clock correct by turning on automatic time
(NTP).

**No internet on the server?** Install from the offline bundle:
[docs/faq.md](docs/faq.md#can-i-install-without-internet). What the ERP connects
to, and what is off by default: [docs/network.md](docs/network.md).

Licences are decided by Tarleaks on tarleaks.com and arrive signed. Your server
has no platform console or platform administrator of any kind.

Details: [docs/licensing.md](docs/licensing.md). Licence terms:
[LICENSE.md](LICENSE.md).

## Companies and addresses

Today one installation runs **one company** at one address of your choice:
`localhost`, an IP address, a name such as `erp.example.com`, or a domain's
root. **From release 1.2.0** one server runs several companies, each with its
own licence, seats and apps, at `<company>.erp.example.com` and, if the server
administrator attaches one, its own domain. Tarleaks adds a company for you, or
whoever holds the server's setup code adds one with a key Tarleaks issued.
Details: [docs/companies-and-domains.md](docs/companies-and-domains.md).

## Your data

Everything lives in Docker volumes on your machine:

- `pgdata`: the database.
- `files`: documents and attachments.
- `redisdata`, `rabbitdata` and `hrdocs`: caches, queues and HR templates.

`.env` holds the passwords and keys. `./tarleaks backup` copies the database,
the files and `.env` into `backups/`. A backup is your whole database in readable
SQL plus your keys: encrypt it before it leaves the machine
([backup and restore](docs/backup-restore.md)).

## Help

- [Setup guide (every environment, step by step)](docs/setup-guide.md)
- [Choosing apps](docs/apps.md)
- [Companies, addresses and who controls what](docs/companies-and-domains.md)
- [Troubleshooting (every error message)](docs/troubleshooting.md)
- [Configuration (every setting)](docs/configuration.md)
- [Your own domain with HTTPS](docs/https.md) · [Running without internet](docs/offline.md)
- [Clock-in machines (fingerprint, face and card readers)](docs/attendance-machines.md)
- [Upgrading](docs/upgrading.md) · [Backup and restore](docs/backup-restore.md) ·
  [Security](docs/security.md) · [Network](docs/network.md) · [FAQ](docs/faq.md)
- Sales and licences: info@tarleaks.com · https://tarleaks.com
- A security problem: write privately to dev@tarleaks.com ([SECURITY.md](SECURITY.md))
- Licence terms: [LICENSE.md](LICENSE.md) · Release notes: [CHANGELOG.md](CHANGELOG.md)
