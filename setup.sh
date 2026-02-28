#!/usr/bin/env bash
# setup.sh — verify/install/reconfigure Pi-hole on the Raspberry Pi
#
# Steps:
#   1. Check Pi-hole is installed
#   2. Install if missing, or repair/reconfigure if present
#   3. Print the Pi's current IP
#   4. Optionally configure a static IP via /etc/dhcpcd.conf

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

require_host

SSH_OPTS=$(ssh_opts)
SSH="ssh $SSH_OPTS $PI_USER@$PI_HOST"

echo "==> Connecting to $PI_USER@$PI_HOST"

# ── Step 1: Check Pi-hole installation ───────────────────────────────────────
echo ""
echo "==> Checking Pi-hole installation..."
pihole_installed=$($SSH 'command -v pihole >/dev/null 2>&1 && echo yes || echo no')

if [[ "$pihole_installed" == "no" ]]; then
    echo "    Pi-hole is NOT installed."
    read -rp "    Install Pi-hole now? [Y/n] " answer
    answer="${answer:-Y}"
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    # ── Step 2a: Install Pi-hole ──────────────────────────────────────────────
    echo ""
    echo "==> Running Pi-hole installer (this will open an interactive setup)..."
    $SSH 'curl -sSL https://install.pi-hole.net | bash'
else
    # ── Step 2b: Detect version and repair ───────────────────────────────────
    echo "    Pi-hole is installed."
    pihole_version=$($SSH 'pihole version 2>/dev/null | head -1' || echo "unknown")
    echo "    Version info: $pihole_version"

    # Determine major version (v5 vs v6)
    major_ver=$($SSH 'pihole version 2>/dev/null | grep -oP "Pi-hole version v\K[0-9]+" | head -1' || echo "5")
    echo "    Detected major version: $major_ver"

    echo ""
    echo "==> Running repair/reconfigure to reset DNS listener and network settings..."
    if [[ "$major_ver" -ge 6 ]]; then
        # Pi-hole v6: use the reconfigure subcommand
        $SSH 'sudo pihole reconfigure' || $SSH 'sudo pihole -r'
    else
        # Pi-hole v5 and earlier
        $SSH 'sudo pihole -r'
    fi
fi

# ── Step 3: Print current IP ─────────────────────────────────────────────────
echo ""
echo "==> Current Pi network info:"
$SSH "hostname -I | tr ' ' '\n' | grep -v '^$' | head -5"
echo ""
echo "    Admin UI: http://$PI_HOST/admin"
echo "    Set your router's DNS server to: $PI_HOST"

# ── Step 4: Optional static IP ───────────────────────────────────────────────
echo ""
read -rp "==> Configure a static IP on the Pi? [y/N] " answer
answer="${answer:-N}"
if [[ "$answer" =~ ^[Yy]$ ]]; then
    read -rp "    Desired static IP (e.g. 192.168.1.10): " static_ip
    read -rp "    Router/Gateway IP (e.g. 192.168.1.1): " gateway_ip
    read -rp "    DNS server IP (e.g. 8.8.8.8): " dns_ip

    echo ""
    echo "==> Writing static IP config to /etc/dhcpcd.conf..."
    $SSH "sudo bash -c 'cat >> /etc/dhcpcd.conf <<EOF

# Static IP configured by pihole-manager/setup.sh
interface eth0
static ip_address=${static_ip}/24
static routers=${gateway_ip}
static domain_name_servers=${dns_ip}
EOF'"
    echo "    Static IP configured. Reboot the Pi to apply: sudo reboot"
    echo "    After reboot, update PI_HOST in config.sh to: $static_ip"
fi

echo ""
echo "==> Setup complete."
