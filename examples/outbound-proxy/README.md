# Behind a company proxy (outbound)

Use this when the server reaches the internet only through a proxy. Without it
the licence check-in to `tarleaks.com` fails, and after 30 hours the ERP stops
serving with `ENTITLEMENT_OFFLINE_TOO_LONG`.

Two things need the proxy: **Docker**, to download the images, and **the ERP's
sign-in service**, which does the check-in.

## 1. Docker downloads through the proxy

Linux (systemd):

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/proxy.conf >/dev/null <<'CONF'
[Service]
Environment="HTTPS_PROXY=http://proxy.example.local:3128"
Environment="HTTP_PROXY=http://proxy.example.local:3128"
Environment="NO_PROXY=localhost,127.0.0.1"
CONF
sudo systemctl daemon-reload && sudo systemctl restart docker
```

Docker Desktop (Mac, Windows): **Settings → Resources → Proxies**.

**Check:** `docker pull hello-world` works.

## 2. The check-in goes through the proxy

```bash
cp examples/outbound-proxy/docker-compose.override.yml .
echo 'OUTBOUND_PROXY=http://proxy.example.local:3128' >> .env
./tarleaks restart
```

A proxy that needs a password: `OUTBOUND_PROXY=http://user:password@proxy.example.local:3128`
(the password sits in `.env`, which only root can read).

**Check:**

```bash
docker compose exec -T auth sh -c 'curl -fsS -o /dev/null --max-time 15 https://tarleaks.com/api/activation/public-key && echo reachable'
```

Then Settings → Licence → **Check now** shows a fresh "last check-in".

## The proxy must not open HTTPS to tarleaks.com

Some proxies decrypt HTTPS and re-sign it with the company's own certificate. The
ERP refuses that for `tarleaks.com`: it accepts only Tarleaks's real certificate,
and every licence answer is signed by Tarleaks as well, so a substituted answer
is rejected either way. Ask your network team to exempt `tarleaks.com` from
inspection (most proxies call this a "bypass" or "do not decrypt" list).

Symptoms when it is not exempt: `./tarleaks logs auth` shows a certificate or
"invalid peer certificate" error on the check-in, and the licence page's "last
error" names `tarleaks.com`.

## Only the sign-in service

This override gives the proxy to `auth`, the one service that talks to
`tarleaks.com`. If you also configure an e-mail or AI provider reached over HTTPS
from another service and it needs the proxy, add that service under
`services:` the same way (`environment: *proxy`).
