#!/usr/bin/env bash
# Issue a leaf/server certificate signed by the LAB Issuing CA.
#
# Usage:
#   ./02-issue-server-cert.sh --cn <common-name> --san <SAN-list> [--days 397] [--force]
#
# Example:
#   ./02-issue-server-cert.sh --cn cloud.lab.internal --san DNS:cloud.lab.internal
#   ./02-issue-server-cert.sh --cn samba-dc01.lab.internal \
#       --san "DNS:samba-dc01.lab.internal,DNS:lab.internal"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CN=""
SAN=""
DAYS=397
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cn) CN="$2"; shift 2 ;;
    --san) SAN="$2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${CN}" ]] || die "Usage: $0 --cn <common-name> --san <SAN-list> [--days N] [--force]"
[[ -n "${SAN}" ]] || SAN="DNS:${CN}"
[[ -f "${INTERMEDIATE_CA_DIR}/private/intermediate.key.pem" ]] || die "Issuing CA not found — run 01-init-intermediate-ca.sh first."

OUT_DIR="${ISSUED_DIR}/${CN}"
if [[ -f "${OUT_DIR}/cert.pem" && "${FORCE}" -eq 0 ]]; then
  warn "Certificate for ${CN} already exists at ${OUT_DIR} — use 03-renew-cert.sh to renew, or pass --force to reissue from a new key."
  exit 0
fi

mkdir -p "${OUT_DIR}"

log "Generating 2048-bit key + CSR for ${CN}"
openssl req -new -nodes -newkey rsa:2048 \
  -keyout "${OUT_DIR}/key.pem" \
  -subj "/C=GB/O=LAB/CN=${CN}" \
  -out "${OUT_DIR}/csr.pem"
chmod 400 "${OUT_DIR}/key.pem"

log "Signing CSR with LAB Issuing CA (SAN: ${SAN}, ${DAYS} days)"
pushd "${INTERMEDIATE_CA_DIR}" >/dev/null
SAN="${SAN}" openssl ca -config "${INTERMEDIATE_CA_CNF}" -batch \
  -extensions server_cert -days "${DAYS}" -notext -md sha384 \
  -in "${OUT_DIR}/csr.pem" \
  -out "${OUT_DIR}/cert.pem"
popd >/dev/null

cp "${INTERMEDIATE_CA_DIR}/certs/ca-chain.cert.pem" "${OUT_DIR}/chain.pem"
cat "${OUT_DIR}/cert.pem" "${OUT_DIR}/chain.pem" > "${OUT_DIR}/fullchain.pem"

log "Verifying issued certificate against the chain"
openssl verify -CAfile "${OUT_DIR}/chain.pem" "${OUT_DIR}/cert.pem"

log "Issued certificate for ${CN} at ${OUT_DIR}"
log "  key.pem        - private key (0400)"
log "  cert.pem        - leaf certificate only"
log "  chain.pem       - intermediate + root (for CA bundle)"
log "  fullchain.pem   - leaf + chain (use this for TLS server config)"
