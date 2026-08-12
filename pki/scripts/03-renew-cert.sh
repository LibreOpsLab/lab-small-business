#!/usr/bin/env bash
# Renew a leaf certificate ahead of expiry. By default reuses the existing key/CSR (so
# downstream config referencing the same key path needs no changes); pass --new-key to
# rotate the key as well. Pass --check with no --cn to list expiry for every issued cert.
#
# Usage:
#   ./03-renew-cert.sh --check
#   ./03-renew-cert.sh --cn cloud.lab.internal [--days 397] [--new-key]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CN=""
DAYS=397
NEW_KEY=0
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cn) CN="$2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --new-key) NEW_KEY=1; shift ;;
    --check) CHECK_ONLY=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

if [[ "${CHECK_ONLY}" -eq 1 && -z "${CN}" ]]; then
  log "Expiry check for all issued certificates:"
  printf '%-40s %-15s %s\n' "CN" "DAYS-LEFT" "NOT-AFTER"
  for dir in "${ISSUED_DIR}"/*/; do
    [[ -f "${dir}cert.pem" ]] || continue
    cn="$(basename "${dir}")"
    not_after="$(openssl x509 -noout -enddate -in "${dir}cert.pem" | cut -d= -f2)"
    end_epoch="$(date -d "${not_after}" +%s)"
    now_epoch="$(date +%s)"
    days_left=$(( (end_epoch - now_epoch) / 86400 ))
    printf '%-40s %-15s %s\n' "${cn}" "${days_left}" "${not_after}"
  done
  exit 0
fi

[[ -n "${CN}" ]] || die "Usage: $0 --cn <common-name> [--days N] [--new-key], or --check for a full expiry report."

OUT_DIR="${ISSUED_DIR}/${CN}"
[[ -f "${OUT_DIR}/cert.pem" ]] || die "No existing certificate for ${CN} — use 02-issue-server-cert.sh first."

SAN="$(openssl x509 -noout -text -in "${OUT_DIR}/cert.pem" \
  | awk '/Subject Alternative Name/{getline; gsub(/^[ \t]+/,""); print}')"
[[ -n "${SAN}" ]] || SAN="DNS:${CN}"

if [[ "${NEW_KEY}" -eq 1 ]]; then
  log "Rotating key for ${CN}"
  openssl req -new -nodes -newkey rsa:2048 \
    -keyout "${OUT_DIR}/key.pem" \
    -subj "/C=GB/O=LAB/CN=${CN}" \
    -out "${OUT_DIR}/csr.pem"
  chmod 400 "${OUT_DIR}/key.pem"
else
  log "Reusing existing CSR/key for ${CN}"
  [[ -f "${OUT_DIR}/csr.pem" ]] || die "No CSR found to reuse — pass --new-key to generate one."
fi

log "Re-signing ${CN} with LAB Issuing CA (SAN: ${SAN}, ${DAYS} days)"
pushd "${INTERMEDIATE_CA_DIR}" >/dev/null
SAN="${SAN}" openssl ca -config "${INTERMEDIATE_CA_CNF}" -batch \
  -extensions server_cert -days "${DAYS}" -notext -md sha384 \
  -in "${OUT_DIR}/csr.pem" \
  -out "${OUT_DIR}/cert.pem.new"
popd >/dev/null

mv "${OUT_DIR}/cert.pem.new" "${OUT_DIR}/cert.pem"
cp "${INTERMEDIATE_CA_DIR}/certs/ca-chain.cert.pem" "${OUT_DIR}/chain.pem"
cat "${OUT_DIR}/cert.pem" "${OUT_DIR}/chain.pem" > "${OUT_DIR}/fullchain.pem"

log "Renewed ${CN}. New expiry:"
openssl x509 -noout -enddate -in "${OUT_DIR}/cert.pem"
log "Restart/reload any service that doesn't hot-reload cert.pem/fullchain.pem (Traefik hot-reloads; Samba/Dovecot need a restart)."
