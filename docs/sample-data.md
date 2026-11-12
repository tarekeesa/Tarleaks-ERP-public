# Sample data

**From 1.2.0.** Releases before 1.2.0 do not have it.

Sample data fills a new company with a fictional one, so people can try the ERP
on records that look real before they enter their own: Coralstone Group, a
trading and fit-out group with about 180 employees. It includes two years of
books, payroll, stock, sales, purchasing, projects, attendance, helpdesk and
more, across every app. There is a UAE version and a Saudi version; the
company's country decides which one is loaded. Other countries have no sample
yet.

Every record the sample writes is noted as it is written, so it can be taken
out again exactly. **Your own records are never changed or deleted**, not when
loading and not when removing.

## Before you start

- The ERP must be running (`./tarleaks start`).
- Load into a **new** company: you, the administrator, are the only one who
  can sign in, and there are no employees, contacts, customers, journal
  entries, stock items or orders yet. Otherwise the load refuses with
  `WORKSPACE_NOT_EMPTY` and names what it found (for example "6 people can
  sign in"). To load the sample next to them anyway, run the load again with
  `--force-nonempty` (Windows: `-ForceNonempty`): it still stops before
  writing anything if a sample record would clash with one of yours, and lists
  them (at most 50, then how many more).
- Take a backup first: `./tarleaks backup`.
- A load takes about 10 to 20 minutes, a removal check up to half an hour, a
  removal an hour or more. They print little while they work: to follow one,
  run `./tarleaks sample-data status` in a second window (it only reads). Leave
  the window open. If it is closed, or you press Ctrl+C, the run may go on
  inside the ERP: while it does, `status` says "loading" or "removing" (wait);
  once it stopped, it adds "The last run was interrupted" (then `resume`). Starting another run while
  one goes on answers "A sample-data run is already in progress".

## Load

```bash
./tarleaks sample-data load --install-packs
```

On Windows:

```powershell
.\tarleaks.ps1 sample-data load -InstallPacks
```

`--install-packs` first installs the company's accounting and payroll country
packs and the correspondence register, for the apps the company holds. It needs
the company's country to be set and an active administrator in the company (it
installs as that administrator); without them it stops before anything is
written. Without the packs, the accounting, payroll and correspondence parts of
the sample (and what needs them) are skipped. The load says which parts were
skipped and why.

With several companies on one server, name the company:
`--workspace <company>` (Windows: `-Company <company>`). The company is its
short name, the first part of its address.

When the load is done it prints how many records it wrote. Sign in as usual.
The sample's people have no working sign-in: their accounts are switched off,
so they use no sign-in seats. They use no employee seats either: a licence
with an employee limit counts only your own employees (Settings, Licence).

The sample never bills, chases or messages anyone: its subscriptions are not
renewed or reminded, and an event about a sample record stays in the bell (no
e-mail, SMS, push, chat message or webhook goes out for it).

## See where it stands

```bash
./tarleaks sample-data status
```

It shows the sample's state and each part of it (done, pending, skipped with the
reason, failed), and whether the last run was interrupted. Add `--json` for the
full detail, including a failed part's error.

If a load was interrupted (a restart, a closed window), go on from where it
stopped:

```bash
./tarleaks sample-data resume
```

`resume` also adds parts that were skipped earlier once what they waited for
is there, for example after installing a country pack in Finance or Payroll.

## Remove

1. Take a backup: `./tarleaks backup`.
2. See what would stop the removal:

   ```bash
   ./tarleaks sample-data check
   ```

   It lists your own records that point at sample records, for example an
   invoice you raised to a sample customer. Change or delete those records, or
   keep the sample records they use (step 3).
   While the sample is loaded the server keeps working on it (automations,
   reminders, scheduled reports). What the system provably made from it goes
   with the removal. The check lists only what a person made or edited, what
   names your own people, and any posted journal entry or e-invoice made from
   it; while anything is listed, nothing is removed.

3. Remove:

   ```bash
   ./tarleaks sample-data remove --yes
   ```

   Add `--adopt` to keep the sample records your own records use (and what
   those point at); everything else of the sample is removed.

   On Windows: `.\tarleaks.ps1 sample-data remove -Yes` (and `-Adopt`).

Without `--yes` nothing is removed: the command says to back up first.

## Leftover sample data after a restore

A backup taken while the sample was loaded holds the sample. Restoring it after
the sample was removed brings the sample back. `./tarleaks sample-data status --json`
then shows `"leftover": true`, and `./tarleaks sample-data remove --yes` removes it
again.

## When something goes wrong

See [troubleshooting](troubleshooting.md#sample-data).
