#!/usr/bin/env bash
# One-time bootstrap of the LAB Root CA (offline root of trust).
# Safe to re-run: exits early if the Root CA key/cert already exist.
#
# Usage: ./00-init-root-ca.sh [--force]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

if [[ -f "${ROOT_CA_DIR}/private/ca.key.pem" && "${FORCE}" -eq 0 ]]; then
  warn "Root CA already initialised at ${ROOT_CA_DIR} — pass --force to regenerate (DANGEROUS: invalidates every issued cert)."
  exit 0
fi

log "Initialising LAB Root CA directory tree at ${ROOT_CA_DIR}"
init_ca_tree "${ROOT_CA_DIR}"

pushd "${ROOT_CA_DIR}" >/dev/null

log "Generating 4096-bit Root CA private key (encrypted with a passphrase you will be prompted for)"
openssl genrsa -aes256 -out private/ca.key.pem 4096
chmod 400 private/ca.key.pem

log "Generating self-signed Root CA certificate (20 year validity)"
openssl req -config "${ROOT_CA_CNF}" \
  -key private/ca.key.pem \
  -new -x509 -days 7300 -sha384 -extensions v3_ca \
  -subj "/C=GB/O=LAB/CN=LAB Root CA" \
  -out certs/ca.cert.pem

chmod 444 certs/ca.cert.pem

popd >/dev/null

log "Root CA certificate:"
openssl x509 -noout -text -in "${ROOT_CA_DIR}/certs/ca.cert.pem" | head -n 20

cat <<EOF

=====================================================================
 LAB Root CA created at: ${ROOT_CA_DIR}

 NEXT STEPS:
   1. Run ./01-init-intermediate-ca.sh to issue the Issuing CA.
   2. Once that succeeds, move ${ROOT_CA_DIR}/private/ca.key.pem to
      offline storage (USB key / powered-off VM). Day-to-day scripts
      never need it again — only ${ROOT_CA_DIR}/certs/ca.cert.pem
      (public) is required for trust distribution.
=====================================================================
EOF
