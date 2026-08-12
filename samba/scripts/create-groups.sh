#!/usr/bin/env bash
# Creates the standard lab groups from samba/data/groups.csv. Idempotent.
# Run on samba-dc01 as root (or any host with samba-tool + admin Kerberos ticket).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV="${SCRIPT_DIR}/../data/groups.csv"

log() { printf '\033[1;34m[create-groups]\033[0m %s\n' "$*"; }

[[ -f "${CSV}" ]] || { echo "Missing ${CSV}" >&2; exit 1; }

while IFS=',' read -r name description; do
  [[ "${name}" =~ ^#.*$ || -z "${name}" ]] && continue
  description="${description%\"}"; description="${description#\"}"
  if samba-tool group show "${name}" >/dev/null 2>&1; then
    log "Group already exists: ${name}"
  else
    samba-tool group add "${name}" --description="${description}"
    log "Created group: ${name} (${description})"
  fi
done < "${CSV}"

log "Current groups:"
samba-tool group list
