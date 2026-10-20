# Security

What the installation exposes, what protects it, and what you need to do.

## What is exposed

Only **one port** is published on the machine: the gateway, on `HTTP_PORT`
(80 by default), on the interface `HTTP_BIND`: only this computer on a laptop or
desktop, the whole network on a server (the installer proposes one and says why;
[network.md](network.md#who-can-open-it)).

| Component | Reachable from outside? |
|---|---|
| Gateway (Traefik) | **Yes**, on `HTTP_BIND:HTTP_PORT` |
| ERP services (`auth`, `hr`, `payroll`, and the rest) | No. Only the gateway talks to them. |
| Document editor, diagram editor, sign-in check proxy | Only through the gateway (`/onlyoffice/`, `/drawio/`); the proxy not at all |
| PostgreSQL database | No port published |
| Redis cache | No port published |
| RabbitMQ message queue and its management page | No port published |
| Bundled file store | Only through the gateway, at `/<STORAGE_BUCKET>/`, and only with a signed link |

Check it from another computer. These should all fail to connect:

```bash
nc -zv <server-ip> 5432 6379 5672 15672 7070 8001
```

CI checks the same on every change (`scripts/check-ports.sh`): the kit
publishes exactly one port, the gateway's, on `HTTP_BIND`.

**A database tool that must connect directly** (pgAdmin, a reporting tool) is
an opt-in: [examples/database-access](../examples/database-access/README.md)
publishes PostgreSQL on `127.0.0.1` only, unless you set `POSTGRES_BIND` in
`.env` to one network address of the machine. Prefer an SSH tunnel to the
`127.0.0.1` port. Docker opens a published port in front of the machine's
firewall (ufw, firewalld), so never publish the database on `0.0.0.0` on a
server that is on the internet.

### What the gateway does with every request

- It **removes** any identity headers the client sent (tenant, user, roles,
  permissions, licence), so a browser can never claim to be someone else.
- On every signed-in request it asks the `auth` service who the caller is and what
  the licence allows. Only then does it forward the request, with the identity
  filled in by `auth`.
- It has **no** `/api/platform` route. A self-hosted installation has no platform
  console and no platform administrator. There is no public sign-up either:
  once the workspace exists, registration is closed.
- **From 1.2.0**, every service also checks the licence by itself and removes
  the platform-administrator flag from every request. A changed gateway file,
  database row or environment setting does not open an unlicensed app, an
  unlicensed company or a platform function.

## Who decides the licence

Tarleaks decides licences, and only on tarleaks.com: trials, keys, seats, apps,
expiry, suspension and, from 1.2.0, which companies a server may run. Your
installation calls out to `tarleaks.com`; nothing calls in, and nothing on your
server listens for tarleaks.com. It acts only on the signed answers to its own
calls.

- Every licence key and every check-in answer is **signed** by Tarleaks. The
  installation checks the signature with a key built into the software and
  ignores anything unsigned or altered.
- The offline allowance is counted from Tarleaks's own signed time, not from a
  date stored on your machine, and a clock set back is refused
  ([licensing.md](licensing.md#the-clock)).
- From 1.2.0, a second running copy of an installation is refused at its
  check-in, and each company runs only while Tarleaks's latest signed answer
  lists it ([companies-and-domains.md](companies-and-domains.md#how-the-licence-is-protected)).

### What can be reached without signing in

These routes are public by design. Sign-in and several of the public pages are
rate-limited:

| Area | Why |
|---|---|
| Sign-in, sign-out, token refresh, password reset, SSO callbacks | So people can sign in |
| `GET /api/auth/installation` | Tells the sign-in page whether setup is needed and the licence state (workspace name, plan, dates). No data. |
| Public documents (shared links), careers page, public helpdesk, customer portals, e-invoicing public pages, public store and subscription endpoints | Things you choose to share with outsiders |
| Notification links: unsubscribe, mail-provider sign-in callbacks, webhooks | Mail and integrations |
| Chat WebSocket | Live chat |
| Clock-in machines and kiosk tablets: `/api/attendance/public/`, `/iclock/`, `/zk/` | Each machine or tablet sends its own key, which the attendance service checks. Keys are shown once and can be replaced or archived on the machine's page; the serial-number address accepts only the IP addresses you allow. No fingerprint, face or photo is ever sent ([details](attendance-machines.md)). |

Everything else needs a signed-in user whose permissions and licence allow it.

## The setup code

`TARLEAKS_SETUP_CODE` (in `.env`) protects the first-run page, so a stranger who finds
a new installation on the internet cannot claim it. It also lets its holder
**replace the licence key**, even while the ERP is locked.

- Treat it like a password. `./tarleaks setup-code` shows it.
- Do not post it in tickets or chats.

## Secrets and keys

- The installer generates every password and key with a strong random generator
  and writes `.env` readable by its owner only (mode 600).
- **Do not change any generated key or password** after the first start. They
  protect data already stored in the database. See
  [configuration.md](configuration.md#keys).
- `.env` is excluded from Git. Never commit it, e-mail it or paste it into a
  support request.
- Anyone in the Linux `docker` group can read everything on the machine, `.env`
  included. Add only administrators to it.

## What the gateway does for you

- Removes the identity headers from every request, so nobody can claim a
  company or a user; signed-in addresses ask the sign-in service first.
- Only a short list of addresses works without signing in (sign-in itself, the
  setup screen, the careers page, share links, the supplier and signer pages,
  clock-in machines, document previews signed with a token). Each is listed in
  `config/traefik/dynamic/routes.yml`, rate-limited per address, and
  `scripts/check-routes.sh` checks that none of them swallows a signed-in
  address.
- The web app's pages cannot be shown inside another website's frame
  (`Content-Security-Policy: frame-ancestors 'self'`, `X-Frame-Options:
  SAMEORIGIN`), and no response names the server software or its version.
- The gateway adds no cross-origin (CORS) permission of its own. Some 1.0.0
  services answer `Access-Control-Allow-Origin: *`; that does not let another
  website use a person's session (the app signs requests with a token, not a
  cookie), and later releases narrow it.

## Use HTTPS on anything beyond your own computer

The bundled gateway speaks plain HTTP. That is fine on `localhost`. On a network,
anyone who can see the traffic can read passwords and documents as they cross it.

| Where it runs | What to do |
|---|---|
| This computer only | HTTP is fine |
| A small trusted office network | HTTP is acceptable. HTTPS or a VPN is better. |
| The internet | **HTTPS is required.** |

For HTTPS put a TLS proxy in front. [Caddy](../examples/vps-https/README.md) is the
simplest: it gets and renews a free certificate by itself. An existing nginx works
too ([examples/behind-nginx](../examples/behind-nginx/README.md)). With a proxy
in front:

- Set `TARLEAKS_URL=https://…`, `HTTP_BIND=127.0.0.1` and `HTTP_PORT=8080`, so only
  the proxy can reach the gateway.
- The proxy must pass the `Host` header unchanged.

If only staff use it from outside the office, consider a VPN instead of exposing
the ERP to the internet.

## Firewall

Allow only what is needed:

| Port | Open to | Why |
|---|---|---|
| `HTTP_PORT` (80) | Your users' network | Using the ERP, without a proxy |
| 80 and 443 | The internet | Only with an HTTPS proxy in front |
| 22 | Your administrators only | SSH |
| Outbound 443 | `tarleaks.com`, `registry.tarleaks.com`, Docker Hub | [requirements.md](requirements.md#network) |

Docker publishes ports by writing its own firewall rules, ahead of `ufw` and
`firewalld`. A rule such as `ufw deny 8080` may **not** stop a published port.
The reliable ways to restrict access:

1. Bind to one interface with `HTTP_BIND`. `127.0.0.1` is the usual choice behind
   a proxy or on a laptop (`./install.sh --bind local`, or later
   `./tarleaks network local`). A LAN address limits it
   to that network card.
2. Filter in the cloud provider's firewall or security group.
3. Always test from another computer.

## Keep it updated

Three layers need updates. The ERP never updates itself.

| Layer | How |
|---|---|
| The operating system | Turn on automatic security updates (`unattended-upgrades` on Ubuntu and Debian, `dnf-automatic` on Red Hat family) and reboot when asked |
| Docker | Update it with the OS packages |
| The ERP and its third-party images | the release's kit (`git fetch --tags && git checkout v<release>`), then `./tarleaks update` ([upgrading.md](upgrading.md)). The kit pins the database, cache, queue, gateway and file-store versions. A new kit release moves them. |

Use SSH keys instead of passwords, and disable password login.

## Backups are sensitive

A backup holds your whole database, in readable SQL, and every key. Anyone with
it can read your
data. Encrypt it before it leaves the machine, store the passphrase elsewhere,
and limit who can read the backup location. See
[backup-restore.md](backup-restore.md).

## What leaves the machine

| What | When | Where to |
|---|---|---|
| Licence ID, installation ID, version, CPU type, edition, active user count | About every 6 hours | `tarleaks.com` |
| **From 1.2.0:** also a random run ID, the server address, each company's licence ID, active users and own domains, the apps run, and how the last update ended ([details](licensing.md#what-is-sent-and-what-is-not)) | With each check-in | `tarleaks.com` |
| Company name, your name, e-mail, country (once) | When you start a trial | `tarleaks.com` |
| Files and their signed links | Only if you chose a remote file store | Your S3, R2 or Wasabi bucket |
| Text sent for AI features | Only if you set an AI key | The AI provider you chose |

No business data goes to Tarleaks. See [licensing.md](licensing.md#what-is-sent-and-what-is-not).

## Before you go live

- [ ] HTTPS in front, if it is reachable from the internet
- [ ] `TARLEAKS_URL` is the final address
- [ ] From another computer, the database, cache and queue ports do not answer
- [ ] The administrator's password is long and unique
- [ ] Automatic time (NTP) is on
- [ ] A nightly backup runs, is copied off the machine and is encrypted
- [ ] You have restored a backup at least once
- [ ] Automatic OS security updates are on
- [ ] Only administrators are in the `docker` group

## Reporting a security problem

Write privately to dev@tarleaks.com. Please do not open a public issue for a
vulnerability. What to include and what happens next:
[SECURITY.md](../SECURITY.md).
