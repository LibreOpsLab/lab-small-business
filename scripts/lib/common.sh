#!/usr/bin/env bash
# Shared helpers for scripts/*.sh — sourced, not executed directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log()   { printf '\033[1;34m[lab]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[lab][warn]\033[0m %s\n' "$*" >&2; }
error() { printf '\033[1;31m[lab][error]\033[0m %s\n' "$*" >&2; }
die()   { error "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

backup_volume() {
  # backup_volume <volume-name> <dest-dir>
  local volume="$1" dest="$2"
  mkdir -p "${dest}"
  docker run --rm -v "${volume}:/data" -v "${dest}:/backup" alpine \
    tar czf "/backup/${volume}-$(date +%F).tar.gz" -C /data .
}
