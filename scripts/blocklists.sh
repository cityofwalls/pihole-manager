#!/usr/bin/env bash
# scripts/blocklists.sh — interactively manage Pi-hole blocklists

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.sh
source "$SCRIPT_DIR/config.sh"

require_host

SSH_OPTS=$(ssh_opts)
SSH="ssh $SSH_OPTS $PI_USER@$PI_HOST"

# Detect Pi-hole major version once
MAJOR_VER=$($SSH 'pihole version 2>/dev/null | grep -oP "Pi-hole version v\K[0-9]+" | head -1' || echo "5")

# ── Helper: list blocklists ───────────────────────────────────────────────────
list_blocklists() {
    echo ""
    echo "Current blocklists:"
    echo "-------------------"
    if [[ "$MAJOR_VER" -ge 6 ]]; then
        # v6: query via REST API
        $SSH "curl -sSf http://localhost/api/lists?type=block 2>/dev/null \
            | python3 -c \"
import sys, json
data = json.load(sys.stdin)
lists = data.get('lists', [])
for i, l in enumerate(lists, 1):
    status = 'enabled' if l.get('enabled') else 'DISABLED'
    print(f'  [{i}] {l[\\\"address\\\"]}  ({status})')
\" 2>/dev/null" || \
        $SSH "sqlite3 /etc/pihole/gravity.db 'SELECT id, address, enabled FROM adlist ORDER BY id' 2>/dev/null \
            | awk -F'|' '{printf \"  [%s] %s  (%s)\\n\", \$1, \$2, (\$3==\"1\" ? \"enabled\" : \"DISABLED\")}'"
    else
        # v5: direct sqlite3 query
        $SSH "sqlite3 /etc/pihole/gravity.db \
            'SELECT id, address, enabled FROM adlist ORDER BY id' 2>/dev/null \
            | awk -F'|' '{printf \"  [%s] %s  (%s)\\n\", \$1, \$2, (\$3==\"1\" ? \"enabled\" : \"DISABLED\")}'" \
        || $SSH "pihole -a -b list 2>/dev/null || echo '  (Unable to retrieve blocklists)'"
    fi
    echo ""
}

# ── Helper: add a blocklist ───────────────────────────────────────────────────
add_blocklist() {
    read -rp "  Enter blocklist URL to add: " url
    if [[ -z "$url" ]]; then
        echo "  No URL entered."; return
    fi

    echo "  Adding: $url"
    if [[ "$MAJOR_VER" -ge 6 ]]; then
        $SSH "curl -sSf -X POST http://localhost/api/lists \
            -H 'Content-Type: application/json' \
            -d '{\"address\":\"$url\",\"type\":\"block\",\"enabled\":true,\"comment\":\"added by pihole-manager\"}'" \
        && echo "  Added via API." \
        || $SSH "pihole -a -b '$url'"
    else
        $SSH "pihole -a -b '$url'"
    fi

    echo "  Refreshing gravity..."
    $SSH "pihole -g"
}

# ── Helper: remove a blocklist ────────────────────────────────────────────────
remove_blocklist() {
    list_blocklists
    read -rp "  Enter blocklist URL (or ID from list above) to remove: " target
    if [[ -z "$target" ]]; then
        echo "  No input."; return
    fi

    echo "  Removing: $target"
    if [[ "$MAJOR_VER" -ge 6 ]]; then
        # Try by URL first via API
        $SSH "curl -sSf -X DELETE 'http://localhost/api/lists/$(python3 -c \"import urllib.parse; print(urllib.parse.quote('$target', safe=''))\")'  2>/dev/null" \
        || $SSH "pihole -a -b -d '$target' 2>/dev/null" \
        || $SSH "sqlite3 /etc/pihole/gravity.db \"DELETE FROM adlist WHERE address='$target' OR id='$target'\""
    else
        $SSH "pihole -a -b -d '$target' 2>/dev/null" \
        || $SSH "sqlite3 /etc/pihole/gravity.db \"DELETE FROM adlist WHERE address='$target' OR id='$target'\""
    fi

    echo "  Refreshing gravity..."
    $SSH "pihole -g"
}

# ── Helper: refresh gravity ───────────────────────────────────────────────────
refresh_gravity() {
    echo "  Refreshing all blocklists (pihole -g)..."
    $SSH "pihole -g"
    echo "  Done."
}

# ── Main menu loop ────────────────────────────────────────────────────────────
while true; do
    echo ""
    echo "Pi-hole Blocklist Manager  (Pi-hole v${MAJOR_VER}x, host: $PI_HOST)"
    echo "=================================================="
    echo "  1) List current blocklists"
    echo "  2) Add a blocklist"
    echo "  3) Remove a blocklist"
    echo "  4) Refresh all blocklists (pihole -g)"
    echo "  q) Quit"
    echo ""
    read -rp "Choose an option: " choice

    case "$choice" in
        1) list_blocklists ;;
        2) add_blocklist ;;
        3) remove_blocklist ;;
        4) refresh_gravity ;;
        q|Q) echo "Bye."; exit 0 ;;
        *) echo "  Unknown option: $choice" ;;
    esac
done
