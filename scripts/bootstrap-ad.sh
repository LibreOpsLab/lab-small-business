#!/usr/bin/env bash
# Thin top-level convenience wrapper around samba/scripts/bootstrap-ad.sh. See
# docs/SambaAdmin.md and docs/DeploymentGuide.md#3-samba-ad-domain-controller.
#
# Usage: sudo ./scripts/bootstrap-ad.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../samba/scripts/bootstrap-ad.sh" "$@"
