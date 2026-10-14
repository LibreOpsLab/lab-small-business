#!/usr/bin/env bash
# Extends the Samba AD schema so Windows LAPS has somewhere to store each machine's local
# administrator password (the msLAPS-* attributes). Run ONCE, on samba-dc01, as root.
#
# A schema extension CANNOT BE UNDONE. This script therefore backs up the domain first, refuses
# to run without --yes, and skips attributes that already exist so a second run is harmless.
#
# You supply the two LDIF files. They define the Microsoft LAPS schema (attribute definitions
# and the Computer-class change). They are not stored in this repo because they are Microsoft's
# schema definitions, and a wrong copy here would be copied into every lab. Get them from the
# Samba-AD documentation page "Configuring LAPS for Samba-AD"
# (https://samba.tranquil.it/doc/en/samba_advanced_methods-samba_configure_laps.html), read them,
# and replace the example domain in them with DC=lab,DC=internal.
#
# Usage:
#   sudo ./extend-schema-laps.sh --ldif1 laps-1.ldif --ldif2 laps-2.ldif --yes
#   sudo ./extend-schema-laps.sh --ldif1 laps-1.ldif --ldif2 laps-2.ldif --dry-run
#
# Not yet run on a lab DC: do it on a snapshot first. See docs/LAPS.md.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAM_LDB="/var/lib/samba/private/sam.ldb"
SCHEMA_DN="CN=Schema,CN=Configuration,DC=lab,DC=internal"
PROBE_ATTRIBUTE="msLAPS-Password"

log() { printf '\033[1;34m[laps-schema]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[laps-schema][error]\033[0m %s\n' "$*" >&2; exit 1; }

LDIF1="" LDIF2="" YES=0 DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ldif1)   [[ $# -ge 2 ]] || die "--ldif1 needs a file"; LDIF1="$2"; shift 2 ;;
    --ldif2)   [[ $# -ge 2 ]] || die "--ldif2 needs a file"; LDIF2="$2"; shift 2 ;;
    --yes)     YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || die "Run as root (sudo $0 ...)."
command -v ldbadd >/dev/null 2>&1 && command -v samba-tool >/dev/null 2>&1 \
  || die "ldbadd and samba-tool are required: run this on the domain controller."
[[ -n "${LDIF1}" && -n "${LDIF2}" ]] || die "Both --ldif1 and --ldif2 are required (see the header of this script)."
[[ -r "${LDIF1}" && -r "${LDIF2}" ]] || die "Cannot read the LDIF files."
[[ -r "${SAM_LDB}" ]] || die "${SAM_LDB} not found: is this a Samba AD DC?"

# The files must be written for THIS domain, or the attributes land in the wrong place.
if ! grep -q 'DC=lab,DC=internal' "${LDIF1}" "${LDIF2}"; then
  die "The LDIF files do not mention DC=lab,DC=internal. Replace the example domain in them first."
fi

# Only the holder of the Schema Master role may change the schema.
SCHEMA_MASTER="$(samba-tool fsmo show | awk -F': ' '/SchemaMasterRole/ {print $2}')"
THIS_HOST="$(hostname -s)"
if ! grep -qi "CN=${THIS_HOST}," <<<"${SCHEMA_MASTER}"; then
  die "This host (${THIS_HOST}) is not the Schema Master (${SCHEMA_MASTER}). Run it there."
fi

# Already done?
if ldbsearch -H "${SAM_LDB}" -b "${SCHEMA_DN}" "(lDAPDisplayName=${PROBE_ATTRIBUTE})" dn 2>/dev/null | grep -q '^dn:'; then
  log "${PROBE_ATTRIBUTE} already exists in the schema: nothing to do."
  exit 0
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log "[dry-run] would back up the domain, then run:"
  log "  ldbadd    -H ${SAM_LDB} --option=\"dsdb:schema update allowed\"=true ${LDIF1}"
  log "  ldbmodify -H ${SAM_LDB} --option=\"dsdb:schema update allowed\"=true ${LDIF2}"
  log "  systemctl restart samba-ad-dc"
  exit 0
fi

[[ "${YES}" -eq 1 ]] || die "A schema extension cannot be undone. Re-run with --yes once you have read the LDIF files and have a VM snapshot."

log "Backing up the domain first (a restore is the only way back)"
"${SCRIPT_DIR}/backup-ad.sh"

# Two steps so the new attributes are committed before the Computer class refers to them.
log "Step 1: add the attribute definitions"
ldbadd -H "${SAM_LDB}" --option="dsdb:schema update allowed"=true "${LDIF1}"

log "Step 2: add the attributes to the Computer class"
ldbmodify -H "${SAM_LDB}" --option="dsdb:schema update allowed"=true "${LDIF2}"

log "Restarting samba-ad-dc"
systemctl restart samba-ad-dc

log "Done. Next, from a Windows machine as a Domain Admin: scripts/windows/Enable-WindowsLaps.ps1"
