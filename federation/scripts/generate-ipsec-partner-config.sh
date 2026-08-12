#!/usr/bin/env bash
# Generates the pfSense IPSec Phase 1 / Phase 2 field values (plus a scoped firewall rule
# recommendation) needed to bridge this business to a partner business. Prints values for
# BOTH sides — you apply "your side" locally and send "their side" to your partner (along
# with the generated PSK, over your existing secure out-of-band channel). See
# docs/MultiBusiness.md#workflow-partnering-two-businesses-via-ipsec.
#
# Usage:
#   ./federation/scripts/generate-ipsec-partner-config.sh \
#     --local federation/registry/<your-business>.yaml \
#     --peer  federation/registry/<their-business>.yaml \
#     [--psk <shared-key>] [--allow-service "https:443" ]
#
# If --psk is omitted, a fresh one is generated — send it to your partner securely; they
# must pass the SAME value via --psk when they run this on their side, since the manifest
# exchange alone (plain YAML) is not a secure channel for the key itself.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;34m[ipsec-partner]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ipsec-partner][error]\033[0m %s\n' "$*" >&2; exit 1; }

LOCAL_FILE=""
PEER_FILE=""
PSK=""
ALLOW_SERVICE="https:443"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local) LOCAL_FILE="$2"; shift 2 ;;
    --peer) PEER_FILE="$2"; shift 2 ;;
    --psk) PSK="$2"; shift 2 ;;
    --allow-service) ALLOW_SERVICE="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -f "${LOCAL_FILE}" ]] || die "Usage: $0 --local <manifest.yaml> --peer <manifest.yaml> [--psk <key>] [--allow-service host:port]"
[[ -f "${PEER_FILE}" ]] || die "Peer manifest not found: ${PEER_FILE} — ask your partner business to run register-business.sh and send it to you first."

manifest_get() { awk -F': ' -v k="$2" '$1==k{print $2}' "$1"; }

LOCAL_NAME="$(manifest_get "${LOCAL_FILE}" name)"
LOCAL_SUBNET="$(manifest_get "${LOCAL_FILE}" lan_subnet)"
LOCAL_WAN="$(manifest_get "${LOCAL_FILE}" wan_endpoint)"
LOCAL_DOMAIN="$(manifest_get "${LOCAL_FILE}" domain)"
LOCAL_APP_IP="$(manifest_get "${LOCAL_FILE}" docker_host_ip)"

PEER_NAME="$(manifest_get "${PEER_FILE}" name)"
PEER_SUBNET="$(manifest_get "${PEER_FILE}" lan_subnet)"
PEER_WAN="$(manifest_get "${PEER_FILE}" wan_endpoint)"
PEER_DOMAIN="$(manifest_get "${PEER_FILE}" domain)"
PEER_APP_IP="$(manifest_get "${PEER_FILE}" docker_host_ip)"

[[ "${LOCAL_SUBNET}" != "${PEER_SUBNET}" ]] || die "Local and peer subnets are identical (${LOCAL_SUBNET}) — they must not overlap for IPSec to route correctly. Re-provision one side with a different --subnet."

if [[ -z "${PSK}" ]]; then
  PSK="$(openssl rand -base64 24)"
  log "Generated a new PSK (send this to your partner over your secure out-of-band channel — do not commit it):"
  log "  PSK: ${PSK}"
fi

SVC_NAME="${ALLOW_SERVICE%%:*}"
SVC_PORT="${ALLOW_SERVICE##*:}"

cat <<EOF

=====================================================================
 IPSec site-to-site: ${LOCAL_NAME} <-> ${PEER_NAME}
=====================================================================

--- YOUR SIDE (${LOCAL_NAME}) — enter under pfSense VPN > IPsec > Tunnels ---
Phase 1:
  Key Exchange version : IKEv2
  Remote Gateway        : ${PEER_WAN}
  Authentication Method  : Mutual PSK
  Pre-Shared Key         : ${PSK}
  Encryption Algorithm   : AES256-GCM
  Hash Algorithm          : SHA256
  DH Group                : 14 (2048 bit)

Phase 2:
  Mode                    : Tunnel IPv4
  Local Network            : ${LOCAL_SUBNET}
  Remote Network            : ${PEER_SUBNET}
  Protocol                  : ESP
  Encryption Algorithms      : AES256-GCM
  PFS key group               : 14

--- THEIR SIDE (${PEER_NAME}) — send this block to your partner ---
Phase 1:
  Key Exchange version : IKEv2
  Remote Gateway        : ${LOCAL_WAN}
  Authentication Method  : Mutual PSK
  Pre-Shared Key         : ${PSK}
  Encryption Algorithm   : AES256-GCM
  Hash Algorithm          : SHA256
  DH Group                : 14 (2048 bit)

Phase 2:
  Mode                    : Tunnel IPv4
  Local Network             : ${PEER_SUBNET}
  Remote Network              : ${LOCAL_SUBNET}
  Protocol                     : ESP
  Encryption Algorithms         : AES256-GCM
  PFS key group                  : 14

--- SCOPED FIREWALL RULE (add on the IPsec interface, NOT a subnet-to-subnet allow) ---
Your side (allow ${PEER_NAME} to reach your ${SVC_NAME} service only):
  Interface : IPsec
  Source     : ${PEER_SUBNET}
  Destination : ${LOCAL_APP_IP} port ${SVC_PORT}
  Action        : Pass

Their side (mirror, allow you to reach their ${SVC_NAME} service only):
  Interface : IPsec
  Source     : ${LOCAL_SUBNET}
  Destination : ${PEER_APP_IP} port ${SVC_PORT}
  Action        : Pass

Do NOT add "Source: ${PEER_SUBNET} / Destination: any" — see
docs/MultiBusiness.md#scoped-firewall-rules-not-full-subnet-trust for why.

--- WHAT THIS DOES NOT DO ---
${LOCAL_DOMAIN} hosts will still show a certificate warning for https://*.${PEER_DOMAIN} until
you deliberately import ${PEER_NAME}'s CA chain (see docs/PKI.md#trust-deployment applied to a
second CA bundle), and there is no AD/Authentik federation between the two businesses. See
docs/MultiBusiness.md#cross-business-trust-what-ipsec-does-and-does-not-give-you.
=====================================================================
EOF
