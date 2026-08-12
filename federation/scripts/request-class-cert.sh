#!/usr/bin/env bash
# Generates a keypair + CSR for <name>.lab.internet / *.<name>.lab.internet LOCALLY (the
# private key never leaves this machine — only the CSR is uploaded), submits it to the class
# registry for signing, and saves the returned certificate for your edge reverse proxy
# (Caddy/HAProxy). See docs/ClassRegistry.md and federation/edge-proxy/.
#
# Usage:
#   ./federation/scripts/request-class-cert.sh \
#     --registry http://<lecturer-host>:8080 --token <class-token> --name acme \
#     [--out-dir federation/class-registry-cert]
#
# Requires: openssl, curl, python3 (used only to parse the JSON response - no jq dependency).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

log()  { printf '\033[1;34m[request-class-cert]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[request-class-cert][error]\033[0m %s\n' "$*" >&2; exit 1; }

REGISTRY=""
TOKEN=""
NAME=""
OUT_DIR="${REPO_ROOT}/federation/class-registry-cert"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --token) TOKEN="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${REGISTRY}" && -n "${TOKEN}" && -n "${NAME}" ]] || \
  die "Usage: $0 --registry <url> --token <token> --name <business> [--out-dir <dir>]"

mkdir -p "${OUT_DIR}"
KEY_FILE="${OUT_DIR}/${NAME}.key.pem"
CSR_FILE="${OUT_DIR}/${NAME}.csr.pem"

log "Generating a 2048-bit key + CSR for ${NAME}.lab.internet (+ wildcard) — key stays local"
openssl req -new -nodes -newkey rsa:2048 \
  -keyout "${KEY_FILE}" \
  -subj "/CN=${NAME}.lab.internet" \
  -addext "subjectAltName=DNS:${NAME}.lab.internet,DNS:*.${NAME}.lab.internet" \
  -out "${CSR_FILE}"
chmod 400 "${KEY_FILE}"

log "Submitting CSR to ${REGISTRY} for signing"
RESPONSE="$(curl -sS -w '\n%{http_code}' -X POST "${REGISTRY%/}/api/request-cert" \
  --data-urlencode "name=${NAME}" \
  --data-urlencode "csr@${CSR_FILE}" \
  --data-urlencode "token=${TOKEN}")"

BODY="$(head -n -1 <<< "${RESPONSE}")"
STATUS="$(tail -n1 <<< "${RESPONSE}")"

[[ "${STATUS}" -ge 200 && "${STATUS}" -lt 300 ]] || die "Cert request failed (HTTP ${STATUS}): ${BODY}"

python3 -c "
import json, sys
data = json.load(sys.stdin)
open('${OUT_DIR}/${NAME}.fullchain.pem', 'w').write(data['fullchain_pem'])
open('${OUT_DIR}/${NAME}.cert.pem', 'w').write(data['cert_pem'])
open('${OUT_DIR}/${NAME}.ca-chain.pem', 'w').write(data['ca_cert_pem'])
" <<< "${BODY}"

log "Saved to ${OUT_DIR}/:"
log "  ${NAME}.key.pem        - private key (keep this, never share it)"
log "  ${NAME}.cert.pem        - your signed leaf certificate"
log "  ${NAME}.ca-chain.pem     - the class CA cert (for validation)"
log "  ${NAME}.fullchain.pem     - leaf + CA chain (use this for your edge proxy's TLS config)"
log "Next: point your Caddy/HAProxy edge proxy at ${NAME}.fullchain.pem + ${NAME}.key.pem"
log "— see federation/edge-proxy/README.md."
