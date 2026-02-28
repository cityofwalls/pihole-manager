#!/usr/bin/env bash
# discover.sh — find the Raspberry Pi on the local network
# Three-phase discovery: mDNS → ARP table → nmap sweep

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Raspberry Pi MAC address OUI prefixes (lowercase, colon-separated)
PI_OUIS=("b8:27:eb" "dc:a6:32" "e4:5f:01")

found_ip=""
found_via=""

# ── Phase 1: mDNS ────────────────────────────────────────────────────────────
echo "Phase 1: Trying mDNS (raspberrypi.local)..."
if mdns_result=$(ping -c1 -W2 raspberrypi.local 2>/dev/null); then
    found_ip=$(echo "$mdns_result" | grep -oE '\(([0-9]{1,3}\.){3}[0-9]{1,3}\)' | tr -d '()' | head -1)
    [[ -n "$found_ip" ]] && found_via="mDNS"
fi

# ── Phase 2: ARP table ───────────────────────────────────────────────────────
if [[ -z "$found_ip" ]]; then
    echo "Phase 2: Scanning ARP table for known Pi MAC OUIs..."
    arp_output=$(arp -a 2>/dev/null || true)
    for oui in "${PI_OUIS[@]}"; do
        # arp -a output format: hostname (ip) at mac [ether] on iface
        match=$(echo "$arp_output" | grep -i "$oui" | grep -oE '\(([0-9]{1,3}\.){3}[0-9]{1,3}\)' | tr -d '()' | head -1 || true)
        if [[ -n "$match" ]]; then
            found_ip="$match"
            found_via="ARP (OUI $oui)"
            break
        fi
    done
fi

# ── Phase 3: nmap subnet sweep ───────────────────────────────────────────────
if [[ -z "$found_ip" ]]; then
    echo "Phase 3: Falling back to nmap subnet sweep..."
    if ! command -v nmap &>/dev/null; then
        echo "  nmap not found. Install with: brew install nmap (macOS) or apt install nmap (Linux)"
    else
        # Detect local subnet from default route interface
        # Prefer the IP on the same interface as the default route
        default_iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' | head -1 \
            || ip route show default 2>/dev/null | awk '/dev/{print $5}' | head -1 || true)
        local_ip=""
        if [[ -n "$default_iface" ]]; then
            local_ip=$(ifconfig "$default_iface" 2>/dev/null \
                | grep -oE 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' \
                | grep -v '127\.' \
                | awk '{print $2}' \
                | head -1 || true)
        fi
        # Fallback: first non-loopback IP
        if [[ -z "$local_ip" ]]; then
            local_ip=$(ifconfig 2>/dev/null \
                | grep -oE 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' \
                | grep -v '127\.' \
                | awk '{print $2}' \
                | head -1 \
                || ip -4 route get 1 2>/dev/null | grep -oP 'src \K\S+' || true)
        fi

        if [[ -z "$local_ip" ]]; then
            echo "  Could not determine local IP address. Set PI_HOST manually in config.sh."
        else
            subnet=$(echo "$local_ip" | cut -d. -f1-3).0
            echo "  Scanning $subnet/24 (this may take ~30 seconds)..."
            nmap_out=$(nmap -sn --open "$subnet/24" -oG - 2>/dev/null || true)
            for oui in "${PI_OUIS[@]}"; do
                # nmap -oG output includes MAC addresses
                match=$(echo "$nmap_out" | grep -i "$oui" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
                if [[ -n "$match" ]]; then
                    found_ip="$match"
                    found_via="nmap (OUI $oui)"
                    break
                fi
            done
        fi
    fi
fi

# ── Result ───────────────────────────────────────────────────────────────────
echo ""
if [[ -z "$found_ip" ]]; then
    echo "Could not find a Raspberry Pi on the network."
    echo ""
    echo "Try:"
    echo "  1. Make sure the Pi is powered on and connected."
    echo "  2. Install nmap: brew install nmap"
    echo "  3. Set PI_HOST manually in config.sh."
    exit 1
fi

echo "Found Raspberry Pi at: $found_ip  (via $found_via)"
echo ""

# Offer to write PI_HOST back into .env
read -rp "Write PI_HOST=$found_ip to .env? [Y/n] " answer
answer="${answer:-Y}"
if [[ "$answer" =~ ^[Yy]$ ]]; then
    env_file="$SCRIPT_DIR/.env"
    if [[ ! -f "$env_file" ]]; then
        cp "$SCRIPT_DIR/.env.example" "$env_file"
    fi
    if grep -q '^PI_HOST=' "$env_file"; then
        sed -i.bak "s|^PI_HOST=.*|PI_HOST=$found_ip|" "$env_file"
        rm -f "$env_file.bak"
    else
        echo "PI_HOST=$found_ip" >> "$env_file"
    fi
    echo "Updated .env: PI_HOST=$found_ip"
else
    echo "Skipped. To set manually, edit .env and set PI_HOST=$found_ip"
fi
