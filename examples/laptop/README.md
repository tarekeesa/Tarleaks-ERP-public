# Try it on your laptop

Run the ERP on your own computer, reachable only from that computer, at
`http://localhost`. Good for a first look, a demo, or evaluating the product.

Time: about 20 minutes, most of it downloading images. Profile: `small`.

> Windows users: follow [../windows](../windows/README.md). It adds the Docker
> Desktop and WSL 2 steps this page skips.

## What you need

| | |
|---|---|
| Memory for Docker | 4 GB or more (the `small` profile) |
| Free disk | about 20 GB |
| Docker | Docker Desktop on macOS and Windows; Docker Engine on Linux |
| Internet | To download the images and to start the trial |
| Licence | A licence key, or start the free 30-day trial during the install |

## Steps

### 1. Install Docker

| System | What to do |
|---|---|
| **macOS** (Intel or Apple Silicon, macOS 13 or newer) | Install [Docker Desktop](https://www.docker.com/products/docker-desktop/). Open it. In **Settings, Resources**, give it **at least 4 GB of memory**. |
| **Windows** | See [../windows](../windows/README.md) |
| **Linux** | `curl -fsSL https://get.docker.com \| sudo sh`, then `sudo usermod -aG docker $USER` and log out and in |

Check: `docker compose version` prints a version.

### 2. Have your licence key ready

You never run `docker login`: the installer downloads the images from
`registry.tarleaks.com` with your licence key. No key yet? The installer offers
the free 30-day trial ([details](../../docs/requirements.md#access-to-the-images)).

### 3. Get the kit

```bash
git clone https://github.com/tarekeesa/Tarleaks-ERP.git
cd Tarleaks-ERP
```

### 4. Install

```bash
./install.sh --profile small --host localhost
```

The installer checks Docker, memory and disk, writes `.env` with generated
secrets, downloads the images and starts everything. It asks a question or two;
press Enter to accept each default. Add `--yes` to skip the questions.

> A laptop with 16 GB of RAM would otherwise get the `standard` or `full`
> profile. For a trial `small` is lighter on the machine. You can change it later:
> `./tarleaks profile standard`.

The first start prepares the database and can take up to 5 minutes. At the end it
prints:

```text
Open http://localhost in your browser.
  Setup code: K7QF-2M9D-XR4P
```

### 5. Set up the workspace

Open **http://localhost** (exactly this, not `127.0.0.1`). Then:

1. Type the **setup code**.
2. Enter your company name and country, and create the first administrator.
3. Choose **Start a 30-day free trial** (needs internet), and accept the terms.
4. Sign in.

### 6. Look around

You have one workspace and an administrator. The apps in the `small` profile are
HR, recruitment, attendance, payroll, accounting, CRM, inventory, sales orders,
chat, documents, activities, reports and more
([the list](../../docs/apps.md)).

## Daily use

```bash
./tarleaks stop       # when you are done; your data stays
./tarleaks start      # next time
./tarleaks status     # what runs, and the licence state
```

Docker Desktop restarts the ERP when it starts, unless you stopped it with
`./tarleaks stop`.

## Port 80 is busy

Another program holds port 80 (a local web server, Skype, another container). Use
another port, and open that address:

```bash
./install.sh --profile small --host localhost --port 8080
```

Open **http://localhost:8080**.

## Notes by system

- **macOS.** Apple Silicon runs the native `arm64` images, so nothing is emulated.
  Do not set `DOCKER_DEFAULT_PLATFORM`. If Docker is slow or services restart,
  raise Docker Desktop's memory.
- **Linux.** Anything in [requirements](../../docs/requirements.md) works. If you see
  "permission denied" talking to Docker, you are not in the `docker` group yet.
- **Sleep and travel.** The ERP checks in with `tarleaks.com` about every 6 hours and
  keeps working for 30 hours without an answer. A laptop that sleeps overnight is
  fine. One closed for days locks until it can reach the internet and you press
  **Check again** ([licensing](../../docs/licensing.md)).
- **Who can open it.** On a laptop the installer proposes **only this computer**
  (it found a battery, a desktop session, Docker Desktop or a Mac) and says so; the
  ERP then listens on `127.0.0.1` only, so nobody else on a café or hotel network
  can reach the sign-in page. `./install.sh --bind office` (or answering "the
  network too") opens it to the network instead, and `./tarleaks network local` or
  `./tarleaks network office` changes it later without installing again.
  `./tarleaks network` shows which it is now. For other computers on your network
  see [office-server](../office-server/README.md).
- **Memory.** The document editor (New and Edit in Documents) needs about 2 GB. On
  a machine where Docker has less than about 5.5 GB the installer leaves it off and
  says so; `./tarleaks editors on` turns it on once you give Docker more memory.

## Clean up

```bash
./tarleaks uninstall            # removes the containers, keeps your data
./tarleaks uninstall --purge    # also deletes the data in Docker
```

`--purge` leaves `backups/`, `.env` and the images, and prints how to delete
them. Delete `backups/` and `.env` too before you give the laptop away: they
hold your data and keys.

## Next

- Keep the data: [backup and restore](../../docs/backup-restore.md).
- Something wrong: [troubleshooting](../../docs/troubleshooting.md).
- A real server for your team: [office-server](../office-server/README.md) or
  [vps-https](../vps-https/README.md).
