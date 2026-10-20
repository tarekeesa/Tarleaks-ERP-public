# An office server on your local network

Run the ERP on one machine in the office. Everyone on the network opens it in a
browser at the server's address, for example `http://192.168.1.20`.

Time: about 30 minutes. Profile: `standard` (8 GB of RAM, 4 CPU cores).

```text
office computers ──HTTP──▶ server 192.168.1.20 :80 ──▶ ERP
```

## What you need

- A server or a spare PC running **Ubuntu 24.04** (22.04 or Debian 12 also work),
  with **8 GB RAM, 4 cores, an SSD of 40 GB or more**
  ([requirements](../../docs/requirements.md)). Use `small` on 4 GB.
- A **fixed address** for it (step 1).
- Outbound HTTPS to `tarleaks.com`, `registry.tarleaks.com` and Docker Hub.
- A licence key, or an e-mail address to start the free 30-day trial
  ([how the images are downloaded](../../docs/requirements.md#access-to-the-images)).

## Steps

### 1. Give the server a fixed address

People type the address into their browser, so it should not move. (If it ever
does, update `TARLEAKS_HOST` and `TARLEAKS_URL` in `.env` and run
`./tarleaks restart`.) Fix it first.
Use **one** of these:

**A. A DHCP reservation (easiest).** In your router or DHCP server, reserve one
address for this machine's network card, for example `192.168.1.20`. Nothing to
change on the server.

**B. A static address on the server (Ubuntu).** Find the interface name with
`ip -br link`, then create `/etc/netplan/60-tarleaks.yaml` (adjust the interface,
address, gateway and DNS):

```yaml
network:
  version: 2
  ethernets:
    eno1:
      dhcp4: false
      addresses: [192.168.1.20/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [192.168.1.1, 1.1.1.1]
```

```bash
sudo chmod 600 /etc/netplan/60-tarleaks.yaml
sudo netplan try
```

`netplan try` rolls back by itself if you lose the connection. Remove any older
netplan file for the same interface.

**Better still, also give it a name.** Ask whoever runs your DNS (often the router)
for a record such as `erp.office.lan` pointing at `192.168.1.20`. A name survives a
change of IP address. Then use the name everywhere below instead of the IP. Choose
one, and tell everyone to use it.

Check the address: `ip -4 addr show`.

### 2. Install Docker and get the kit

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Log out and in again. There is no `docker login` step: the installer signs
Docker in to `registry.tarleaks.com` with your licence key.

```bash
sudo mkdir -p /opt/tarleaks-erp && sudo chown "$USER": /opt/tarleaks-erp
git clone https://github.com/tarekeesa/Tarleaks-ERP.git /opt/tarleaks-erp
cd /opt/tarleaks-erp
```

Make sure the clock is right and Docker starts at boot (both are the default on
Ubuntu):

```bash
sudo timedatectl set-ntp true
sudo systemctl enable --now docker
```

### 3. Open the firewall for your network only

Replace `192.168.1.0/24` with your network.

**Ubuntu, Debian (`ufw`):**

```bash
sudo ufw allow OpenSSH
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp
sudo ufw enable
sudo ufw status numbered
```

**Red Hat, Rocky, Alma (`firewalld`):**

```bash
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port protocol="tcp" port="80" accept'
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```

> **Docker publishes its ports ahead of these rules.** A `ufw` or `firewalld` rule
> may not stop another network from reaching port 80. So also keep the server off
> the internet: no port forwarding to it on the router, and no public IP address.
> Always test from a computer outside the allowed network. Strict per-network
> control of a Docker port is possible with Docker's `DOCKER-USER` firewall chain
> (see Docker's documentation on packet filtering).

### 4. Install

With the address from step 1 (an IP or the internal name):

```bash
./install.sh --yes --profile standard --host 192.168.1.20
```

The installer checks Docker, memory and disk, writes `.env`, downloads the images
and starts everything. The first start prepares the database and takes up to
5 minutes. At the end it prints the address and the **setup code**.

The relevant `.env` lines are now:

```text
TARLEAKS_HOST=192.168.1.20
TARLEAKS_URL=http://192.168.1.20
HTTP_PORT=80
HTTP_BIND=0.0.0.0
```

If port 80 is taken, add `--port 8080`. People then use `http://192.168.1.20:8080`.

### 5. Set up the workspace, from any office computer

Open **http://192.168.1.20** in a browser (the exact address the installer
printed). Type the setup code (`./tarleaks setup-code` shows it again), enter the
company and the first administrator, and start the 30-day trial or paste a
licence key.

Then create your colleagues' accounts in the application.

## Check it works

- From **another computer** on the network, the address opens the sign-in page.
- Sign in, upload a document in **Documents** and open it again.
- Reboot the server, wait a few minutes, and check that the address answers
  again. The ERP starts by itself; then run `./tarleaks doctor`. If it says an
  app is "not receiving events", run `./tarleaks restart`
  ([after a reboot](../../docs/troubleshooting.md#after-a-restart-or-a-reboot)).
- `./tarleaks doctor` on the server reports no problems.

## Keep it healthy

| Task | How |
|---|---|
| **Backups** | Every night, copied to another machine: [scheduled-backups](../scheduled-backups/README.md) |
| **Upgrades** | `git fetch --tags && git checkout v<release>`, then `./tarleaks update` ([upgrading](../../docs/upgrading.md)) |
| **Status** | `./tarleaks status` |
| **Security updates** | Turn on `unattended-upgrades` and reboot when asked ([security](../../docs/security.md)) |
| **Power cuts** | A small UPS protects the database. Everything restarts after power returns. |

## Plain HTTP on a network

This setup uses plain HTTP. Anyone who can see the office network's traffic can read
what is sent. That is acceptable on a small trusted network. For anything else add
HTTPS: use a real domain name and [vps-https](../vps-https/README.md), or
[behind-nginx](../behind-nginx/README.md).

## If something is wrong

| Symptom | Fix |
|---|---|
| Works on the server, not from other computers | The firewall, or `TARLEAKS_HOST` is `localhost`. See [troubleshooting](../../docs/troubleshooting.md#other-computers-cannot-connect). |
| Uploads stopped after the server's IP changed | `TARLEAKS_HOST` and `TARLEAKS_URL` still name the old address. Run `./install.sh --host <new address>` (it keeps everything else), or give the server its old address back. Links sent before the change keep the old address. |
| "Port 80 is already in use" | `./install.sh --port 8080` |
| Lock screen about the licence | [licensing](../../docs/licensing.md#when-the-erp-is-blocked) |
