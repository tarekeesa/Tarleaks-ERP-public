# A server on the internet with HTTPS (Ubuntu + Caddy)

Use this to run the ERP on a cloud server (a VPS) with your own domain and a free,
automatically renewed HTTPS certificate. [Caddy](https://caddyserver.com) runs as
one more container next to the ERP.

```text
browser ──HTTPS 443──▶ Caddy (container) ──HTTP──▶ gateway:80 ──▶ ERP services
```

Time: about 30 minutes, most of it waiting for DNS and the first image download.

## Files in this folder

| File | What it is | Where it goes |
|---|---|---|
| [Caddyfile](Caddyfile) | Tells Caddy to serve your domain and pass everything to the ERP | Next to `docker-compose.yml` |
| [docker-compose.override.yml](docker-compose.override.yml) | Adds a `caddy` service (image `caddy:2.10-alpine`) on ports 80 and 443 | Next to `docker-compose.yml`, with this exact name |
| [address.env](address.env) | The four `.env` lines to change | Read it; step 5 applies it |

## What you need

- A VPS running **Ubuntu 24.04** (or 22.04) with a public IP address. Size it for
  the profile: 4 GB for `small`, 8 GB for `standard`, 16 GB for `full`
  ([requirements](../../docs/requirements.md)). Intel or ARM both work.
- A **domain name** you control, such as `erp.example.com`.
- Docker signed in to the registry (step 3).

## Steps

### 1. Point the domain at the server

At your DNS provider create an **A record**:

| Type | Name | Value |
|---|---|---|
| A | `erp` (for `erp.example.com`) | the server's public IPv4 address |

Add an `AAAA` record only if the server has working IPv6. Then wait until this
prints the server's address (from your own computer):

```bash
dig +short erp.example.com          # or: getent hosts erp.example.com
```

If your DNS provider has a "proxy" switch (orange cloud), turn it **off**: Caddy
must reach Let's Encrypt directly.

### 2. Open the firewall

On the server, over SSH. Allow SSH first so you do not lock yourself out:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw enable
```

If your provider has its own firewall or security group, open 22, 80 and 443
there too. Port 80 must be open: Let's Encrypt uses it to check the domain.

The ERP's gateway is bound to `127.0.0.1:8080` (step 5), so it is not reachable
from outside even though Docker is running it.

### 3. Install Docker and get the kit

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Log out and in again. There is no `docker login` step: the installer signs
Docker in to `registry.tarleaks.com` with your licence key
([requirements](../../docs/requirements.md#access-to-the-images)).

Get the kit:

```bash
sudo mkdir -p /opt/tarleaks-erp && sudo chown "$USER": /opt/tarleaks-erp
git clone https://github.com/tarekeesa/Tarleaks-ERP.git /opt/tarleaks-erp
cd /opt/tarleaks-erp
```

### 4. Write the settings, without starting

```bash
./install.sh --yes --host erp.example.com --port 8080 --no-start
```

This creates `.env` with generated passwords and keys. Use your own domain.

### 5. Switch the settings to HTTPS

The installer wrote `TARLEAKS_URL=http://erp.example.com:8080`. Change it, and make
the gateway listen on this machine only (the lines are in [address.env](address.env)):

```bash
sed -i 's|^TARLEAKS_URL=.*|TARLEAKS_URL=https://erp.example.com|' .env
sed -i 's|^HTTP_BIND=.*|HTTP_BIND=127.0.0.1|' .env
grep -E '^(TARLEAKS_HOST|TARLEAKS_URL|HTTP_PORT|HTTP_BIND)=' .env
```

You should see exactly:

```text
TARLEAKS_HOST=erp.example.com
TARLEAKS_URL=https://erp.example.com
HTTP_PORT=8080
HTTP_BIND=127.0.0.1
```

Do this before the setup screen if you can. If you add HTTPS later, change these
lines and run `./tarleaks restart` ([configuration](../../docs/configuration.md#decide-before-the-first-setup)).

### 6. Add Caddy

```bash
cp examples/vps-https/Caddyfile examples/vps-https/docker-compose.override.yml .
```

Nothing to edit: the Caddyfile reads your domain from `TARLEAKS_HOST`.

### 7. Start

```bash
./tarleaks start
```

The first start downloads the images, including Caddy, and prepares the database.
Allow up to 10 minutes. Caddy asks Let's Encrypt for a certificate as soon as the
domain answers; that takes under a minute. Watch it:

```bash
docker compose logs -f caddy
```

Look for `certificate obtained successfully`. Press Ctrl+C to stop following.

### 8. Set up the workspace

Open **https://erp.example.com**. The padlock should be valid. Then:

```bash
./tarleaks setup-code
```

Type the code, enter your company and the first administrator, and start the
30-day trial (or paste a licence key).

## Check it works

- `https://erp.example.com` opens with a valid certificate, and
  `http://erp.example.com` redirects to it.
- Sign in, upload a document in **Documents**, open it again.
- `./tarleaks doctor` reports no problems.
- From another computer, `nc -zv <server-ip> 8080 5432` fails: only 80 and 443 answer.

## Day two

| Task | How |
|---|---|
| Stop, start, logs | `./tarleaks stop`, `./tarleaks start`, `./tarleaks logs auth`. They include Caddy because of the override file. |
| Backups | [scheduled-backups](../scheduled-backups/README.md). Caddy's certificates are not in the backup; Caddy gets new ones. |
| Upgrade | `git fetch --tags && git checkout v<release>`, then `./tarleaks update` ([upgrading](../../docs/upgrading.md)) |
| Logs of Caddy | `docker compose logs caddy` |

## Things to know

- **Re-running the installer undoes step 5.** `./install.sh` and
  `./tarleaks profile …` rewrite `TARLEAKS_URL` as `http://…`. After either, run
  the first `sed` line of step 5 again, then `./tarleaks restart`.
- **Do not add `header_up Host`** to the Caddyfile. The file store checks the signed
  link against the Host header, and Caddy already passes it unchanged.
- **Red Hat, Rocky, Alma with SELinux:** change the Caddyfile mount in the override to
  `./Caddyfile:/etc/caddy/Caddyfile:ro,z`.
- Port 80 and 443 belong to Caddy now. Do not run another web server on this machine.
- `./tarleaks uninstall --purge` also deletes Caddy's volumes. They only hold
  certificates, and Caddy requests new ones.
- Let's Encrypt limits how many certificates one domain can get per week. Do not
  delete and recreate the `caddy_data` volume in a loop while testing.

## Problems

| Symptom | Fix |
|---|---|
| No certificate, `docker compose logs caddy` shows `challenge failed` | DNS does not point here yet, or port 80 is blocked (server firewall or provider). Fix it; Caddy retries by itself. |
| `502 Bad Gateway` from Caddy | The ERP is still starting, or stopped: `./tarleaks status` |
| Browser says the certificate is wrong | You opened the server's IP, not the domain |
| Uploads fail after switching to HTTPS later | Set `TARLEAKS_URL=https://…` in `.env` and run `./tarleaks restart` ([details](../../docs/configuration.md#decide-before-the-first-setup)). |

More: [troubleshooting](../../docs/troubleshooting.md).
