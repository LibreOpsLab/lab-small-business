#!/usr/bin/env bash
# Restores a Samba AD DC from a backup produced by backup-ad.sh, onto a freshly installed
# (unprovisioned) Ubuntu 24.04 host. See docs/Backup.md#samba-ad for the full DR narrative.
#
# Usage: sudo ./restore-ad.sh /var/backups/samba-ad/<timestamp>

set -euo pipefail

BACKUP_DIR="${1:-}"
NEW_SERVER_NAME="samba-dc01"

log() { printf '\033[1;34m[restore-ad]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[restore-ad][error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root."
[[ -n "${BACKUP_DIR}" && -d "${BACKUP_DIR}" ]] || die "Usage: $0 <backup-directory>  (e.g. /var/backups/samba-ad/20260101T000000Z)"
[[ -f /var/lib/samba/private/sam.ldb ]] && die "This host already has a provisioned Samba database — restore must target a clean host. Wipe /var/lib/samba first if intentional."

BACKUP_ARCHIVE="$(find "${BACKUP_DIR}" -maxdepth 1 -name 'samba-backup-*.tar.bz2' | head -n1)"
[[ -n "${BACKUP_ARCHIVE}" ]] || die "No samba-backup-*.tar.bz2 found in ${BACKUP_DIR}"

log "Installing Samba packages if not already present"
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq samba smbclient krb5-user winbind chrony

log "Restoring domain from ${BACKUP_ARCHIVE}"
samba-tool domain backup restore \
  --backup-file="${BACKUP_ARCHIVE}" \
  --targetdir=/var/lib/samba \
  --newservername="${NEW_SERVER_NAME}"

log "Installing restored krb5.conf"
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

log "Enabling samba-ad-dc"
systemctl unmask samba-ad-dc
systemctl enable --now samba-ad-dc
systemctl enable --now chrony

log "Restore complete. Running health check..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/health-check.sh" || log "Health check reported issues — review output above before returning this DC to production."

log "If GPOs were backed up separately, restore each with:"
log "  samba-tool gpo restore <GUID> <gpo-backup-dir> --entities=<entities.xml>"
