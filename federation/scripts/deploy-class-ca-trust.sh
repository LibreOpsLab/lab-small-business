#!/usr/bin/env bash
# Downloads the class CA root certificate from the registry and installs it into this Linux
# host's system trust store — the same update-ca-certificates mechanism as
# ansible/roles/pki_trust, applied to a second, independent CA bundle. See
# docs/ClassRegistry.md#trusting-the-class-ca.
#
# Usage: sudo ./federation/scripts/deploy-class-ca-trust.sh --registry http://<lecturer-host>:8080

set -euo pipefail

log()  { printf '\033[1;34m[deploy-class-ca-trust]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[deploy-class-ca-trust][error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root (sudo $0) — writes to /usr/local/share/ca-certificates/."

REGISTRY=""
[[ "${1:-}" == "--registry" ]] && REGISTRY="$2"
[[ -n "${REGISTRY}" ]] || die "Usage: $0 --registry <url>"

log "Downloading the class CA certificate from ${REGISTRY}"
curl -fsSL "${REGISTRY%/}/ca/root.crt" -o /usr/local/share/ca-certificates/lab-class-ca.crt

log "Updating the system trust store"
update-ca-certificates

log "Done. Verify with: openssl s_client -connect <any-business>.lab.internet:443 -CAfile /etc/ssl/certs/ca-certificates.crt"
