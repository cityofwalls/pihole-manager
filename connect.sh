#!/usr/bin/env bash
# connect.sh — SSH convenience wrapper for the Raspberry Pi
#
# Usage:
#   ./connect.sh                      # interactive SSH session
#   ./connect.sh "sudo pihole status" # run a single command and return

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

require_host

SSH_OPTS=$(ssh_opts)

if [[ $# -eq 0 ]]; then
    # Interactive session
    # shellcheck disable=SC2086
    exec ssh $SSH_OPTS "$PI_USER@$PI_HOST"
else
    # Non-interactive: pass the command through
    # shellcheck disable=SC2086
    exec ssh $SSH_OPTS "$PI_USER@$PI_HOST" "$@"
fi
