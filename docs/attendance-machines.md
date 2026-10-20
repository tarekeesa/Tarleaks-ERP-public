# Clock-in machines (fingerprint, face and card readers)

Attendance machines send their punches straight to this installation. Nothing
is installed on the machines, and no internet connection is needed when the
machines and the server are on the same network.

The full guide for every machine type, with screenshots of the menus, the API
reference and examples, is at
<https://tarleaks.com/developers/attendance-devices/> (Arabic:
<https://tarleaks.com/ar/developers/attendance-devices/>). This page covers
only what is different on your own server.

## Before you start

1. **The address machines use is `TARLEAKS_URL`** in `.env`. It must be an
   address the machines can reach: the server's fixed IP or DNS name, for
   example `http://192.168.1.20`. `http://localhost` does not work, because a
   machine's `localhost` is the machine itself. After changing it, run
   `./tarleaks restart`.
2. **The machines must reach the server on the port in `TARLEAKS_URL`**, which
   is `HTTP_PORT` (80 by default), or 443 behind your own HTTPS proxy. If the
   server has a firewall, allow that port from the machines' network.
3. **Attendance must be installed and in your licence.** It is in every preset;
   with a hand-picked list, `./tarleaks apps add attendance`.

## Add a machine

In the ERP: **Attendance → Clock-in machines → Add a machine.** Choose the
machine type. The last step shows:

- the **connection key** (shown once; copy it then);
- the exact settings to type into the machine, already filled in with your
  address, port and whether to switch HTTPS on.

On a plain `http://` installation the steps say **HTTPS: OFF**. Leave it off:
the machine talks to the server inside your office network.

| Machine | What you type on the machine |
|---|---|
| ZKTeco, eSSL and other "Cloud Server / ADMS" models | Server address `<your address>/zk/<key>`, the port shown, HTTPS as shown |
| Hikvision access terminals | HTTP listening: host, port and URL shown on the Connection tab |
| Anything else | The on-site bridge or a log-file import (below) |

If a ZKTeco machine's Server Address field is too short for the key address,
open **Advanced** on the machine's Connection tab and switch on the
**serial-number address**. Then type only your server's address on the machine.
That address accepts the machine only from the IP addresses you allow there,
so give the machine a fixed IP. Behind your own HTTPS proxy, use the key
address: the gateway then sees every request coming from the proxy.

## Machines the server cannot hear from

Some machines only answer when asked (no "push"). Run the small bridge program
on any office PC that can reach both the machine and this server. Download it,
with its checksum, from
<https://tarleaks.com/developers/attendance-devices/#the-on-site-bridge>, and
add the machine in the ERP as **Another brand, or an older machine on our
office network** to get its key. In the bridge's settings file, the server
address is your `TARLEAKS_URL`.

Machines with no network at all: export the attendance log to a USB stick and
use **Import a log file** on the machine's Punches tab.

## Check that it works

From a PC on the machines' network:

```bash
curl -i http://192.168.1.20/api/attendance/public/v1/device
```

- `401` with `DEVICE_TOKEN_INVALID`: the route works. The machine only needs
  its key.
- `404`: this kit is older than the attendance machines. Update it
  ([upgrading](upgrading.md)).
- No answer: the address or the port is blocked between the two (step 2 above).

When a machine connects, its page shows **Last contact** within a minute.

## Background jobs

The `attendance-jobs` container finishes punches that a restart left half
processed (every 5 minutes) and, once a day, deletes machine punches older
than **Settings → Attendance → Keep machine punches for (months)**. The
clock-ins made from them stay. Its log:

```bash
./tarleaks logs attendance-jobs
```

## What is never stored

Fingerprints, face images, photos, temperature or mask readings and machine
passwords never leave the machine. The ERP receives only the person's number on
the machine, the time and, when the machine sends it, in or out.
