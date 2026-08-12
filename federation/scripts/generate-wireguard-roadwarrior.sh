#!/usr/bin/env bash
# Generates a WireGuard keypair + client config for one remote user, scoped via AllowedIPs
# to only the specific hosts they need — never the full business subnet. See
# docs/MultiBusiness.md#remote-access-wireguard-road-warrior.
#
# Usage:
#   ./federation/scripts/generate-wireguard-roadwarrior.sh --user student01 \
#     --allowed-hosts 10.10.0.20/32,10.10.0.30/32 [--server-endpoint <wan-ip>:51820] [--openvpn]
#
# Requires the `wg` CLI (wireguard-tools package) for real keypairs. Falls back to a clearly
# marked placeholder keypair (with a loud warning) if `wg` isn't installed, so the config
# shape can still be reviewed/taught without the tool present.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

log()  { printf '\033[1;34m[wg-roadwarrior]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[wg-roadwarrior][warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[wg-roadwarrior][error]\033[0m %s\n' "$*" >&2; exit 1; }

USER=""
ALLOWED_HOSTS=""
SERVER_ENDPOINT=""
USE_OPENVPN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER="$2"; shift 2 ;;
    --allowed-hosts) ALLOWED_HOSTS="$2"; shift 2 ;;
    --server-endpoint) SERVER_ENDPOINT="$2"; shift 2 ;;
    --openvpn) USE_OPENVPN=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${USER}" && -n "${ALLOWED_HOSTS}" ]] || die "Usage: $0 --user <name> --allowed-hosts <cidr,cidr,...> [--server-endpoint <ip>:51820] [--openvpn]"

ALL_YML="${REPO_ROOT}/ansible/group_vars/all.yml"
SUBNET_IP="$(awk -F': ' '/^samba_dc_ip:/{print $2}' "${ALL_YML}" | tr -d '"' | tr -d "'")"
SUBNET_PREFIX="$(cut -d. -f1-3 <<< "${SUBNET_IP}")"
SERVER_ENDPOINT="${SERVER_ENDPOINT:-<fill-in-your-pfsense-wan-ip>:51820}"

if [[ "${USE_OPENVPN}" -eq 1 ]]; then
  log "OpenVPN mode: this script only prints the field values — OpenVPN cert/key issuance"
  log "should go through pki/scripts/02-issue-server-cert.sh (client cert for ${USER}) plus"
  log "pfSense's OpenVPN client-export package. Recommended default remains WireGuard below."
  cat <<EOF

--- pfSense VPN > OpenVPN > Client Specific Overrides for ${USER} ---
  Common Name        : ${USER}.roadwarrior
  Tunnel Network       : (assign from pfSense's OpenVPN server config)
  Advanced (route)      : $(IFS=,; for h in ${ALLOWED_HOSTS}; do echo -n "push \"route ${h%/*} 255.255.255.255\"; "; done)

Issue the client certificate with:
  pki/scripts/02-issue-server-cert.sh --cn ${USER}.roadwarrior --san "DNS:${USER}.roadwarrior"
(client certs and server certs share the same Issuing CA in this lab; extendedKeyUsage on the
generated cert is serverAuth only, which most OpenVPN client configs accept for a lab, but note
this in your write-up as a shortcut you'd fix for production — a real client-auth cert should
carry extendedKeyUsage=clientAuth instead.)
EOF
  exit 0
fi

mkdir -p "${REPO_ROOT}/federation/wireguard-clients"
OUT="${REPO_ROOT}/federation/wireguard-clients/${USER}.conf"

if command -v wg >/dev/null 2>&1; then
  CLIENT_PRIVATE="$(wg genkey)"
  CLIENT_PUBLIC="$(echo "${CLIENT_PRIVATE}" | wg pubkey)"
else
  warn "wg CLI not found (install wireguard-tools) — emitting PLACEHOLDER keys. Replace both"
  warn "before actually connecting; this output is for reviewing the config shape only."
  CLIENT_PRIVATE="REPLACE_ME_CLIENT_PRIVATE_KEY"
  CLIENT_PUBLIC="REPLACE_ME_CLIENT_PUBLIC_KEY"
fi

cat > "${OUT}" <<EOF
# WireGuard client config for ${USER} — import into the WireGuard app on the remote device.
# Scoped to specific hosts only (least privilege), not the full business subnet.
[Interface]
PrivateKey = ${CLIENT_PRIVATE}
Address = ${SUBNET_PREFIX}.200/32
DNS = ${SUBNET_IP}

[Peer]
PublicKey = REPLACE_WITH_PFSENSE_WIREGUARD_SERVER_PUBLIC_KEY
Endpoint = ${SERVER_ENDPOINT}
AllowedIPs = ${ALLOWED_HOSTS}
PersistentKeepalive = 25
EOF

log "Wrote ${OUT} (gitignored — never commit client private keys)"
log "Client public key to add as a peer on pfSense (VPN > WireGuard > Peers):"
log "  ${CLIENT_PUBLIC}"
log "Peer stanza to add on pfSense:"
cat <<EOF
  Peer public key : ${CLIENT_PUBLIC}
  Allowed IPs      : ${SUBNET_PREFIX}.200/32
  (pfSense routes ${ALLOWED_HOSTS} back to this peer via its own firewall rules on the WireGuard interface — add a scoped Pass rule the same way as the IPSec case, not a blanket allow.)
EOF
