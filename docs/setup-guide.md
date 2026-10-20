# Setup guide

From an empty machine to your first sign-in, for every kind of machine this kit
supports. Follow the parts that apply to you, in order. Each step says how to
check it worked, and what to do when it did not.

| Your situation | Read |
|---|---|
| A Linux server in the office, used over the office network | 1, 2, 3, 4, 5 (office network), 6, 7 |
| A cloud server (VPS) with a domain name and HTTPS | 1, 2, 3, 4, 5 (internet), 6, 7 |
| Trying it on your own Mac or Windows PC | 1, 2 (Mac / Windows), 4, 6 |
| A Raspberry Pi 5 | 1, 2, 3, 4, 6, then [examples/raspberry-pi](../examples/raspberry-pi/README.md) |
| A company network where the internet goes through a proxy | add [examples/outbound-proxy](../examples/outbound-proxy/README.md) to step 3 |
| A second server to test on, next to the one you use | all steps, and [A test server](#a-test-server) first |

Something failed? [troubleshooting.md](troubleshooting.md) lists every message
the installer, `./tarleaks` and the ERP can show, with the fix.

---

## 1. Decide which apps you need

You install apps, not the whole ERP. The installer adds what each app cannot
work without; nothing else runs.

| Example | Command | Containers | Memory to plan for | Machine |
|---|---|---|---|---|
| HR and CRM | `--apps hr,crm` | 22 | about 4 GB (2 GB with the editors off) | 2 CPU, 8 GB (4 GB with the editors off), 20 GB disk |
| HR, payroll and attendance (Accounting comes with Payroll) | `--apps hr,payroll,attendance` | 24 | about 4.1 GB (2.1 GB) | 2 CPU, 8 GB (4 GB), 20 GB disk |
| The `small` preset | `--profile small` | 29 | about 4.6 GB (2.6 GB) | 2 CPU, 8 GB (4 GB), 20 GB disk |
| The `standard` preset | `--profile standard` | 42 | about 5.8 GB (3.8 GB) | 4 CPU, 8 GB, 40 GB disk |
| Everything (`full`) | `--profile full` | 48 | about 7.1 GB (5.1 GB) | 8 CPU, 16 GB, 80 GB disk |

The editors (New and Edit in Documents, the diagram editor) come with these
and need about 2 GB of the figure; `./tarleaks editors off` gives it back.

What each app needs and costs: [apps.md](apps.md). You can add or remove apps
later with `./tarleaks apps add …` / `remove …`; nothing is reinstalled and no
data is lost.

**Check:** you have a list like `hr,crm`. Your licence (a trial covers every
app) decides who may use them; installing decides what runs.

## 2. Prepare the machine

### Linux server (Ubuntu 22.04/24.04, Debian 12, RHEL/Rocky/Alma 9)

```bash
# Docker Engine and the compose plugin
curl -fsSL https://get.docker.com | sudo sh        # RHEL family: see requirements.md
sudo usermod -aG docker "$USER"                     # then log out and back in
# Time must be right: the licence refuses a clock that runs behind
sudo timedatectl set-ntp true
# git and curl, if missing
sudo apt-get install -y git curl                    # RHEL family: sudo dnf install -y git curl
```

**Check:**

```bash
docker version --format '{{.Server.Version}}'      # 24 or newer
docker compose version                              # v2.x
timedatectl | grep -E 'synchronized|NTP'            # "System clock synchronized: yes"
uname -m                                            # x86_64 or aarch64
```

`permission denied … docker.sock` → you did not log out and in after `usermod`.
`aarch64`/`x86_64` anything else (`armv7l`) → install a 64-bit operating system.
On RHEL, Rocky and Alma with SELinux enforcing, also read
[troubleshooting.md → SELinux](troubleshooting.md#selinux-permission-denied-on-red-hat-rocky-almalinux).

### Mac (Intel or Apple Silicon)

1. Install Docker Desktop: <https://www.docker.com/products/docker-desktop/>.
2. Docker Desktop → **Settings → Resources → Memory**: at least the memory to
   plan for from step 1 plus 2 GB (6 GB for HR and CRM).
3. Open **Terminal** for the commands below.

**Check:** `docker info --format '{{.MemTotal}}'` shows about the memory you set.

### Windows 10/11

1. Install Docker Desktop with the **WSL 2** engine and **Linux containers**.
2. Give WSL enough memory: [examples/windows](../examples/windows/README.md)
   (`.wslconfig` with `memory=8GB`, then `wsl --shutdown`).
3. Use **PowerShell**. If scripts are blocked: `Set-ExecutionPolicy -Scope Process Bypass`.
4. If you downloaded the kit as a ZIP: `Get-ChildItem -Recurse | Unblock-File` in its folder.

**Check:** `docker info --format '{{.OSType}}'` prints `linux`.

### Raspberry Pi 5 (8 GB)

64-bit Raspberry Pi OS, an SSD rather than an SD card, then the Linux steps
above. Details: [examples/raspberry-pi](../examples/raspberry-pi/README.md).

## 3. Open the network paths

The machine needs to reach these **outbound** over HTTPS (port 443):

| Address | Why | When |
|---|---|---|
| `tarleaks.com` | The licence check-in (about every 6 hours; at least once every 30 hours) | Always |
| `registry.tarleaks.com` | The Tarleaks ERP images (signed in with your licence key) | Install and upgrade |
| `registry-1.docker.io`, `auth.docker.io`, `production.cloudflare.docker.com` | Database, queue, gateway and file-store images | Install and upgrade |
| `github.com` | `git clone` of this kit | Install and upgrade |

**Inbound**: only the port people use to open the ERP (80 by default, or 443
behind your HTTPS proxy). Nothing else needs to be open.

**Check (Linux, macOS):**

```bash
for h in tarleaks.com registry.tarleaks.com registry-1.docker.io github.com; do
  curl -sS -o /dev/null --max-time 10 -w "$h %{http_code}\n" "https://$h" || echo "$h BLOCKED"
done
```

Any `BLOCKED` → ask your network team to allow it. If the company reaches the
internet through a proxy, add the proxy for Docker and for the ERP:
[examples/outbound-proxy](../examples/outbound-proxy/README.md). A proxy that
inspects HTTPS must leave `tarleaks.com` alone: the ERP checks that it is
really talking to Tarleaks and will not accept a substituted certificate.

## 4. Install

Your **licence key** is also the password for downloading the images: the
installer signs Docker in with it by itself (no `docker login`). Have it ready,
or let the installer start the free 30-day trial (it asks for your company name
and e-mail address; on the setup screen choose the trial again with the same
address to continue it).

```bash
git clone https://github.com/tarekeesa/Tarleaks-ERP.git
cd Tarleaks-ERP
./install.sh --apps hr,crm                 # your list from step 1
# or, unattended:
./install.sh --apps hr,crm --licence-key nxs1.…
./install.sh --apps hr,crm --trial you@yourcompany.com --company "Your company" --accept-terms
```

Windows:

```powershell
git clone https://github.com/tarekeesa/Tarleaks-ERP.git
cd Tarleaks-ERP
.\install.ps1 -Apps hr,crm
```

The installer:

1. checks Docker, memory, disk and CPU type, then (before any download) that
   tarleaks.com answers, that the clock is right and that the image registry
   accepts the licence key;
2. shows the apps it will run, what it added and why, and the memory to plan for;
3. asks for the address people will use (step 5 explains which);
4. writes `.env` with freshly generated passwords and keys (kept on a re-run);
5. downloads the images and starts them (the first start prepares the database:
   allow up to 5 minutes, longer on a Raspberry Pi);
6. prints the **address** and the **setup code**.

Useful options: `--host 192.168.1.20` (the address), `--port 8080` (when 80 is
taken), `--licence-key nxs1…` (your key; also the download password),
`--trial you@… --company … --accept-terms` (no key yet), `--yes` (accept every default),
`--no-start` (write `.env` only). `./install.sh --help` lists them.

**Check:** `./tarleaks status` shows every service `running`, and
`./tarleaks doctor` reports no `✗`.

| If you see | Do |
|---|---|
| "The image registry did not accept the licence key: …" | The sentence says why (ended, withdrawn, mistyped). Fix the licence, or ask info@tarleaks.com |
| "Downloading Tarleaks ERP needs a licence key" | `./install.sh --licence-key <key>`, or `--trial you@… --company … --accept-terms` |
| "Port 80 is already in use" | `./install.sh --apps … --port 8080` |
| "These apps need about … GB" | Fewer apps, or more memory for Docker |
| "Not answering yet after 10 minutes" | `./tarleaks doctor`, then `./tarleaks logs auth` |

Every other message: [troubleshooting.md](troubleshooting.md#install-and-start).

## 5. Choose how people reach it

### On the office network

Use the server's network address as the host, and let everyone open it by that
address:

```bash
./install.sh --host 192.168.1.20           # the installer shows the address it found
```

Open the port in the server's firewall (`sudo ufw allow 80/tcp`, or see
[examples/office-server](../examples/office-server/README.md)). A name in your
office DNS (`erp.office.local`) works the same way: `--host erp.office.local`.

**Check:** from another computer, `http://192.168.1.20` shows the setup screen.

### On the internet, with HTTPS

Point a DNS name at the server, then put an HTTPS proxy in front:
[examples/vps-https](../examples/vps-https/README.md) (Caddy, automatic
certificates) or [examples/behind-nginx](../examples/behind-nginx/README.md)
(your nginx). Both keep the ERP itself on `127.0.0.1` so only the proxy is
reachable.

**Check:** `https://erp.example.com` shows the setup screen with a valid padlock,
and an upload works after setup (uploads go to the address in `TARLEAKS_URL`,
so it must be exactly the address people open).

### Several companies, each at its own address (from 1.2.0)

Today one installation is one company at one address. From release 1.2.0 a
server runs several companies, each at `<company>.<server address>` and, if the
server administrator attaches one, its own domain. You then also need a wildcard DNS record
(`*.erp.example.com`). Plan the address now so it does not change later:
[companies-and-domains.md](companies-and-domains.md#addresses).

### Just this computer

Keep `localhost` (the default) and open `http://localhost`.

## 6. Set up your workspace

Open the address. The **setup screen** asks for:

1. **The setup code** the installer printed (`./tarleaks setup-code` shows it
   again). It stops a stranger who finds the page first from claiming it.
2. Your company name and country, and the first administrator's name, e-mail and
   password (at least 10 characters).
3. **Start a 30-day free trial** (needs internet; every app, 25 users) or
   **I have a licence key** (one long line starting `tlk1.`).

Then sign in as that administrator. There is no company field to fill: the
installation has one workspace.

**Check:** Settings → Licence shows "active", your apps, your seats and the
next check-in.

| If you see | Do |
|---|---|
| "That setup code is not right" | `./tarleaks setup-code`, copy it again |
| "We could not reach tarleaks.com" | Step 3 for `tarleaks.com`; or use a licence key |
| "tarleaks.com did not start a trial" | The message says why (one trial per e-mail address); ask info@tarleaks.com for a key |

## 7. Make it safe to rely on

Before people depend on it:

1. **Backups every night**: [examples/scheduled-backups](../examples/scheduled-backups/README.md).
   Copy them off the machine. `./tarleaks backup` takes one now.
2. **Keep `.env` safe**: it holds the keys that unlock your data. Without it a
   backup cannot be read. Store a copy with your backups.
3. **Updates**: `./tarleaks update` backs up first, then moves to the newest
   release and checks it ([upgrading.md](upgrading.md)).
4. **E-mail**: Settings → Notifications → Provider to send invitations, resets and
   approvals through your mail server.
5. **Monitoring**: `./tarleaks doctor` from cron, or watch `./tarleaks status`.
   The licence page warns 12 hours before the offline allowance runs out.
6. **Security**: read [security.md](security.md) (what is exposed, what to keep
   closed).

## A test server

To try a release or a change on another machine before your team uses it:

- **Install it fresh** with the steps above. Do not copy the Docker volumes of
  the server you use: a copy of the volumes is the same installation. Today both
  copies would run on one licence, which the licence terms do not allow; from
  1.2.0 one of them is refused at its check-in. Do not copy its `.env` either: a
  licence key in a copied `.env` makes a second installation that is refused at
  once.
- **Give it its own licence.** Start a trial with **another e-mail address**, or
  ask info@tarleaks.com for a test key. Do not reuse the e-mail address of your
  real server's trial: that moves the trial to the test server, and your real
  server is then refused with "This licence is already in use on another
  machine".
- **To test with your real data**, know that a restored backup brings the
  licence of the server it came from: the copy *is* that installation. Follow
  [Test a restore](backup-restore.md#test-a-restore): download the images, then
  take the test server off the internet before you restore. It then works
  until 30 hours after the last check-in recorded in the backup (so restore a
  fresh one). Without internet it cannot reach an internet mail service, but a
  mail server on your office network would still deliver: switch e-mail off on
  the test copy (Settings → Notifications → Provider) in that case.
  If a restored copy does reach `tarleaks.com` while your real server runs, the
  two share one licence. From 1.2.0 the copy whose `auth` service started most
  recently keeps it and the other is refused: stop the copy, then
  `./tarleaks restart` on your real server.
- When you are done: `./tarleaks uninstall --purge` on the test server.

## Everyday commands

| Linux / macOS | Windows | What it does |
|---|---|---|
| `./tarleaks status` | `.\tarleaks.ps1 status` | What runs, the licence state |
| `./tarleaks apps` | `.\tarleaks.ps1 apps` | The apps, what each needs, memory |
| `./tarleaks apps add payroll` | `.\tarleaks.ps1 apps add payroll` | Add apps (and what they need) |
| `./tarleaks apps remove crm` | `.\tarleaks.ps1 apps remove crm` | Remove apps (data kept) |
| `./tarleaks doctor` | — | Check everything, say what is wrong |
| `./tarleaks logs auth` | `.\tarleaks.ps1 logs auth` | Follow a service's log |
| `./tarleaks backup` | `.\tarleaks.ps1 backup` | Database, files and `.env` into `backups/` |
| `./tarleaks update` | `.\tarleaks.ps1 update` | Back up, then move to the newest release |
| `./tarleaks stop` / `start` | `.\tarleaks.ps1 stop` / `start` | Stop and start (data kept) |
| `./tarleaks setup-code` | `.\tarleaks.ps1 setup-code` | Show the setup code again |
