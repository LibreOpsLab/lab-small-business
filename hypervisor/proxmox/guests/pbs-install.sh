#!/usr/bin/env bash
# Install Proxmox Backup Server inside the pbs01 container that Terraform created.
#
# Run it from the Proxmox host (the container id is 150, see ../terraform/lxc.tf):
#   pct exec 150 -- bash -s < pbs-install.sh
#
# What it does: adds the no-subscription PBS repository, installs proxmox-backup-server,
# creates the datastore on the separate mount point, and prints the fingerprint the Proxmox
# host needs to trust this server. It does not set a password: do that afterwards (below).
#
# Not yet run on a real container: confirm the keyring URLs against the Proxmox documentation
# for your Debian version, and verify the key fingerprint before trusting it.

set -euo pipefail

log()  { printf '\033[1;34m[pbs]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[pbs][error]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root inside the container."

DATASTORE_NAME="lab"
DATASTORE_PATH="/mnt/datastore/lab"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
log "Debian ${CODENAME}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

case "${CODENAME}" in
  bookworm)
    curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
      -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
    echo "deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription" \
      > /etc/apt/sources.list.d/pbs-no-subscription.list
    ;;
  trixie)
    curl -fsSL https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
      -o /usr/share/keyrings/proxmox-archive-keyring.gpg
    cat > /etc/apt/sources.list.d/pbs-no-subscription.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    ;;
  *) die "Unsupported Debian release '${CODENAME}'. Supported: bookworm, trixie." ;;
esac

apt-get update
apt-get install -y proxmox-backup-server

# A container mount point is owned by container root. PBS runs as the "backup" user.
[ -d "${DATASTORE_PATH}" ] || die "${DATASTORE_PATH} is missing: was the container created by ../terraform/lxc.tf?"
chown backup:backup "${DATASTORE_PATH}"

if proxmox-backup-manager datastore list | grep -q "^${DATASTORE_NAME} "; then
  log "datastore ${DATASTORE_NAME} already exists"
else
  proxmox-backup-manager datastore create "${DATASTORE_NAME}" "${DATASTORE_PATH}"
fi

log "Installed. Next steps:"
log "  1. Set a password for the backup user. Inside the container, run:"
log "       proxmox-backup-manager user create backup@pbs --password '<choose one>'"
log "       proxmox-backup-manager acl update /datastore/${DATASTORE_NAME} DatastoreBackup --auth-id backup@pbs"
log "  2. Fingerprint for the Proxmox host:"
proxmox-backup-manager cert info | grep -i fingerprint || true
log "  3. On the Proxmox host, add it as storage:"
log "       pvesm add pbs pbs01 --server 10.10.10.50 --datastore ${DATASTORE_NAME} \\"
log "         --username backup@pbs --password '<the password>' --fingerprint '<fingerprint>'"
log "  4. Web interface: https://10.10.10.50:8007"
