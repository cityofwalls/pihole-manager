#!/usr/bin/env bash
# scripts/backup.sh — backup Pi-hole config via teleporter

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.sh
source "$SCRIPT_DIR/config.sh"

require_host

SSH_OPTS=$(ssh_opts)
SSH="ssh $SSH_OPTS $PI_USER@$PI_HOST"

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOCAL_FILE="$BACKUP_DIR/pihole-teleporter_${TIMESTAMP}.tar.gz"

echo "==> Detecting Pi-hole version..."
major_ver=$($SSH 'pihole version 2>/dev/null | grep -oE "v[0-9]+" | head -1 | tr -d v' || echo "5")
echo "    Major version: $major_ver"

echo "==> Generating teleporter backup..."

if [[ "$major_ver" -ge 6 ]]; then
    # Pi-hole v6: use REST API
    echo "    Authenticating with Pi-hole API..."
    sid=$(pihole_api_login)

    echo "    Downloading teleporter archive..."
    http_code=$(curl -sSf \
        -H "X-FTL-SID: $sid" \
        "http://$PI_HOST/api/teleporter" \
        -o "$LOCAL_FILE" \
        -w "%{http_code}")

    pihole_api_logout "$sid"

    if [[ "$http_code" != "200" ]] || [[ ! -s "$LOCAL_FILE" ]]; then
        echo "ERROR: Teleporter export failed (HTTP $http_code)" >&2
        rm -f "$LOCAL_FILE"
        exit 1
    fi
else
    # Pi-hole v5: use CLI
    REMOTE_FILE="/tmp/pihole-teleporter_${TIMESTAMP}.tar.gz"
    $SSH "cd /tmp && pihole -a -t"
    REMOTE_FILE=$($SSH 'ls -t /tmp/pi-hole-teleporter_*.tar.gz 2>/dev/null | head -1' || echo "")
    if [[ -z "$REMOTE_FILE" ]]; then
        echo "ERROR: Could not locate teleporter archive on Pi." >&2
        exit 1
    fi
    # shellcheck disable=SC2086
    scp $SSH_OPTS "$PI_USER@$PI_HOST:$REMOTE_FILE" "$LOCAL_FILE"
    $SSH "rm -f '$REMOTE_FILE'" 2>/dev/null || true
fi

echo ""
echo "==> Backup saved to: $LOCAL_FILE"
ls -lh "$LOCAL_FILE"
