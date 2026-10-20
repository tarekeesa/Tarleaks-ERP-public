# External PostgreSQL

> **Advanced. Not yet supported.**
> In this version the **bundled database is the supported setup**. There is no
> Compose override, setting or script in this kit that points the ERP at another
> PostgreSQL server, and we do not publish one, because it would not work.
> This page explains why, and lists what an external server would need, so you can
> judge the effort. If you need it, write to info@tarleaks.com so we know.

## Why there is no override file

The database server is wired into the stack in several places that are not settings:

- Every ERP service (thirty of them) has its own database address written into
  `docker-compose.yml`, with the host name `postgres` and a search path that picks
  its own schema.
- The `auth` service creates your workspace's own database during setup, by
  connecting to the server's maintenance database through an address that is also
  written into the compose file.
- The `migrate` service connects with a third address.
- Every service waits for the bundled `postgres` container to be healthy before it
  starts.
- On the first start, `config/postgres/init/00-init.sh` prepares the database: four
  extensions and one schema per service. That script only runs inside the bundled
  container, on an empty data folder.
- `./tarleaks backup` and `./tarleaks restore` talk to the bundled container.

A short override cannot change all of that. Writing one by hand would mean
replacing about thirty service definitions, and nobody has tested the result.

## What an external server would need

These are the requirements we know of today. Meeting them is **necessary, but not
proven sufficient**, because this setup has not been tested.

| Need | Detail |
|---|---|
| PostgreSQL **16** | The bundled image is `pgvector/pgvector:0.8.7-pg16` |
| Extensions available | `vector` (pgvector), `uuid-ossp`, `pgcrypto`, `citext` |
| A role that can create databases and extensions | The workspace's database is created at setup "with everything it needs", and the platform database needs the four extensions |
| A platform database (`POSTGRES_DB`, default `tarleaks`) | With the schemas that `config/postgres/init/00-init.sh` creates, one per service |
| Enough connections | The installer sets `max_connections` to 150 (`small`), 300 (`standard`) or 400 (`full`) on the bundled server. Size yours the same. |
| Local-quality storage | Fast SSD. **Never a network share.** |
| A low-latency link to the ERP's host | Same machine or same data-centre network |
| Your own backups | `./tarleaks backup` would not reach it |

## Use a PostgreSQL on this same machine

**From 1.2.0.** From release 1.2.0, a company can keep its business data in a PostgreSQL server
that runs on the same machine as the ERP. The choice is offered once, while the
company is being set up: **Use another PostgreSQL server**, already filled in for
this machine (address `host.docker.internal`, port 5432, database and user
`tarleaks`), so you only type the password. The installation's own database
stays in the bundled container either way. Moving a company that is already set
up is not offered.

Prepare the server first:

1. PostgreSQL **16 or newer**, with the extensions `vector` (pgvector),
   `btree_gist`, `uuid-ossp`, `pgcrypto`, `citext` and `pg_trgm` available.
2. An **empty** database and a user that owns it (the screen suggests `tarleaks`
   for both):

   ```sql
   CREATE USER tarleaks WITH PASSWORD '<a long password>';
   CREATE DATABASE tarleaks OWNER tarleaks;
   CREATE ROLE app NOLOGIN;
   GRANT app TO tarleaks;
   ```

3. Let the containers reach it. In `postgresql.conf`, `listen_addresses` must
   include the Docker bridge (for example `listen_addresses = 'localhost,172.17.0.1'`).
   In `pg_hba.conf`, allow the Docker networks:

   ```text
   host  tarleaks  tarleaks  172.16.0.0/12  scram-sha-256
   ```

   Restart PostgreSQL.
4. Open the firewall for the containers only, for example on Ubuntu:
   `sudo ufw allow from 172.16.0.0/12 to any port 5432`.
5. Use port **5432** (or 5439). In the form, choose the connection security
   **Not encrypted (private network only)**: the traffic never leaves this
   machine.
6. **Back it up yourself.** `./tarleaks backup` copies only the bundled database.

If the test in the form fails, it says which of these steps to check. On Linux
the name `host.docker.internal` works once the kit is up to date (`git pull`,
then `./tarleaks start`). With an older kit the form offers `172.17.0.1`, the
Docker bridge address of this machine, instead: keep it.

## What to do instead

Run the bundled database, and make it safe:

| Do this | How |
|---|---|
| Keep it on a local SSD | It is the Docker volume `pgdata`. Leave it where Docker puts it. |
| Back it up every night, off the machine | [scheduled-backups](../scheduled-backups/README.md) |
| Rehearse a restore | [backup-restore](../../docs/backup-restore.md) |
| Watch the disk | `df -h` and `docker system df` |
| Give the host enough memory | [requirements](../../docs/requirements.md) |

If a managed database is a hard requirement for your organisation (a compliance
rule, a DBA team, a cloud policy), tell info@tarleaks.com what you need and why.
