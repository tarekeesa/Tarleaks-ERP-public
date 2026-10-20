# Running without internet

Tarleaks ERP runs on a server with no internet connection at all: sign-in,
documents (upload, open, edit in the document editor, download), HR, payroll,
accounting, point of sale and the other apps use only what is on the machine.
This page says how to switch an installation to that mode, what it turns off,
and how to prove nothing leaves the server.

Installing without internet (the **offline bundle** of images) is a separate
step: [faq.md](faq.md#can-i-install-without-internet).

## The switch

```bash
./tarleaks offline on       # no optional outside service
./tarleaks offline sealed   # and nothing inside Docker can leave this machine
./tarleaks offline off      # back to normal
./tarleaks offline          # which one is in force
```

| | `on` | `sealed` |
|---|---|---|
| AI keys in `.env` (`GROQ_API_KEY`, `OLLAMA_*`, `DIAGRAMS_AI_BASE_URL`) | cleared (kept in `.env` as `#offline-saved` lines; `off` puts them back) | cleared |
| The AI drawing engine (`diagrams-engine`) | not started | not started |
| `./tarleaks doctor` | no internet checks (licence server, image registry, clock against tarleaks.com) | the same |
| A mail relay, a NAS or a database on your **office network** | still reached | **not reached**: every service sits on a Docker network with no route out (`config/offline/compose.sealed.yml`); only the gateway also has a network, to receive your users |
| Internet | not used by the ERP (see below) | impossible from any ERP container |

`sealed` re-creates the Docker network once (the containers stop for a few
seconds; no data is touched). Use `on` when the ERP must still send e-mail
through your own mail server.

`TARLEAKS_OFFLINE` in `.env` holds the mode. The services also receive it.

## What needs internet otherwise, and what to do about it

| Normally | Offline |
|---|---|
| **Licence check-in** with tarleaks.com about every 6 hours | Needs an **offline licence key**: one whose check-ins are switched off. Ask Tarleaks for one (say the installation has no internet). A normal key keeps working only for its offline allowance, then the ERP stops. `./tarleaks doctor` reads the key in `.env` and tells you which kind it is. |
| Image downloads (install, upgrade, a new app) | The offline bundle: `./tarleaks load-bundle <folder>`, then `./tarleaks update --to <release> --offline` |
| E-mail through an outside provider | Your own mail server (SMTP) on your network, set in Settings, E-mail (mode `on`, not `sealed`) |
| AI features (document questions, AI drawing, assistants) | Off. Each screen says AI is not set up. A company may point Settings, AI at a model server on your own network (mode `on`) |
| Map tiles (fleet) | None by default; a company can set its own tile server |
| Time (NTP) for e-invoice timestamps | Your own time server: point the server's clock at it (`timedatectl`, chrony) |
| Government and e-invoicing services (UAE PASS, ZATCA, FTA access point) | Not reachable. Leave them off, or allow those addresses only ([network.md](network.md)) |
| HTTPS certificates from Let's Encrypt | Not possible sealed. Use `--tls proxy` with a certificate from your own CA |

The document editor, the file store, the database, the message queue and the
web app all run on the server itself and never call out. The web pages load
every font, icon and script from your server.

## Prove it

With the installation running in `sealed` mode:

```bash
# 1. Nothing inside can reach the internet (expect a failure, not a page):
docker compose exec -T auth curl -sS -m 5 https://tarleaks.com -o /dev/null; echo "exit $?"
# 2. ...and the ERP still answers:
./tarleaks doctor
```

Then sign in and use it: upload a document, open it in the editor, change it,
save, download it; add an employee; post a journal entry; make a sale at the
point of sale. Keep the browser's developer tools open on the **Network** tab:
every request goes to your own address.

To list connection attempts while you click, on a Linux server:

```bash
sudo tcpdump -ni any 'tcp[tcpflags] & tcp-syn != 0 and not dst net 10.0.0.0/8 and not dst net 172.16.0.0/12 and not dst net 192.168.0.0/16 and not dst host 127.0.0.1'
```

Nothing should print while the ERP is used.

### What was proved (2026-10-18)

On a test installation (release 1.2.0 images built from the same source,
apps HR, attendance, payroll, accounting, CRM, inventory, sales orders, chat,
point of sale, document editor on), with `./tarleaks offline sealed` and an
offline licence key:

- `curl https://tarleaks.com` from inside `auth`, `documents` and
  `onlyoffice`: "Could not resolve host"; a machine on the office network:
  "Couldn't connect". `./tarleaks doctor`: no problems.
- First-run setup with the offline licence key completed without any
  outside connection.
- In a browser: sign-in, Documents, Employees, Finance, Journal entries and
  Point of Sale opened with **no request to any other host** and no server
  error.
- A Word document: uploaded, opened in the document editor, text typed, the
  editor closed, a second version saved 10 seconds later, downloaded, and the
  typed text was inside it.
- An employee added, the UAE accounting pack installed, a journal entry
  created and posted, a point-of-sale shop, till, session and a paid sale.
- 40 minutes of container logs held no attempt to reach an outside address.

## See also

- [network.md](network.md): every outside address, for firewall rules
- [licensing.md](licensing.md): licence keys and check-ins
- [https.md](https.md): your own domain with HTTPS
