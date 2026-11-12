# Security policy

## Reporting a vulnerability

Report a security problem **privately**. Do not open a public issue, discussion
or pull request for it.

1. **Preferred:** use GitHub's private vulnerability reporting on this
   repository: the **Security** tab, then **Report a vulnerability**. Only
   Tarleaks sees the report, and we can talk to you and publish an advisory
   from it.
2. **If you cannot use GitHub:** e-mail **dev@tarleaks.com**.

Include, as far as you can:

- the Tarleaks ERP version (Settings, Licence, under "This installation", or
  `grep ^TARLEAKS_VERSION .env`);
- what you found and how to reproduce it;
- what an attacker could do with it.

We acknowledge a report within three working days and tell you what we will do
and when. Please give us reasonable time to release a fix before you publish
anything. We credit reporters who want to be credited.

## What is in scope

- The files in this repository: the installers, the `tarleaks` command, the
  Docker Compose files and the configuration they write.
- The Tarleaks ERP images they install from `registry.tarleaks.com`.

Your own server, Docker, your reverse proxy and anything else outside these
files are yours to secure; [docs/security.md](docs/security.md) lists what we
recommend.

## Supported versions

Security fixes are released for the newest release, and for the release before
it for 90 days after a new release comes out. Release candidates (such as
`1.2.0-rc.2`) are for evaluation and are replaced, not patched.

| Version | Security fixes |
|---|---|
| 1.2.x | yes, once 1.2.0 is released |
| 1.2.0 release candidates | replaced by the next candidate |
| 1.0.x | until 90 days after 1.2.0 is released |

## Keeping an installation secure

[docs/security.md](docs/security.md): what the ERP protects by itself, and a
short checklist for the server (updates, backups, who may run Docker).
