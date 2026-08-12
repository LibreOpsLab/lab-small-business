#!/usr/bin/env bash
# Thin top-level convenience wrapper around samba/scripts/join-linux-client.sh — run this
# directly on a freshly installed Ubuntu client to join it to LAB.LOCAL. See
# docs/DeploymentGuide.md#7-endpoints and docs/SambaAdmin.md#linux-client-integration-sssd.
#
# Usage: sudo ./scripts/join-linux-client.sh [--user administrator]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../samba/scripts/join-linux-client.sh" "$@"
