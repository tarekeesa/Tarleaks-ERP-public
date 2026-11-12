# Configuration

Everything you can set lives in one file: **`.env`**, next to `docker-compose.yml`.

- The installer (`./install.sh` or `.\install.ps1`) creates it from
  [`.env.example`](../.env.example) and fills in the generated passwords and keys.
  You normally never edit it by hand.
- After you edit it, apply the change with `./tarleaks restart`
  (Windows: `.\tarleaks.ps1 restart`).
- `.env` is private. It is excluded from Git. Back it up with your data:
  the database cannot be read without the keys in it
  ([backup-restore.md](backup-restore.md)).
- Write `KEY=value` with no spaces around `=` and no quotes. If a value contains
  a `$` (an S3 secret key can), write it as `$$`.
- To add your own Docker settings, create a file called
  `docker-compose.override.yml` next to `docker-compose.yml`. Docker Compose
  reads it automatically. Never edit `docker-compose.yml`: it is replaced when you
  update the kit.

Contents: [Version](#version) · [Address](#address) · [Apps](#apps) ·
[Licence](#licence) · [File storage](#file-storage) ·
[Database and message queue](#database-and-message-queue) · [Keys](#keys) ·
[AI features](#ai-features-optional) · [Outbound proxy](#outbound-proxy) ·
[E-invoicing time server](#e-invoicing-time-server) ·
[Editors](#editors) · [Calls](#calls-livekit) ·
[Other](#other) · [Container security](#container-security) ·
[Advanced](#advanced-settings-not-in-envexample)

## Version

| Variable | Default | What it does |
|---|---|---|
| `COMPOSE_PROJECT_NAME` | `tarleaks` (written by the installer) | The installation's name in Docker: its containers and data volumes carry it, and a backup's copy of `.env` says whose data it holds (a restore refuses another installation's backup unless `--keep-settings`). Choose another one only for a second, separate installation on the same machine: `COMPOSE_PROJECT_NAME=erp2 ./install.sh --port 8080`. Never change it afterwards, or `./tarleaks` no longer finds the installation's data. An `.env` from an older installer without the line means `tarleaks`. |
| `TARLEAKS_VERSION` | `1.2.0-rc.2` | The release to run. Compose refuses to start without it. `./tarleaks update` changes it for you. Images exist only under exact version numbers: there is no `latest`. |
| `TARLEAKS_REGISTRY` | `registry.tarleaks.com/tarleaks-erp` | Where the images are pulled from. Leave as it is: the installer and `./tarleaks` sign Docker in with the licence key ([requirements.md](requirements.md#access-to-the-images)). Your own mirror: its address here, and sign Docker in to it yourself. |
| `TARLEAKS_MIGRATE_IMAGE` | set by `./tarleaks` from the version | The database-update image: `nexus-migrate` up to 1.1.x, `tarleaks-migrate` from 1.2.0. Set it only for your own mirror with another name. |
| `TARLEAKS_DOWNLOAD_KEY` | empty | Written by `./install.sh --trial`: the trial it started, used only to download until the installation holds its licence. |

<a id="profile"></a>
## Profile: local or production

One setting says what kind of installation this is, so that a test machine's
settings can never end up on a production server, or the other way round.
`./install.sh --profile-env local|production` writes it (or asks); the
installer and `./tarleaks doctor` refuse settings that do not fit it.

| Variable | Default | What it does |
|---|---|---|
| `TARLEAKS_PROFILE_ENV` | `local` | `local`: this computer or the office network, `http://` is fine. `production`: a real domain, HTTPS only, browsers told to stay on HTTPS (HSTS). |
| `TARLEAKS_TLS` | empty | Production only. `letsencrypt`: the gateway gets a free certificate over port 80. `cloudflare`: the same through Cloudflare DNS (wildcard, no port 80 needed). `proxy`: your own reverse proxy holds it. [https.md](https.md) |
| `ACME_EMAIL` | empty | Where Let's Encrypt writes before a certificate ends (`letsencrypt`, `cloudflare`). |
| `CF_DNS_API_TOKEN` | empty | Cloudflare API token with Zone, DNS, Edit (`cloudflare`). Secret: never put it on a command line. |
| `COMPOSE_FILE` | written by the kit | The extra compose files these settings need (HTTPS, sealed offline mode). Written on every `./tarleaks start` / `restart`; do not edit it. A `docker-compose.override.yml` of yours is kept in it. |

What is refused (`✗` in `doctor`, and `./install.sh` stops before starting):

| Profile | Refused |
|---|---|
| both | `TARLEAKS_URL` and `TARLEAKS_HOST` naming different machines; a browser address (`TARLEAKS_STORAGE_PRESIGN_ENDPOINT`, `ONLYOFFICE_PUBLIC_URL`, `DRAWIO_URL`) on `localhost` while people use another address, or `http://` inside an `https://` ERP |
| `production` | an `http://` address; an IP address or `localhost` instead of a domain; no `TARLEAKS_TLS`; `letsencrypt` on a port other than 80 or bound to `127.0.0.1`; `letsencrypt`/`cloudflare` without `ACME_EMAIL`; `cloudflare` without a token |
| `local` | `TARLEAKS_TLS=letsencrypt` or `cloudflare` (they need a real domain: use `production`) |

The services check the same addresses when they start and write any mix-up to
their log (`./tarleaks logs auth documents hr`, lines with `public address:`).

## Address

The address is the one thing to get right **before** you run the setup screen.
See [File storage](#file-storage) for why.

| Variable | Default | What it does |
|---|---|---|
| `TARLEAKS_HOST` | `localhost` | The name or IP address people type, **without** `http://` and without a port. |
| `TARLEAKS_URL` | `http://localhost` | The full address, including the port when it is not 80 or 443. Used in the links the ERP creates (share links, e-mails) and to sign browser uploads. It must match exactly what people see in the browser's address bar. |
| `HTTP_PORT` | `80` | The port the gateway listens on, on this machine. |
| `HTTP_BIND` | chosen by the installer | Which network interface it listens on. `0.0.0.0` means all (this computer and the network). `127.0.0.1` means this machine only (a laptop, or behind a reverse proxy). A LAN address such as `192.168.1.20` means only that interface; `./tarleaks status` and `doctor` then check that address. The installer looks at the machine, proposes one and says why (a laptop or desktop: only this computer; a server: the network); `--bind local` / `--bind office` overrides it, and `./tarleaks network local|office` changes it later ([network.md](network.md#who-can-open-it)). |

Typical sets:

| Situation | `TARLEAKS_HOST` | `TARLEAKS_URL` | `HTTP_PORT` | `HTTP_BIND` |
|---|---|---|---|---|
| This computer only | `localhost` | `http://localhost` | `80` | `127.0.0.1` |
| Port 80 is taken | `localhost` | `http://localhost:8080` | `8080` | `127.0.0.1` |
| Office network | `192.168.1.20` | `http://192.168.1.20` | `80` | `0.0.0.0` |
| Internet, HTTPS by the gateway (`production`, [https.md](https.md)) | `erp.example.com` | `https://erp.example.com` | `80` (and 443) | `0.0.0.0` |
| Internet, your own proxy in front (`production`, `TARLEAKS_TLS=proxy`) | `erp.example.com` | `https://erp.example.com` | `8080` | `127.0.0.1` |

Rules:

- Open the ERP at **exactly** `TARLEAKS_URL`. `http://localhost` and
  `http://127.0.0.1` are different addresses to a browser.
- The installer writes `TARLEAKS_URL` as `http://<host>` or `http://<host>:<port>`.
  For HTTPS behind a proxy, change it to `https://…` yourself
  ([examples/vps-https](../examples/vps-https/README.md)).
- Re-running the installer keeps an `https://` `TARLEAKS_URL` as long as the
  host stays the same. Given another host, it writes `http://<new host>`: on an
  HTTPS setup put the `https://` address back, then `./tarleaks restart`.
  `./tarleaks apps` and `./tarleaks profile` never touch it.
- The address can be changed later: edit `TARLEAKS_HOST` and `TARLEAKS_URL` (or
  run the installer again with `--host`), then `./tarleaks restart`. Links
  already sent out (e-mails, share links) keep the old address.
- Keep the address stable. Use a fixed IP or a DNS name
  ([examples/office-server](../examples/office-server/README.md)).
- **From 1.2.0** this address is the server address. With a DNS name, each
  company also gets `<company>.<server address>` (it needs a wildcard DNS
  record), and the server administrator can attach a company's own domain. On an
  IP address or `localhost`, several companies still work: people give their
  company when they sign in:
  [companies-and-domains.md](companies-and-domains.md#addresses).

## Apps

| Variable | Default | What it does |
|---|---|---|
| `TARLEAKS_APPS` | set by the installer | The apps you chose, as licence names (`hr,crm`). The only one of the three you may edit by hand; `./tarleaks start` recomputes the other two from it. |
| `COMPOSE_PROFILES` | computed | The services to start: one per app that runs (the chosen apps and what they need). Infrastructure, sign-in and the base apps always run. |
| `TARLEAKS_AVAILABLE_MODULES` | computed | The apps this installation runs. The licence is cut down to these, so no tile points at an app that is not started. |

Change the apps with `./tarleaks apps add …` / `remove …` or a preset with
`./tarleaks profile small|standard|full` (Windows: `.\tarleaks.ps1 …`). Keys,
passwords and data are kept. What each app needs: [apps.md](apps.md).

## Licence

| Variable | Default | What it does |
|---|---|---|
| `TARLEAKS_SETUP_CODE` | generated, like `K7QF-2M9D-XR4P` | You type it once on the setup screen. It is also needed to replace the licence key. Keep it private. Show it again: `./tarleaks setup-code`. |
| `TARLEAKS_LICENSE_KEY` | empty | Optional licence key (`tlk1.…`; keys issued earlier start `nxs1.` and work the same). Leave empty to start the 30-day trial on the setup screen. While it is set, the screen refuses a different key (change it here and restart). See [licensing.md](licensing.md). |

## File storage

<a id="file-storage"></a>

Documents, attachments and exports go to an S3-compatible file store.

- **By default** that is a store bundled with the ERP (`versitygw`). The files
  sit in the Docker volume `files` on your machine. You do not have to do
  anything.
- **Or you can use** AWS S3, Cloudflare R2, Wasabi, or a NAS gateway, by setting
  a few lines in `.env` **before the first setup**.

### How a file moves

When someone uploads a document, the browser asks the ERP for a **signed link**
and then sends the file **straight to the file store** with that link.
Downloads work the same way. So there are two routes to the store:

```text
ERP server ──────────────────────────▶ store   TARLEAKS_STORAGE_ENDPOINT
Browser    ──signed link──────────────▶ store   TARLEAKS_STORAGE_PRESIGN_ENDPOINT
```

| Variable | Default | What it is |
|---|---|---|
| `TARLEAKS_STORAGE_PROVIDER` | `nas_versitygw` | The kind of store. See the table below. |
| `TARLEAKS_STORAGE_ENDPOINT` | `http://objects:7070` | Where the ERP's own services reach the store (inside Docker, or your S3 address). |
| `TARLEAKS_STORAGE_PRESIGN_ENDPOINT` | the value of `TARLEAKS_URL` | The address **browsers** use to reach the store. With the bundled store it is the ERP's own address, because the gateway passes `/<bucket>/` through. With a remote S3 it is the S3 address. |
| `STORAGE_BUCKET` | `tarleaks-files` | The bucket name. |
| `STORAGE_ACCESS_KEY` | generated | The access key. |
| `STORAGE_SECRET_KEY` | generated | The secret key. |
| `STORAGE_REGION` | `us-east-1` | The region. R2 wants `auto`. AWS and Wasabi want the bucket's real region. |

`TARLEAKS_STORAGE_PROVIDER` values you will use:

| Value | Store |
|---|---|
| `nas_versitygw` | The bundled store, or your own versitygw on a NAS |
| `s3` | AWS S3 |
| `r2` | Cloudflare R2 |
| `wasabi` | Wasabi |
| `custom` | Any other S3-compatible service that has an address (also `minio`, `spaces`) |

Two things to know:

- `STORAGE_ACCESS_KEY` and `STORAGE_SECRET_KEY` are the credentials for
  **whatever store you use**. The bundled store reads the same two values as its
  own login, but when you use S3 it sits idle.
- With a remote store, set **all three** `TARLEAKS_STORAGE_*` lines together. If you
  leave `TARLEAKS_STORAGE_PRESIGN_ENDPOINT` out, it falls back to your ERP address and
  browser uploads fail.

### Decide before the first setup

The setup screen copies these values into the workspace's storage settings
**once**, when you press **Create workspace**. Afterwards the workspace does not
follow `.env`: change the bucket, keys and region in **Settings, Document
management, Storage**. Do not change `STORAGE_ACCESS_KEY` or `STORAGE_SECRET_KEY`
in `.env` on their own: the bundled store would stop accepting the keys the
workspace saved.

> **The upload address follows `.env`.** While the workspace uses the bundled
> store, browsers upload and download through `TARLEAKS_STORAGE_PRESIGN_ENDPOINT`
> (your ERP address unless you set it). The ERP reads it on every start, so you
> can change the address later (a new IP, a domain, `http` to `https`): update
> `TARLEAKS_HOST` and `TARLEAKS_URL` in `.env` and run `./tarleaks restart`.
> After switching the workspace to another storage service in Settings, that
> service's own address is used.

Files you already uploaded stay where they are when you switch storage; only new
uploads go to the new place.

### Option 1: the bundled store (default)

Nothing to configure. Files are in the Docker volume `files` and are included in
`./tarleaks backup`.

**From 1.2.0** the app names it: **Settings, Document management, Storage**
shows **This server (built-in storage)**, already selected and working. A company
that wants its files elsewhere chooses **Use S3, R2, Wasabi or a NAS instead**
there.

Browsers reach it at `<your address>/<STORAGE_BUCKET>/`. If you put a reverse
proxy in front, it must pass that path through to the gateway, keep the `Host`
header unchanged, and allow large bodies
([examples/behind-nginx](../examples/behind-nginx/README.md)).

### Option 2: AWS S3

1. Create a bucket. Keep **Block all public access** on.
2. Create an IAM user for the ERP with access to that bucket only, and an access
   key for it. A starting policy is in
   [examples/s3-storage/aws-iam-policy.json](../examples/s3-storage/aws-iam-policy.json).
3. Add the [CORS rule](#cors-rule-for-a-remote-bucket) to the bucket.
4. Put this in `.env` before the first setup (change the names, region and keys):

   ```ini
   TARLEAKS_STORAGE_PROVIDER=s3
   TARLEAKS_STORAGE_ENDPOINT=https://s3.eu-central-1.amazonaws.com
   TARLEAKS_STORAGE_PRESIGN_ENDPOINT=https://s3.eu-central-1.amazonaws.com
   STORAGE_BUCKET=my-company-erp-files
   STORAGE_ACCESS_KEY=AKIAXXXXXXXXXXXXXXXX
   STORAGE_SECRET_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   STORAGE_REGION=eu-central-1
   ```

   The region in the endpoint and in `STORAGE_REGION` must be the bucket's region.

### Option 3: Cloudflare R2

1. In the Cloudflare dashboard open **R2**, create a bucket, and note your
   **account ID** (32 letters and digits).
2. Create an **R2 API token** with *Object Read & Write* limited to that bucket.
   It gives you an access key ID and a secret.
3. Add the [CORS rule](#cors-rule-for-a-remote-bucket) to the bucket.
4. Put this in `.env` before the first setup:

   ```ini
   TARLEAKS_STORAGE_PROVIDER=r2
   TARLEAKS_STORAGE_ENDPOINT=https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com
   TARLEAKS_STORAGE_PRESIGN_ENDPOINT=https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com
   STORAGE_BUCKET=my-company-erp-files
   STORAGE_ACCESS_KEY=your-r2-access-key-id
   STORAGE_SECRET_KEY=your-r2-secret
   STORAGE_REGION=auto
   ```

Keep the bucket private: do not turn on public access or a public bucket URL.

### Option 4: Wasabi

1. Create a bucket in the region you want and an access key for it.
2. Add the [CORS rule](#cors-rule-for-a-remote-bucket) to the bucket.
3. Put this in `.env` before the first setup (use your region in both places):

   ```ini
   TARLEAKS_STORAGE_PROVIDER=wasabi
   TARLEAKS_STORAGE_ENDPOINT=https://s3.eu-central-1.wasabisys.com
   TARLEAKS_STORAGE_PRESIGN_ENDPOINT=https://s3.eu-central-1.wasabisys.com
   STORAGE_BUCKET=my-company-erp-files
   STORAGE_ACCESS_KEY=your-wasabi-access-key
   STORAGE_SECRET_KEY=your-wasabi-secret
   STORAGE_REGION=eu-central-1
   ```

### Option 5: your own NAS (versitygw)

Keep the files on a NAS share, so staff can still open them from the shared
folder. You run a small S3 gateway, `versitygw`, next to the share: on the
NAS's Docker, or on a small server that mounts the share. It stores each
object as an ordinary file at the path its key names.

1. Create a shared folder on the NAS, for example `/volume1/erp-files`, and a
   sub-folder with the bucket's name: `mkdir /volume1/erp-files/erp-documents`
   (with versitygw a bucket is a folder).
2. Run versitygw on the share. The shape of the command is
   `versitygw --port :7070 posix /data` with `-v /volume1/erp-files:/data`,
   `ROOT_ACCESS_KEY` and `ROOT_SECRET_KEY` set, and a certificate (`--cert`,
   `--key`) if the ERP is served over HTTPS. Check the flags against
   `versitygw --help` for the version you run.
3. Add the [CORS rule](#cors-rule-for-a-remote-bucket) to the bucket.
4. Put this in `.env` before the first setup:

   ```ini
   TARLEAKS_STORAGE_PROVIDER=nas_versitygw
   TARLEAKS_STORAGE_ENDPOINT=http://192.168.1.50:7070
   TARLEAKS_STORAGE_PRESIGN_ENDPOINT=http://192.168.1.50:7070
   STORAGE_BUCKET=erp-documents
   STORAGE_ACCESS_KEY=the-ROOT_ACCESS_KEY-you-chose
   STORAGE_SECRET_KEY=the-ROOT_SECRET_KEY-you-chose
   STORAGE_REGION=us-east-1
   ```

Notes:

- Use the NAS's real network address or name. Loopback (`127.0.0.1`,
  `localhost`) and the cloud metadata address are always refused.
- **If the ERP is served over `https://`, the NAS address must be `https://` too.**
  Browsers block an upload from a secure page to a plain `http://` address.
- On a NAS, put only the **files** there. **Never put the database on a NAS.**
- Test the setup before you rely on it (see below). NAS storage depends on how
  well your gateway handles CORS, so check it with a real upload.

### CORS rule for a remote bucket

Browsers send the file straight to a remote bucket, from the ERP's page. The
bucket must say that is allowed. This is a **CORS rule**. Without it, uploads
fail in the browser even though the keys are right.

Allow the ERP's address (`TARLEAKS_URL`, with scheme and port, no trailing
slash), the methods `PUT`, `GET` and `HEAD`, and the headers `content-type` and
`x-amz-*`:

```json
{
  "CORSRules": [
    {
      "AllowedOrigins": ["https://erp.example.com"],
      "AllowedMethods": ["PUT", "GET", "HEAD"],
      "AllowedHeaders": ["content-type", "x-amz-*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3600
    }
  ]
}
```

The same file is [examples/s3-storage/cors.json](../examples/s3-storage/cors.json).
Change `AllowedOrigins` to your address, for example `http://192.168.1.20` or
`http://192.168.1.20:8080`.

Apply it with the AWS command line (works for S3, R2 and Wasabi; add
`--endpoint-url` for R2, Wasabi and a NAS):

```bash
aws s3api put-bucket-cors --bucket my-company-erp-files \
  --cors-configuration file://cors.json
# R2, Wasabi or NAS: add the endpoint
#   --endpoint-url https://<account-id>.r2.cloudflarestorage.com
```

Or paste it in the provider's page: S3 *Permissions, Cross-origin resource
sharing*; R2 *Settings, CORS Policy*; Wasabi *Settings, CORS*. Some of these ask
for only the list inside `CORSRules` (the part in square brackets), or show a form
for the same fields. If a provider rejects `x-amz-*`, use `*` for
`AllowedHeaders`.

### Check that it works

After the setup screen, sign in as the administrator and:

1. Open **Settings, Document management, Storage** and press **Test connection**. It checks
   the keys, the bucket and the CORS rule, and says what is wrong.
2. Upload a file in **Documents**, then open it again.

If the upload fails, see
[troubleshooting.md](troubleshooting.md#uploads-fail-or-files-do-not-open).

### Backups and remote storage

`./tarleaks backup` copies the Docker volume `files` only. With S3, R2, Wasabi or
a NAS your files are **not** in the backup. Use the provider's own versioning or
replication, or copy the NAS share. See [backup-restore.md](backup-restore.md).

## Database and message queue

Internal. These are never published on a network port.

| Variable | Default | What it does |
|---|---|---|
| `POSTGRES_USER` | `tarleaks` | Database user. |
| `POSTGRES_DB` | `tarleaks` | Database name. |
| `POSTGRES_PASSWORD` | generated | Database password. |
| `RABBITMQ_USER` | `tarleaks` | Message queue user. |
| `RABBITMQ_PASSWORD` | generated | Message queue password. |
| `PG_MAX_CONNECTIONS` | `300` | Set by the installer: 150 (`small`), 300 (`standard`), 400 (`full`). |
| `PG_SHARED_BUFFERS` | `256MB` | Set by the installer: 128MB, 256MB, 512MB. |
| `PG_EFFECTIVE_CACHE_SIZE` | `1GB` | Set by the installer: 512MB, 1GB, 2GB. |
| `PG_WORK_MEM` | `4MB` | Memory one sort or join may use before it spills to disk. Each connection can use several. |
| `PG_STATEMENT_TIMEOUT` | `300s` | The longest one query may run, the same budget production gives its longest requests. A query caught in a loop is stopped instead of holding the server. Raise it (`900s`) only if a database update during an upgrade stops with "canceling statement due to statement timeout" on a very large database. |
| `PG_IDLE_IN_TRANSACTION_TIMEOUT` | `60s` | A transaction left open and doing nothing is ended after this, so its locks do not block everyone else. |
| `PG_LOCK_TIMEOUT` | `0` (no limit) | How long a query waits for a lock. |

Backups (`pg_dumpall`), restores and the app's own backups lift these limits for
their own sessions, so a large backup is never cut off.

Never change the user, database name or password after the first start. The
database is created with them once. Changing them in `.env` afterwards stops the
ERP from connecting. Leave the tuning values to the installer unless you know why
you are changing them.

## Keys

Generated by the installer. **Never change, delete or share them.** They sign
sign-in sessions and encrypt secrets stored in the database, so changing one
can make stored data unreadable and signs everyone out.

```text
JWT_SECRET
CLUSTER_DSN_KEY
INTERNAL_TOKEN
PORTAL_JWT_SECRET
NOTIFICATIONS_KEK
NOTIFICATIONS_UNSUB_SECRET
NOTIFICATIONS_OAUTH_SECRET
HELPDESK_TOKEN_KEY
SUBSCRIPTIONS_KEY_SEAL_KEY
MARKETPLACE_TOKEN_KEY
INSIGHTS_SOURCE_KEY
INSIGHTS_VISITOR_HASH_KEY
PROCUREMENT_KEK
CONTRACTS_PROVIDER_KEY
ACTIVITIES_INVITE_SECRET
CORRESPONDENCE_MAILBOX_KEY
CRM_EMAIL_TOKEN_KEY
EINVOICE_SEAL_KEY
PDFTOOLS_SIGN_KEY
SOCIAL_TOKEN_KEY
SSO_CREDENTIAL_KEY
ONLYOFFICE_JWT_SECRET
JWT_SIGNING_KID
JWT_SIGNING_KEY_DER
JWT_PUBLIC_KEYS
LMS_PASSPORT_SIGNING_KEY_DER
BADGE_SIGNING_KEY_DER
```

`JWT_SIGNING_KID`, `JWT_SIGNING_KEY_DER` and `JWT_PUBLIC_KEYS` are the sign-in
token key (Ed25519): its name, its private half
(only the auth service reads it) and its public half. Two-step confirmation,
which opening a sealed tender needs, works only with them. The installer makes
them; an installation from an older kit gets them on its next `./tarleaks
start`. Empty, the ERP signs sessions with `JWT_SECRET` as before. The
private half also protects the keys a workspace uses to let people sign in to
other apps with their ERP account: keep it with the other keys. A restored
`.env` from before these lines existed gets a new key on the next start, which
only signs everyone out once.

`LMS_PASSPORT_SIGNING_KEY_DER` and `BADGE_SIGNING_KEY_DER` are the private
halves of two more Ed25519 keys, each the app's own: learning certificates and
passport links (LMS), and Open Badges (Gamification). The installer makes them;
an installation from an older kit gets them on its next `./tarleaks start`.
Empty, those apps issue no certificates or badges; everything else works. A new
key makes the certificates and badges issued before fail their check.

Back them up: they are in `.env`, which `./tarleaks backup` copies.

## AI features (optional)

| Variable | Default | What it does |
|---|---|---|
| `GROQ_API_KEY` | empty | An API key for the Groq service, for AI features. |
| `OLLAMA_API_KEY` | empty | An API key for Ollama (cloud). |
| `OLLAMA_BASE_URL` | empty | The address of an Ollama server. |

Leave them empty to run without AI. Each workspace can also set its own AI
provider and key in **Settings, AI**. When AI is on, the text you send to it goes
to the provider you chose.

## Outbound proxy

For networks where servers reach the internet only through a proxy.

| Variable | Default | What it does |
|---|---|---|
| `HTTPS_PROXY` | empty | The proxy for outside HTTPS connections, for example `http://proxy.example.com:3128`. Empty = connect directly. |
| `HTTP_PROXY` | empty | The same for plain HTTP. Usually the same value. |
| `NO_PROXY` | empty | Extra hosts that must **not** go through the proxy, comma-separated: a mail relay, a NAS, `192.168.0.0/16`. |

```bash
HTTPS_PROXY=http://proxy.example.com:3128
HTTP_PROXY=http://proxy.example.com:3128
NO_PROXY=mail.example.local,192.168.0.0/16
```

Then `./tarleaks restart`. Every ERP service gets these values. Its own
services (database, file store, gateway and so on) and the address in
`TARLEAKS_HOST` never go through the proxy, so you do not list them.

Good to know:

- Put the values in **`.env`**. The ERP ignores a proxy set only in your shell
  or in Windows, because one that works on this machine (say `127.0.0.1:3128`)
  does not exist inside a container. The installer warns when your shell has a
  proxy and `.env` has none.
- The proxy must **pass HTTPS through** (the usual `CONNECT` tunnel). The ERP
  checks certificates against the public certificate authorities only, so a
  proxy that opens and re-signs HTTPS breaks its connections. Exempt this
  server from HTTPS inspection.
- A proxy that needs a user name and password takes them in the address:
  `http://user:password@proxy.example.com:3128`. Write a `$` in the password as
  `$$`.
- These settings do **not** cover image downloads: Docker makes those itself,
  with its own proxy setting ([requirements.md](requirements.md#network)).

What goes out at all: [network.md](network.md).

## E-invoicing time server

| Variable | Default | What it does |
|---|---|---|
| `EINVOICE_NTP_SERVER` | empty (no check) | Your own time server (`host:port`, UDP). When set, the clock is compared with it before an e-invoice is signed; empty, the server's own time sync is trusted. |
| `EINVOICE_PROBE_URL` | empty | Optional. An address outside your network that the ERP tries when an e-invoicing provider does not answer, to tell their outage from yours. Empty = no such check. |

## Editors

Documents and Diagrams work here as they do in the hosted service, because the
installation ships the same editors, next to the apps that use them:

| Editor | Runs with | What it does | Memory |
|---|---|---|---|
| Document editor (ONLYOFFICE Document Server, `onlyoffice`) | Documents (every installation) | **New** and **Edit** in Documents, co-editing, versions; the letter and contract templates of HR | about 2 GB |
| Diagram editor (draw.io, `drawio`) | Diagrams | Drawing and editing saved diagrams | about 0.3 GB |

They are on unless you switch them off. The installer turns them off by itself
when Docker has less than about 5.5 GB of memory, and says so.

```bash
./tarleaks editors            # are they on?
./tarleaks editors off        # stop them all and give the memory back
./tarleaks editors on         # start them again (downloads the images the first time)
./install.sh --editors off    # choose at install time
```

(Windows: `.\tarleaks.ps1 editors off`, `.\install.ps1 -Editors off`.)

With the editors off, Documents still stores, previews, shares and downloads
files, and says that editing is not part of this installation; the Diagrams app
says its editor is not installed. Nothing is deleted. Turn them on again and
everything is back.

**Where they are.** Browsers open the document editor at `<address>/onlyoffice/`
and the diagram editor at `<address>/drawio/`: the same address as the ERP,
through the gateway, so nothing else needs to be opened on the firewall. The
installer writes `TARLEAKS_ONLYOFFICE_URL` and `TARLEAKS_DRAWIO_URL` into
`.env` from `TARLEAKS_URL` on every start;
do not edit those. Behind a reverse proxy with its own name, send both paths
(and the editor's WebSocket) to the gateway and, only if people reach the
editors at a different address than `TARLEAKS_URL`, set `ONLYOFFICE_PUBLIC_URL`
or `DRAWIO_URL`.

**No third-party calls.** The document editor's own AI tab is not offered on a
self-hosted installation: its panel is loaded from a third-party website, and
nothing here calls one by default. The diagram editor is served by your own
server too (it does not use the public draw.io service).

**The secret.** The document editor and the ERP check each other with one
shared secret, `ONLYOFFICE_JWT_SECRET`. The installer generates it once and no
script ever changes it; keep it with the rest of `.env`. Anyone who knows it
could open any document the editor can reach.

**What they keep.** The document editor keeps only editing sessions and
caches, in three Docker volumes (`onlyoffice-data`, `onlyoffice-lib`,
`onlyoffice-db`). Your documents are in the file store, which the backup covers,
so these volumes are not in the backup: after a restore the editor starts empty
and rebuilds them. A document someone had open and unsaved when the machine
stopped is lost, as in any editor. The diagram editor keeps
nothing.

**AI drawing** also needs an AI provider: each company sets its own in
**Settings, AI** (a provider, key and model). `GROQ_API_KEY` in `.env` is only
the fallback for a company that set none. Until one exists, the Diagrams app
says that AI drawing needs an AI provider instead of offering it.

| Variable | Default | What it does |
|---|---|---|
| `TARLEAKS_EDITORS` | `on` | `on` or `off`; use `./tarleaks editors`. |
| `ONLYOFFICE_IMAGE` | the release's `onlyoffice` image | The document editor's image (amd64 and arm64). Set it only to use your own build. |
| `ONLYOFFICE_MEM_LIMIT` | `3g` | Memory limit of the document editor. |
| `DRAWIO_IMAGE` | `jgraph/drawio:31.7.0` | The diagram editor's image. |
| `DRAWIO_MEM_LIMIT` | `1g` | Memory limit of the diagram editor. |
| `ONLYOFFICE_PUBLIC_URL`, `DRAWIO_URL` | empty | Only behind a proxy with its own name (above). |

The document editor's image is the same one the hosted service runs: ONLYOFFICE
Document Server 9.4.0.1 with about 100 extra Arabic fonts, published with every
release as `onlyoffice` (Intel/AMD and ARM), so a document looks the same here
as online. A release before 1.2.0 has no such image: the installer then keeps
the standard Document Server for it (Arabic text is shown and edited correctly,
but a document that asks for a font the standard image lacks falls back to
another one) and switches to the release's image when you upgrade to 1.2.0.

**First start.** The images are about 3 GB (document editor) and 0.5 GB
(diagram editor); the document editor then takes a minute or two to start.
The installer and `./tarleaks start` wait for it and say when it is ready;
`./tarleaks doctor` checks it. With no internet, load the images first: the
offline bundle of a release includes them ([faq.md](faq.md#can-i-install-without-internet)):
the document editor (`onlyoffice`) and the two proxies (`nginx`), plus the
diagram editor (`jgraph/drawio`) when you run Diagram Studio.

## Many people at once

Every request a signed-in person makes is first checked with the sign-in
service. The gateway's own connection pool for that check is tiny, so with
more than about ten people working at once it ran out of network ports and
answered 500 or 502. Two things in the kit prevent it:

- the check goes to `authproxy`, a small proxy that keeps a pool of open
  connections to the sign-in service (the same arrangement production runs);
- the gateway has a wider range of local ports, and reuses the ports of closed
  connections at once.

Nothing to configure. If people still see 502 under load, `./tarleaks doctor`
and `./tarleaks logs gateway authproxy auth` say which part is busy.

## Calls (LiveKit)

Voice and video calls in Chat need a [LiveKit](https://livekit.io) media server
that you run yourself. Leave these empty and calls are simply off.

| Variable | Default | What it does |
|---|---|---|
| `LIVEKIT_URL` | empty | The server's address, for example `https://rtc.example.com`. |
| `LIVEKIT_WS_URL` | empty | The address browsers connect to, for example `wss://rtc.example.com`. Empty = derived from `LIVEKIT_URL`. |
| `LIVEKIT_API_KEY` | empty | The API key from the LiveKit server's configuration. |
| `LIVEKIT_API_SECRET` | empty | Its secret. |

## Other

| Variable | Default | What it does |
|---|---|---|
| `TZ` | `UTC` | Time zone of the servers' logs and scheduled jobs. The workspace has its own time zone setting. Use a name such as `Asia/Dubai`. |
| `LOG_LEVEL` | `info` | `info`, `warn` or `debug`. |

## Memory limits

Every container has a memory limit, so one that runs away (a heavy report, a
leak, a loop) is stopped and restarted on its own instead of slowing the whole
machine until it stops answering. `./tarleaks doctor` and
`docker stats --no-stream` show what each one uses.

| Variable | Default | Container |
|---|---|---|
| `PG_MEM_LIMIT` | a quarter of Docker's memory, at least `1024m` (set by the installer, kept on re-runs) | the database |
| `SERVICE_MEM_LIMIT` | `1g` | each ERP service |
| `PDFTOOLS_MEM_LIMIT` | `2g` | PDF tools (OCR) |
| `JOBS_MEM_LIMIT` | `512m` | each `<app>-jobs` container |
| `RABBITMQ_MEM_LIMIT` | `1g` | the message queue |
| `REDIS_MEM_LIMIT` | `1g` | the cache |
| `OBJECTS_MEM_LIMIT` | `512m` | the bundled file store |
| `GATEWAY_MEM_LIMIT` | `512m` | the gateway |
| `WEB_MEM_LIMIT` | `256m` | the web app |
| `DRAWIO_MEM_LIMIT` | `1g` | the diagram editor |

A limit is a ceiling, not a reservation: the machine still needs the memory the
apps use ([apps.md](apps.md)). If `./tarleaks status` shows a container
restarting and its log ends abruptly, `docker inspect <container> --format
'{{.State.OOMKilled}}'` says `true` when it hit its limit: raise that limit in
`.env`, then `./tarleaks restart`. When the database reaches its limit, the
system stops one of its processes and PostgreSQL reconnects everyone within
seconds; requests running at that moment fail once.

## Container security

Each container gets only the rights its job needs, so a flaw in one program
cannot take over the machine or change the ERP.

- **The ERP's own containers** (every app, its `<app>-jobs` container and the
  update steps) run as an ordinary user (uid `10001`), never as root. Their
  program files are read-only. They have no Linux capabilities. No program in
  them can gain rights (`no-new-privileges`). They write only to `/tmp`, in
  memory and emptied at every restart, and to their volumes. Backups, restores
  and PDF tools keep their working files on disk instead, in the volumes
  `scratch-auth` and `scratch-pdftools`. Those volumes are not part of the backup.
- **The database, cache, message queue and web servers** start as root only to
  hand their data folder to their own user, then switch to it. They keep the
  five capabilities that step needs and no others.
- **The gateway** keeps one capability: opening ports 80 and 443. **The sign-in
  proxy** runs as nginx's own user. The file store and the one-off set-up steps
  run with no capabilities and no network, where they need none.
- **The document editor** (ONLYOFFICE) keeps its capabilities: it sets itself up
  as root. No program in it can gain more.
- Every start, a one-off step (`volume-owner`) gives the HR documents volume to
  the ERP's user. Installations from before 1.2.0 wrote it as root.

| Variable | Default | What it does |
|---|---|---|
| `TARLEAKS_RUN_AS` | `10001:10001` | The user and group the ERP's containers run as. `0:0` runs them as root again (`./tarleaks restart` applies it, and the HR documents volume follows). Root here still has no Linux capabilities and a read-only system, so it fixes a file-ownership problem, not one that needs extra rights. Use it only while a problem is being fixed, and tell us. |
| `SERVICE_TMP_SIZE` | `256m` | The largest `/tmp` of each ERP container. It is in memory and counts towards the container's memory limit. |

Neither is in `.env.example`. Add the line to `.env` when you need it.

## Scheduled jobs

Work that runs on a clock (SLA deadlines, recurring invoices, scheduled reports,
expiry reminders, retention clean-up, search indexing) runs in one small
`<app>-jobs` container per app, next to the app, with the app's own program
and settings. It starts and stops with its app. Each job runs about two minutes
after the container starts, then on its interval:

| Container | Jobs |
|---|---|
| `auth-jobs` | ended sign-in sessions (hourly), old security events (daily), from 1.2.0 the app's own nightly company backups (`backup-tick`) |
| `activities-jobs` | reminders and due activities (every 5 minutes) |
| `documents-jobs` | search index (hourly), retention rules and "expiring soon" notices (daily) |
| `reports-jobs` | scheduled reports (every minute) |
| `insights-jobs` | scheduled dashboards (every minute), the data catalogue scan (hourly: a new workspace has its reports and dashboards within the hour) |
| `hr-jobs` | surveys (hourly), visa / ID / document expiry and certification expiry (daily) |
| `attendance-jobs` | clock-in machine punches (every 5 minutes), old machine punches (daily) |
| `accounting-jobs` | scheduled financial reports and the anomaly scan (daily) |
| `payroll-jobs` | salary (WPS) file reminders (daily) |
| `helpdesk-jobs` | ticket deadlines (SLA, every 5 minutes) |
| `subscriptions-jobs` | recurring invoices, renewals, trial ends, unpaid-invoice reminders (hourly) |
| `rental-jobs` | overdue rentals (every 15 minutes) |
| `correspondence-jobs` | reply deadlines and delegations (hourly), retention and the import gate (daily) |
| `project_management-jobs` | scheduled automations (every minute), risk and unassigned-work checks (daily), retention (monthly) |
| `fleet-jobs` | licence, insurance and registration expiry (daily) |

`./tarleaks logs hr-jobs` shows what ran. A failed run is logged ("FAILED") and
tried again at the next interval; a job the release does not have yet is
logged once and skipped. Daily jobs run 24 hours apart, counted from the
container's start, not at a fixed hour. To run an app's jobs now:
`docker compose restart hr-jobs` (they run two minutes later).

| Variable | Default | What it does |
|---|---|---|
| `JOBS_START_DELAY` | `120` | Seconds after a jobs container starts before its first run. |
| `JOBS_TIMEOUT` | `3600` | A single run is stopped after this many seconds. |
| `JOBS_MEM_LIMIT` | `512m` | Memory limit of each jobs container. |

## Advanced settings not in `.env.example`

`docker-compose.yml` reads these too. Leave them alone unless you have a reason,
for example a private image mirror. If you change an image here on an
installation without internet, load that image yourself (`docker load`).

| Variable | Default | What it does |
|---|---|---|
| `POSTGRES_IMAGE` | `pgvector/pgvector:0.8.7-pg16` | Database image. Must be PostgreSQL 16 with pgvector. |
| `REDIS_IMAGE` | `redis:7.4.12-alpine` | Cache image. |
| `RABBITMQ_IMAGE` | `rabbitmq:3.13.7-management-alpine` | Message queue image. |
| `CURL_IMAGE` | `curlimages/curl:8.23.0` | Small helper image for first-start tasks. |
| `OBJECTS_IMAGE` | `versity/versitygw:v1.10.0` | Bundled file store image. |
| `TRAEFIK_IMAGE` | `traefik:v3.7.17` | Gateway image. It runs with its version check and usage statistics switched off. |
| `ALPINE_IMAGE` | `alpine:3.22.6` | Small helper image: prepares the file store. (`./tarleaks backup` and `restore` use the database image.) |
| `DRAWIO_IMAGE` | `jgraph/drawio:31.7.0` | The diagram editor ([above](#editors)). |
| `ONLYOFFICE_IMAGE` | the release's `onlyoffice` image | The document editor ([above](#editors)). |
| `AUTHPROXY_IMAGE` | `nginx:1.30.6-alpine` | The sign-in check proxy and the document editor's proxy ([above](#many-people-at-once)). |
| `PG_SHM_SIZE` | `256mb` | Shared memory for the database container. |
| `GATEWAY_LOG_LEVEL` | `WARN` | Gateway log level. |
| `GATEWAY_ACCESS_LOG` | `false` | Set `true` to log every request at the gateway. |

The third-party images are pinned in the kit. A new kit release moves the pins.

## Settings you cannot change

The compose file fixes a few things on purpose: self-hosted mode, one workspace,
no platform console, and no public sign-up. They are not settings.

## Applying and checking a change

```bash
./tarleaks restart      # apply
./tarleaks status       # services, workspace and licence
./tarleaks doctor       # explains what is wrong
```

Windows: `.\tarleaks.ps1 restart` and `.\tarleaks.ps1 status`.
