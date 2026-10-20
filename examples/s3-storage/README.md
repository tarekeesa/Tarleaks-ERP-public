# File storage on AWS S3, Cloudflare R2, Wasabi or a NAS

By default documents and attachments live in a store bundled with the ERP (the
Docker volume `files`). Use this example to keep them in your own bucket instead.

Time: about 20 minutes per provider. Profile: any.

> **Easiest before the setup screen.** The setup screen copies the storage settings
> into your workspace once. Afterwards, change them in **Settings → Document
> management → Storage** instead of `.env`
> ([details](../../docs/configuration.md#decide-before-the-first-setup)).

## Files in this folder

| File | What it is |
|---|---|
| [aws-s3.env](aws-s3.env) | The `.env` lines for AWS S3 |
| [cloudflare-r2.env](cloudflare-r2.env) | The `.env` lines for Cloudflare R2 |
| [wasabi.env](wasabi.env) | The `.env` lines for Wasabi |
| [nas-versitygw.env](nas-versitygw.env) | The `.env` lines for your own NAS gateway |
| [cors.json](cors.json) | The CORS rule the bucket needs, in the AWS format |
| [aws-iam-policy.json](aws-iam-policy.json) | A starting policy for the AWS user the ERP uses |

Full explanation of every setting: [configuration, file storage](../../docs/configuration.md#file-storage).

## How it works, in two lines

Browsers send each file **straight to your bucket** over a signed link. So the
bucket must accept uploads from the ERP's address (**CORS**), and the ERP must
sign for the bucket's address (`TARLEAKS_STORAGE_PRESIGN_ENDPOINT`).

## Order of work

1. Install with `./install.sh --no-start` (or `.\install.ps1 -NoStart`). This creates `.env`.
2. Create the bucket, the credentials and the CORS rule (below).
3. Put the storage lines in `.env`.
4. `./tarleaks start`, then open the setup screen.

If the ERP is already running but you have **not** finished the setup screen, edit
`.env` and run `./tarleaks restart`. If the setup is already done, see the note above.

## Step 1: the bucket and its keys

### AWS S3

With the AWS command line (or do the same in the console). Replace the bucket name
and region. A bucket name is unique across all of AWS.

```bash
aws s3api create-bucket --bucket my-company-erp-files --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1
aws s3api put-public-access-block --bucket my-company-erp-files \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

(For `us-east-1` leave out the `--create-bucket-configuration` line.)

Create a user that can reach only this bucket. Edit the bucket name in
[aws-iam-policy.json](aws-iam-policy.json) first:

```bash
aws iam create-user --user-name tarleaks-erp
aws iam put-user-policy --user-name tarleaks-erp --policy-name tarleaks-erp-bucket \
  --policy-document file://aws-iam-policy.json
aws iam create-access-key --user-name tarleaks-erp
```

The last command prints the **access key ID** and **secret access key**. They are
shown once. The policy is the minimum we know of: if S3 refuses something, widen
it and tell us.

Never use the root account's keys.

### Cloudflare R2

In the Cloudflare dashboard:

1. **R2**, **Create bucket**. Keep it private.
2. Note your **Account ID** on the R2 overview page (32 letters and digits).
3. **Manage R2 API Tokens**, **Create API token**, permission **Object Read & Write**,
   limited to this bucket. Copy the **Access Key ID** and **Secret Access Key**.

### Wasabi

1. Create a bucket in the region you want.
2. Create a sub-user with an access key and a policy limited to the bucket (the
   AWS policy file above works on Wasabi with the bucket name changed).

### Your own NAS (versitygw)

Run the `versitygw` S3 gateway on the NAS (or on a small server that mounts the
share), pointing at a shared folder, and make the bucket a folder inside it. The
steps and notes are in
[configuration, option 5](../../docs/configuration.md#option-5-your-own-nas-versitygw).

## Step 2: the CORS rule

Edit [cors.json](cors.json) and set `AllowedOrigins` to the address people open the
ERP at, exactly as in `TARLEAKS_URL` (scheme, host, port; no trailing slash):

| ERP address | `AllowedOrigins` |
|---|---|
| `https://erp.example.com` | `["https://erp.example.com"]` |
| `http://192.168.1.20` | `["http://192.168.1.20"]` |
| `http://192.168.1.20:8080` | `["http://192.168.1.20:8080"]` |

Apply it:

```bash
# AWS S3
aws s3api put-bucket-cors --bucket my-company-erp-files --cors-configuration file://cors.json

# Cloudflare R2 (use the R2 keys in your AWS CLI profile)
aws s3api put-bucket-cors --bucket my-company-erp-files --region auto \
  --endpoint-url https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com \
  --cors-configuration file://cors.json

# Wasabi
aws s3api put-bucket-cors --bucket my-company-erp-files \
  --endpoint-url https://s3.eu-central-1.wasabisys.com --cors-configuration file://cors.json

# NAS gateway, if your version supports bucket CORS
aws s3api put-bucket-cors --bucket erp-documents \
  --endpoint-url http://192.168.1.50:7070 --cors-configuration file://cors.json
```

Or paste it into the provider's page. R2: **Settings, CORS Policy**. S3: **Permissions,
Cross-origin resource sharing**. Wasabi: **Settings, CORS**. Some of these want only
the list inside `"CORSRules"` (the part in square brackets), or show a form for the
same fields: methods `PUT`, `GET`, `HEAD`; headers `content-type` and `x-amz-*`.
If a provider rejects `x-amz-*`, use `*`.

If people open the ERP at two addresses, list both origins. Better: keep one address
([why](../../docs/configuration.md#address)).

## Step 3: the `.env` lines

Open the snippet for your provider, copy it, change the values:

```bash
cp examples/s3-storage/aws-s3.env my-storage.env      # or cloudflare-r2.env, wasabi.env
nano my-storage.env
```

Then apply it to `.env` (Linux; on macOS use `sed -i ''`). This removes the old
lines and adds yours:

```bash
while IFS='=' read -r key value; do
  case "$key" in ''|\#*) continue ;; esac
  sed -i "/^${key}=/d" .env
  printf '%s=%s\n' "$key" "$value" >> .env
done < my-storage.env
grep -E '^(TARLEAKS_STORAGE|STORAGE_)' .env
rm my-storage.env
```

On Windows edit `.env` in Notepad: set each of the seven variables and remove any
`#` in front of the three `TARLEAKS_STORAGE_…` lines.

Check:

- The three `TARLEAKS_STORAGE_*` lines are present and **not** commented out.
- The endpoint and presign endpoint are the same address for a remote store.
- `STORAGE_REGION` is the bucket's region (`auto` for R2).
- A secret with a `$` in it is written `$$`.

`STORAGE_ACCESS_KEY` and `STORAGE_SECRET_KEY` are your **bucket's** credentials.
The bundled store reads the same two values as its own login but sits idle.

## Step 4: start, set up, test

```bash
./tarleaks start
./tarleaks setup-code
```

Open the ERP, run the setup screen, sign in as the administrator, then:

1. **Settings, Document management, Storage**: the bucket and keys you set should
   be there. Press **Test connection**. It checks the keys, the bucket and the CORS
   rule.
2. In **Documents**, upload a file and open it again.

## If it fails

| Symptom | Fix |
|---|---|
| "blocked by CORS policy" in the browser console | The CORS rule is missing, or `AllowedOrigins` is not exactly your ERP address |
| `403 SignatureDoesNotMatch` | Wrong keys or region, or a clock that is off (turn on NTP) |
| `NoSuchBucket` | The bucket name or region is wrong, or the bucket does not exist |
| "Mixed Content" | The ERP is `https://` and the store address is `http://` |
| Test connection fails on keys | Check `STORAGE_ACCESS_KEY` and `STORAGE_SECRET_KEY` have no stray spaces |
| Uploads worked, then stopped after you changed the ERP's address | Set the new address in `.env` (`TARLEAKS_HOST`, `TARLEAKS_URL`) and run `./tarleaks restart` ([details](../../docs/configuration.md#decide-before-the-first-setup)) |

More: [troubleshooting, uploads](../../docs/troubleshooting.md#uploads-fail-or-files-do-not-open).

## Backups

`./tarleaks backup` does **not** include files kept in S3, R2, Wasabi or a NAS. Turn
on the provider's versioning or replication, or copy the NAS share, and keep the
bucket's credentials safe. See [backup and restore](../../docs/backup-restore.md).
