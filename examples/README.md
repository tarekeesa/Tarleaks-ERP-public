# Examples

Pick the one that matches your situation. Each folder has a `README.md` with the
steps, and the files you need.

| You want to… | Example | Profile | Address people use |
|---|---|---|---|
| Try it on your own computer | [laptop](laptop/README.md) | `small` | `http://localhost` |
| Run it for the office on a local server | [office-server](office-server/README.md) | `standard` | `http://192.168.1.20` or an internal name |
| Put it on the internet with a free HTTPS certificate | [vps-https](vps-https/README.md) | by RAM | `https://erp.example.com` |
| Run it on a Raspberry Pi 5 | [raspberry-pi](raspberry-pi/README.md) | `small` | the Pi's address |
| Use the nginx you already have for HTTPS | [behind-nginx](behind-nginx/README.md) | any | `https://erp.example.com` |
| Keep documents in AWS S3, Cloudflare R2, Wasabi or on a NAS | [s3-storage](s3-storage/README.md) | any | any |
| Install on Windows with Docker Desktop | [windows](windows/README.md) | by RAM | `http://localhost` or the PC's address |
| Back up every night | [scheduled-backups](scheduled-backups/README.md) | any | not applicable |
| Use your own PostgreSQL server | [external-postgres](external-postgres/README.md) | not yet supported | not applicable |
| Let a database tool (pgAdmin, reporting) connect to the bundled database | [database-access](database-access/README.md) | any | not applicable |

Examples combine. A typical production server is **vps-https** (or **behind-nginx**)
plus **scheduled-backups**, and perhaps **s3-storage**.

## Before any of them

1. **Docker** with Compose v2, and a 64-bit machine. See
   [requirements](../docs/requirements.md).
2. **A licence key**, or an e-mail address to start the free 30-day trial. The
   installer signs Docker in to `registry.tarleaks.com` with it; you never run
   `docker login` ([how](../docs/requirements.md#access-to-the-images)).
3. **Decide where files will be kept** before you open the setup screen (the
   bundled store is the default). The address can change later: edit `.env` and
   `./tarleaks restart` ([details](../docs/configuration.md#decide-before-the-first-setup)).

On the server examples the kit lives in `/opt/tarleaks-erp`:

```bash
sudo mkdir -p /opt/tarleaks-erp && sudo chown "$USER": /opt/tarleaks-erp
git clone https://github.com/tarekeesa/Tarleaks-ERP.git /opt/tarleaks-erp
cd /opt/tarleaks-erp
```

## Using an example's files

Some examples hold files (a `Caddyfile`, a Compose override, `.env` lines). Copy
them from the example's folder, as its README says. They never change the kit's own
files: add-on Compose settings go in `docker-compose.override.yml`, which Docker
Compose reads by itself and `git pull` never touches.

## Everyday commands

```bash
./tarleaks status       # what runs, the workspace, the licence
./tarleaks logs auth    # follow a service's log
./tarleaks backup       # database, files and settings into backups/
./tarleaks update       # the newest release: check, back up, update
./tarleaks doctor       # explains what is wrong
```

On Windows use `.\tarleaks.ps1` (no `doctor`). Everything else:
[docs](../docs/troubleshooting.md).
