#!/usr/bin/env bash
# Provisions a fresh Ubuntu Server 24.04 host as the LAB.INTERNAL Active Directory Domain
# Controller (samba-dc01, 10.10.0.10). Idempotent-ish: refuses to re-provision an already
# provisioned DC (samba-tool provisioning is not safely re-runnable).
#
# Must be run as root on the target DC. See docs/SambaAdmin.md and docs/DeploymentGuide.md.

set -euo pipefail

DOMAIN="lab.internal"
REALM="LAB.INTERNAL"
NETBIOS="LAB"
DC_IP="10.10.0.10"
ADMIN_PASSWORD="${SAMBA_ADMIN_PASSWORD:-}"

log()  { printf '\033[1;34m[bootstrap-ad]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[bootstrap-ad][error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root (sudo $0)."

if [[ -f /var/lib/samba/private/sam.ldb ]]; then
  log "This host already has a provisioned Samba database (/var/lib/samba/private/sam.ldb) — refusing to re-provision."
  log "To start over, wipe /var/lib/samba and /etc/krb5.conf first (destructive)."
  exit 0
fi

if [[ -z "${ADMIN_PASSWORD}" ]]; then
  read -r -s -p "Administrator password for the new domain (min 12 chars, complex): " ADMIN_PASSWORD
  echo
fi

log "Setting hostname to samba-dc01"
hostnamectl set-hostname samba-dc01

log "Fixing /etc/hosts for the DC's own FQDN"
if ! grep -q "samba-dc01.${DOMAIN}" /etc/hosts; then
  echo "${DC_IP} samba-dc01.${DOMAIN} samba-dc01" >> /etc/hosts
fi

log "Disabling systemd-resolved's stub listener on :53 (Samba needs the port)"
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/no-stub.conf <<EOF
[Resolve]
DNSStubListener=no
EOF
systemctl restart systemd-resolved || true
rm -f /etc/resolv.conf
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
search ${DOMAIN}
EOF

log "Installing Samba AD DC packages (this will prompt debconf for Kerberos realm — answer ${REALM})"
DEBIAN_FRONTEND=noninteractive apt-get update -qq
echo "krb5-config krb5-config/default_realm string ${REALM}" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  samba smbclient krb5-user krb5-kdc winbind libnss-winbind libpam-winbind chrony ufw

log "Removing distro smb.conf so samba-tool provision can generate a clean one"
[[ -f /etc/samba/smb.conf ]] && mv /etc/samba/smb.conf /etc/samba/smb.conf.pre-provision.bak

log "Stopping/masking standalone smbd/nmbd/winbind — samba-ad-dc replaces them"
systemctl disable --now smbd nmbd winbind 2>/dev/null || true
systemctl mask smbd nmbd winbind 2>/dev/null || true

log "Provisioning the ${DOMAIN} / ${REALM} domain (functional level 2016)"
samba-tool domain provision \
  --realm="${REALM}" \
  --domain="${NETBIOS}" \
  --server-role=dc \
  --dns-backend=SAMBA_INTERNAL \
  --host-ip="${DC_IP}" \
  --function-level=2016 \
  --adminpass="${ADMIN_PASSWORD}"

log "Installing generated krb5.conf as the system config"
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

log "Unmasking and enabling the unified samba-ad-dc service"
systemctl unmask samba-ad-dc
systemctl enable --now samba-ad-dc

log "Enabling chrony NTP (Samba AD requires authoritative time on the DC)"
systemctl enable --now chrony

log "Configuring ufw for AD DC traffic (53, 88, 123, 135, 137-139, 389, 445, 464, 636, 3268-3269)"
ufw allow 53 comment 'DNS'
ufw allow 88 comment 'Kerberos'
ufw allow 123/udp comment 'NTP'
ufw allow 135 comment 'RPC endpoint mapper'
ufw allow 137:138/udp comment 'NetBIOS'
ufw allow 139 comment 'NetBIOS session'
ufw allow 389 comment 'LDAP'
ufw allow 445 comment 'SMB'
ufw allow 464 comment 'Kerberos kpasswd'
ufw allow 636 comment 'LDAPS'
ufw allow 3268:3269/tcp comment 'Global Catalog'
ufw --force enable

log "Setting default domain password policy"
samba-tool domain passwordsettings set --complexity=on
samba-tool domain passwordsettings set --history-length=24
samba-tool domain passwordsettings set --min-pwd-length=12
samba-tool domain passwordsettings set --max-pwd-age=90
samba-tool domain passwordsettings set --account-lockout-threshold=5
samba-tool domain passwordsettings set --account-lockout-duration=15
samba-tool domain passwordsettings set --reset-account-lockout-after=15

log "Domain provisioned. Next: samba/scripts/create-ous.sh, create-groups.sh, create-users.sh, health-check.sh"
