# Requirements

What your machine needs before you run `./install.sh` (Linux, macOS) or
`.\install.ps1` (Windows).

## Hardware

You choose the apps; the machine follows from them. Only the chosen apps run,
with the apps they need and the base apps every workspace holds
([apps.md](apps.md)).

| You run | Containers | Memory to plan for | Machine |
|---|---|---|---|
| HR and CRM (`--apps hr,crm`) | 31 | about 4 GB (2 GB with the editors off) | 2 CPU cores, 8 GB (4 GB with the editors off), 20 GB disk |
| The `small` preset | 41 | about 4.6 GB (2.6 GB) | 2 CPU cores, 8 GB (4 GB), 20 GB disk |
| The `standard` preset | 57 | about 5.8 GB (3.8 GB) | 4 CPU cores, 8 GB, 40 GB disk |
| Every app (`full`) | 63 | about 7.1 GB (5.1 GB) | 8 CPU cores, 16 GB, 80 GB disk |

The figures include the editors that come with Documents and Diagrams (the
document editor is the large one, about 2 GB): New and Edit in Documents and
drawing in Diagrams. On a smaller machine switch them off with
`./tarleaks editors off`; the installer does so by itself when Docker has less
than about 5.5 GB ([configuration.md](configuration.md#editors)).

The containers include the start-up steps that run once and exit, and one
small scheduled-jobs container per app (a few MB each while idle).
"Memory to plan for" is what the containers use at light use (one company, tens
of users). Leave about 1 GB more for the operating system, and more again for
many users or large imports. `./install.sh` and `./tarleaks apps` print the
figure for your own choice and compare it with what Docker can use.

Memory means the memory **Docker can use**. On Linux that is the whole machine.
On macOS and Windows it is the share you give Docker Desktop (see
[examples/windows](../examples/windows/README.md) for Windows).

The disk figure is a starting point for the images, the database and the first
files. It grows with your documents. Leave room for backups as well.

### Choosing

```bash
./install.sh --apps hr,crm               # only these (and what they need)
./install.sh --profile small             # a preset: small | standard | full
./install.sh                             # asks, suggesting a preset from the memory
```

Later: `./tarleaks apps add payroll`, `./tarleaks apps remove crm`,
`./tarleaks profile standard` (Windows: `.\tarleaks.ps1 …`). The presets:

| Preset | Apps |
|---|---|
| `small` | HR, recruitment, attendance, payroll, accounting, CRM, inventory, sales orders, chat |
| `standard` | `small` + projects, learning, recognition, assets, helpdesk, fleet, correspondence, point of sale, rentals, subscriptions (from release 1.2.0 also procurement, construction, contracts) |
| `full` | `standard` + PDF tools with OCR, ISO compliance (and diagrams on 1.0.0; Diagram Studio is not in 1.2.0) |

Every installation also runs Documents, Notifications, Activities, Parties,
Reports and Insights, and the apps a chosen app needs (CRM brings Products &
Online Store; Payroll brings Accounting).

Your licence also has to include an app before people can use it. See
[licensing.md](licensing.md).

The installer suggests `full` (every app, which is what the trial covers)
whenever Docker has the memory for it with about 1 GB to spare (about 6 GB),
otherwise the largest preset that fits. It warns when Docker has less memory
than the chosen apps need, and when there is less than 15 GB of free disk. To
switch an installed server to every app later: `./tarleaks profile full`.

## Supported systems

| System | Versions | CPU | Notes |
|---|---|---|---|
| Ubuntu | 22.04, 24.04 | Intel/AMD, ARM | Best choice for a server |
| Debian | 12 | Intel/AMD, ARM | |
| Red Hat Enterprise Linux, Rocky Linux, AlmaLinux | 9 | Intel/AMD, ARM | See the SELinux note in [troubleshooting.md](troubleshooting.md#selinux-permission-denied-on-red-hat-rocky-almalinux) |
| macOS | 13 or newer | Intel or Apple Silicon | Needs Docker Desktop. Good for trying it out. |
| Windows | 10 or 11 (64-bit) | Intel/AMD | Needs Docker Desktop with the WSL 2 engine and Linux containers |
| Raspberry Pi 5 | 8 GB model, 64-bit Raspberry Pi OS | ARM | Up to the `small` preset. See [examples/raspberry-pi](../examples/raspberry-pi/README.md) |
| AWS Graviton, Ampere, Hetzner ARM | Ubuntu or Debian as above | ARM | Native images, no emulation |

Every Tarleaks image is published for `linux/amd64` and `linux/arm64`, so Docker
pulls the right one for your CPU by itself.

Not on the supported list: 32-bit systems (the installer stops with "CPU
architecture ... is not supported"), Windows containers mode in Docker Desktop,
and Raspberry Pi models older than the Pi 5.

We recommend Linux with **Docker Engine** for anything your staff depend on every
day. Docker Desktop (macOS, Windows, and also offered for Linux) runs everything
inside a virtual machine: fine for evaluation, a laptop and small teams, but the
virtual machine alone can keep a CPU core busy, and after a restart of the
computer its port forwarding can leave the address silent until you run
`docker compose up -d --force-recreate gateway`. On a Linux server install Docker
Engine, not Docker Desktop.

With Docker Desktop:

- Give it enough memory: **Settings, Resources, Memory**. About 6 GB runs every
  app; 4 GB is the minimum for a few apps.
- Keep the kit in a folder Docker Desktop shares with containers (your home
  folder is shared by default; others are added in **Settings, Resources, File
  sharing**). Otherwise the start fails with "mounts denied … not shared from
  the host".

## Software on the machine

| You need | Why | Check |
|---|---|---|
| Docker Engine 24 or newer (Docker Desktop on macOS and Windows) | Runs the ERP | `docker version --format '{{.Server.Version}}'` |
| Docker Compose v2 (the `docker compose` command) | Starts the services | `docker compose version` |
| `bash` and `curl` (Linux, macOS) | Used by `install.sh` and `./tarleaks` | `curl --version` |
| `git`, or a ZIP download of this repository | To get these files | `git --version` |
| `python3` (optional) | Makes `./tarleaks status` neater and lets `./tarleaks doctor` check the clock | `python3 --version` |

On Windows, PowerShell 5.1 (included with Windows) or newer is enough.

### Installing Docker

The official instructions are at <https://docs.docker.com/engine/install/>. The
short versions:

**Ubuntu, Debian, Raspberry Pi OS**

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Log out and in again so the group change applies. Read the script first if your
policy requires it; it is the one Docker publishes.

**Red Hat Enterprise Linux, Rocky Linux, AlmaLinux 9**

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

On Red Hat Enterprise Linux itself use `.../linux/rhel/docker-ce.repo` in the
second line. Log out and in again.

**macOS and Windows**

Install Docker Desktop from <https://www.docker.com/products/docker-desktop/>.
On Windows choose the WSL 2 engine. Start it and wait for "Engine running".

Test any of them:

```bash
docker run --rm hello-world
```

Podman is not on the supported list.

## Network

| Direction | Port | To or from | Needed for |
|---|---|---|---|
| Outbound | 443 (HTTPS) | `tarleaks.com` | The licence check-in, unless your licence key has check-ins switched off ([licensing.md](licensing.md)) |
| Outbound | 443 (HTTPS) | `registry.tarleaks.com` (and `tarleaks.com`, which checks the licence key for it) | Downloading the Tarleaks images (install and upgrade), unless you use the offline bundle |
| Outbound | 443 (HTTPS) | Docker Hub (`registry-1.docker.io`, `docker.io`, `production.cloudflare.docker.com`) | Downloading the database, cache, message queue, gateway, file-store and helper images, unless you use the offline bundle |
| Outbound | 123 (UDP) | A time server | Correct time ([Time](#time)) and the check before e-invoices are signed |
| Inbound | `HTTP_PORT` (80 by default) | Your users | Using the ERP |
| Inbound | 80 and 443 | The internet | Only if you add HTTPS in front, see [examples/vps-https](../examples/vps-https/README.md) |

Nothing else needs to be reachable from outside. The database, cache and
message queue are not published on any port. Government and e-invoicing
services, and integrations a workspace switches on, add their own addresses:
[network.md](network.md) explains them, and the release's
`docs/EXTERNAL-ENDPOINTS.md` lists every one.

**No internet at all?** Install from the offline bundle:
[faq.md](faq.md#can-i-install-without-internet).

**A proxy?** There are two settings, because two different programs go out:

- **The ERP** (licence check-in, e-invoicing, integrations) uses `HTTPS_PROXY`,
  `HTTP_PROXY` and `NO_PROXY` in `.env`:
  [configuration.md](configuration.md#outbound-proxy).
- **Docker** downloads the images. On Linux, give the Docker service the proxy
  in a systemd drop-in, then restart it:

  ```bash
  sudo mkdir -p /etc/systemd/system/docker.service.d
  printf '[Service]\nEnvironment="HTTPS_PROXY=http://proxy.example.com:3128"\n' \
    | sudo tee /etc/systemd/system/docker.service.d/proxy.conf
  sudo systemctl daemon-reload && sudo systemctl restart docker
  ```

  On macOS and Windows: Docker Desktop, **Settings, Resources, Proxies**.

Give the server a fixed address (a DHCP reservation or a static IP) or a DNS
name. People type that address into their browser and the ERP remembers it
during setup. See [examples/office-server](../examples/office-server/README.md).

## Storage and disks

- Use an **SSD**. A spinning disk works but the ERP feels slow, and the first
  start takes much longer.
- Put Docker's data (`/var/lib/docker` on Linux) on **local** disk.
- **Never put PostgreSQL on a network share or NAS** (NFS, SMB, iSCSI to a
  shared volume). Databases need reliable local file locking and fast
  writes. The database lives in the Docker volume `pgdata`; leave it where
  Docker puts it.
- Documents may go elsewhere. The file store can be AWS S3, Cloudflare R2,
  Wasabi or a NAS gateway. See [configuration.md](configuration.md#file-storage).
- Keep backups on a **different** disk or machine. See [backup-restore.md](backup-restore.md).

## Time

Turn on automatic time (NTP). The licence refuses a clock that runs behind the
licence server's last answer. See [licensing.md](licensing.md#the-clock).

## Access to the images

The images come from `registry.tarleaks.com`, and **your licence key is the
password**. You never run `docker login`: the installer and `./tarleaks`
sign Docker in themselves before every download (user name `licence`), with

1. the key in `.env` (`./install.sh --licence-key <key>`), or
2. the key your installation already holds (entered on the setup screen or in
   Settings, Licence), or
3. the free trial the installer starts when you have no key yet
   (`./install.sh --trial you@yourcompany.com --company "Your company"
   --accept-terms`, or answer its question).

The key is handed to Docker on its standard input, never on a command line
and never printed. Docker keeps the sign-in in its own credential store, like
any `docker login`; `docker logout registry.tarleaks.com` removes it.

A licence that is withdrawn, suspended or past its end date cannot download
new versions; what is already installed keeps its images. Your own mirror of
the images: put its address in `TARLEAKS_REGISTRY` in `.env` and sign Docker
in to it the way it says (the installers leave it alone).

An `.env` from the private preview that still names `ghcr.io/tarekeesa/tarleaks-erp`
is moved to `registry.tarleaks.com/tarleaks-erp` by the next install, upgrade or
download, and the images already on the machine are renamed, so nothing is
downloaded twice. The personal GitHub token is no longer needed.

## Next

- [examples/](../examples/README.md): pick the one that matches your situation.
- [troubleshooting.md](troubleshooting.md): when something does not start.
