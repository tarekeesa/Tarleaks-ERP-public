# Put your installation on your own domain with HTTPS

This page takes an installation from `http://192.168.1.20` (or `localhost`) to
`https://erp.example.com`, with a free certificate that renews by itself.
Arabic summary at the end ([ملخص بالعربية](#ملخص-بالعربية)).

Pick the way that fits your network:

| Your situation | Use | Section |
|---|---|---|
| A server on the internet (a VPS, or an office server with a public IP), ports 80 and 443 free | The kit's gateway gets the certificate itself (Let's Encrypt, HTTP-01) | [A](#a-the-gateway-gets-the-certificate-http-01) |
| Your DNS is at Cloudflare, you want `*.erp.example.com` for companies, or port 80 cannot be opened | The gateway gets it through Cloudflare DNS (DNS-01) | [B](#b-through-cloudflare-dns-dns-01-wildcard) |
| nginx, Caddy, Traefik or a load balancer already runs on that machine or in front of it | Your proxy holds the certificate, the ERP stays on plain http behind it | [C](#c-behind-a-reverse-proxy-you-already-run) |
| The server is at home or in an office behind a router (NAT) | A or B, plus port forwarding | [D](#d-behind-a-home-or-office-router-nat) |

Whichever you use, the installation must know it is in **production**: one
setting, `TARLEAKS_PROFILE_ENV=production`, makes it serve HTTPS only and makes
`./tarleaks doctor` refuse a mix-up (an `http://` address, an IP instead of a
name, a missing e-mail address). Everything else here is set by the installer.

## 1. Before you start (every way)

### DNS records

At the company that holds your domain (your registrar, or Cloudflare), create
records pointing the name at the server's **public** address:

| Type | Name | Value | When |
|---|---|---|---|
| `A` | `erp` (for `erp.example.com`) | the server's public IPv4, e.g. `203.0.113.10` | always |
| `AAAA` | `erp` | the server's public IPv6 | only if the server really answers on IPv6 |
| `A` | `*.erp` | the same IPv4 | from 1.2.0, for company addresses `acme.erp.example.com` ([companies-and-domains.md](companies-and-domains.md#dns-for-company-addresses-from-120)) |

Check from **another** computer (not the server) that the name answers:

```bash
dig +short erp.example.com        # must print 203.0.113.10
dig +short AAAA erp.example.com   # empty, or an address the server really has
```

An `AAAA` record for an address the server does not answer on is the most
common reason Let's Encrypt fails while "everything looks right": it prefers
IPv6. Remove the record, or make IPv6 work.

### Firewall

| Port | Who must reach it | Why |
|---|---|---|
| 443/tcp | everyone who uses the ERP | HTTPS |
| 80/tcp | the internet, for way A | Let's Encrypt checks the name over port 80; afterwards it only redirects to HTTPS |
| 22/tcp | you only | SSH. Limit it to your own address |

Ubuntu (`ufw`):

```bash
sudo ufw allow 22/tcp            # first, or you lock yourself out
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

A cloud server usually has a second firewall in its provider's console
("security group", "firewall rules"): open the same ports there.

Docker publishes its ports past `ufw` on Linux. The kit publishes only the
gateway's ports, so this changes nothing for the ERP, but do not publish other
containers' ports on that machine.

### Cloudflare: proxied (orange cloud) or DNS only (grey cloud)?

| | DNS only (grey) | Proxied (orange) |
|---|---|---|
| Who sees the traffic | your server only | Cloudflare ends HTTPS, then connects to your server |
| Way A (HTTP-01) | works | works only while Cloudflare's SSL mode is **Full (strict)**, and the first certificate is easier to get with grey; switch to orange after |
| Way B (DNS-01) | works | works |
| Company addresses `*.erp.example.com` | work | **break**: Cloudflare's free certificate covers one level (`*.example.com`), not `acme.erp.example.com` |
| Uploads over 100 MB | work | refused by Cloudflare's free plan |

Use **DNS only** unless you have a reason not to. If you proxy, set SSL/TLS to
**Full (strict)** (never "Flexible": it sends your passwords to the server
unencrypted and makes a redirect loop with the ERP's own HTTPS).

## A. The gateway gets the certificate (HTTP-01)

For one name (`erp.example.com`) on a server the internet can reach on ports 80
and 443.

```bash
cd Tarleaks-ERP
./install.sh --profile-env production --host erp.example.com \
  --tls letsencrypt --acme-email it@example.com
```

What it does:

- writes `TARLEAKS_PROFILE_ENV=production`, `TARLEAKS_TLS=letsencrypt`,
  `TARLEAKS_URL=https://erp.example.com`, `ACME_EMAIL` to `.env`;
- adds `config/https/compose.https-letsencrypt.yml` to `COMPOSE_FILE`, which
  makes the gateway listen on 80 and 443, ask Let's Encrypt for a certificate,
  send every `http://` visitor to `https://`, and send `Strict-Transport-Security`
  (browsers then use HTTPS for this name for a year);
- keeps the certificate in the `certs` Docker volume (back it up with the rest:
  `./tarleaks backup`).

The first certificate arrives within a minute of the start. Check:

```bash
./tarleaks doctor                      # "Profile production, HTTPS by letsencrypt"
curl -sI https://erp.example.com | head -1
curl -sI http://erp.example.com  | grep -i location   # → https://erp.example.com/
```

An existing installation on `http://` moves the same way: run the command
above in the kit folder. Keys, data and companies are kept; the address in
links sent before (old e-mails, share links) keeps the old `http://` address.

HTTP-01 cannot issue a wildcard. From 1.2.0, company addresses
(`acme.erp.example.com`) need way B, or way C with your own wildcard
certificate.

## B. Through Cloudflare DNS (DNS-01, wildcard)

For a domain whose DNS is at Cloudflare. Port 80 is not needed for the
certificate (it still redirects to HTTPS), and the certificate covers
`erp.example.com` **and** `*.erp.example.com`.

1. In Cloudflare: **My Profile → API Tokens → Create Token → Edit zone DNS**.
   Zone resources: *Include → Specific zone → example.com*. Copy the token (it
   starts with `cfut_` on new accounts; older tokens work too).
2. Install, giving the token through the environment (never on the command
   line, where other users of the machine can read it):

   ```bash
   read -rs CF_DNS_API_TOKEN && export CF_DNS_API_TOKEN   # paste, Enter
   ./install.sh --profile-env production --host erp.example.com \
     --tls cloudflare --acme-email it@example.com
   unset CF_DNS_API_TOKEN
   ```

   The token is written to `.env` (readable by its owner only). Run the
   installer interactively instead and it asks for it without showing it.

The gateway creates a `_acme-challenge` TXT record, waits for Cloudflare to
publish it, and removes it after. The first certificate takes one to three
minutes. Other DNS providers: Traefik supports most of them under the same
scheme ([list](https://doc.traefik.io/traefik/https/acme/#providers)); copy
`config/https/compose.https-cloudflare.yml` to `docker-compose.override.yml`
territory only with care, as the next kit update replaces the original.

## C. Behind a reverse proxy you already run

Your proxy terminates HTTPS and passes requests to the ERP's gateway on plain
http. The ERP then listens on this machine only.

```bash
./install.sh --profile-env production --host erp.example.com --tls proxy --port 8080
```

This writes `TARLEAKS_TLS=proxy`, `TARLEAKS_URL=https://erp.example.com`,
`HTTP_BIND=127.0.0.1`, `HTTP_PORT=8080`. Point the proxy at
`http://127.0.0.1:8080` and make it:

- pass the original `Host` header (the ERP signs file links for it);
- pass `X-Forwarded-Proto: https`;
- allow uploads of at least 200 MB and requests of 300 seconds;
- pass WebSocket upgrades (chat, the document editor).

nginx (complete file: [examples/behind-nginx](../examples/behind-nginx/README.md)):

```nginx
server {
  listen 443 ssl;
  http2 on;
  server_name erp.example.com;
  ssl_certificate     /etc/letsencrypt/live/erp.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/erp.example.com/privkey.pem;
  client_max_body_size 200m;
  proxy_read_timeout 300s;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;   # map in http {}: see the example
  }
}
```

Caddy (it gets and renews the certificate itself; complete example with
per-company certificates: [examples/vps-https](../examples/vps-https/README.md)):

```text
erp.example.com {
  reverse_proxy 127.0.0.1:8080
}
```

Traefik you already run (file provider):

```yaml
http:
  routers:
    tarleaks:
      rule: Host(`erp.example.com`) || HostRegexp(`^[a-z0-9-]+\.erp\.example\.com$`)
      entryPoints: [websecure]
      tls: { certResolver: le }
      service: tarleaks
  services:
    tarleaks:
      loadBalancer:
        passHostHeader: true
        servers: [{ url: "http://127.0.0.1:8080" }]
```

A proxy on **another** machine: use `--bind office` and allow port 8080 only
from the proxy's address in the firewall.

## D. Behind a home or office router (NAT)

1. Give the server a fixed address on your network (a DHCP reservation in the
   router, for example `192.168.1.20`).
2. In the router, forward **TCP 80 → 192.168.1.20:80** and
   **TCP 443 → 192.168.1.20:443** ("port forwarding", "virtual server",
   "NAT rules").
3. Find your public address: `curl -4 https://ifconfig.me` from the server.
   Use it in the `A` record. If it changes (most home connections), use your
   router's dynamic DNS, or Cloudflare with a small updater, so the record
   follows it.
4. Then way A, or way B if your provider blocks port 80 (several do on home
   lines).

Two traps:

- **CGNAT.** If the router's own "WAN address" is not the address
  `ifconfig.me` shows (often `100.64.x.x`), your provider shares one public
  address among many customers and no port forwarding can work. Ask the
  provider for a public IPv4, or use way B with a tunnel (for example
  Cloudflare Tunnel) and way C.
- **Opening it from inside the office.** Some routers cannot send
  `erp.example.com` back into the same network ("hairpin NAT"). If it works
  from a phone on mobile data but not from the office, add the name to the
  office DNS (or each PC's hosts file) pointing at `192.168.1.20`.

## Renewing

Nothing to do. Certificates last 90 days; the gateway renews each one 30 days
before it ends and keeps working on the old one meanwhile. Let's Encrypt
e-mails `ACME_EMAIL` only if renewing keeps failing. To see the current
certificate:

```bash
echo | openssl s_client -connect erp.example.com:443 -servername erp.example.com 2>/dev/null \
  | openssl x509 -noout -issuer -dates
```

## Going back to local

```bash
./install.sh --profile-env local --host 192.168.1.20
```

Browsers that visited the HTTPS address remember it for a year (HSTS) and
refuse `http://erp.example.com`; use the IP address, or another name.

## Troubleshooting

| What you see | Why | Fix |
|---|---|---|
| `doctor`: "The production profile needs a domain name" | `TARLEAKS_HOST` is an IP or `localhost` | Use the DNS name: `./install.sh --profile-env production --host erp.example.com …` |
| `doctor`: "serves HTTPS only, but TARLEAKS_URL is http://…" | an older `.env`, or edited by hand | run the installer command of your way again |
| `doctor`: "proves the name over port 80, but HTTP_PORT is 8080" | port 80 taken | free it, or use way B or C |
| Browser: `NET::ERR_CERT_AUTHORITY_INVALID`, certificate "TRAEFIK DEFAULT CERT" | the certificate was not issued (yet) | wait a minute; then `./tarleaks logs gateway` and read the `acme` lines |
| gateway log: `Timeout during connect (likely firewall problem)` | Let's Encrypt cannot reach port 80 | open 80/tcp in `ufw`, the provider's firewall and the router; check from outside: `curl -I http://erp.example.com` |
| gateway log: `DNS problem: NXDOMAIN` | the name has no record yet, or it has not spread | check `dig +short erp.example.com` from outside; wait for the TTL |
| gateway log: mentions an IPv6 address | a wrong `AAAA` record | remove it (above) |
| gateway log: `too many certificates already issued` | five certificates for the same name in a week (reinstalls) | wait for the week to pass; keep the `certs` volume when you reinstall |
| gateway log: Cloudflare `Invalid request headers` / `7003` | the token is wrong, or not for this zone | make a new token with *Zone, DNS, Edit* on exactly this domain |
| Too many redirects | Cloudflare proxied with SSL mode "Flexible" | set SSL/TLS to **Full (strict)** |
| `ERR_SSL_PROTOCOL_ERROR` on a company address | Cloudflare proxied record for `acme.erp.example.com` | make the record **DNS only** |
| Uploads fail, pages load | proxy (way C) does not pass `Host`, or limits the body size | `proxy_set_header Host $host;`, `client_max_body_size 200m;` |
| Editor opens a blank page | proxy (way C) drops WebSocket upgrades | add the `Upgrade` / `Connection` headers |
| Works from outside, not from the office | hairpin NAT | office DNS entry (section D) |

## Test it with a local CA

To try all of this without a real domain, run a private ACME server instead
of Let's Encrypt:
[Pebble](https://github.com/letsencrypt/pebble), the test server Let's Encrypt
publishes. Point the gateway at it with two settings in `.env`, and trust
Pebble's root in the browser you test with:

```text
ACME_CA_SERVER=https://pebble:14000/dir
ACME_CA_CERTIFICATES=/certs/pebble.minica.pem
```

Pebble must resolve your test name to the gateway: run Pebble's companion
DNS server (`pebble-challtestsrv -defaultIPv4 <the gateway's address>`) and
start Pebble with `-dnsserver challtestsrv:8053`; copy Pebble's
`test/certs/pebble.minica.pem` into the `certs` volume before the gateway
starts. What this proved on 2026-10-18 (kit `config/https/compose.https-letsencrypt.yml`,
Traefik v3.7.14, Pebble as the CA): Pebble validated
`http://erp.tlhttps.test:80/.well-known/acme-challenge/…` through the gateway
(the redirect to HTTPS does not get in the way of the challenge), issued the
certificate, the gateway served it on 443 (`Verify return code: 0` against
Pebble's root) with `strict-transport-security: max-age=31536000`, and
`http://` answered `308` to `https://` without HSTS.

Remove both lines for the real certificate. A certificate from a local CA is
never trusted by your users' browsers; it only proves the setup works.

---

## ملخص بالعربية

**لتشغيل النظام على نطاقك الخاص عبر HTTPS:**

1. **سجلات DNS:** أنشئ سجل `A` باسم `erp` يشير إلى عنوان IP العام للخادم (وسجل `AAAA` فقط إذا كان الخادم يعمل فعلاً على IPv6). لعناوين الشركات (من الإصدار 1.2.0) أضف سجل `A` باسم `*.erp`.
2. **الجدار الناري:** افتح المنفذين 80 و443 (TCP)، وقيّد المنفذ 22 على عنوانك فقط. افتحها أيضاً في جدار مزوّد الخدمة السحابية إن وجد.
3. **اختر الطريقة:**
   - **(أ) شهادة Let's Encrypt عبر المنفذ 80:**
     `./install.sh --profile-env production --host erp.example.com --tls letsencrypt --acme-email it@example.com`
   - **(ب) عبر Cloudflare DNS** (تشمل `*.erp.example.com` ولا تحتاج المنفذ 80): أنشئ رمز API بصلاحية *Zone → DNS → Edit*، ثم مرّره عبر متغير البيئة `CF_DNS_API_TOKEN` (وليس في سطر الأوامر) واستخدم `--tls cloudflare`.
   - **(ج) خلف خادم وسيط موجود** (nginx أو Caddy أو Traefik): `--tls proxy --port 8080`، ووجّه الوسيط إلى `http://127.0.0.1:8080` مع تمرير ترويسة `Host` و`X-Forwarded-Proto: https` ودعم WebSocket وحجم رفع 200 ميغابايت.
   - **(د) خلف راوتر منزلي أو مكتبي:** ثبّت عنوان الخادم الداخلي، ووجّه المنفذين 80 و443 إليه. إن كان عنوان WAN في الراوتر مختلفاً عن عنوانك العام (CGNAT) فلن ينجح توجيه المنافذ؛ اطلب IP عاماً من المزوّد.
4. **Cloudflare:** اجعل السجلات **DNS only** (السحابة الرمادية). إذا استخدمت الوكيل (البرتقالية) فاضبط SSL على **Full (strict)** وليس Flexible، ولن تعمل عناوين الشركات الفرعية.
5. **التجديد تلقائي:** الشهادة صالحة 90 يوماً وتُجدَّد قبل انتهائها بـ30 يوماً.
6. **التحقق:** `./tarleaks doctor` يرفض أي خلط (عنوان `http://` أو IP بدل اسم نطاق في ملف الإنتاج).

**الأخطاء الشائعة:** شهادة "TRAEFIK DEFAULT CERT" تعني أن الشهادة لم تصدر بعد — راجع `./tarleaks logs gateway`. خطأ "Timeout during connect" يعني أن المنفذ 80 مغلق. "Too many redirects" يعني أن Cloudflare على وضع Flexible.
