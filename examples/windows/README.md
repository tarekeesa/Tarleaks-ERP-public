# Windows 10 and 11

Run the ERP on a Windows PC with **Docker Desktop and WSL 2**. Good for evaluation
and for a small team on one PC. For something your staff depend on all day, we
recommend a Linux server ([office-server](../office-server/README.md)).

Time: about 45 minutes, including a restart. Profile: chosen from the memory you
give Docker.

## What you need

| | |
|---|---|
| Windows | 10 or 11, 64-bit, fully updated. Home, Pro and Enterprise all work with WSL 2. |
| CPU | Intel or AMD with virtualization switched on (Task Manager, Performance, CPU: "Virtualization: Enabled") |
| Memory | 8 GB or more in the PC. Docker needs 4 GB (`small`), 8 GB (`standard`) or 16 GB (`full`) of it. |
| Disk | 20 GB free or more on `C:` |
| Internet | To download images and for the licence check-in |
| PowerShell | The one built into Windows is enough |

## Steps

### 1. Install WSL 2

Open **PowerShell as Administrator** and run:

```powershell
wsl --install
```

Restart when it asks. Then check:

```powershell
wsl --status
```

It should say the default version is 2. If WSL was already installed, run
`wsl --update`.

### 2. Install Docker Desktop

1. Download it from <https://www.docker.com/products/docker-desktop/> and run the
   installer. Keep **Use WSL 2 instead of Hyper-V** ticked.
2. Start Docker Desktop and wait until it says **Engine running**.
3. Check in PowerShell:

   ```powershell
   docker version
   docker compose version
   docker info --format "{{.OSType}}"
   ```

   The last line must print `linux`. If it says `windows`, right-click the Docker
   icon in the tray and choose **Switch to Linux containers**.

Docker Desktop for business use may need a paid subscription. Check Docker's terms.

### 3. Get the kit

Put it somewhere simple, with no spaces and not inside OneDrive: `C:\Tarleaks-ERP`.

```powershell
git clone https://github.com/tarekeesa/Tarleaks-ERP.git C:\Tarleaks-ERP
cd C:\Tarleaks-ERP
```

No Git? Download the repository as a ZIP, unpack it to `C:\Tarleaks-ERP`, then
unblock the files:

```powershell
cd C:\Tarleaks-ERP
Get-ChildItem -Recurse | Unblock-File
```

### 4. Give Docker enough memory

WSL 2 uses only part of your PC's memory by default. Set it:

1. Copy [wslconfig.example](wslconfig.example) to `.wslconfig` in your user folder:

   ```powershell
   Copy-Item examples\windows\wslconfig.example "$env:USERPROFILE\.wslconfig"
   notepad "$env:USERPROFILE\.wslconfig"
   ```

   Run it from the kit folder (`C:\Tarleaks-ERP`). Set `memory=` to at least the
   profile you want, and leave 2 GB for Windows.
2. Apply it:

   ```powershell
   wsl --shutdown
   ```

   Start Docker Desktop again and wait for **Engine running**.

The installer chooses the hardware profile from the memory it sees, so do this before
the installer (step 7). With `memory=8GB` it suggests `full` (every app); with `memory=4GB`, `small`.

### 5. Have your licence key ready

You never run `docker login`: the installer downloads the images from
`registry.tarleaks.com` with your licence key, or starts the free 30-day trial
when you have no key yet ([details](../../docs/requirements.md#access-to-the-images)).

### 6. Allow the scripts to run

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

This lasts for this PowerShell window only. If you open a new window later, run it
again before `.\tarleaks.ps1`.

### 7. Install

```powershell
.\install.ps1
```

It checks Docker, memory and disk, asks a few questions (press Enter for the
default), writes `.env` with generated secrets, downloads the images and starts
everything. The first start prepares the database; allow up to 5 minutes.

Options (all optional):

| Option | Meaning |
|---|---|
| `-Yes` | Accept every default, ask nothing |
| `-HardwareProfile small` | `small`, `standard`, `full` or `auto`. `-Profile` also works. |
| `-HostName localhost` | The address people use: `localhost`, the PC's IP or a name |
| `-Port 8080` | When port 80 is taken |
| `-LicenceKey tlk1.…` | Use a key instead of the trial |
| `-NoStart` | Write `.env` only |

For example, for this PC only: `.\install.ps1 -Yes -HostName localhost -HardwareProfile small`.

At the end it prints the address and the **setup code**.

### 8. Set up the workspace

Open **http://localhost** (exactly the address it printed). Type the setup code
(`.\tarleaks.ps1 setup-code` shows it again), enter your company and the first
administrator, and start the 30-day trial.

## Letting other computers in

By default only this PC uses `localhost`. To let the office reach it:

1. Give the PC a fixed address (a DHCP reservation on your router), for example
   `192.168.1.20`.
2. Install with that address: `.\install.ps1 -HostName 192.168.1.20`. If you already
   did the setup screen with `localhost`, see
   [the address notes](../../docs/configuration.md#decide-before-the-first-setup).
3. Open the firewall. In PowerShell **as Administrator**:

   ```powershell
   New-NetFirewallRule -DisplayName "Tarleaks ERP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow -Profile Private
   ```

   Use your port instead of 80 if you chose `-Port`. `-Profile Private` limits it to
   networks Windows calls Private.
4. From another computer open `http://192.168.1.20`.

## Daily use

```powershell
.\tarleaks.ps1 status       # what runs, the workspace and the licence
.\tarleaks.ps1 stop         # your data stays
.\tarleaks.ps1 start
.\tarleaks.ps1 logs auth    # Ctrl+C to stop following
.\tarleaks.ps1 backup       # database, files and settings into backups\
.\tarleaks.ps1 restore backups\<folder>
.\tarleaks.ps1 uninstall    # -Purge also deletes the data
.\tarleaks.ps1 update       # the newest release (-To <release>, -Check)
.\tarleaks.ps1 profile standard
```

Back up on a schedule: [scheduled-backups](../scheduled-backups/README.md). How a
restore works: [backup and restore](../../docs/backup-restore.md#restore).

## Keep it running

- **Docker Desktop starts when someone signs in.** In Docker Desktop, **Settings,
  General**, tick **Start Docker Desktop when you sign in**. The ERP then starts with
  it, unless you stopped it with `.\tarleaks.ps1 stop`.
- A PC that restarts after Windows Update and waits at the sign-in screen has the ERP
  stopped until someone signs in. For an always-on ERP, use a Linux server.
- **Sleep and hibernate** pause the ERP. The licence allows 30 hours without a
  check-in, so a PC off for a weekend is fine, but one off for days locks until it
  can reach the internet ([licensing](../../docs/licensing.md)).
- Turn on **Set time automatically** (Settings, Time & language). A wrong clock locks
  the licence.

## If something is wrong

| Symptom | Fix |
|---|---|
| "running scripts is disabled on this system" | `Set-ExecutionPolicy -Scope Process Bypass` |
| "Docker Desktop is not running" | Start it and wait for **Engine running** |
| "Docker is in Windows-containers mode" | Tray icon, **Switch to Linux containers** |
| "Less than 4 GB of memory" or services restart | Raise `memory=` in `.wslconfig`, `wsl --shutdown`, restart Docker Desktop |
| "Port 80 is already in use" | Often IIS (World Wide Web Publishing Service) or Skype. See below, or use `-Port 8080` |
| "The image registry did not accept the licence key" | The key ended, was withdrawn or was copied incompletely: fix it and run the installer again ([access to the images](../../docs/requirements.md#access-to-the-images)) |
| Other computers cannot connect | The firewall rule above, and the address in `.env` is the PC's IP |
| Everything is slow | Give WSL more memory and keep the kit on `C:` (an SSD), not a network drive |

Find what holds port 80:

```powershell
Get-NetTCPConnection -LocalPort 80 -State Listen | Select-Object LocalAddress, OwningProcess
Get-Process -Id 4        # replace 4 with the OwningProcess from the line above
```

More: [troubleshooting](../../docs/troubleshooting.md).
