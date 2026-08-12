#!/usr/bin/env bash
# Creates the seed lab users from samba/data/users.csv, places them in the right OU, and
# adds them to their groups. Idempotent. Prompts once for a shared initial password unless
# SAMBA_SEED_PASSWORD is set in the environment (useful for non-interactive Ansible runs).
#
# Run on samba-dc01 as root (or any host with samba-tool + admin Kerberos ticket).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV="${SCRIPT_DIR}/../data/users.csv"
DOMAIN_DN="DC=lab,DC=internal"

log() { printf '\033[1;34m[create-users]\033[0m %s\n' "$*"; }

[[ -f "${CSV}" ]] || { echo "Missing ${CSV}" >&2; exit 1; }

SEED_PASSWORD="${SAMBA_SEED_PASSWORD:-}"
if [[ -z "${SEED_PASSWORD}" ]]; then
  read -r -s -p "Initial password for seeded accounts (users must change at next logon): " SEED_PASSWORD
  echo
fi

while IFS=',' read -r username given surname ou groups description; do
  [[ "${username}" =~ ^#.*$ || -z "${username}" ]] && continue
  ou="${ou%\"}"; ou="${ou#\"}"
  description="${description%\"}"; description="${description#\"}"

  if samba-tool user show "${username}" >/dev/null 2>&1; then
    log "User already exists: ${username}"
  else
    samba-tool user create "${username}" "${SEED_PASSWORD}" \
      --given-name="${given}" --surname="${surname}" \
      --userou="${ou}" \
      --mail-address="${username}@lab.internal" \
      --description="${description}" \
      --must-change-at-next-login
    log "Created user: ${username} in ${ou},${DOMAIN_DN} (mail: ${username}@lab.internal)"
  fi

  if [[ -n "${groups}" ]]; then
    IFS='|' read -r -a group_list <<< "${groups}"
    for g in "${group_list[@]}"; do
      [[ -z "${g}" ]] && continue
      if samba-tool group listmembers "${g}" 2>/dev/null | grep -qx "${username}"; then
        log "  ${username} already in ${g}"
      else
        samba-tool group addmembers "${g}" "${username}"
        log "  Added ${username} to ${g}"
      fi
    done
  fi
done < "${CSV}"

log "Seed users created. Users must change their password at next interactive logon."
