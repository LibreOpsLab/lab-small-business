#!/usr/bin/env bash
# Registers this business with the lecturer's class registry: domain label, subnet, and edge
# proxy IP. Run once per business. See docs/ClassRegistry.md.
#
# Usage:
#   ./federation/scripts/register-with-class.sh \
#     --registry http://<lecturer-host>:8080 --token <class-token> \
#     --name acme --subnet 10.20.0.0/24 --edge-ip 203.0.113.10 [--contact "Jane, group 3"]

set -euo pipefail

log()  { printf '\033[1;34m[register-with-class]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[register-with-class][error]\033[0m %s\n' "$*" >&2; exit 1; }

REGISTRY=""
TOKEN=""
NAME=""
SUBNET=""
EDGE_IP=""
CONTACT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --token) TOKEN="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --subnet) SUBNET="$2"; shift 2 ;;
    --edge-ip) EDGE_IP="$2"; shift 2 ;;
    --contact) CONTACT="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${REGISTRY}" && -n "${TOKEN}" && -n "${NAME}" && -n "${SUBNET}" && -n "${EDGE_IP}" ]] || \
  die "Usage: $0 --registry <url> --token <token> --name <business> --subnet <cidr> --edge-ip <ip> [--contact <text>]"

log "Registering '${NAME}' with ${REGISTRY}"
RESPONSE="$(curl -sS -w '\n%{http_code}' -X POST "${REGISTRY%/}/api/register" \
  --data-urlencode "name=${NAME}" \
  --data-urlencode "subnet=${SUBNET}" \
  --data-urlencode "edge_ip=${EDGE_IP}" \
  --data-urlencode "contact=${CONTACT}" \
  --data-urlencode "token=${TOKEN}")"

BODY="$(head -n -1 <<< "${RESPONSE}")"
STATUS="$(tail -n1 <<< "${RESPONSE}")"

echo "${BODY}"
if [[ "${STATUS}" -ge 200 && "${STATUS}" -lt 300 ]]; then
  log "Registered. Next: ./federation/scripts/request-class-cert.sh --registry ${REGISTRY} --token <token> --name ${NAME}"
else
  die "Registration failed (HTTP ${STATUS}) — see response above."
fi
