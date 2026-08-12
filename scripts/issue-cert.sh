#!/usr/bin/env bash
# Thin top-level convenience wrapper around pki/scripts/02-issue-server-cert.sh, so the
# common "issue a cert for X" action doesn't require remembering which subdirectory owns
# PKI tooling. See docs/PKI.md for the full certificate lifecycle.
#
# Usage: ./scripts/issue-cert.sh --cn <common-name> [--san <SAN-list>] [--days N]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../pki/scripts/02-issue-server-cert.sh" "$@"
