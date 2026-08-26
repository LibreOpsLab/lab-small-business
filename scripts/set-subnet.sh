#!/usr/bin/env bash
# Rebases this repo's subnet (only) onto a fresh copy — for anyone who wants a different
# subnet than the shipped 10.10.10.0/24 default without renaming domain/NetBIOS identity.
# For a full business rename (domain + netbios + subnet), see provision-business.sh instead.
#
# Usage:
#   ./scripts/set-subnet.sh 10.20.30.0/24 [--output ../lab-small-business-30] [--force]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/business-rebase.sh"

[[ $# -ge 1 ]] || die "Usage: $0 <new-subnet-cidr> [--output <dir>] [--force]"
SUBNET="$1"
shift

OUTPUT=""
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

NEW_PREFIX="$(validate_subnet "${SUBNET}")"

if [[ "${NEW_PREFIX}" == "${REPO_DEFAULT_SUBNET_PREFIX}" ]]; then
  die "subnet ${SUBNET} matches the repo's current default (${REPO_DEFAULT_SUBNET_PREFIX}.0/24) — nothing to do."
fi

LAST_OCTET="${NEW_PREFIX##*.}"
OUTPUT="${OUTPUT:-${REPO_ROOT}/../$(basename "${REPO_ROOT}")-${LAST_OCTET}}"
if [[ -e "${OUTPUT}" && "$(ls -A "${OUTPUT}" 2>/dev/null)" && "${FORCE}" -eq 0 ]]; then
  die "${OUTPUT} already exists and is non-empty — pass --force to overwrite, or choose a different --output."
fi

log "Rebasing subnet ${REPO_DEFAULT_SUBNET_PREFIX}.0/24 -> ${SUBNET} -> ${OUTPUT}"

copy_repo "${REPO_ROOT}" "${OUTPUT}"
rewrite_subnet "${OUTPUT}" "${REPO_DEFAULT_SUBNET_PREFIX}" "${NEW_PREFIX}"

log "Writing provenance banner into ${OUTPUT}/README.md"
{
  echo "> **Subnet-rebased instance.** Generated $(date -u +%FT%TZ) from"
  echo "> lab-small-business by \`scripts/set-subnet.sh\` with subnet=\`${SUBNET}\`"
  echo "> (was \`${REPO_DEFAULT_SUBNET_PREFIX}.0/24\`). Domain, realm, and NetBIOS name are"
  echo "> unchanged from the source repo — for a full business rename, see"
  echo "> \`scripts/provision-business.sh\` instead."
  echo ""
  cat "${OUTPUT}/README.md"
} > "${OUTPUT}/README.md.new"
mv "${OUTPUT}/README.md.new" "${OUTPUT}/README.md"

log "Done. ${OUTPUT} uses subnet ${SUBNET}."
log "Next steps:"
log "  cd ${OUTPUT}"
log "  Continue docs/DeploymentGuide.md from this copy."
