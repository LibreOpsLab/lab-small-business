#!/usr/bin/env bash
# One-time bootstrap of the class CA (lecturer runs this once, before the first
# `docker compose up`). Safe to re-run: exits early if the key/cert already exist.
#
# Usage: ./init-class-ca.sh [--force]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;34m[init-class-ca]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[init-class-ca][warn]\033[0m %s\n' "$*" >&2; }

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

if [[ -f "${SCRIPT_DIR}/private/class-ca.key.pem" && "${FORCE}" -eq 0 ]]; then
  warn "Class CA already initialised at ${SCRIPT_DIR} — pass --force to regenerate (invalidates every business's edge-proxy cert)."
  exit 0
fi

mkdir -p "${SCRIPT_DIR}"/{certs,private,db}
chmod 700 "${SCRIPT_DIR}/private"
touch "${SCRIPT_DIR}/db/index.txt"
echo 1000 > "${SCRIPT_DIR}/db/serial"

pushd "${SCRIPT_DIR}" >/dev/null

log "Generating the class CA private key (encrypted with a passphrase you'll be prompted for once, then decrypted into an unencrypted copy for the registry container to use unattended — see the note below)"
openssl genrsa -aes256 -out private/class-ca.key.pem.enc 4096
openssl rsa -in private/class-ca.key.pem.enc -out private/class-ca.key.pem
chmod 400 private/class-ca.key.pem private/class-ca.key.pem.enc

log "Generating the self-signed class CA certificate (2 year validity - a course-length CA, not a long-lived one)"
openssl req -config class-ca.cnf \
  -key private/class-ca.key.pem \
  -new -x509 -days 730 -sha384 -extensions v3_ca \
  -subj "/O=LAB Class/CN=LAB Class CA" \
  -out certs/class-ca.cert.pem

popd >/dev/null

cat <<'EOF'

=====================================================================
 Class CA created. IMPORTANT trade-off (see docs/ClassRegistry.md#pki-design):

 private/class-ca.key.pem is UNENCRYPTED on disk because the registry container
 must sign business CSRs unattended, on demand, for the whole course. This is
 a deliberately different posture from every business's own offline Root CA
 (pki/scripts) - keep this CA's blast radius in mind: it should only ever be
 used to sign edge-proxy leaf certs for this course's registry, nothing else.
 Destroy private/class-ca.key.pem* at the end of the course.

 Next: docker compose up -d (from federation/class-registry/), then give
 students the registry URL and the CLASS_REGISTRY_TOKEN from your .env.
=====================================================================
EOF
