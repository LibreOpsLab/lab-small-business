#!/usr/bin/env bash
# One-time bootstrap of the LAB Issuing CA (online), signed by the Root CA.
# Requires 00-init-root-ca.sh to have been run first (and the Root CA key to still be
# available locally — this is the one time after bootstrap you'll need it before it goes
# offline for good).
#
# Usage: ./01-init-intermediate-ca.sh [--force]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

[[ -f "${ROOT_CA_DIR}/private/ca.key.pem" ]] || die "Root CA not found — run 00-init-root-ca.sh first."

if [[ -f "${INTERMEDIATE_CA_DIR}/private/intermediate.key.pem" && "${FORCE}" -eq 0 ]]; then
  warn "Issuing CA already initialised — pass --force to regenerate (invalidates every issued leaf cert)."
  exit 0
fi

log "Initialising LAB Issuing CA directory tree at ${INTERMEDIATE_CA_DIR}"
init_ca_tree "${INTERMEDIATE_CA_DIR}"

pushd "${INTERMEDIATE_CA_DIR}" >/dev/null

log "Generating 4096-bit Issuing CA private key"
openssl genrsa -aes256 -out private/intermediate.key.pem 4096
chmod 400 private/intermediate.key.pem

log "Generating Issuing CA CSR"
openssl req -config "${INTERMEDIATE_CA_CNF}" -new -sha384 \
  -key private/intermediate.key.pem \
  -subj "/C=GB/O=LAB/CN=LAB Issuing CA" \
  -out csr/intermediate.csr.pem

popd >/dev/null

log "Signing Issuing CA CSR with the Root CA (10 year validity)"
pushd "${ROOT_CA_DIR}" >/dev/null
openssl ca -config "${ROOT_CA_CNF}" -batch \
  -extensions v3_intermediate_ca -days 3650 -notext -md sha384 \
  -in "${INTERMEDIATE_CA_DIR}/csr/intermediate.csr.pem" \
  -out "${INTERMEDIATE_CA_DIR}/certs/intermediate.cert.pem"
popd >/dev/null

chmod 444 "${INTERMEDIATE_CA_DIR}/certs/intermediate.cert.pem"

log "Verifying chain of trust"
openssl verify -CAfile "${ROOT_CA_DIR}/certs/ca.cert.pem" \
  "${INTERMEDIATE_CA_DIR}/certs/intermediate.cert.pem"

log "Building full chain bundle (intermediate + root) for server cert distribution"
cat "${INTERMEDIATE_CA_DIR}/certs/intermediate.cert.pem" \
    "${ROOT_CA_DIR}/certs/ca.cert.pem" \
    > "${INTERMEDIATE_CA_DIR}/certs/ca-chain.cert.pem"

cat <<EOF

=====================================================================
 LAB Issuing CA created at: ${INTERMEDIATE_CA_DIR}
 Chain bundle: ${INTERMEDIATE_CA_DIR}/certs/ca-chain.cert.pem

 NEXT STEPS:
   1. Move ${ROOT_CA_DIR}/private/ca.key.pem to offline storage now.
   2. Issue leaf certificates with ./02-issue-server-cert.sh.
   3. Distribute trust: see docs/PKI.md and ansible/roles/pki_trust.
=====================================================================
EOF
