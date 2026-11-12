# Release signatures

Every offline bundle Tarleaks publishes is signed with the Tarleaks release key, and so is every image of the
release. `./tarleaks load-bundle` (Windows: `.\tarleaks.ps1 load-bundle`) checks the bundle's signature before it
checks or loads anything, and refuses a bundle that is unsigned, signed by someone else or changed after signing.

**Downloaded images are checked too (from 1.2.0-rc.7).** After `./install.sh`, `./tarleaks upgrade`,
`./tarleaks update`, `./tarleaks apps add` or `./tarleaks editors on` download images, every Tarleaks image must carry
the release signature, by the exact digest Docker downloaded, before anything starts with it. An image that is not
signed by Tarleaks is refused, named and removed; an upgrade then stops before its backup and the release you run keeps
running. When the signature cannot be read (no connection), nothing is removed: fix the connection and run the command
again. Releases from before signing began (1.2.0-rc.6 and older) are not checked. Third-party images (PostgreSQL,
Redis, RabbitMQ, Traefik, ...) are pinned to exact versions that every release scans.

**Images already on the server are used only when this server checked them.** Each image that passes is recorded in
`.tarleaks-verified` (the image and its content id), and so are the images of a signed offline bundle that
`load-bundle` loaded. `./tarleaks start` and `restart`, `apps remove`, `editors off`, `update`, the off-site backup
engine (`./tarleaks cloud`), the sign-in restart of `migrate-from-cloud --vendor`, an install or upgrade that downloads
nothing (`--offline`, or the download failed and every image is here) all check that record first. An image that was
never checked here or changed since is checked now with internet (the same cosign check, by the digest Docker holds),
and refused offline; a missing image is refused (a start would otherwise download it unchecked). The fix they print:
with internet `./tarleaks upgrade <release>` (it downloads and checks), without internet load the signed offline
bundle; images you built yourself: `TARLEAKS_ALLOW_UNSIGNED=1`. When the record cannot be written (a kit folder
left to root by `sudo`), the check refuses and says how to give the folder back to your user. `./tarleaks profile` downloads and checks first, like `apps add`.

| File | What it is |
|---|---|
| `tarleaks-release.pub` | The public half of the Tarleaks release key (sha256 of the file `c54c6007458834e186648309da358d79e6bdb3b9ae140cb3b0f186c7ca60dccb`). A signature that does not verify with it is refused. |
| `trusted_root.json` | Sigstore's public trust root (its transparency-log and certificate keys). It lets the check work on a server without internet. |

Checking a bundle needs [cosign](https://github.com/sigstore/cosign/releases) 2.4 or later on the server (one file; on
Windows `winget install sigstore.cosign`). Checking downloaded images uses that cosign when it is there; otherwise
Docker runs Sigstore's own cosign image (`ghcr.io/sigstore/cosign/cosign`, pinned by digest in
`scripts/lib-signature.sh`), read-only, as your user, with only this folder and a sign-in for the image registry
mounted. That image comes from ghcr.io: behind a firewall that allows only the addresses in
[docs/network.md](../../docs/network.md), install cosign instead, or also allow `ghcr.io` and `pkg-containers.githubusercontent.com`.

Check a bundle or an image yourself:

```bash
cosign verify-blob --key config/sigstore/tarleaks-release.pub \
  --bundle tarleaks-<version>-linux-amd64.SHA256SUMS.sigstore.json tarleaks-<version>-linux-amd64.SHA256SUMS
cosign verify --key config/sigstore/tarleaks-release.pub <registry>/tarleaks-erp/auth:<version>
cosign verify-attestation --key config/sigstore/tarleaks-release.pub --type cyclonedx <registry>/tarleaks-erp/auth:<version>   # its SBOM
# without internet, add: --trusted-root config/sigstore/trusted_root.json
# cosign 2.x (2.4 or later): add --new-bundle-format to verify-blob
```

A bundle you built yourself has no Tarleaks signature: load it with `./tarleaks load-bundle --allow-unsigned <folder>`
(Windows: `-AllowUnsigned`), which says loudly that the signature was not checked.
Images you built or copied into your own registry without their signatures: run the command with
`TARLEAKS_ALLOW_UNSIGNED=1` in front (Windows: `$env:TARLEAKS_ALLOW_UNSIGNED = '1'` first), which says loudly that
the signatures were not checked. A mirror made with `cosign copy` keeps the signatures, and then the check passes.
