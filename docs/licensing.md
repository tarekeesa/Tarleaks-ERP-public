# Licensing

Every installation runs under a licence: a **30-day free trial** or a **licence
key** from Tarleaks. The installation proves it is licensed by checking in with
`https://tarleaks.com`.

The short version:

| | |
|---|---|
| Trial | 30 days, 25 users, started from the setup screen. Needs internet. |
| Check-in | About every 6 hours, to `tarleaks.com`, over HTTPS (port 443). |
| Offline allowance | It keeps working for 30 hours without an answer. After that it stops serving until a check-in succeeds. |
| What is sent | Licence ID, installation ID, version, CPU type, number of active users. No business data. |
| Your data | Stays on your machine. When a licence lapses the ERP stops serving; it does not delete anything. |

Terms: [LICENSE.md](../LICENSE.md).

A licence covers **one company**, and today an installation runs one company.
From release 1.2.0 one server can run several companies, each under its own
licence from Tarleaks: see [companies-and-domains.md](companies-and-domains.md).

## The trial

The images are downloaded with a licence key (it is the download password,
[requirements.md](requirements.md#access-to-the-images)), so without a key the
**installer starts the trial**: it asks for your company name and e-mail
address (or take `--trial you@yourcompany.com --company "Your company"
--accept-terms`) and keeps the trial in `.env` as `TARLEAKS_DOWNLOAD_KEY`. Then,
on the setup screen, choose **Start a 30-day free trial (needs internet)** with
the **same e-mail address**: it continues the same trial.

- The installation registers the trial with Tarleaks **once**, at that moment.
  After that it checks in about every six hours.
- The trial covers every app you install, and up to **25 users**.
- To issue the trial, Tarleaks receives your company name, your name, your
  e-mail address, your country, the installation ID, the version and the CPU
  type. Tarleaks uses these to issue the trial and may contact you about it.
- There is **one trial per e-mail address**. Setting up again with the same
  address (after a reinstall, for instance) gives you the same trial with the
  **same end date**. It does not start 30 new days.
- When the trial ends the installation locks. Ask for a licence key at
  info@tarleaks.com. Your data is still there, and nothing needs to be
  reinstalled: enter the key and carry on.

If the setup screen says it could not reach `tarleaks.com`, the server has no
route to the internet. See [troubleshooting.md](troubleshooting.md#the-setup-screen-shows-an-error).

## A licence key

A key is one long line that starts with `tlk1.`. Keys issued earlier start
with `nxs1.` and keep working. You get a key from Tarleaks
(info@tarleaks.com).

Ways to enter it:

| When | How |
|---|---|
| At install time | `./install.sh --licence-key tlk1.…` (Windows: `.\install.ps1 -LicenceKey tlk1.…`) |
| On the setup screen | Choose **I have a licence key** and paste it |
| Later, signed in as the administrator | **Settings, Licence, Change licence key** |
| When the ERP is locked | **Enter a licence key** on the lock screen |
| In the settings file | `TARLEAKS_LICENSE_KEY=` in `.env`, then `./tarleaks restart` |

Entering a key on screen needs the **setup code**. Show it again with
`./tarleaks setup-code` (Windows: `.\tarleaks.ps1 setup-code`).

> A key written in `.env` as `TARLEAKS_LICENSE_KEY` is the installation's key.
> While it is set, the screen refuses another key and says so: change it in
> `.env` and run `./tarleaks restart`, or empty that line to manage the key on
> screen.

You do **not** need a new key for a renewal, a plan change, more seats or more
apps. Tarleaks's answer at each check-in carries the expiry date, the apps and
the number of users, so a change reaches your installation within a few hours.
Use **Check now** (see below) to get it immediately.

## The check-in

```text
your server  ──HTTPS 443──▶  tarleaks.com        about every 6 hours
             ◀── signed answer: valid until, apps, seats ──
```

- Every check-in sends a small request and receives a **signed** answer. The
  answer says whether the licence is active and for how long.
- If a check-in fails, the ERP keeps serving and tries again.
- The 30 hours are counted from the last answer Tarleaks gave, using Tarleaks's
  clock. They are not a date stored on your machine.
- A machine that is switched off overnight is fine: it starts in the morning
  inside its allowance. A machine that cannot reach `tarleaks.com` stops about a
  day after its last answer.
- Once blocked, the installation retries by itself every 2 minutes. A person can
  retry at once with **Check again** (lock screen) or **Check now**
  (Settings, Licence). Both wait at least 30 seconds between tries.
- Sites that cannot reach the internet every day can get a key with check-ins
  switched off. It still needs one check-in to activate; activation without
  any connection is planned but not available yet. See
  [faq.md](faq.md#can-i-install-without-internet) and write to
  info@tarleaks.com.

## What is sent, and what is not

**Every check-in sends exactly this:**

| Item | Example | Why |
|---|---|---|
| Licence ID | an identifier, not your name | Which licence is checking in |
| Installation ID | a random identifier made on first start | Stops one licence running on two machines at once |
| Version | `1.0.0` | Tarleaks knows which release you run |
| CPU type | `aarch64` or `x86_64` | Same |
| Active users | `4` | Compared with your seats |
| Edition | `selfhosted` | Which kind of installation is calling |

**The trial sign-up** (once, on the setup screen) also sends the contact details
listed under [The trial](#the-trial).

**From 1.2.0, a check-in also sends:**

- a run ID: a random identifier the `auth` service makes each time it starts and
  keeps in memory only, so a restart can be told apart from a second copy;
- the server's address;
- for each company on the server: its identifier, its licence ID, its number of
  active users, whether its first administrator has signed in, a short problem
  code if something is wrong, and its own domain names, plus how many companies
  are not on the licence;
- the kit version, the apps the server runs, whether automatic updates are on,
  and how the last update ended.

When a company is added with a key, the name and address you type for it go to
Tarleaks too, so it can be licensed.

**Never sent:** employees, payroll, invoices, customers, documents, file names,
user names, passwords, or anything else you type into the ERP.

Licensing talks only to `tarleaks.com`. If you want to be sure, allow outbound
port 443 to that one name and watch the firewall log.

## Reading the licence state

Signed in as the administrator, open **Settings, Licence**.

| Section | What it shows |
|---|---|
| Status | **Active**, **Needs attention**, **Blocked** or **Not set up**, with a sentence that says why, and the **Last problem** if a check-in failed |
| Subscription | Customer, plan (a trial is marked **Trial**) and the expiry date |
| Check-ins | Last check-in, next check-in, the **Offline deadline**, and "Every 6 hours, with 30 hours allowed offline" |
| Users | "N of M users" |
| This installation | Version, CPU architecture, last attempt, and a **Reference for support** (the installation ID) |
| Apps | The apps your licence includes. The workspace can only use an app that is in both its plan and its licence. |

**Needs attention** means it is still serving, but the offline deadline is less
than 12 hours away, or the subscription ends within 7 days.

From a terminal, `./tarleaks status` prints the workspace name and the licence
state in one line.

## When the ERP is blocked

A blocked installation answers every request with a lock screen instead of the
application, on the sign-in page and over a signed-in session. Nothing is
deleted, and your data is untouched. Services keep running; they just refuse to
serve until the licence is in order again.

The lock screen has a title, a sentence on what to do, and the licence server's
own message under **From the licence server**. Two buttons:

- **Check again**: ask Tarleaks now.
- **Enter a licence key**: paste a new key (needs the setup code).

### Recover, in this order

1. **Read the lock screen.** The title tells you which of the cases in
   [troubleshooting.md](troubleshooting.md#licence-blocked-codes) it is.
2. **Click Check again.** A renewal, a resumed subscription or a restored
   internet connection clears the lock this way.
3. **Check the server can reach Tarleaks.** On Linux or macOS:

   ```bash
   ./tarleaks doctor
   ```

   Look at the "Licence server" and "Clock" lines. On Windows:

   ```powershell
   docker compose exec -T auth curl -fsS -o /dev/null --max-time 10 https://tarleaks.com/api/activation/public-key
   ```

   No output and no error means it is reachable. Anything else means outbound
   port 443 to `tarleaks.com` is blocked.
4. **Check the clock.** Turn on automatic time. See [The clock](#the-clock).
5. **Enter a new key** if Tarleaks sent you one: **Enter a licence key**, paste
   the whole key, type the setup code (`./tarleaks setup-code`).
6. **Still stuck?** Write to info@tarleaks.com with the lock-screen title, the
   text under "From the licence server", the **Reference for support** from Settings, Licence (if you can reach it), and the output of
   `./tarleaks status` and `./tarleaks doctor`.

## Seats

The number of users your licence allows is shown under **Users** on the licence
page. A trial allows 25.

- Only **active** users count. Deactivate a person who left and the seat is free.
- Creating a user, or re-activating one, beyond the limit is refused with:
  "This licence allows N active users and M are active. Deactivate a user, or
  ask the vendor for more seats."
- People who already have an account can still sign in and work.
- More seats need no new key: Tarleaks changes your licence and the installation
  learns it at its next check-in (or press **Check now**).

**From 1.2.0**, seats are also checked when people sign in and use the ERP,
company by company. If more people are active than a company's licence allows
(after the seats were reduced, for example), only the administrators who manage
users can sign in. Anyone else is refused at the sign-in form with a sentence
that says how many users are active and how many the licence allows, and people
already signed in see the lock screen "More people are active than the licence
allows". It clears when an administrator switches people off in **Settings,
Users** or Tarleaks adds seats.

## Moving to new hardware

The licence is tied to the installation, not to the machine's hardware, and it
is held by **one installation at a time**.

**Best way: move the installation with a backup.**

1. On the old machine: `./tarleaks backup`, then copy the backup folder to the
   new machine. See [backup-restore.md](backup-restore.md).
2. **Stop the old one**: `./tarleaks stop`.
3. Install the kit on the new machine, run `./tarleaks restore <backup-folder>`.

The restored installation is the same installation as before, so the licence
carries over. Do not run the old and the new at the same time: two copies
checking in with one licence look like one installation calling from two places.
From 1.2.0 this is detected: the copy whose `auth` service started most
recently (a restart counts) keeps the licence, and the other one is refused at
its next check-in with "This licence is already in use
on another machine", then locks when its offline allowance runs out.

**Fresh install on the new machine** (no restore):

- A **trial** moves straight away: set up again with the **same e-mail address**.
- A **licence key** is still bound to the old machine. It moves to the new one
  automatically once the old machine has been silent for its whole allowance
  (30 hours by default). Until then the new installation is not activated.
  If you cannot wait, write to info@tarleaks.com and we will release it.

## The clock

The licence refuses a clock that runs **behind** Tarleaks's last answer. The
check allows a few minutes of drift (about 15). Turning the clock back is the
only way to stretch the offline allowance without a network, which is why it is
refused.

The lock screen says "The clock on this machine is wrong".

Fix it by turning on automatic time:

| System | Command or setting |
|---|---|
| Linux | `sudo timedatectl set-ntp true`, then `timedatectl` should say `System clock synchronized: yes` |
| macOS | System Settings, General, Date & Time, "Set time and date automatically" |
| Windows | Settings, Time & language, Date & time, "Set time automatically", then **Sync now** |
| Virtual machine | Enable the time-sync feature of your hypervisor, and NTP inside the guest |

Then press **Check again**. If it stays locked, restart: `./tarleaks restart`.

On a small computer without a clock battery (a Raspberry Pi, for example), the
clock can start wrong after a power cut until it reaches an NTP server. Give it
a minute, then press **Check again**.

**From 1.2.0** the ERP also refuses a clock more than about 15 minutes behind the
latest time this installation has recorded itself, even with no internet, and
the lock screen's sentence then says the clock is behind a time the installation
has already confirmed.

**From 1.2.0**, the ERP also compares its clock with the database server's. More
than about 15 minutes apart locks it with "The clocks on this installation
disagree". With the bundled database both use the same machine's clock, so this
only happens with your own PostgreSQL server
([examples/external-postgres](../examples/external-postgres/README.md)): turn on
automatic time on both machines, then `./tarleaks restart`.

## See also

- [Troubleshooting: licence codes](troubleshooting.md#licence-blocked-codes)
- [FAQ](faq.md)
- [Security](security.md)
