# Companies, addresses and who controls what

How many companies one installation can run, at which addresses people reach
them, and who decides what. Parts of this page describe **release 1.2.0**, which
is in preparation. They are marked **From 1.2.0**. Everything else is how the
current release works.

## The short version

| | Current release (1.0.0) | From 1.2.0 |
|---|---|---|
| Companies per installation | One | Several, each under its own licence (up to 200 by default) |
| What lets a company run | The installation's licence (trial or key) | Its **own** licence, issued by Tarleaks |
| Who adds a company | The setup screen, once | Tarleaks, on tarleaks.com, **or** the holder of the server's setup code, with a company key Tarleaks issued |
| Addresses | One address, any form (`localhost`, an IP, `erp.example.com`, `example.com`) | `<company>.<server address>` for every company, plus an own domain that the server administrator attaches |
| Platform administration on your server | None | None |

## Who controls what

**Tarleaks controls licences, and only from tarleaks.com.** Trials, licence keys,
seats, apps, renewals and suspension are decided on tarleaks.com (from 1.2.0,
which companies a server may run as well). Your installation learns each
decision at its next check-in (about every 6 hours, or at once with **Check
now**). Every decision arrives **signed** by Tarleaks, and the installation
refuses anything that is not.

**Your server has no platform administration of any kind.** There is no
platform console, no platform route and no platform administrator on a
self-hosted installation, and no setting creates one. From 1.2.0 not even a
changed gateway file or a direct call to a service can. Tarleaks never connects
*into* your server: nothing on your server listens for tarleaks.com, and your
installation only acts on the signed answers to its own calls.

**You control everything inside your companies.** Users, roles, permissions,
data, backups, the apps you install ([apps.md](apps.md)) and the addresses. Your
business data never leaves your server ([licensing.md](licensing.md#what-is-sent-and-what-is-not)).

| Decision | Who | Where |
|---|---|---|
| Issue a trial or a licence key | Tarleaks | tarleaks.com |
| Seats, apps, expiry, renewal of a licence | Tarleaks | tarleaks.com |
| Suspend or end a licence | Tarleaks | tarleaks.com |
| **From 1.2.0:** add a company | Tarleaks, or the holder of the server's setup code with a key Tarleaks issued | tarleaks.com, or the **This server** page (`/admin/server`) or `./tarleaks companies add` |
| **From 1.2.0:** attach a company's own domain | The holder of the server's setup code | The **This server** page or `./tarleaks companies domain add` |
| Which apps run on the server | You | `./tarleaks apps` |
| Users, roles and data inside a company | That company's administrator | The ERP |
| The address of the server, and DNS | You | `.env` and your DNS provider |

## Companies

### Today: one company per installation

The setup screen creates one company and its first administrator, under one
licence. There is no public sign-up, and registration closes once the company
exists. A second company needs a second installation, on another machine, with
its own licence.

### From 1.2.0: several companies on one server

A server can run several companies (up to 200 by default; the setting
`TARLEAKS_MAX_COMPANIES` raises it, to at most 1000). Each one runs **only while
Tarleaks's latest signed answer lists it**, with its own seats, its own apps and
its own expiry.

There are two ways to add a company:

1. **Tarleaks adds it for you.** Ask info@tarleaks.com, or your account contact.
   Tarleaks adds the company to your installation on tarleaks.com. Your server
   asks every few minutes whether anything changed, so it creates the company
   within about five minutes (at once with **Check now**). Tarleaks gives you a
   one-time link for the company's first administrator to set a password. If
   your server can send e-mail, it also e-mails that person a link.
2. **The server's administrator adds it with a key.** Tarleaks issues one key
   per company. Whoever holds the server's **setup code** opens the **This
   server** page (the "Manage this server" link under the sign-in form, or
   `/admin/server`), chooses **Add a company**, pastes the key and creates the
   company's first administrator. `./tarleaks companies add` does the same from
   a terminal.
   - A key works on **one** server only, and only once.
   - The server must be online to add a company.

A company that is not on Tarleaks's signed list does not run, however it was
made: one added straight into the database, or one company's database copied in
from another server. Its people see the lock screen with a sentence saying the
company is not licensed on this server. Nothing is deleted: when the licence is
in order again, the company is back as it was. (A whole-server backup restored
on another machine is the *same* installation with the same companies; see
[licensing.md](licensing.md#moving-to-new-hardware).)

What each licence decides, company by company:

| | Per company |
|---|---|
| Seats | Active users of that company only |
| Apps | The apps that company may use (the server must also run them: [apps.md](apps.md)) |
| Expiry, suspension | That company only. The others carry on. |

**An installation set up before 1.2.0** keeps working after the update. Its
company becomes the first company under its existing licence, and you change
nothing.

## Addresses

### Today

The installation answers at the address in `TARLEAKS_URL`: `http://localhost`,
an IP address such as `http://192.168.1.20`, a name such as
`https://erp.example.com`, or a domain's root such as `https://example.com`.
Choosing it is step 5 of the [setup guide](setup-guide.md#5-choose-how-people-reach-it).
People open exactly that address.

### From 1.2.0: one address per company

Your server keeps its address (the **server address**, for example
`erp.example.com`). With a DNS name, every company also gets its own address
below it, and the server administrator may attach a company's own domain:

| Address | Example | What it needs |
|---|---|---|
| Company address | `acme.erp.example.com` | A wildcard DNS record `*.erp.example.com` pointing at the server, once for all companies |
| Company's own domain | `acme.com` or `hr.acme.com` | A DNS record for that name pointing at the server; then the server administrator attaches it on the **This server** page or with `./tarleaks companies domain add <company> <domain>` |
| The server address itself | `erp.example.com` | It keeps opening your first company, with a link to sign in to another company. Or the server administrator sets it to ask for the company's address. It never lists the server's companies. |

A server reached by an IP address or `localhost` can still run several
companies: people give their company at sign-in. Only the per-company addresses
need a DNS name.

Rules that always hold:

- **One address belongs to one company.** A company cannot take an address
  another company uses.
- **A sign-in is refused at another company's address.** An e-mail and password
  from company A do not work on company B's address, even on the same server.
- **Certificates are issued only for addresses the server serves.** With the
  Caddy HTTPS example ([examples/vps-https](../examples/vps-https/README.md)),
  Caddy asks the installation before getting a certificate for a new name, so
  each company's address gets one by itself and a stranger's domain never does.
  Behind your own nginx you manage the certificates, for example one wildcard
  certificate ([examples/behind-nginx](../examples/behind-nginx/README.md)).

#### DNS for company addresses (from 1.2.0)

At your DNS provider, for a server address `erp.example.com` on `203.0.113.10`:

```text
erp.example.com.      A   203.0.113.10
*.erp.example.com.    A   203.0.113.10
```

A company's own domain needs its own record, made by whoever controls that
domain:

```text
acme.com.             A      203.0.113.10
hr.acme.com.          CNAME  erp.example.com.
```

On an office network without public DNS, add the same names to the office DNS
server. The wildcard lets every new company work without another DNS change.

**Cloudflare:** keep these records **DNS only** (grey cloud). A proxied record
ends the HTTPS connection at Cloudflare, with a certificate that does not cover
`acme.erp.example.com`, and the company's address stops working.

## How the licence is protected

- **Signed by Tarleaks.** Licence keys and every check-in answer carry a
  signature only tarleaks.com can make. The installation checks it with a key
  built into the software.
- **From 1.2.0, checked by every service.** Each app's service checks the licence
  and the company list on its own. A change to the gateway settings, the
  database or the environment does not give an unlicensed company access.
- **One licence, one installation.** A licence key is held by one installation
  at a time. Another installation with the same key is refused
  ([moving to new hardware](licensing.md#moving-to-new-hardware)).
- **From 1.2.0, one running copy.** A copy of the same installation (a cloned
  virtual machine, or a backup restored on a second server while the first still
  runs) is detected at its check-in. The copy whose `auth` service started most
  recently keeps the licence (a restart counts); the other is refused and locks
  when its offline allowance runs out. Stop the copy you do not use.
- **The clock.** A clock that is wrong or set back is refused (see
  [licensing.md](licensing.md#the-clock)).
- **From 1.2.0, seats are checked at sign-in.** When more people are active than
  a company's licence allows, only the administrators who manage users can sign
  in, so they can switch people off or buy more seats.
- **The licence terms** ([LICENSE.md](../LICENSE.md)) forbid reverse engineering,
  modifying the images and working around the licence check.

## See also

- [licensing.md](licensing.md): trials, keys, check-ins, seats, what is sent
- [apps.md](apps.md): which apps run, what each needs
- [setup-guide.md](setup-guide.md): installing, step by step
- [security.md](security.md): what the server exposes
