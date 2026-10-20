# Open the database to a database tool

> **Advanced, opt-in.** Out of the box the database, the cache (Redis), the
> message queue (RabbitMQ) and the file store publish **no port**: only the
> gateway listens ([security](../../docs/security.md#what-is-exposed)). Do this
> only when a person or a reporting tool really needs to read the database
> directly, and close it again when they are done.

## Steps

1. Copy the override next to `docker-compose.yml`:

   ```bash
   cp examples/database-access/docker-compose.override.yml docker-compose.override.yml
   ```

   If you already have a `docker-compose.override.yml` (for example from
   [vps-https](../vps-https/README.md)), add its `postgres:` block under the
   `services:` you already have instead.

2. Leave `.env` alone for **this machine only** (`127.0.0.1`, the default). To
   allow one network, add the machine's address on that network:

   ```bash
   POSTGRES_BIND=192.168.1.20
   POSTGRES_PUBLISH_PORT=5432
   ```

3. `./tarleaks restart`

4. Connect with host `127.0.0.1` (or the address you chose), port `5432`, the
   database and user `POSTGRES_DB` / `POSTGRES_USER` from `.env` (both
   `tarleaks` by default) and the password `POSTGRES_PASSWORD` from `.env`.
   That user can change everything: give a reporting tool its own read-only
   user instead:

   ```bash
   docker compose exec -T postgres psql -U tarleaks -d tarleaks -c \
     "CREATE ROLE reporting LOGIN PASSWORD 'choose-a-long-one'; GRANT pg_read_all_data TO reporting;"
   ```

## From another computer, safely: an SSH tunnel

Keep `POSTGRES_BIND=127.0.0.1` and open a tunnel from the other computer:

```bash
ssh -N -L 5432:127.0.0.1:5432 you@erp-server
```

The tool then connects to `127.0.0.1:5432` on **its own** computer. Nothing new
is open on the network, and only people with an SSH login get in.

## Why not 0.0.0.0

Docker opens published ports **in front of** the machine's firewall (ufw,
firewalld): a rule that blocks 5432 does not stop it. A database on 0.0.0.0 on
an internet-facing server is found by scanners within hours.

## Close it again

Remove the `postgres:` block (or the whole file) and `./tarleaks restart`.
