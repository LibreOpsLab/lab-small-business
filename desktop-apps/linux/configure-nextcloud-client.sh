#!/usr/bin/env bash
# Pre-seeds the NextCloud desktop client's server URL so the student opens the app and sees
# the login screen immediately (server field pre-filled) instead of typing a hostname. Login
# itself still goes through the real Authentik SSO browser flow — this only removes the
# "what's the server address" friction, not the login step itself (by design: real SSO).
#
# Run as the student's own user (not root) — writes to their own ~/.config.
#
# Usage: ./desktop-apps/linux/configure-nextcloud-client.sh

set -euo pipefail

log() { printf '\033[1;34m[configure-nextcloud-client]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[configure-nextcloud-client][error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -ne 0 ]] || die "Run as the student's own user, not root — this writes to \$HOME/.config."

CONFIG_DIR="${HOME}/.config/Nextcloud"
CONFIG_FILE="${CONFIG_DIR}/nextcloud.cfg"
mkdir -p "${CONFIG_DIR}"

if [[ -f "${CONFIG_FILE}" ]] && grep -q "cloud.lab.internal" "${CONFIG_FILE}" 2>/dev/null; then
  log "Server URL already configured in ${CONFIG_FILE} — nothing to do."
  exit 0
fi

log "Writing default server URL into ${CONFIG_FILE}"
cat >> "${CONFIG_FILE}" <<'EOF'

[General]
overrideServerUrl=https://cloud.lab.internal
EOF

log "Done. Open NextCloud Desktop — the server field will be pre-filled; click through the"
log "Authentik SSO login to finish setup."
