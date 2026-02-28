#!/usr/bin/env bash
# scripts/update.sh — update OS packages and Pi-hole

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.sh
source "$SCRIPT_DIR/config.sh"

require_host

SSH_OPTS=$(ssh_opts)
SSH="ssh $SSH_OPTS $PI_USER@$PI_HOST"

echo "==> Updating OS packages on $PI_HOST..."
$SSH 'sudo apt update && sudo apt upgrade -y'

echo ""
echo "==> Updating Pi-hole..."
$SSH 'sudo pihole -up'

echo ""
echo "==> Refreshing gravity (blocklists)..."
$SSH 'sudo pihole -g'

echo ""
echo "==> Update complete."
$SSH 'pihole version'
