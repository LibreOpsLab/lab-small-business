#!/usr/bin/env bash
# Writes this business's public connection manifest to federation/registry/<name>.yaml —
# the file you send a partner business out-of-band (never via git) so they can generate an
# IPSec config pointed at you. See docs/MultiBusiness.md.
#
# Usage: ./federation/scripts/register-business.sh --wan-endpoint <ip-or-hostname> [--name <override>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

log()  { printf '\033[1;34m[register-business]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[register-business][error]\033[0m %s\n' "$*" >&2; exit 1; }

WAN_ENDPOINT=""
NAME_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wan-endpoint) WAN_ENDPOINT="$2"; shift 2 ;;
    --name) NAME_OVERRIDE="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${WAN_ENDPOINT}" ]] || die "Usage: $0 --wan-endpoint <ip-or-hostname> [--name <override>]"

# Pull domain/realm/netbios/subnet out of ansible/group_vars/all.yml so this always reflects
# whatever provision-business.sh rebased this repo to, without a second source of truth.
ALL_YML="${REPO_ROOT}/ansible/group_vars/all.yml"
[[ -f "${ALL_YML}" ]] || die "${ALL_YML} not found"

DOMAIN="$(awk -F': ' '/^lab_domain:/{print $2}' "${ALL_YML}" | tr -d '"' | tr -d "'")"
REALM="$(awk -F': ' '/^lab_realm:/{print $2}' "${ALL_YML}" | tr -d '"' | tr -d "'")"
NETBIOS="$(awk -F': ' '/^lab_netbios:/{print $2}' "${ALL_YML}" | tr -d '"' | tr -d "'")"
SUBNET_IP="$(awk -F': ' '/^samba_dc_ip:/{print $2}' "${ALL_YML}" | tr -d '"' | tr -d "'")"
SUBNET_PREFIX="$(cut -d. -f1-3 <<< "${SUBNET_IP}")"
SUBNET="${SUBNET_PREFIX}.0/24"
NAME="${NAME_OVERRIDE:-${DOMAIN%%.*}}"

mkdir -p "${REPO_ROOT}/federation/registry"
OUT="${REPO_ROOT}/federation/registry/${NAME}.yaml"

cat > "${OUT}" <<EOF
# LAB federation manifest — send this file to a partner business out-of-band (chat, email,
# in person). Do NOT commit it to a shared/public repo. See docs/MultiBusiness.md.
name: ${NAME}
domain: ${DOMAIN}
realm: ${REALM}
netbios: ${NETBIOS}
lan_subnet: ${SUBNET}
wan_endpoint: ${WAN_ENDPOINT}
pfsense_lan_ip: ${SUBNET_PREFIX}.1
docker_host_ip: ${SUBNET_PREFIX}.20
authentik_host_ip: ${SUBNET_PREFIX}.30
generated_at: $(date -u +%FT%TZ)
EOF

log "Wrote ${OUT}"
log "Send this file to your partner business's admins out-of-band. Ask them for theirs and"
log "drop it into federation/registry/ before running generate-ipsec-partner-config.sh."
