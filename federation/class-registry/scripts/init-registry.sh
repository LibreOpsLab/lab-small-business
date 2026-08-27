#!/usr/bin/env bash
# One-time setup, run by the lecturer before the first `docker compose up`: generates the
# rndc/TSIG key BIND9 and the registry container share, seeds the initial zone file, and
# initialises the class CA. Safe to re-run (skips anything already present).
#
# This is the fast-path version of 4 steps worth understanding individually the first time —
# see docs/ClassRegistry.md#end-to-end-workflow for what each one does and why.
#
# Usage: ./scripts/init-registry.sh --ns-ip <this-host's-IP-students-will-reach-it-on>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log()  { printf '\033[1;34m[init-registry]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[init-registry][error]\033[0m %s\n' "$*" >&2; exit 1; }

NS_IP=""
[[ "${1:-}" == "--ns-ip" ]] && NS_IP="$2"
[[ -n "${NS_IP}" ]] || die "Usage: $0 --ns-ip <IP students' pfSense/DNS forwarders will reach this registry host on>"

KEY_DIR="${REGISTRY_ROOT}/bind/keys"
ZONE_DIR="${REGISTRY_ROOT}/bind/zones"
mkdir -p "${KEY_DIR}"

if [[ -f "${KEY_DIR}/rndc.key" ]]; then
  log "rndc key already exists at ${KEY_DIR}/rndc.key — leaving it in place."
else
  log "Generating a shared rndc/TSIG key (bind9 <-> registry container)"
  SECRET="$(openssl rand -base64 32)"
  cat > "${KEY_DIR}/rndc.key" <<EOF
key "rndc-key" {
    algorithm hmac-sha256;
    secret "${SECRET}";
};
EOF
  chmod 600 "${KEY_DIR}/rndc.key"
fi

if [[ -f "${ZONE_DIR}/db.lab.internet" ]]; then
  log "Zone file already exists at ${ZONE_DIR}/db.lab.internet — leaving it in place."
else
  log "Seeding the initial lab.internet zone (NS/A for ns1 = ${NS_IP})"
  sed "s/__ZONE_NS_IP__/${NS_IP}/" "${ZONE_DIR}/db.lab.internet.seed" > "${ZONE_DIR}/db.lab.internet"
fi

log "Initialising the class CA (prompts once for a passphrase)"
"${REGISTRY_ROOT}/ca/init-class-ca.sh"

if [[ ! -f "${REGISTRY_ROOT}/.env" ]]; then
  log "Writing ${REGISTRY_ROOT}/.env from .env.example (fill in CLASS_REGISTRY_TOKEN)"
  cp "${REGISTRY_ROOT}/.env.example" "${REGISTRY_ROOT}/.env"
  TOKEN="$(openssl rand -hex 16)"
  sed -i.bak "s/^CLASS_REGISTRY_TOKEN=.*/CLASS_REGISTRY_TOKEN=${TOKEN}/" "${REGISTRY_ROOT}/.env"
  sed -i.bak "s/^ZONE_NS_IP=.*/ZONE_NS_IP=${NS_IP}/" "${REGISTRY_ROOT}/.env"
  rm -f "${REGISTRY_ROOT}/.env.bak"
  log "Generated registration token: ${TOKEN} (also in ${REGISTRY_ROOT}/.env) — give this to students."
fi

log "Setup complete. Next: cd ${REGISTRY_ROOT} && docker compose up -d"
log "Registry will be reachable at http://${NS_IP}:8080 ; DNS at ${NS_IP}:53."
