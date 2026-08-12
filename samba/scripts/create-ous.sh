#!/usr/bin/env bash
# Creates the LAB OU structure and delegates scoped admin rights to IT-Admins.
# Idempotent: samba-tool ou create fails harmlessly on an existing OU, which we ignore.
# Run on samba-dc01 as root (or any host with samba-tool + admin Kerberos ticket).

set -euo pipefail
DOMAIN_DN="DC=lab,DC=local"

log() { printf '\033[1;34m[create-ous]\033[0m %s\n' "$*"; }

create_ou() {
  local ou_dn="$1"
  if samba-tool ou create "${ou_dn}" 2>/dev/null; then
    log "Created ${ou_dn}"
  else
    log "Already exists (or parent missing): ${ou_dn}"
  fi
}

create_ou "OU=LAB,${DOMAIN_DN}"
create_ou "OU=IT-Admins,OU=LAB,${DOMAIN_DN}"
create_ou "OU=Staff,OU=LAB,${DOMAIN_DN}"
create_ou "OU=Lecturers,OU=Staff,OU=LAB,${DOMAIN_DN}"
create_ou "OU=Students,OU=LAB,${DOMAIN_DN}"
create_ou "OU=Service-Accounts,OU=LAB,${DOMAIN_DN}"
create_ou "OU=Workstations,OU=LAB,${DOMAIN_DN}"
create_ou "OU=Linux,OU=Workstations,OU=LAB,${DOMAIN_DN}"
create_ou "OU=Windows,OU=Workstations,OU=LAB,${DOMAIN_DN}"

log "Delegating scoped administration of OU=LAB to the IT-Admins group (not full Domain Admins)"
# create-groups.sh creates IT-Admins itself; this script only wires up the ACL delegation,
# so it's safe to run create-ous.sh before or after create-groups.sh.
IT_ADMINS_SID="$(samba-tool group getobjectsid IT-Admins 2>/dev/null || true)"
if [[ -n "${IT_ADMINS_SID}" ]]; then
  # Grant generic-all over the OU subtree (CI = container-inherit) to the IT-Admins SID.
  samba-tool dsacls set --objectdn="OU=LAB,${DOMAIN_DN}" \
    --sddl="(A;CI;RPWPCRCCDCLCLORCWOWDSDDTSW;;;${IT_ADMINS_SID})"
  log "Delegated OU=LAB control to IT-Admins (SID ${IT_ADMINS_SID})"
else
  log "IT-Admins group not found yet — re-run this script after create-groups.sh to apply delegation."
fi

log "OU structure ready:"
samba-tool ou list
