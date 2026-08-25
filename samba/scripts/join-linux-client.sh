#!/usr/bin/env bash
# Joins an Ubuntu Desktop/Server host to LAB.INTERNAL via SSSD (not winbind — SSSD is the
# modern, actively-maintained path and integrates better with polkit/GDM).
#
# Usage: sudo ./join-linux-client.sh [--user administrator]
# Assumes DNS is already correctly pointed at 10.10.10.10 (via DHCP option 6 from pfSense).

set -euo pipefail

JOIN_USER="administrator"
[[ "${1:-}" == "--user" ]] && JOIN_USER="$2"

DOMAIN="lab.internal"

log() { printf '\033[1;34m[join-linux-client]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[join-linux-client][error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root (sudo $0)."

log "Verifying DNS resolves ${DOMAIN} to the DC before attempting to join"
if ! host -t SRV "_kerberos._udp.${DOMAIN}" >/dev/null 2>&1; then
  die "Cannot resolve _kerberos._udp.${DOMAIN} — check /etc/resolv.conf points at 10.10.10.10. See docs/Troubleshooting.md#dns."
fi

log "Installing SSSD + realmd + adcli + Kerberos client packages"
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  sssd sssd-tools realmd adcli krb5-user packagekit libnss-sss libpam-sss

log "Joining ${DOMAIN} as ${JOIN_USER} (you will be prompted for the domain password)"
realm join --client-software=sssd --os-name="Ubuntu" \
  --computer-ou="OU=Linux,OU=Workstations,OU=LAB,DC=lab,DC=internal" \
  -U "${JOIN_USER}" "${DOMAIN}"

log "Installing lab-tuned sssd.conf (short usernames, home dir auto-create, enumerate on for teaching)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../templates/sssd.conf.j2" ]]; then
  # Static substitution here since this script may run before Ansible does; ansible/roles/sssd_client
  # re-renders the same template with full Jinja2 support on subsequent config-managed runs.
  sed -e 's/{{ *lab_domain[^}]*}}/lab.internal/' \
      -e 's/{{ *lab_realm[^}]*}}/LAB.INTERNAL/' \
      "${SCRIPT_DIR}/../templates/sssd.conf.j2" > /etc/sssd/sssd.conf
  chmod 600 /etc/sssd/sssd.conf
fi

log "Enabling home directory auto-creation via pam_mkhomedir"
pam-auth-update --enable mkhomedir

log "Restarting SSSD"
systemctl restart sssd

log "Verifying: id administrator@${DOMAIN}"
id "administrator@${DOMAIN}" || die "Join appears to have succeeded but SSSD lookup failed — check journalctl -u sssd."

log "Join complete. Domain users can now log in with short usernames (e.g. student01)."
log "Next: run ansible/playbooks/05-pki-trust.yml against this host so HTTPS to *.lab.internal is trusted."
