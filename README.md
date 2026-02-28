# pihole-manager

Management scripts for a Raspberry Pi Zero W running Pi-hole on the home network.

---

## Setup

### 1. Generate an SSH key for this machine

Each machine gets its own key. This way if a machine is lost you can revoke just that key on the Pi without affecting others.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_pi -C "pihole-manager@$(hostname -s)"
```

Add a passphrase when prompted (recommended). `ssh-agent` will cache it so you won't be prompted on every run:

```bash
ssh-add ~/.ssh/id_ed25519_pi
```

### 2. Authorize the key on the Pi

You'll need to authenticate once with the Pi's password to install the public key:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_pi.pub raspberrypi@<PI_HOST>
```

After this, password auth is no longer needed. To disable it entirely on the Pi (optional but recommended):

```bash
./connect.sh "sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo systemctl restart ssh"
```

### 3. Configure .env

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

`.env` is gitignored and never committed.

### Setting up on a new machine

Repeat steps 1 and 2 — generate a fresh key on the new machine and authorize it on the Pi. Do not copy the private key from another machine. To revoke access for a machine, remove its public key from `~/.ssh/authorized_keys` on the Pi:

```bash
./connect.sh  # SSH in
nano ~/.ssh/authorized_keys  # delete the line for the machine being removed
```

---

## Current configuration

| Item | Value |
|---|---|
| Pi model | Raspberry Pi Zero W v1.1 |
| OS | Raspberry Pi OS Lite (Bullseye, 32-bit) |
| Pi-hole version | v6.4 |
| Pi IP address | set in `.env` as `PI_HOST` |
| SSH user | `raspberrypi` |
| SSH auth | Key-based (path set in `.env` as `SSH_KEY`) |
| Router | ASUS |
| Router DNS | Primary: Pi IP (Pi-hole), Fallback: `1.1.1.1` |
| Gravity domains blocked | 78,113 |
| Admin UI | `http://<PI_HOST>/admin` |

The Pi's static IP is managed by a DHCP reservation on the router bound to the Pi's MAC address. If the reservation is ever removed, run `./discover.sh` to find the new IP and update `PI_HOST` in `.env`.

---

## Project structure

```
pihole-manager/
├── .env                # Local secrets — never committed (copy from .env.example)
├── .env.example        # Template for .env
├── config.sh           # Shared config — sources .env, defines helpers
├── discover.sh         # Find the Pi on the network (if IP is unknown)
├── connect.sh          # SSH into the Pi
├── setup.sh            # Install or repair Pi-hole
├── backups/            # Local teleporter backups land here (gitignored)
└── scripts/
    ├── update.sh       # Update OS + Pi-hole + refresh blocklists
    ├── backup.sh       # Export Pi-hole config to ./backups/
    ├── restore.sh      # Restore Pi-hole config from a backup
    └── blocklists.sh   # Interactively manage blocklists
```

---

## Connecting to the Pi

SSH into the Pi directly:

```bash
./connect.sh
```

Run a single command without opening an interactive session:

```bash
./connect.sh "pihole status"
./connect.sh "sudo reboot"
```

---

## Admin web interface

Open `http://<PI_HOST>/admin` in a browser.

- Admin password: set in `.env` as `PIHOLE_PASSWORD`
- Shows live DNS query log, top blocked domains, per-device stats

---

## Updating Pi-hole and the OS

Runs `apt upgrade`, `pihole -up`, and refreshes the blocklist gravity database:

```bash
./scripts/update.sh
```

Run this periodically (monthly is fine for a home setup).

---

## Managing blocklists

Launch the interactive blocklist manager:

```bash
./scripts/blocklists.sh
```

Menu options:
1. **List** — show all current blocklists and their enabled/disabled state
2. **Add** — enter a URL to add a new blocklist, then refreshes gravity
3. **Remove** — remove a blocklist by URL or ID
4. **Refresh** — re-download all blocklists and rebuild the gravity database (`pihole -g`)

### Recommended blocklists to add

| List | URL |
|---|---|
| Steven Black (default, included) | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` |
| oisd (comprehensive) | `https://big.oisd.nl` |
| HaGeZi Multi Pro | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.plus.txt` |
| No-track mobile | `https://raw.githubusercontent.com/notracking/hosts-blocklists/master/hostnames.txt` |

After adding lists, refresh gravity to apply them (`option 4` in the menu, or `./connect.sh "sudo pihole -g"`).

---

## Backing up and restoring

### Create a backup

Exports the full Pi-hole config (blocklists, allow/denylists, settings) as a teleporter archive:

```bash
./scripts/backup.sh
```

Backups are saved to `./backups/pihole-teleporter_YYYYMMDD_HHMMSS.tar.gz`.

### Restore a backup

Lists available backups and lets you choose one to restore:

```bash
./scripts/restore.sh
```

Good practice: run a backup before and after any major change.

---

## If the Pi's IP changes

If the DHCP reservation is ever removed or the Pi ends up on a new network:

```bash
./discover.sh
```

This runs a three-phase scan (mDNS → ARP table → nmap subnet sweep) and offers to update `PI_HOST` in `.env` automatically.

---

## If Pi-hole needs to be reinstalled

```bash
./setup.sh
```

This SSHes into the Pi and either installs Pi-hole from scratch or runs `pihole -r` (repair) if it's already present. It will also offer to set a static IP.

---

## .env reference

All sensitive and environment-specific values live here. See `.env.example` for the full template.

```bash
PI_HOST=<pi ip address>       # Pi's IP address
SSH_KEY=~/.ssh/id_ed25519_pi  # Path to SSH private key
PIHOLE_PASSWORD=<password>    # Pi-hole web admin password (used by backup/restore)
```

---

## Router DNS settings (ASUS)

**LAN → DHCP Server:**
- DNS Server 1: `<PI_HOST>` (Pi-hole)
- DNS Server 2: `1.1.1.1` (fallback — keeps internet working if Pi is down)

**LAN → DHCP Server → Manually Assigned IP:**
- Bind the Pi's MAC address to `<PI_HOST>`

To temporarily disable Pi-hole as the network DNS (e.g., for troubleshooting), replace DNS Server 1 with `1.1.1.1` on the router. Revert when done.
