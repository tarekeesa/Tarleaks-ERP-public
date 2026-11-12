# Network: what the ERP connects to

What leaves your server, when, and how to run without it. Use this page to
write firewall rules, or to plan an installation with no internet at all.

**The full, always-current list is `docs/EXTERNAL-ENDPOINTS.md` in the release**
(the release notes link it). It lists every outside address the software can
call, which feature calls it, and whether it is on by default. This page is the
summary.

## In short

| What | When | Default |
|---|---|---|
| Image downloads (`registry.tarleaks.com`, Docker Hub) | `./install.sh`, `./tarleaks update` and `./tarleaks upgrade` only | Needed, unless you use the [offline bundle](faq.md#can-i-install-without-internet) |
| Licence check-in (`tarleaks.com`, HTTPS 443) | About every 6 hours | Needed, unless your licence key has check-ins switched off. See [licensing.md](licensing.md) |
| Moving a company from Tarleaks Cloud (`tarleaks.com`, HTTPS 443) | **From 1.2.0.** Only during a [move to this server](move-from-cloud.md), then every 6 hours until the signed deletion certificate has arrived | Off: only when you run the move |
| Government and e-invoicing services | Only when a workspace uses them | Off until set up |
| A time server (NTP) | Before e-invoices are signed | Uses a public one unless you name yours |
| Any other outside service | Only when a workspace switches it on | **Off** |

**Nothing third-party is called by default.** The pages your people open load
their files from your own server, not from other sites (the release's
`EXTERNAL-ENDPOINTS.md` records any exception). Optional integrations (AI,
e-mail providers, text messages, push notifications, social networks, payments,
exchange rates, single sign-on, webhooks) stay off until an administrator turns
one on, and the ERP keeps working when any of them cannot be reached.

## Who can open it

The ERP listens on one port. Who may connect to it is one setting, `HTTP_BIND`:

| Choice | `HTTP_BIND` | Who can open it |
|---|---|---|
| Only this computer | `127.0.0.1` | Programs on this computer. Nobody else on the café, hotel or office network |
| The office network | `0.0.0.0` | Every computer that can reach this machine on that port |

The installer looks at the machine and proposes one, and always says which and
why:

- a **laptop or desktop** (it has a battery, a desktop session, runs Docker
  Desktop, is a Mac, or runs Windows 10/11 rather than Windows Server) gets
  **only this computer**, so a laptop on a shared Wi-Fi does not open the
  sign-in page to everyone around it;
- a **server** (none of those) gets **the office network**, which is what a
  server is for;
- an address other people type (`--host 192.168.1.20`) always means the network;
- an installation you run again keeps what it had.

You can always decide yourself: `./install.sh --bind local` or `--bind office`
(Windows: `-Bind local`, `-Bind office`), or later, without installing again:

```bash
./tarleaks network            # what it is now
./tarleaks network office     # everyone on the network (then allow the port in the firewall)
./tarleaks network local      # only this computer
```

(Windows: `.\tarleaks.ps1 network office`.) Only the gateway restarts; nothing
else is touched. Going to the office network on a machine whose address is
still `localhost` also needs its real address for the links in e-mails:
`./install.sh --host <address>`.

## Government and e-invoicing

These are allowed by design, because the law or the tax authority requires
them. They are called only by workspaces that use the feature:

- E-invoicing in Saudi Arabia (ZATCA Fatoora, including its certificate
  revocation lists) and the UAE (the FTA and the accredited service providers,
  for example Storecove).
- Identity and signing services (UAE PASS, Nafath) for contracts, when set up.
- Labour and statutory services (for example MOHRE) when a workspace uses them.

Before it signs an e-invoice, the ERP can compare its clock with a time
server. By default it asks no one and relies on the server's own time sync
(signing never waits on this check). To have the clock measured, name your
own NTP server in `.env`:

```bash
EINVOICE_NTP_SERVER=ntp.example.local:123
```

`EINVOICE_PROBE_URL` (empty by default) can name an address outside your
network that the ERP tries when an e-invoicing provider does not answer, to
tell "their outage" from "our network". Leave it empty to skip that check.

## Downloads at install time

`./install.sh`, `./tarleaks update` and `./tarleaks upgrade` download the images:

| Host | What |
|---|---|
| `registry.tarleaks.com` (and `tarleaks.com`, which checks the licence key for it) | The Tarleaks images, signed in with your licence key |
| Docker Hub (`registry-1.docker.io`, `docker.io`, `production.cloudflare.docker.com`) | The database, cache, message queue, gateway, file store and helper images, and the optional diagram editor |
| `ghcr.io`, `pkg-containers.githubusercontent.com` | Only when the server has no cosign 2.4 or later: Sigstore's cosign image, which checks the Tarleaks signature of every downloaded Tarleaks image ([config/sigstore](../config/sigstore/README.md)) |

These downloads are done by Docker itself, so they follow **Docker's** proxy
setting, not the ERP's ([requirements.md](requirements.md#network)). Without
internet, load the offline bundle instead: no download happens at all
([faq.md](faq.md#can-i-install-without-internet)).

## Through a proxy

If your servers reach the internet only through a proxy, set it in `.env`
(`HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`). Every ERP service uses it for the
connections above. Details:
[configuration.md](configuration.md#outbound-proxy).

## Things you provide on a closed network

| Need | What to set up |
|---|---|
| Correct time | An NTP server on your network; point the server's clock at it, and set `EINVOICE_NTP_SERVER` |
| E-mail (optional) | An SMTP relay on your network, set in **Settings, Notifications** (Custom SMTP) |
| HTTPS (recommended) | Your own certificate on a reverse proxy ([examples/behind-nginx](../examples/behind-nginx/README.md)) |
| Maps (optional) | Your own map tile server, set in **Fleet, Settings** (Map tile server address). With none, maps show positions without a background map |
| Calls (optional) | Your own LiveKit server ([configuration.md](configuration.md#calls-livekit)). With none, calls are off |
| Document and diagram editors | Part of the installation, served by your own server at `/onlyoffice/` and `/drawio/` ([configuration.md](configuration.md#editors)); nothing to set up |
