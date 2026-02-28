#!/usr/bin/env bash
# scripts/restore.sh — restore Pi-hole config from a teleporter archive

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.sh
source "$SCRIPT_DIR/config.sh"

require_host

SSH_OPTS=$(ssh_opts)
SSH="ssh $SSH_OPTS $PI_USER@$PI_HOST"

# ── List available backups ────────────────────────────────────────────────────
echo "==> Available backups in $BACKUP_DIR:"
echo ""

mapfile -t backups < <(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true)

if [[ ${#backups[@]} -eq 0 ]]; then
    echo "  No backups found in $BACKUP_DIR"
    echo "  Run ./scripts/backup.sh first."
    exit 1
fi

for i in "${!backups[@]}"; do
    size=$(ls -lh "${backups[$i]}" | awk '{print $5}')
    mtime=$(ls -l "${backups[$i]}" | awk '{print $6, $7, $8}')
    printf "  [%d] %s  (%s, %s)\n" "$((i+1))" "$(basename "${backups[$i]}")" "$size" "$mtime"
done

echo ""
read -rp "Select backup to restore [1-${#backups[@]}]: " selection

if ! [[ "$selection" =~ ^[0-9]+$ ]] || \
   (( selection < 1 )) || \
   (( selection > ${#backups[@]} )); then
    echo "Invalid selection."
    exit 1
fi

selected="${backups[$((selection-1))]}"

echo ""
echo "==> Restoring: $(basename "$selected")"
read -rp "    This will overwrite current Pi-hole config. Continue? [y/N] " confirm
confirm="${confirm:-N}"
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ── Detect version and restore ────────────────────────────────────────────────
echo ""
major_ver=$($SSH 'pihole version 2>/dev/null | grep -oE "v[0-9]+" | head -1 | tr -d v' || echo "5")

if [[ "$major_ver" -ge 6 ]]; then
    # Pi-hole v6: upload via REST API multipart form
    echo "==> Authenticating with Pi-hole API..."
    sid=$(pihole_api_login)

    echo "==> Uploading and importing backup via API..."
    http_code=$(curl -sSf \
        -X POST "http://$PI_HOST/api/teleporter" \
        -H "X-FTL-SID: $sid" \
        -F "file=@$selected;type=application/gzip" \
        -o /dev/null \
        -w "%{http_code}")

    pihole_api_logout "$sid"

    if [[ "$http_code" != "200" ]]; then
        echo "ERROR: Restore failed (HTTP $http_code)" >&2
        exit 1
    fi
else
    # Pi-hole v5: scp then CLI import
    remote_file="/tmp/$(basename "$selected")"
    echo "==> Uploading backup to Pi..."
    # shellcheck disable=SC2086
    scp $SSH_OPTS "$selected" "$PI_USER@$PI_HOST:$remote_file"
    echo "==> Importing on Pi..."
    $SSH "sudo pihole -a -i '$remote_file'"
    $SSH "rm -f '$remote_file'" 2>/dev/null || true
fi

echo ""
echo "==> Restore complete. Pi-hole may restart — allow a few seconds."
echo "    Admin UI: http://$PI_HOST/admin"
