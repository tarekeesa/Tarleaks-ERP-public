# Behind your existing nginx

Use this when a server already runs nginx, or your company standard is nginx, and
you want it to terminate HTTPS for the ERP.

```text
browser ──HTTPS 443──▶ nginx ──HTTP──▶ 127.0.0.1:8080 (ERP gateway) ──▶ ERP services
```

Time: about 20 minutes. Profile: any.

## What you need

- A server with Docker, the kit and nginx. See [requirements](../../docs/requirements.md).
- A domain name (`erp.example.com`) whose DNS A record points at the server.
- Ports 80 and 443 open to the internet (for the certificate and for users).
- `certbot` for a free Let's Encrypt certificate, or a certificate you already have.

## Steps

### 1. Install the ERP, but do not start it yet

```bash
sudo mkdir -p /opt/tarleaks-erp && sudo chown "$USER": /opt/tarleaks-erp
git clone https://github.com/tarekeesa/Tarleaks-ERP.git /opt/tarleaks-erp
cd /opt/tarleaks-erp
./install.sh --yes --host erp.example.com --port 8080 --no-start
```

The installer downloads the images from `registry.tarleaks.com` with your
licence key (no `docker login`). See
[requirements](../../docs/requirements.md#access-to-the-images).

### 2. Point the settings at the proxy

The installer wrote `http://erp.example.com:8080` as the address. Replace it with
the public HTTPS address, and make the gateway listen on this machine only. The
four lines are in [address.env](address.env):

```bash
sed -i 's|^TARLEAKS_URL=.*|TARLEAKS_URL=https://erp.example.com|' .env
sed -i 's|^HTTP_BIND=.*|HTTP_BIND=127.0.0.1|' .env
grep -E '^(TARLEAKS_HOST|TARLEAKS_URL|HTTP_PORT|HTTP_BIND)=' .env
```

You should see:

```text
TARLEAKS_HOST=erp.example.com
TARLEAKS_URL=https://erp.example.com
HTTP_PORT=8080
HTTP_BIND=127.0.0.1
```

Do this **before** the setup screen. The ERP stores the address during setup.

### 3. Start the ERP

```bash
./tarleaks start
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/api/auth/installation   # prints 200
```

### 4. Get a certificate and add the server block

```bash
sudo certbot certonly --nginx -d erp.example.com
sudo cp examples/behind-nginx/erp.example.com.conf /etc/nginx/conf.d/erp.example.com.conf
sudo sed -i 's/erp\.example\.com/YOUR.DOMAIN/g' /etc/nginx/conf.d/erp.example.com.conf
sudo nginx -t && sudo systemctl reload nginx
```

Use your own domain instead of `YOUR.DOMAIN`. If you already have a certificate,
point `ssl_certificate` and `ssl_certificate_key` in the file at it instead.

### 5. Set up the workspace

Open `https://erp.example.com`. Setup code: `./tarleaks setup-code`.

## What the file does, and why

[erp.example.com.conf](erp.example.com.conf) has two blocks: port 80 redirects to
HTTPS, and port 443 proxies to the gateway.

| Setting | Why it matters |
|---|---|
| `proxy_set_header Host $http_host;` | The **Host header must reach the ERP unchanged.** Signed upload and download links are checked against it. If nginx rewrites it, uploads fail with `SignatureDoesNotMatch`. `$http_host` keeps a port if there is one. |
| `client_max_body_size 100m;` | nginx refuses larger bodies with `413`. Raise it if people upload bigger files. |
| `location = /api/chat/ws` with `Upgrade` and `Connection` | Live chat uses a WebSocket. Without the upgrade headers it never connects. |
| `proxy_*_timeout 300s;` | Long requests (reports, exports, big uploads) are not cut off at nginx's 60-second default. The gateway itself allows 300 seconds. |
| `proxy_pass` without a path | Every path is forwarded as it is, including `/<bucket>/…` for files. Do not limit the proxy to `/api/`. |
| `X-Forwarded-*` | Pass the client address and scheme on. |

A `location` that sets any `proxy_set_header` loses the ones from the `server`
block, which is why the chat block repeats all of them.

## Check it works

1. `https://erp.example.com` shows the sign-in or setup page, with a valid
   certificate.
2. Sign in, upload a document in **Documents**, and open it again.
3. Open the chat. It should connect.
4. `./tarleaks doctor` reports no problems.

## If something is wrong

| Symptom | Fix |
|---|---|
| `502 Bad Gateway` from nginx | The ERP is not running or not on `127.0.0.1:8080`. `./tarleaks status`, `curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/api/auth/installation`. |
| `413 Request Entity Too Large` | Raise `client_max_body_size` |
| Uploads fail, `403 SignatureDoesNotMatch` | The Host header was changed. Keep `proxy_set_header Host $http_host;` and do not add `proxy_set_header Host $proxy_host;`. Check `TARLEAKS_URL` equals the address in the browser. |
| Chat does not connect | The `location = /api/chat/ws` block is missing or the `map` is not at the `http` level |
| Chat drops when idle | Raise `proxy_read_timeout` in the chat block |
| SELinux denies `proxy_pass` (Red Hat family) | `sudo setsebool -P httpd_can_network_connect 1` |
| Certificate errors | `sudo certbot certificates`, and check DNS and port 80 |

More: [troubleshooting](../../docs/troubleshooting.md).

## Notes

- Re-running `./install.sh` with another `--host` rewrites `TARLEAKS_URL` to
  `http://…`. Run the `sed` line from step 2 again afterwards, then
  `./tarleaks restart`.
- Optional hardening: add `add_header Strict-Transport-Security "max-age=31536000" always;`
  once you are sure HTTPS works for good.
- No Docker Compose override is needed for this setup. The ERP's own port is
  bound to `127.0.0.1`, so only nginx can reach it.
