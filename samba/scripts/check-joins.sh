#!/usr/bin/env bash
# Lists which machines have a computer account in the domain, from the DC's point of view.
# This is the one check that covers EVERY machine, Windows and Linux, joined by Ansible or by
# hand. A machine that is not here is not joined.
#
# Usage (on samba-dc01, as root):
#   sudo ./check-joins.sh                      # core machines required, optional ones reported
#   sudo ./check-joins.sh --require PBS01      # also require an optional machine
#
# Exit code: 0 = every required machine is joined, 1 = at least one is missing.

set -euo pipefail

log()  { printf '\033[1;34m[check-joins]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[check-joins][error]\033[0m %s\n' "$*" >&2; exit 1; }

# Computer account names are the hostname in upper case. Core machines are part of every build.
REQUIRED=(DOCKER01 AUTHENTIK01 LINUX-CLIENT01 WIN-CLIENT01)
# Optional machines exist in some scenarios only (Proxmox guests, the scanner, a Windows Server).
OPTIONAL=(WINSRV01 PBS01 SCANNER01)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require)
      [[ $# -ge 2 ]] || die "--require needs a machine name"
      REQUIRED+=("${2^^}"); shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

command -v samba-tool >/dev/null 2>&1 || die "samba-tool not found: run this on the domain controller."

# samba-tool prints one account per line with a trailing dollar sign, for example DOCKER01$
JOINED="$(samba-tool computer list | sed 's/\$$//' | tr '[:lower:]' '[:upper:]')"

missing=0
log "Computer accounts in the domain:"
printf '%s\n' "${JOINED}" | sed 's/^/    /'
echo

for name in "${REQUIRED[@]}"; do
  if grep -qx "${name}" <<<"${JOINED}"; then
    log "OK       ${name}"
  else
    printf '\033[1;31m[check-joins]\033[0m MISSING  %s (required)\n' "${name}"
    missing=1
  fi
done

for name in "${OPTIONAL[@]}"; do
  # Skip optional machines that were promoted to required with --require.
  if printf '%s\n' "${REQUIRED[@]}" | grep -qx "${name}"; then continue; fi
  if grep -qx "${name}" <<<"${JOINED}"; then
    log "OK       ${name} (optional)"
  else
    log "absent   ${name} (optional)"
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  die "At least one required machine is not joined. See docs/DomainJoin.md."
fi
log "Every required machine is joined."
