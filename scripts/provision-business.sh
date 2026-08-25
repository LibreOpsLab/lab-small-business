#!/usr/bin/env bash
# Clones this repository into a new directory with its domain, realm, NetBIOS name, and
# subnet re-based to new values — i.e. it turns "the lab" into "a business". Used both to
# simply rename the single default lab, and to stamp out additional independent businesses
# for the multi-business federation model (see docs/MultiBusiness.md).
#
# Each output is a fully independent copy: its own PKI (regenerated from scratch — CA key
# material is gitignored so nothing is carried over), its own Ansible inventory, its own
# Docker stacks. Nothing here talks to another business until you explicitly bridge them via
# the federation/ tooling.
#
# Usage:
#   ./scripts/provision-business.sh --name businessb --domain businessb.internal \
#       --netbios BIZB --subnet 10.20.0.0/24 [--output ../businessb-lab] [--force]
#
# Constraints (validated below, with rationale):
#   --domain   Exactly two DNS labels (e.g. "acme.internal", "bizb.lan") — the repo's LDAP
#              DNs are generated as DC=<label1>,DC=<label2> and a 3+ label domain would need
#              a 3+ component DN throughout, which this sed-based rename doesn't attempt.
#              Refuses a ".local" TLD by default — see docs/Architecture.md#domain-and-subnet-naming.
#   --netbios  1-15 chars, uppercase letters/digits/hyphens (NetBIOS name limit).
#   --subnet   A /24 in RFC1918 space. If you intend to bridge two businesses over IPSec
#              (docs/MultiBusiness.md), their subnets MUST NOT overlap — this script warns
#              but does not track other businesses' subnets for you; keep a note of what
#              you've allocated (the federation registry in scripts/federation/ does this
#              once businesses are registered for peering).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log()  { printf '\033[1;34m[provision-business]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[provision-business][warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[provision-business][error]\033[0m %s\n' "$*" >&2; exit 1; }

NAME=""
DOMAIN=""
NETBIOS=""
SUBNET=""
OUTPUT=""
FORCE=0
ALLOW_LOCAL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --netbios) NETBIOS="$2"; shift 2 ;;
    --subnet) SUBNET="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --allow-local-tld) ALLOW_LOCAL=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${NAME}" && -n "${DOMAIN}" && -n "${NETBIOS}" && -n "${SUBNET}" ]] || \
  die "Usage: $0 --name <business> --domain <two-label-domain> --netbios <NETBIOS> --subnet <a.b.c.0/24> [--output <dir>] [--force]"

# --- Validate domain: exactly two labels, not .local unless explicitly allowed ---
DOMAIN_LABEL_COUNT="$(awk -F. '{print NF}' <<< "${DOMAIN}")"
[[ "${DOMAIN_LABEL_COUNT}" -eq 2 ]] || die "--domain must have exactly two labels (e.g. acme.internal), got '${DOMAIN}' (${DOMAIN_LABEL_COUNT} labels). See the script header comment for why."
DOMAIN_LABEL1="${DOMAIN%%.*}"
DOMAIN_LABEL2="${DOMAIN#*.}"
if [[ "${DOMAIN_LABEL2}" == "local" && "${ALLOW_LOCAL}" -eq 0 ]]; then
  die "--domain ends in .local, which conflicts with mDNS (see docs/Architecture.md#domain-and-subnet-naming). Pass --allow-local-tld to override anyway."
fi
REALM="$(tr '[:lower:]' '[:upper:]' <<< "${DOMAIN}")"

# --- Validate NetBIOS: 1-15 chars, uppercase alnum/hyphen ---
[[ "${NETBIOS}" =~ ^[A-Z0-9-]{1,15}$ ]] || die "--netbios must be 1-15 uppercase letters/digits/hyphens, got '${NETBIOS}'"

# --- Validate subnet: RFC1918 /24 ---
[[ "${SUBNET}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.0/24$ ]] || die "--subnet must be a /24 CIDR ending in .0/24, e.g. 10.20.0.0/24, got '${SUBNET}'"
SUBNET_PREFIX="${SUBNET%.0/24}"  # e.g. "10.20.0"
IFS='.' read -r O1 O2 O3 <<< "${SUBNET_PREFIX}"
case "${O1}" in
  10) : ;;
  172) [[ "${O2}" -ge 16 && "${O2}" -le 31 ]] || die "--subnet 172.x.x.0/24 must have x in 16-31 (RFC1918)" ;;
  192) [[ "${O2}" -eq 168 ]] || die "--subnet 192.x.x.0/24 must be 192.168.x.0/24 (RFC1918)" ;;
  *) die "--subnet must be within RFC1918 private space (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)" ;;
esac
if [[ "${SUBNET_PREFIX}." == "10.10.10." ]]; then
  warn "--subnet matches the base lab's default (10.10.10.0/24). Fine for a standalone rename, but if this business will be IPSec-bridged to another running instance of the base lab, they'll collide — pick a distinct /24."
fi

OUTPUT="${OUTPUT:-${REPO_ROOT}/../${NAME}-lab}"
if [[ -e "${OUTPUT}" && "$(ls -A "${OUTPUT}" 2>/dev/null)" && "${FORCE}" -eq 0 ]]; then
  die "${OUTPUT} already exists and is non-empty — pass --force to overwrite, or choose a different --output."
fi

log "Provisioning '${NAME}': domain=${DOMAIN} realm=${REALM} netbios=${NETBIOS} subnet=${SUBNET} -> ${OUTPUT}"

mkdir -p "${OUTPUT}"
log "Copying repository (excluding .git, generated secrets, and any existing PKI/env material)"
if command -v rsync >/dev/null 2>&1; then
  rsync -a \
    --exclude=.git \
    --exclude='pki/root-ca' --exclude='pki/intermediate-ca' --exclude='pki/issued' \
    --exclude='*.env' --exclude='**/.generated-secrets' \
    --exclude='ansible/inventory/host_vars/*/vault.yml' \
    "${REPO_ROOT}/" "${OUTPUT}/"
else
  warn "rsync not found — falling back to cp -a (Git for Windows' Git Bash doesn't bundle rsync by default; install it via MSYS2 or run this from WSL2/Linux for the cleaner path)"
  cp -a "${REPO_ROOT}/." "${OUTPUT}/"
  rm -rf "${OUTPUT}/.git" \
    "${OUTPUT}/pki/root-ca" "${OUTPUT}/pki/intermediate-ca" "${OUTPUT}/pki/issued"
  find "${OUTPUT}" -name '*.env' -delete
  find "${OUTPUT}" -type d -name '.generated-secrets' -exec rm -rf {} +
  find "${OUTPUT}/ansible/inventory/host_vars" -mindepth 2 -name 'vault.yml' -delete 2>/dev/null || true
fi

log "Rewriting domain/realm references (lab.internal -> ${DOMAIN}, LAB.INTERNAL -> ${REALM})"
FILES="$(grep -rlI "lab\.internal\|LAB\.INTERNAL\|DC=lab,DC=internal\|\bLAB\b\|10\.10\.0\." "${OUTPUT}" 2>/dev/null || true)"
for f in ${FILES}; do
  sed -i \
    -e "s/lab\.internal/${DOMAIN}/g" \
    -e "s/LAB\.INTERNAL/${REALM}/g" \
    -e "s/DC=lab,DC=internal/DC=${DOMAIN_LABEL1},DC=${DOMAIN_LABEL2}/g" \
    -e "s/\bLAB\b/${NETBIOS}/g" \
    -e "s/10\.10\.0\./${SUBNET_PREFIX}./g" \
    "${f}"
done

log "Writing provenance banner into ${OUTPUT}/README.md"
{
  echo "> **Derived business instance.** Generated $(date -u +%FT%TZ) from"
  echo "> lab-small-business by \`scripts/provision-business.sh\` with:"
  echo "> domain=\`${DOMAIN}\`, realm=\`${REALM}\`, netbios=\`${NETBIOS}\`, subnet=\`${SUBNET}\`."
  echo "> This copy has its own PKI, secrets, and inventory — nothing is shared with the"
  echo "> source repo or any other business instance unless explicitly bridged. See"
  echo "> docs/MultiBusiness.md."
  echo ""
  cat "${OUTPUT}/README.md"
} > "${OUTPUT}/README.md.new"
mv "${OUTPUT}/README.md.new" "${OUTPUT}/README.md"

log "Done. ${OUTPUT} is a standalone lab instance for '${NAME}'."
log "Next steps:"
log "  cd ${OUTPUT}"
log "  git init && git add -A && git commit -m 'Initial provision: ${NAME}'   # optional, own history"
log "  make pki-init && make pki-issue-all   # this business needs its OWN CA, not a copy of anyone else's"
log "  make deploy"
log "To later bridge this business to another via IPSec/VPN, see docs/MultiBusiness.md and scripts/federation/."
