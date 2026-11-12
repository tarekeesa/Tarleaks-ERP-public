# Move a company from Tarleaks Cloud to your own server

**From 1.2.0-rc.6.** Earlier releases do not have it.

A company that works on Tarleaks Cloud today can move to a server it runs
itself, whole: every app's records and files, settings, roles, people and
their two-step sign-in, the history of every record and the audit trail. Your
people keep working in the cloud while the copy is made; they stop only for
the few minutes of the switch over. Afterwards they sign in on your server with
the same e-mail and password.

How it is kept safe:

- **Your server pulls; nothing pushes to it.** Nothing on the internet has to
  reach your server. It fetches the company from `tarleaks.com` over HTTPS,
  the same connection the licence check uses.
- **Encrypted to your server only.** Your server makes a key pair; the cloud
  encrypts every part of the company to that key and signs it. The private key
  never leaves your server, and nothing in between can read or change a part.
- **Two codes, two owners.** The move code, made by the cloud workspace's
  administrator with their authenticator app, says the company may leave. The
  setup code (`TARLEAKS_SETUP_CODE` in `.env`) says you own this server. The
  move needs both.
- **Checked before anything changes.** Every table is compared with the cloud
  by row count and checksum, every file by size and SHA-256. Nothing switches
  until you say so.
- **A signed deletion certificate.** After the switch the cloud copy stays
  read-only for a retention period (30 days unless changed, 7 to 365), then
  Tarleaks destroys it and signs a certificate your server checks and shows.

## Before you start

- **A move code.** In the cloud workspace, an administrator opens
  **Settings > Move to your own server**, reads what moves and what has to be
  connected again, and presses **Make the move code** with a code from their
  authenticator app. It looks like `TLM-XXXXX-XXXXX-XXXXX-XXXXX`, works
  **once** and for **24 hours**. Anyone holding it can take a copy of the
  company: never send it by e-mail or chat; type or paste it on the server.
- **A fresh installation.** The move needs a server with no company on it yet:
  a new install, or an installed server whose setup screen was never finished.
  A server that already runs a company refuses.
- **The same release as the cloud, or newer.** An older server is refused
  before anything is copied, and the code is not used up: run
  `./tarleaks update`, then the same command again.
- **Room.** The cloud page's **What moves** card shows the size of the
  database and the files; keep about half as much again free
  ([requirements.md](requirements.md)).
- **Outbound HTTPS to `tarleaks.com`** ([network.md](network.md)).

If Tarleaks has to approve every move first, the cloud page says the move is
waiting; once it shows the move approved, run the same command again.

## Move

On a new Linux or macOS server, in the unpacked kit:

```bash
bash install.sh --from-cloud TLM-XXXXX-XXXXX-XXXXX-XXXXX
```

On a new Windows server (Docker Desktop), in the kit folder:

```powershell
.\install.ps1 -FromCloud TLM-XXXXX-XXXXX-XXXXX-XXXXX
```

On a server already installed but not set up yet:

```bash
./tarleaks migrate-from-cloud TLM-XXXXX-XXXXX-XXXXX-XXXXX
```

```powershell
.\tarleaks.ps1 migrate-from-cloud TLM-XXXXX-XXXXX-XXXXX-XXXXX
```

Leave the code out and the command asks for it without showing it, so it does
not stay in the shell's history. The cloud page shows these commands with the
code filled in.

On Linux, a script can pipe the code in from a file only you can read (delete
the file afterwards); it works with `--switch-over` too:

```bash
./tarleaks migrate-from-cloud --switch-over < move-code.txt
```

The installer installs the ERP as usual, then starts the move instead of the
setup screen. You can also start it from the browser: on the setup screen,
press **Moving your company from Tarleaks Cloud? Use a move code** and type
the setup code and the move code.

### What you see

The command prints this server's **key fingerprint** first. Compare it with
the cloud page's **New server** box, which shows the same fingerprint and the
address the code was used from. If they differ, or the address is not yours,
cancel at once (below, or on the cloud page).

Then one line follows the work: connecting, database layout, data (batch by
batch, with sizes), people and settings, files, indexes and keys, checks.
When it is done it prints the check report:

- every check passed, or what did not;
- tables and rows, each compared by row count and checksum;
- people, how many active and how many with two-step sign-in;
- files copied, already here, their size, any that failed;
- **what to connect again** after the switch over (below);
- how long each step took.

The move runs inside the ERP, not in your window: closing the window or
pressing Ctrl+C stops only the watching. `./tarleaks migrate-from-cloud
--status` shows it again. A move that was running when the server restarted
goes on by itself.

## Switch over

When the report is green and your team is ready:

```bash
./tarleaks migrate-from-cloud --switch-over
```

```powershell
.\tarleaks.ps1 migrate-from-cloud -SwitchOver
```

(The command asks before switching when it finishes the copy in a terminal; on
the setup screen the button is **Switch over**. `--switch-over` together with
the code, or `install.sh --from-cloud <code> --switch-over`, switches without
asking once everything is copied and checked.)

The cloud workspace becomes read-only at once: its pages show a banner and a
save answers that the workspace moved. Only what changed since the copy comes
over, usually in a few minutes, and is checked again. Then this server opens.

If this server stops answering during the switch, the cloud workspace opens
again by itself after 6 hours, so the company always has a working copy.
Start this server again and the switch is tried again.

## After the move

- **Everyone signs in here with the same e-mail and password**; authenticator
  apps keep working. Sessions do not move, so each person signs in once.
  Tell your people the new address ([https.md](https.md),
  [companies-and-domains.md](companies-and-domains.md)).
- **Passkeys** belong to the cloud's address: people who used one add it again.
- **Connect again** what the report lists. Passwords and keys of outside
  services (mail and calendar connections, social accounts, single sign-on,
  e-invoicing devices, payment keys, webhooks, your own storage keys) are
  locked with Tarleaks Cloud's own keys and are never exported; type them
  again in Settings. **Face photos** enrolled for clock-in do not move:
  people enrol again.
- **Licence.** The company's plan, apps and seats come with it, as a
  self-hosted licence key the move applies by itself ([licensing.md](licensing.md)).
- **Take a first backup**: `./tarleaks backup` ([backup-restore.md](backup-restore.md)).
- **Files kept in your own bucket.** If the cloud workspace kept its files in
  its own storage bucket and you chose to keep using it, the files are not
  copied: enter that bucket's keys again in Settings > Document management >
  Storage.

## The deletion certificate

After the retention period Tarleaks destroys the cloud copy: the company's
database, every file in Tarleaks storage (never files in your own bucket) and
its platform records. It keeps only what it must by law, such as its own
invoices to the company and the record of the move. This server asks for the
signed deletion certificate by itself every few hours, checks Tarleaks's
signature and shows it in **Settings > Move to your own server** with a
**Download the signed certificate** button.

## Stop, go on, cancel

| Command (Windows: `.\tarleaks.ps1 migrate-from-cloud …`) | What it does |
|---|---|
| `./tarleaks migrate-from-cloud --status` (`-Status`) | Shows where the move stands; changes nothing |
| `./tarleaks migrate-from-cloud --resume` (`-Resume`) | Goes on after a stop, from where it stopped |
| `./tarleaks migrate-from-cloud --switch-over` (`-SwitchOver`) | Switches over, once the copy is checked |
| `./tarleaks migrate-from-cloud --cancel` (`-Cancel`) | Stops the move and removes what was copied here; the cloud workspace stays as it is. Refused once the switch over has put the copy in place (finish it with `--resume`), unless that last try stopped |

After a cancel, start again with a new move code. To use the server for a different company instead, install it afresh.

## When something goes wrong

| Message | What to do |
|---|---|
| `That is not a move code` | It looks like `TLM-XXXXX-XXXXX-XXXXX-XXXXX`; copy it again from the cloud page |
| `This move code is not valid` (the move stops) | Mistyped, used already or older than 24 hours: make a new one on the cloud page, then run the command again |
| `This server already has a company` | A move needs a fresh installation: install a new copy on another server, or in a second copy of the kit folder with its own name and port |
| `This server runs an older Tarleaks` | `./tarleaks update`, then the same command with the same code |
| `Tarleaks has not approved this move yet` | Wait until the cloud page shows it approved, then the same command again |
| `That setup code is not right` | The kit sends `TARLEAKS_SETUP_CODE` from `.env`; if you changed it there, apply it first: `./tarleaks restart` |
| `There is no setup code in .env` | Run `./install.sh` again: it makes one |
| `This release cannot take a company from Tarleaks Cloud` | The installed release is older than 1.2.0-rc.6: `./tarleaks update` |
| The move shows **Stopped** with another reason | `./tarleaks migrate-from-cloud --resume`. Nothing was lost: the cloud workspace is unchanged |
| No answer from `tarleaks.com` | Check outbound HTTPS ([network.md](network.md)); the command keeps trying for a while, then `--resume` |

For anything else: `./tarleaks doctor --bundle` and send the file to support
([troubleshooting.md](troubleshooting.md)). The bundle never contains the
setup code or the move code.
