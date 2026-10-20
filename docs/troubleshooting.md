# Troubleshooting

Find your symptom, read the cause, apply the fix.

## Start here

Three commands tell you most of what you need.

| Command (Windows) | What it shows |
|---|---|
| `./tarleaks status` (`.\tarleaks.ps1 status`) | Which services run, the workspace name and the licence state |
| `./tarleaks doctor` (Linux, macOS) | Checks Docker, every container (stopped, failing its health check, a failed start-up step), the memory, the workspace database, whether each app receives events, the address, whether `tarleaks.com` is reachable, the clock and Docker's disk, and says what to do. It goes through every check and ends with exit code 1 when a line is red. |
| `./tarleaks logs auth` (`.\tarleaks.ps1 logs auth`) | The sign-in and licensing service's log. Replace `auth` with any service name. Press Ctrl+C to stop following. |

Service names are the ones in `./tarleaks status`: `auth`, `hr`, `payroll`,
`accounting`, `project_management`, `sales_orders` and so on.

Send these three outputs when you write to info@tarleaks.com.

## Install and start

| Symptom | Cause | Fix |
|---|---|---|
| "Port 80 is already in use by another program" | Another program (a web server, IIS, Skype, another container) holds the port | Run `./install.sh --port 8080` (Windows `.\install.ps1 -Port 8080`) and open `http://<address>:8080`. Or stop the other program. Find it: `sudo ss -ltnp 'sport = :80'` (Windows: `Get-NetTCPConnection -LocalPort 80 -State Listen`). |
| `Bind for 0.0.0.0:80 failed: port is already allocated` | Same | Same |
| "The image registry did not accept the licence key: …" | The licence key cannot download: the sentence says why (it ended, was withdrawn or suspended, or was copied incompletely) | Fix the licence (Settings, Licence, or `./install.sh --licence-key <key>`), then run the installer again. Still refused: info@tarleaks.com. See [requirements.md](requirements.md#access-to-the-images). |
| "Docker on this machine already holds the data of an installation named 'tarleaks', and this folder has no .env" | You ran the installer in a new folder on a machine that already runs (or once ran) Tarleaks ERP. Going on would attach a second copy, with new passwords, to that installation's data | Manage that installation from its own folder. Restoring it: put its `.env` back from the backup first. A separate second installation: `COMPOSE_PROJECT_NAME=erp2 ./install.sh --port 8080` (Windows: `$env:COMPOSE_PROJECT_NAME='erp2'; .\install.ps1 -Port 8080`). Old data you no longer want: `docker volume ls --filter label=com.docker.compose.project=tarleaks`, then remove those volumes yourself |
| "Downloading Tarleaks ERP needs a licence key" | No key in `.env`, none in the installation, no trial started | `./install.sh --licence-key <key>`, or start the trial: `./install.sh --trial you@yourcompany.com --company "Your company" --accept-terms` |
| "The registry refused the download", `unauthorized`, `denied` | The sign-in worked but a download was still refused | Run `./tarleaks doctor` (section Image downloads) and the command again; if it repeats, send the message to info@tarleaks.com |
| "Release N has no image …" (`manifest unknown`) | `TARLEAKS_VERSION` names a release that does not have that app yet, or a typo in the version | Use a release that has it (release notes), or remove the app: `./tarleaks apps remove <app>` |
| "An image is not published for this CPU" (`no matching manifest`) | A 32-bit system, or `DOCKER_DEFAULT_PLATFORM` forces another CPU type | 64-bit OS; `unset DOCKER_DEFAULT_PLATFORM` |
| "Docker Hub limits anonymous downloads" (`toomanyrequests`) | Docker Hub's free download limit for your address | Wait a few hours, or `docker login` with a free Docker account |
| "A certificate was not accepted while downloading" (`x509`) | A proxy inspects HTTPS | Exempt `registry.tarleaks.com`, `tarleaks.com` and Docker Hub from inspection, or set Docker's proxy ([examples/outbound-proxy](../examples/outbound-proxy/README.md)) |
| "The server could not reach the image registries" (`dial tcp`, `timeout`, `no such host`) | No route to the registries | Allow the addresses in [setup-guide.md, step 3](setup-guide.md#3-open-the-network-paths) |
| "Docker is installed but not running (or this user may not use it)" | The Docker service is stopped, or your user is not allowed to use it | Start Docker. On Linux: `sudo usermod -aG docker $USER`, then log out and in. The message `permission denied ... docker.sock` is the same problem. |
| "Docker Compose v2 is missing" | Only the old `docker-compose` is installed | Install the `docker-compose-plugin` package, or update Docker Desktop |
| `RABBITMQ_PASSWORD is not set - run ./install.sh` (or another variable name) | `.env` is missing or incomplete | Run `./install.sh`. It keeps the values you already have and fills the gaps. |
| "No .env here. Run ./install.sh first." | You are in the wrong folder, or the installer has not run | `cd` to the kit folder and run `./install.sh` |
| "CPU architecture 'armv7l' is not supported" | A 32-bit operating system | Install a 64-bit one. Raspberry Pi: 64-bit Raspberry Pi OS. |
| "Docker is in Windows-containers mode" | Docker Desktop is set to Windows containers | Right-click the Docker icon, **Switch to Linux containers**, run the installer again |
| "Not answering yet after 10 minutes" | The first start prepares the database and needs time, or there is not enough memory or a slow disk | Run `./tarleaks doctor` and `./tarleaks logs auth`. Check memory below. Give a slow disk or a Raspberry Pi extra minutes. |
| PowerShell: "running scripts is disabled on this system" | The execution policy | `Set-ExecutionPolicy -Scope Process Bypass`, then run the script again in the same window |
| PowerShell: the script is "not digitally signed" or from the internet | The kit came from a ZIP download | `Get-ChildItem -Recurse \| Unblock-File` in the kit folder |

## Memory and disk

| Symptom | Cause | Fix |
|---|---|---|
| Installer warns "Less than 4 GB of memory for Docker" | Docker has too little memory | Give Docker 4 GB or more. Docker Desktop: **Settings, Resources, Memory**. Windows: see the next row. |
| Services keep restarting, `Exited (137)`, the ERP is slow then stops answering | **Out of memory.** More apps run than the machine can hold | Remove apps nobody uses (`./tarleaks apps`, then `./tarleaks apps remove <app>`), or add RAM, or swap (below). [apps.md](apps.md) gives the memory each app needs. |
| Windows: Docker has far less memory than the PC | WSL 2 limits itself to a share of RAM | Create `%UserProfile%\.wslconfig` with `[wsl2]` and `memory=8GB`, run `wsl --shutdown`, restart Docker Desktop. A sample is in [examples/windows](../examples/windows/README.md). |
| `no space left on device` | The disk is full | `df -h` and `docker system df` show where. `docker image prune` removes unused images. Container logs are capped at 3 files of 10 MB each. |

Confirm an out-of-memory kill:

```bash
docker inspect --format '{{.Name}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}}' $(docker ps -aq)
sudo dmesg -T | grep -i -E 'out of memory|killed process'
free -h
docker stats --no-stream
```

Add 4 GB of swap on Linux as a safety net (it does not replace RAM):

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Apple Silicon (M1 to M4 Macs)

The images are native for Apple Silicon, so nothing needs emulating. If it is slow
or a container will not start, check that you did not force Intel images:

```bash
echo "$DOCKER_DEFAULT_PLATFORM"      # must print nothing
unset DOCKER_DEFAULT_PLATFORM
```

Remove any `DOCKER_DEFAULT_PLATFORM=linux/amd64` from your shell profile, then
`./tarleaks restart`. Give Docker Desktop enough memory
(**Settings, Resources, Memory**).

## Choosing apps

Messages from `./install.sh --apps …`, `./tarleaks apps …` and their Windows twins.
What each app needs: [apps.md](apps.md).

| Message | Cause | Fix |
|---|---|---|
| "Unknown app: …" | A typo, or a name the sheet does not know | `./tarleaks apps` lists the names (and [apps.md](apps.md#names-you-can-type) the other words accepted) |
| "Choose at least one app" / "At least one app must stay" | The list is empty | Name at least one app. To remove everything: `./tarleaks uninstall` |
| "These apps need about N GB plus room to work, and Docker has M GB" | The chosen apps need more memory than Docker can use | Fewer apps, or give Docker more memory (Docker Desktop: Settings, Resources; Windows: [examples/windows](../examples/windows/README.md)) |
| "X is installed because Y needs it. Removing that removes it too" | You tried to remove an app you did not choose; a chosen app needs it | Remove the app that needs it (the command is in the message) |
| "Cannot remove X: Y needs it. Remove both" | Another chosen app cannot work without X | Remove both, as the message shows, or keep X |
| "X is part of every installation and cannot be removed" | Documents, Notifications, Activities, Parties, Reports and Insights always run | Nothing to do. They are needed by the other apps and cost little memory |
| "X is not installed" | It was never chosen | Nothing to remove |
| "stopped <service> (no chosen app needs it; its data is kept)" | Normal after `apps remove` or a smaller preset | Nothing. `./tarleaks apps add` brings it back with its data |
| An installed app shows a lock, or says your plan does not include it | The app runs, but your licence does not cover it | Ask info@tarleaks.com to add it. No reinstall needed: it appears at the next check-in (Settings, Licence, **Check now**) |
| A licensed app is missing from the launcher | It is not installed on this server | `./tarleaks apps add <app>` |
| On the Apps page: "'crm' is not available for this workspace" (or another app's name) | This server does not run that app, or an app it needs. CRM needs Products & Online Store; Sales Orders needs CRM, Inventory, Accounting and Products & Online Store. Installations made with the first kit's "small" profile ran CRM without the store, so CRM is refused | On the server: `git pull`, then `./tarleaks apps add crm sales_orders` (it adds what they need), then sign out and in. Windows: `.\tarleaks.ps1 apps add crm sales_orders` |
| The home page shows only a few apps (HR, Payroll, Finance, …) and the trial should have them all | The server runs only the apps chosen at install (the first kit suggested `small` on most machines), and on 1.0.0 a trial opens only the apps picked in "What will you use first?" | On the server: `git pull`, then `./tarleaks profile full` (every app; Windows: `.\tarleaks.ps1 profile full`). Then in the ERP open **Apps**, then **Add apps**, select every app and press **Add**, and sign out and in. **From 1.2.0** a trial opens every app the server runs by itself |
| "Not in release 1.0.0 yet: Procurement (from release 1.2.0)" | That app's image exists only from a newer release ([apps.md](apps.md#apps-that-are-not-in-every-release)) | Choose other apps for now, or update to that release first |
| "Not in release 1.2.0: Diagram Studio (taken out in release 1.2.0 …)" | Diagram Studio is not in 1.2.0 while it is rebuilt ([apps.md](apps.md#apps-that-are-not-in-every-release)); its data is kept | Choose other apps; it returns in a later release |
| After `git pull`, an app you had is gone, or a new one starts | The new release changed what an app needs; `./tarleaks start` reads the sheet again | Read the release notes; `./tarleaks apps` shows the result. Your chosen list (`TARLEAKS_APPS` in `.env`) is changed by an update only to drop an app the new release does not have (Diagram Studio in 1.2.0); its data is kept, and `./tarleaks apps add` brings it back on a release that has it |

## After a restart or a reboot

| Symptom | Cause | Fix |
|---|---|---|
| Data entered in one app does not show up in another (a payroll run never reaches the ledger, a new employee never gets a welcome task, notifications stop) and `./tarleaks doctor` says "Running but not receiving events" | After a reboot an app started before the message queue was ready and stopped listening for events. The kit makes every app wait for the queue, but an app can still lose it later (the queue restarted on its own, or ran out of memory) | `./tarleaks restart`. Events sent while it was deaf wait in the queue (up to 30 days, 200,000 per queue) and are delivered then |
| The address answers "Empty reply from server" (curl) or the browser says the connection was closed, right after the computer restarted; `./tarleaks status` shows everything running | Docker Desktop lost the gateway's port forwarding during the restart | `docker compose up -d --force-recreate gateway`. On a server, use Docker Engine instead of Docker Desktop ([requirements](requirements.md)) |
| `mounts denied: The path … is not shared from the host and is not known to Docker` | Docker Desktop (Linux, macOS) only lets containers use folders it shares. The kit is outside them | Move the kit under your home folder, or add its folder in Docker Desktop: **Settings, Resources, File sharing**, then `./tarleaks start` |
| Every page answers `404 page not found` after a restart, although `./tarleaks status` shows everything running; `./tarleaks doctor` says "The gateway started without its routes", or `./tarleaks logs gateway` shows `couldn't initialize inotify: too many open files` | The gateway reads its routes through a file watch (inotify). Linux allows 128 watch instances by default, shared by every container that runs as root; on a machine with many containers they run out and the gateway starts with no routes. `./tarleaks doctor` warns about it in advance when the limit is 128 or lower and the machine runs more than 60 containers | Raise the limit and keep it after a reboot: `echo fs.inotify.max_user_instances=1024 \| sudo tee /etc/sysctl.d/60-tarleaks-inotify.conf && sudo sysctl --system`, then `./tarleaks restart` |
| `./tarleaks doctor`: "A start-up step failed: migrate(exit 1)" | The database update step failed. Before the setup screen has been used there is no workspace, and doctor does not count it | `./tarleaks logs migrate`; then `./tarleaks start`. After an upgrade, its output is in `backups/pre-update-*/migrate.log` (or `backups/pre-upgrade-*/`) |
| `./tarleaks doctor`: "Workspace …: its database is 'provisioning', not 'active'" | Setup stopped half-way while it prepared the workspace database | Send `./tarleaks doctor` and `./tarleaks logs auth` to info@tarleaks.com |

## Reaching the ERP

| Symptom | Cause | Fix |
|---|---|---|
| Works on the server, not from other computers | A firewall, or `HTTP_BIND=127.0.0.1`, or `TARLEAKS_HOST` is `localhost` | See below |
| New or Edit in Documents does nothing, or says the editor is not part of this installation | The document editor is off (the installer leaves it off on a machine with under about 5.5 GB for Docker) or still starting (the first start takes a minute or two) | `./tarleaks editors` shows which; `./tarleaks editors on` turns it on; `./tarleaks doctor` and `./tarleaks logs onlyoffice` say why it does not answer |
| A document opens in the editor, then "Download failed" or "the document security token is not correctly formed" | The editor and the ERP do not share the secret (`.env` was changed or restored from another installation), or the editor cannot reach Documents inside Docker | `./tarleaks restart`; check `ONLYOFFICE_JWT_SECRET` in `.env` is the one this installation was made with; `./tarleaks logs onlyoffice documents` |
| `502` only on `/onlyoffice/` | The editor is starting or stopped | Wait a minute, then `./tarleaks doctor` |
| The page loads but sign-in or uploads misbehave | You opened a different address from `TARLEAKS_URL` (`127.0.0.1` instead of `localhost`, an IP instead of the name, `http` instead of `https`) | Open exactly `TARLEAKS_URL` (`grep ^TARLEAKS_URL .env`) |
| `502 Bad Gateway` on one app only | That app's service is still starting, has crashed, or the app is not installed | `./tarleaks status`, then `./tarleaks logs <service>`. If it is not installed: `./tarleaks apps add <app>`. |
| Everything answers `502` or "connection refused" | The gateway or the stack is down | `./tarleaks start`, then `./tarleaks doctor` |
| 402 on sign-in, or a lock screen | The licence | See [Licence blocked](#licence-blocked-codes) |

### Other computers cannot connect

Work down the list:

1. `./tarleaks network` says who may connect (`./tarleaks network office` opens it
   to the network). `grep -E '^(TARLEAKS_HOST|TARLEAKS_URL|HTTP_PORT|HTTP_BIND)=' .env`. For the
   office network, `TARLEAKS_HOST` is the server's IP or name (not `localhost`),
   and `HTTP_BIND` is `0.0.0.0`.
2. From the server: `curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<HTTP_PORT>/api/auth/installation`
   should print `200`. If not, it is not running: `./tarleaks doctor`.
3. From another computer: `curl -fsS -o /dev/null -w '%{http_code}\n' http://<server>:<HTTP_PORT>/api/auth/installation`.
   If this times out, a firewall is in the way. Open the port
   ([examples/office-server](../examples/office-server/README.md)). On Windows
   add an inbound rule ([examples/windows](../examples/windows/README.md)). On a
   cloud server also open it in the provider's firewall or security group.
4. `ufw` and `firewalld` rules do not always control a port that Docker
   publishes, because Docker writes its own rules first. To limit who can connect,
   keep the server off the internet, or put a proxy in front and bind the gateway
   to `127.0.0.1` (`HTTP_BIND`). Always test from another computer.

### SELinux: permission denied on Red Hat, Rocky, AlmaLinux

With SELinux enforcing, containers cannot read the kit's `config/` folder, and the
database, the message queue loader or the gateway fail with "Permission denied"
on files under `config/`.

Fix 1, label the folder for containers (survives restarts and relabels):

```bash
sudo dnf -y install policycoreutils-python-utils
sudo semanage fcontext -a -t container_file_t "$PWD/config(/.*)?"
sudo restorecon -Rv "$PWD/config"
./tarleaks restart
```

Fix 2, ask Docker to relabel when it mounts. Create `docker-compose.override.yml`
next to `docker-compose.yml` and add `:z` to the three `config` mounts:

```yaml
services:
  postgres:
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./config/postgres/init:/docker-entrypoint-initdb.d:ro,z
  rabbitmq-init:
    volumes:
      - ./config/rabbitmq/definitions.json:/definitions.json:ro,z
  gateway:
    volumes:
      - ./config/traefik/dynamic:/etc/traefik/dynamic:ro,z
```

Do not turn SELinux off.

## Licence blocked codes

A blocked installation shows a lock screen, and any request answers HTTP `402` with
a code that starts with `ENTITLEMENT_`. The lock screen quotes the licence
server's own sentence under **From the licence server**. First press
**Check again**. If it stays locked:

| Code | Lock screen title | What it means | What to do |
|---|---|---|---|
| `ENTITLEMENT_MISSING` | No licence key yet | There is no licence: setup was not finished, or the key was removed | Finish the setup screen, or **Enter a licence key** |
| `ENTITLEMENT_MALFORMED` | The licence key is damaged | The key could not be read, usually because part of it was lost when it was copied | Enter it again. It is one long line starting `tlk1.` (or `nxs1.` for keys issued earlier): copy all of it |
| `ENTITLEMENT_INVALID` | The licence key is not valid | The key was not issued by Tarleaks, or was altered | Enter the key Tarleaks sent you, or ask for a new one |
| `ENTITLEMENT_EXPIRED` | Your licence has expired | The trial or subscription ended | Ask info@tarleaks.com to renew or issue a key, then **Check again** or enter the new key |
| `ENTITLEMENT_NOT_ACTIVATED` | Licence not activated yet | The installation never reached `tarleaks.com` to activate within the allowed time | Allow outbound HTTPS to `tarleaks.com`, then **Check again** |
| `ENTITLEMENT_SUSPENDED` | Your licence is suspended | Tarleaks suspended the licence | Contact info@tarleaks.com, then **Check again** |
| `ENTITLEMENT_REVOKED` | Your licence was withdrawn | Tarleaks withdrew the licence | Contact info@tarleaks.com, then enter the new key |
| `ENTITLEMENT_OFFLINE_TOO_LONG` | This installation has to check in | No successful check-in for more than the **30-hour** allowance | Restore internet access to `tarleaks.com:443`. It retries every 2 minutes by itself. Press **Check again** to retry now. |
| `ENTITLEMENT_CLOCK_BEHIND` | The clock on this machine is wrong | The machine's date and time are earlier than the licence server's last answer (by more than about 15 minutes) | Turn on automatic time ([licensing.md](licensing.md#the-clock)), then **Check again** or `./tarleaks restart` |
| **From 1.2.0:** `ENTITLEMENT_CLOCK_SKEW` | The clocks on this installation disagree | The ERP's clock and the database server's clock are more than about 15 minutes apart. Only possible with your own PostgreSQL server. | Turn on automatic time on both machines, then `./tarleaks restart` |
| `ENTITLEMENT_USER_LIMIT` | (a message, not a lock) | You tried to create or re-activate a user beyond your seats | Deactivate a user, or ask for more seats. Existing users still sign in. |
| **From 1.2.0:** `ENTITLEMENT_USER_LIMIT` on sign-in | More people are active than the licence allows | More users are active than the licence's seats (for example after seats were reduced). Only administrators who manage users can sign in; anyone else is refused at the sign-in form with a sentence giving the numbers, and people already signed in see this lock screen. | An administrator signs in, switches off people who left at **Settings, Users**, or asks info@tarleaks.com for more seats, then **Check now** |
| (licence page, last error) | "This licence is already in use on another machine" | The same licence key checks in from a second installation: a fresh install that was given the key, a test server that was given the same key or trial e-mail, or the old server still running after a move. From 1.2.0 also a copy of this server (a restored backup, a cloned virtual machine) running at the same time. | Stop the installation you do not use. A licence moves to new hardware by itself once the old installation has been silent for the offline allowance (30 hours); to move it sooner, ask info@tarleaks.com. |

**Cannot reach `tarleaks.com`?** Run `./tarleaks doctor` and read the "Licence
server" line. On Windows:

```powershell
docker compose exec -T auth curl -fsS -o /dev/null --max-time 10 https://tarleaks.com/api/activation/public-key
```

No output means it works. Otherwise outbound port 443 to `tarleaks.com` is blocked
by a firewall or a proxy, or DNS fails inside Docker. If the company reaches the
internet through a proxy, use [examples/outbound-proxy](../examples/outbound-proxy/README.md).
If DNS fails inside Docker only (`Could not resolve host` from the command above,
but `curl https://tarleaks.com` works on the server), set DNS servers for Docker in
`/etc/docker/daemon.json` (`{"dns": ["1.1.1.1", "8.8.8.8"]}`, or your company's)
and `sudo systemctl restart docker`.

**"This installation's licence key is set in its .env file":** the key is in
`.env` as `TARLEAKS_LICENSE_KEY`. Put the new key in that line (or empty it to
manage the key on screen), then `./tarleaks restart`.

## The setup screen shows an error

| What you see | Cause | Fix |
|---|---|---|
| "That setup code is not right" | Wrong code. Case, spaces and dashes do not matter. | `./tarleaks setup-code` (Windows `.\tarleaks.ps1 setup-code`) and copy it again |
| "This installation is already set up" | A workspace exists | Sign in with the administrator created at setup. The setup screen is closed once it has run. |
| "We could not reach tarleaks.com to start your trial" | The server cannot reach the internet | Allow outbound HTTPS to `tarleaks.com`. Or choose **I have a licence key**. |
| "tarleaks.com did not start a trial" | The trial was refused, and the message says why: the trial for that e-mail address already ended, it is not active, trials are closed for now, or too many trials were started from your network address today | Follow the message, or contact info@tarleaks.com for a licence key |
| "Accept the licence terms to continue" | The terms box is not ticked | Tick it |
| "Something in the form is not valid: …" | The message names the field. A password needs at least 10 characters. | Correct it and submit again |
| "The installation could not finish setting up your workspace" | The database or a service was not ready | Wait a minute and try again. If it repeats: `./tarleaks logs auth` |
| "That licence key was not accepted" | The key is wrong, partly copied, or not for this software | Paste the whole key. Ask Tarleaks for a new one. |

## Somebody cannot sign in

| Who | Fix |
|---|---|
| A person forgot the password and the server sends e-mail | **Forgot password?** on the sign-in page sends a link. |
| A person forgot the password and the server sends **no** e-mail (the default) | An administrator opens **Settings, Users** and presses **Set a password** on that person's row, then gives them the password over a channel you trust. Every session of that person ends. |
| An **administrator** who cannot sign in, with nobody else to help (the only administrator forgot the password, or their account was switched off) | On the server, in the installation's folder: `./tarleaks reset-admin <their e-mail>` (Windows `.\tarleaks.ps1 reset-admin <their e-mail>`). It prints a temporary password once, switches the account on again, gives the Administrator role back and ends every session; the company's audit log records it. Add `--company <short name>` (Windows `-Company`) when the address exists in more than one company, and `--reset-two-factor` (Windows `-ResetTwoFactor`) when the phone with the authenticator app is lost too. Then sign in and choose a new password under your profile, Security. |

The ERP refuses to switch off, archive or delete the last person who can manage
users and roles, or to take that person's roles away: give another active
person the Administrator role first.

## Two-step confirmation is not switched on

"Two-step confirmation is not switched on for this server yet" when a sealed
tender is opened (or another action asks for the authenticator code again)
means the installation has no sign-in token key. The installer makes it; an
installation from an older kit gets it on its next `./tarleaks start`
(`./tarleaks restart`). The start says "Created the sign-in token key". If it
says it could not, the message-queue image is missing from this machine: check
with `docker image ls rabbitmq`, get it with `./tarleaks upgrade` (or
`./tarleaks load-bundle` without internet), and start again. People signed in
before keep their session.

## Uploads fail or files do not open

Uploads and downloads go **from the browser straight to the file store** over a
signed link, so they break differently from the rest of the ERP. Everything else
works, and only file transfers fail.

Open the browser's developer tools (F12) and try an upload. Look at the Console
and the Network tab, then match what you see:

| What you see | Cause | Fix |
|---|---|---|
| The request goes to a different address from the one in the address bar, or the console says "blocked by CORS policy" with the **bundled** store | The address you opened is not the address the ERP signs for. `TARLEAKS_URL` is wrong, or you opened the ERP by another name (`127.0.0.1` against `localhost`, an IP against a name), or you **changed the address after the setup screen** | Open the ERP at exactly the address `TARLEAKS_URL` holds. If you changed the address, update `TARLEAKS_HOST` and `TARLEAKS_URL` in `.env` and run `./tarleaks restart`. |
| `403 SignatureDoesNotMatch` | A proxy changed the `Host` header, or the keys are wrong | Make the proxy pass `Host` unchanged ([examples/behind-nginx](../examples/behind-nginx/README.md)). Check `STORAGE_ACCESS_KEY` and `STORAGE_SECRET_KEY`. |
| `413 Request Entity Too Large` | A proxy limits the body size | nginx: `client_max_body_size 100m;` or more |
| "blocked by CORS policy" with **S3, R2, Wasabi or a NAS** | The bucket has no CORS rule for your address | Add the rule from [configuration.md](configuration.md#cors-rule-for-a-remote-bucket). The address in `AllowedOrigins` must match `TARLEAKS_URL` exactly. |
| "Mixed Content" | The ERP is `https://` and the store address is `http://` | Give the store an `https://` address |
| `404` on `/<bucket>/...` | A proxy does not pass the bucket path to the gateway | Forward every path, not just `/api/` |
| `RequestTimeTooSkewed` or `403` from S3 | The server's clock is off | Turn on NTP |
| `NoSuchBucket`, `InvalidAccessKeyId` | The bucket does not exist, or the keys or region are wrong | Check them in the provider's console. Then Settings, Document management, Storage, **Test connection**. |

After the setup screen, **Settings, Document management, Storage, Test
connection** checks the keys, the bucket and the CORS rule and says what is wrong.

## Live chat does not connect, or drops

A proxy in front of the ERP must pass WebSocket upgrades for `/api/chat/ws`
([examples/behind-nginx](../examples/behind-nginx/README.md)). If chat drops when
idle, raise the proxy's read timeout for that path.

## Upgrade and backup problems

- A step of `./tarleaks update` fails (it prints the way back): [upgrading.md](upgrading.md#if-the-download-fails).
- The database update reports a problem: `./tarleaks logs migrate`.
- A restore ends with the ERP not answering: `./tarleaks logs auth`. Check that
  `.env` is the one from the same backup.

## Still stuck

Make a support bundle, one file with everything support needs:

```bash
./tarleaks doctor --bundle
```

It writes `backups/tarleaks-support-<date>.tar.gz` (or the file you name:
`./tarleaks doctor --bundle /tmp/support.tar.gz`) with:

- the doctor's report, the release, the apps, and the Docker, system and memory
  versions;
- the containers and their images, and the free disk space;
- the last 2000 log lines of every service;
- the size of each database and the migrations each one has;
- the **names** of the settings in `.env` and whether each is set (never the
  values).

Before it packs anything it takes out, in the shapes it knows: the passwords
and keys from `.env` wherever they appear (values of 8 characters or more, or
4 or more under a setting named like a password, key, token or code; plain
settings such as versions, apps, ports, addresses and user names stay so
support can read them), licence keys, sign-in tokens, passwords inside
addresses, signed download links, private keys, e-mail addresses, bank account
numbers (IBAN, with or without spaces), Emirates ID numbers and international
phone numbers. Logs can still name people or companies, or hold numbers in
other shapes, so look inside before you send it. The command prints the exact
lines to open it, for example:

```bash
mkdir -p /tmp/tarleaks-support && tar -xzf backups/tarleaks-support-20261021-090000.tar.gz -C /tmp/tarleaks-support
less /tmp/tarleaks-support/doctor.txt
```

Then write to info@tarleaks.com with what you did, what you expected, and the
bundle attached. Nothing is sent anywhere by itself. (Windows: `tarleaks.ps1`
has no doctor yet; send the output of `.\tarleaks.ps1 status` and
`.\tarleaks.ps1 logs auth`.)

Do not send `.env` or a backup: they hold your keys.
