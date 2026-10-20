# Raspberry Pi 5

Run the ERP for a small team on a Raspberry Pi 5. The images are native `arm64`, so
nothing is emulated.

Time: about an hour, mostly flashing and downloading. Profile: `small`.

## What you need

| | |
|---|---|
| Computer | **Raspberry Pi 5, 8 GB**. Other models are not on the supported list. |
| Operating system | **64-bit Raspberry Pi OS** (Lite is enough). A 32-bit system fails: "CPU architecture 'armv7l' is not supported". |
| Disk | **An SSD** on USB 3 (or an NVMe board), 64 GB or more. **Do not run the database from an SD card.** SD cards wear out and are slow. |
| Power | The official 27 W Raspberry Pi 5 power supply. A weak supply causes random crashes. |
| Cooling | A heatsink with a fan (the Pi 5 active cooler). |
| Network | Wired Ethernet, and a fixed address (a DHCP reservation on your router) |
| Internet | To download images and for the licence check-in |

The `small` profile is the one for a Pi: HR, recruitment, attendance, payroll,
accounting, CRM, inventory, sales orders, chat, documents, activities and reports
([list](../../docs/apps.md)). Do not use `standard`
or `full` on a Pi.

## Steps

### 1. Put the OS on the SSD

On your computer, use **Raspberry Pi Imager**:

1. Choose **Raspberry Pi 5** and **Raspberry Pi OS Lite (64-bit)**.
2. Choose your **SSD** as the storage. (Or flash an SD card, boot, and copy it to the
   SSD later.)
3. In the settings (the gear, or "Edit settings"), set a host name, a user name and
   password, enable **SSH**, and set your Wi-Fi country and time zone.
4. Write it, put the SSD in the Pi and power on.

If the Pi does not boot from the SSD, run `sudo raspi-config`, **Advanced Options**,
**Boot Order**, and choose **USB Boot**.

Connect with SSH: `ssh youruser@hostname.local`. Check that it is 64-bit:

```bash
uname -m          # must print aarch64
```

Give the Pi a fixed address with a DHCP reservation on your router (or see
[office-server](../office-server/README.md)). Decide the address now: the ERP stores
it during setup.

### 2. Update and add swap

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

Add 2 GB of swap as a safety net for busy moments. On Raspberry Pi OS it is managed
by `dphys-swapfile`. Because the OS is on the SSD, the swap file is too:

```bash
sudo dphys-swapfile swapoff
sudo sed -i '/^#\? \?CONF_SWAPSIZE=/d' /etc/dphys-swapfile
echo 'CONF_SWAPSIZE=2048' | sudo tee -a /etc/dphys-swapfile
sudo dphys-swapfile setup
sudo dphys-swapfile swapon
free -h
```

`free -h` should show about 2 GB of swap. Swap does not replace RAM. If the Pi
swaps all the time, the machine is too small for what you run.

### 3. Install Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Log out and in. Check: `docker compose version`. There is no `docker login`
step: the installer signs Docker in to `registry.tarleaks.com` with your licence
key ([how](../../docs/requirements.md#access-to-the-images)).

### 4. Install the ERP

```bash
sudo mkdir -p /opt/tarleaks-erp && sudo chown "$USER": /opt/tarleaks-erp
git clone https://github.com/tarekeesa/Tarleaks-ERP.git /opt/tarleaks-erp
cd /opt/tarleaks-erp
./install.sh --yes --profile small --host 192.168.1.30
```

Use the Pi's own address or name instead of `192.168.1.30`. The first start
downloads the images and prepares the database. **On a Pi allow 10 minutes or more.**
The installer waits up to 10 minutes and then tells you to look at
`./tarleaks doctor`; if so, keep waiting and check `./tarleaks logs auth`.

### 5. Set up the workspace

Open `http://192.168.1.30` from another computer. Setup code: `./tarleaks setup-code`.
Enter the company and the first administrator, and start the trial.

## Keeping it healthy

| Concern | What to do |
|---|---|
| **Temperature** | `vcgencmd measure_temp` should stay under about 80 °C under load. Fit the fan. |
| **Power cuts** | Put the Pi on a small UPS. A sudden power loss can corrupt a database. |
| **Backups** | The Pi's SSD can fail. Back up every night to **another device**: [scheduled-backups](../scheduled-backups/README.md) |
| **Clock** | The Pi 5 has no clock battery by default. After a power cut the clock can be wrong until the network is up, and the licence refuses a clock that is behind. Check `timedatectl` shows `System clock synchronized: yes`. If the ERP says "The clock on this machine is wrong", wait a minute and press **Check again**. An RTC battery for the Pi 5 removes the problem. |
| **Updates** | `sudo apt update && sudo apt full-upgrade`, and `git fetch --tags && git checkout v<release>` then `./tarleaks update` for the ERP |
| **Reboots** | The ERP starts by itself after a reboot. Give it a few minutes. |

## Check it works

- Another computer opens the Pi's address.
- Sign in, upload a document, open it again.
- `./tarleaks doctor` reports no problems, and `free -h` shows memory is not full.

## If something is wrong

| Symptom | Fix |
|---|---|
| Containers restart, the Pi is very slow | Out of memory. Check `free -h` and `docker stats --no-stream`. Make sure the profile is `small` (`grep COMPOSE_PROFILES .env` shows an empty value). |
| "CPU architecture 'armv7l' is not supported" | You installed the 32-bit OS. Reinstall the 64-bit one. |
| Very slow start or disk errors | The database is on an SD card or a slow disk. Move to an SSD. |
| The Pi crashes under load | Check the power supply and cooling |

More: [troubleshooting](../../docs/troubleshooting.md).
