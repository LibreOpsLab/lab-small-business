#!/usr/bin/env bash
# Full online backup of the Samba AD DC (SYSVOL, sam.ldb, secrets, DNS) plus every linked
# GPO. Intended to run daily via the systemd timer installed by
# ansible/playbooks/99-backups.yml (lab-samba-backup.timer). Retains 14 days locally.
#
# Run on samba-dc01 as root.

set -euo pipefail

BACKUP_ROOT="/var/backups/samba-ad"
GPO_BACKUP_ROOT="/var/backups/samba-gpo"
RETAIN_DAYS=14
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="${BACKUP_ROOT}/${TIMESTAMP}"

log() { printf '\033[1;34m[backup-ad]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[backup-ad][error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root."

mkdir -p "${DEST}" "${GPO_BACKUP_ROOT}"

log "Running samba-tool domain backup online -> ${DEST}"
samba-tool domain backup online \
  --server=localhost \
  --targetdir="${DEST}" \
  -U administrator

log "Backing up all linked GPOs to ${GPO_BACKUP_ROOT}/${TIMESTAMP}"
mkdir -p "${GPO_BACKUP_ROOT}/${TIMESTAMP}"
if samba-tool gpo listall >/dev/null 2>&1; then
  samba-tool gpo backup --all -o "${GPO_BACKUP_ROOT}/${TIMESTAMP}" 2>/dev/null || \
    log "No GPOs found to back up (or samba-tool gpo backup unsupported on this version) — skipping."
fi

log "Pruning backups older than ${RETAIN_DAYS} days"
find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -mtime "+${RETAIN_DAYS}" -exec rm -rf {} \;
find "${GPO_BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -mtime "+${RETAIN_DAYS}" -exec rm -rf {} \;

log "Backup complete: ${DEST}"
log "Restore procedure: docs/Backup.md#samba-ad, or samba/scripts/restore-ad.sh"
