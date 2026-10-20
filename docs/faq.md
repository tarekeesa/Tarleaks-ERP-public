# FAQ

## The product

**What is in this repository?**
Only what you need to install the ERP: a Docker Compose file, installers, settings,
examples and documentation. The software comes as pre-built Docker images. No source
code is included or needed.

**Is it free?**
You get a 30-day trial with up to 25 users, started from the setup screen. After
that you need a licence key from Tarleaks (info@tarleaks.com). See
[licensing.md](licensing.md).

**Can I have the source code, or change the software?**
No. The licence ([LICENSE.md](../LICENSE.md)) forbids reverse engineering,
modifying the images and bypassing the licence check. You may copy and change the
files in this repository (compose file, scripts, examples) to run the software.

**Which apps do I get?**
The apps you install and your licence includes. You choose the apps
(`./install.sh --apps hr,crm`); each brings what it needs ([apps.md](apps.md)).
Check **Settings, Licence** for the apps on your licence.

**Can I run several companies?**
Today one installation runs **one company**. For a second company, use a second
installation on its own machine, with its own licence. Two installations cannot
share one Docker host with this kit, because the containers and volumes all belong
to one project, `tarleaks`.

**From 1.2.0**, one server runs several companies (up to 200 by default). Each
company has its own licence from Tarleaks, its own seats and apps, and its own
address (`acme.erp.example.com`, or an own domain the server administrator
attaches). Tarleaks adds a company for you, or whoever holds the server's setup
code adds one with a key Tarleaks issued. A company without a valid licence from
Tarleaks does not run. See
[companies-and-domains.md](companies-and-domains.md).

**Can a company use its own domain?**
Today the installation answers at one address of your choice, which can be a
domain's root (`https://example.com`). From 1.2.0 every company gets an address
under the server's address, and the server administrator (the holder of the
setup code) can attach a company's own domain to it:
[companies-and-domains.md](companies-and-domains.md#addresses).

**Is there a platform console or a super-administrator?**
No. A self-hosted installation has no platform console, no platform route and no
platform administrator, and the kit has no setting that adds one. Today sign-in
already refuses a platform-administrator account and the `auth` service answers
"not found" for platform addresses. From 1.2.0 every other service also ignores
the platform-administrator flag, so not even a changed gateway file or a direct
call to a service can reach a platform function. Licences, trials, seats and companies
are decided by Tarleaks on tarleaks.com and arrive signed. Inside your company,
your administrator manages users, roles and data.

## Installing

**Do I need a domain name?**
No. `localhost` works on one computer, and a local IP address works on an office
network. Use a domain and HTTPS when the ERP must be reachable from the internet
([examples/vps-https](../examples/vps-https/README.md)).

**Which operating systems?**
Ubuntu 22.04 and 24.04, Debian 12, Red Hat, Rocky and Alma 9, macOS 13 or newer,
Windows 10 and 11 with Docker Desktop and WSL 2, and Raspberry Pi 5 with 64-bit
Raspberry Pi OS. Details: [requirements.md](requirements.md).

**Intel or ARM?**
Both. Every image is published for `amd64` and `arm64`.

<a id="can-i-install-without-internet"></a>
**Can I install without internet?**
Yes, with the **offline bundle**: every image of one version, for one CPU type,
in a few files you carry to the server. Nothing is downloaded while you install.

What you need first:

- Docker Engine and Docker Compose on the server, installed from your own
  package mirror. The installer does not install Docker.
- This kit (the Git repository or its ZIP) at the same version as the bundle.
- The offline bundle for that version and CPU type,
  `tarleaks-<version>-linux-amd64` (Intel/AMD) or `tarleaks-<version>-linux-arm64`
  (ARM). It is a few files ending in `.tar.part-00`, `.tar.part-01` and so on,
  plus one `.images.txt` and one `.SHA256SUMS`. It holds every image the kit
  can start, the editors included: the document editor (with the Arabic
  fonts), the proxies and, on 1.0.0, the diagram editor (Diagram Studio is not in 1.2.0). Ask info@tarleaks.com for the
  download link, and keep the files of one bundle together in one folder.
- A licence key made for a site without internet (see the licence step below).

Then, on the server:

1. Load the bundle. It checks every file first, then loads the images into
   Docker. It needs free disk of about twice the bundle's size.

   ```bash
   ./tarleaks load-bundle /media/usb/tarleaks-1.2.0-linux-amd64
   ```

   Windows: `.\tarleaks.ps1 load-bundle D:\tarleaks-1.2.0-linux-amd64`

2. Install without downloading anything:

   ```bash
   ./install.sh --offline --version 1.2.0 --licence-key nxs1.…
   ```

   Windows: `.\install.ps1 -Offline -Version 1.2.0 -LicenceKey nxs1.…`

3. Open the address it prints, type the setup code and choose **I have a
   licence key**.

To upgrade later, load the new version's bundle the same way, then run
`./tarleaks update --to 1.3.0 --offline` (Windows: `.\tarleaks.ps1 update -To 1.3.0 -Offline`).
`.env` names the new version only once every one of its images is on the
machine, so a missing image changes nothing. Without `--offline`, the installer
and `upgrade` also carry on by themselves when the download fails but every
image is already there.

What `load-bundle` accepts: the folder with the downloaded `.tar.part-NN`
files (it checks them against the `.SHA256SUMS` file next to them, joins and
unpacks them), one joined `.tar` file, the `.tar.part-00` file, or a bundle
folder that is already unpacked. An unpacked bundle looks like this:

```text
tarleaks-1.2.0-linux-amd64/
  images.txt        "# version: 1.2.0", "# platform: linux/amd64", then one image per line
  SHA256SUMS        the sha256 of every file under images/ (sha256sum format)
  images/*.tar      one archive per image, as docker save writes it (.tar.gz works too)
```

It refuses a bundle made for another CPU type and any file whose checksum does
not match, then loads every image file listed in `SHA256SUMS` and tells you
what to run next.

A closed network has none of these from the internet, so **you provide them**:

| What | Why | Where you set it |
|---|---|---|
| A time server (NTP) | The licence refuses a clock that runs behind, and e-invoices are signed with the time | Point the server's own clock at it, and set `EINVOICE_NTP_SERVER=ntp.example.local:123` in `.env` |
| An SMTP relay, if the ERP should send e-mail | No e-mail leaves without one | **Settings, Notifications**, Custom SMTP |
| Your own TLS certificate, for HTTPS | Let's Encrypt cannot reach a closed network | A reverse proxy in front of the ERP: [examples/behind-nginx](../examples/behind-nginx/README.md) |
| A map tile server (optional) | Background maps in Fleet and Attendance. Without it, positions show on a plain background | **Fleet, Settings**, Map tile server address |
| A LiveKit server (optional) | Voice and video calls. Without it, calls are off | [configuration.md](configuration.md#calls-livekit) |
| The editors (document, diagram) | New and Edit in Documents; drawing in the Diagrams app | They run on your own server, next to the ERP; their images (`onlyoffice`, `nginx`, and on 1.0.0 `jgraph/drawio`; Diagram Studio is not in 1.2.0) must be in the bundle or already loaded. [configuration.md](configuration.md#editors) |

**The licence step.** Today a licence still needs **one** connection to
`tarleaks.com`: the 30-day trial is started online, and a licence key is
activated by its first check-in. For a site with no internet, ask
info@tarleaks.com for a key with **check-ins switched off**: once activated it
never calls again. Until then it works up to the activation date written in it
(30 days unless agreed otherwise). Activate inside that window over any route
you allow for a moment: outbound HTTPS to `tarleaks.com`, directly or through
`HTTPS_PROXY` in `.env` ([configuration.md](configuration.md#outbound-proxy)).
**Activation with no connection at all is planned but not available yet.**

Which outside addresses the ERP can use, and which are off by default:
[network.md](network.md).

**Can I use my own PostgreSQL server?**
Not yet. The bundled database is the supported setup in this version. See
[examples/external-postgres](../examples/external-postgres/README.md) for what an
external server would need.

**Can I keep documents on S3, R2, Wasabi or a NAS?**
Yes. Set it in `.env` before the first setup:
[configuration.md](configuration.md#file-storage).

**Port 80 is taken. What now?**
`./install.sh --port 8080`, then open `http://<address>:8080`.

**Can I add or remove apps later?**
Yes: `./tarleaks apps add payroll`, `./tarleaks apps remove crm`, or a preset with
`./tarleaks profile standard`. Data and keys are kept; a removed app's data comes
back when you add it again.

## Licence

**What happens if the internet is down?**
The ERP keeps working for **30 hours** after its last successful check-in, then stops
serving until a check-in succeeds. It checks in about every 6 hours and retries
every 2 minutes once blocked. Your data stays where it is.

**Does Tarleaks see my data?**
No. A check-in sends the licence ID, the installation ID, the version, the CPU type
and the number of active users. See
[licensing.md](licensing.md#what-is-sent-and-what-is-not).

**Can I start the trial again?**
No. There is one trial per e-mail address. Setting up again with the same address
gives you the same trial with the same end date.

**The ERP says my licence is blocked.**
Press **Check again**, then follow
[troubleshooting.md](troubleshooting.md#licence-blocked-codes).

**I need more users or more apps.**
Ask info@tarleaks.com. You do not need a new key: the change reaches your
installation at its next check-in, or press **Check now** in **Settings, Licence**.

**I am moving to a new server.**
See [licensing.md](licensing.md#moving-to-new-hardware).

## Your data

**Where is my data?**
In Docker volumes on your machine: `pgdata` (the database), `files` (documents and
attachments in the bundled store), `redisdata`, `rabbitdata` and `hrdocs`.

**How do I back it up?**
`./tarleaks backup`. Schedule it, copy it off the machine and encrypt it:
[backup-restore.md](backup-restore.md).

**Can I get my data out?**
Yes. Your data belongs to you, and the licence lets you export it before the end of
the term. Use each app's exports, and keep regular backups.

**Does it start again after a reboot?**
Yes, if Docker starts at boot (the default on Linux packages, and "Start Docker
Desktop when you sign in" on macOS and Windows). Containers restart unless you
stopped them with `./tarleaks stop`. Each app waits for the message queue before
it starts. After a reboot, run `./tarleaks doctor` once: if it says an app is
"not receiving events", run `./tarleaks restart`. On Docker Desktop the address
can stay silent after a restart of the computer: `docker compose up -d
--force-recreate gateway` ([troubleshooting](troubleshooting.md#after-a-restart-or-a-reboot)).

## Everyday

**How do I see the version?**
**Settings, Licence**, under "This installation".

**How do I stop it, start it, update it?**

```bash
./tarleaks stop
./tarleaks start
./tarleaks update
```

On Windows use `.\tarleaks.ps1`.

**How do I read the logs?**
`./tarleaks logs auth`, or the name of any service in `./tarleaks status`.

**How do I remove it?**
`./tarleaks uninstall` removes the containers and keeps your data.
`./tarleaks uninstall --purge` deletes the data in Docker as well. Back up first.
It does **not** delete `backups/` (full copies of your data and keys), `.env`
or the images; it lists them with the commands that remove them. On Windows:
`.\tarleaks.ps1 uninstall` and `.\tarleaks.ps1 uninstall -Purge`.

**Where do I get help?**
[troubleshooting.md](troubleshooting.md), then info@tarleaks.com with the output of
`./tarleaks status` and `./tarleaks doctor`.
