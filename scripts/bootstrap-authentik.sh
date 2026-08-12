#!/usr/bin/env bash
# Thin top-level convenience wrapper around authentik/scripts/bootstrap-authentik.sh. See
# docs/AuthentikAdmin.md and authentik/README.md.
#
# Usage: ./scripts/bootstrap-authentik.sh [--sync-secrets]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../authentik/scripts/bootstrap-authentik.sh" "$@"
