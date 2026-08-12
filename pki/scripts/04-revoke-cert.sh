#!/usr/bin/env bash
# Revoke an issued certificate and regenerate the Issuing CA's CRL.
#
# Usage:
#   ./04-revoke-cert.sh --cn cloud.lab.local
#   ./04-revoke-cert.sh --serial 100A

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cn) CN="$2"; shift 2 ;;
    --serial) SERIAL="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${CN}" || -n "${SERIAL}" ]] || die "Usage: $0 --cn <common-name> | --serial <hex-serial>"

CERT_PATH=""
if [[ -n "${CN}" ]]; then
  CERT_PATH="${ISSUED_DIR}/${CN}/cert.pem"
  [[ -f "${CERT_PATH}" ]] || die "No issued certificate found for ${CN}"
else
  CERT_PATH="${INTERMEDIATE_CA_DIR}/db/${SERIAL}.pem"
  [[ -f "${CERT_PATH}" ]] || die "No certificate found in CA database for serial ${SERIAL}"
fi

log "Revoking certificate: ${CERT_PATH}"
pushd "${INTERMEDIATE_CA_DIR}" >/dev/null
openssl ca -config "${INTERMEDIATE_CA_CNF}" -revoke "${CERT_PATH}" || {
  warn "Certificate may already be revoked — continuing to regenerate CRL."
}

log "Regenerating CRL"
openssl ca -config "${INTERMEDIATE_CA_CNF}" -gencrl -out crl/intermediate.crl.pem
popd >/dev/null

log "CRL updated at ${INTERMEDIATE_CA_DIR}/crl/intermediate.crl.pem"
log "Publish it via Traefik (docker/reverse-proxy/traefik/dynamic.yml serves pki/intermediate-ca/crl/ at /crl/) and re-push to trust stores if clients enforce CRL checking."

if [[ -n "${CN}" ]]; then
  warn "The revoked cert's files remain under ${ISSUED_DIR}/${CN}/ for audit purposes — remove or re-issue as needed."
fi
