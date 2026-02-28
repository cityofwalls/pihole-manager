#!/usr/bin/env bash
# config.sh — shared configuration for pihole-manager scripts
# Sensitive values (PI_HOST, SSH_KEY, PIHOLE_PASSWORD) are loaded from .env
# Copy .env.example to .env and fill in your values before running any script.

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if present
if [[ -f "$SCRIPT_ROOT/.env" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_ROOT/.env"
else
    echo "ERROR: .env file not found. Copy .env.example to .env and fill in your values." >&2
    exit 1
fi

# SSH credentials
PI_USER="${PI_USER:-raspberrypi}"
PI_HOST="${PI_HOST:?PI_HOST must be set in .env}"
SSH_KEY="${SSH_KEY:-}"
PIHOLE_PASSWORD="${PIHOLE_PASSWORD:?PIHOLE_PASSWORD must be set in .env}"

# Local backup directory (relative to pihole-manager root)
BACKUP_DIR="${BACKUP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backups}"

# ── helpers ──────────────────────────────────────────────────────────────────

# Build SSH option string from config
ssh_opts() {
    local opts=(-o StrictHostKeyChecking=no -o ConnectTimeout=5)
    [[ -n "$SSH_KEY" ]] && opts+=(-i "$SSH_KEY")
    printf '%s ' "${opts[@]}"
}

# Validate that PI_HOST is set before any operation that needs it
require_host() {
    if [[ -z "$PI_HOST" ]]; then
        echo "ERROR: PI_HOST is not set." >&2
        echo "Run ./discover.sh first, or set PI_HOST in config.sh." >&2
        exit 1
    fi
}

# Pi-hole v6 API: get a session ID (echoes SID, exits 1 on failure)
pihole_api_login() {
    local response sid
    response=$(curl -sSf -X POST "http://$PI_HOST/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"password\":\"$PIHOLE_PASSWORD\"}" 2>&1) || {
        echo "ERROR: Could not reach Pi-hole API at http://$PI_HOST/api/auth" >&2
        return 1
    }
    sid=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['session']['sid'])" 2>/dev/null)
    if [[ -z "$sid" || "$sid" == "None" ]]; then
        echo "ERROR: API login failed — check PIHOLE_PASSWORD in config.sh" >&2
        return 1
    fi
    echo "$sid"
}

# Pi-hole v6 API: log out a session
pihole_api_logout() {
    local sid="$1"
    curl -sSf -X DELETE "http://$PI_HOST/api/auth" \
        -H "X-FTL-SID: $sid" &>/dev/null || true
}
