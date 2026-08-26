#!/usr/bin/env bash
# Shared logic for scripts that rebase this repo's identity onto a fresh copy:
# scripts/provision-business.sh (full domain/netbios/subnet rebase) and
# scripts/set-subnet.sh (subnet-only rebase). Sourced, not executed directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# The repo's checked-in default subnet prefix. Both provision-business.sh and
# set-subnet.sh rebase away from this fixed value — neither auto-detects the
# current subnet of an already-rebased copy.
readonly REPO_DEFAULT_SUBNET_PREFIX="10.10.10"

# copy_repo <src> <dst>
# Copies <src> into <dst>, excluding .git, PKI key material, and secrets.
copy_repo() {
  local src="$1" dst="$2"
  mkdir -p "${dst}"
  log "Copying repository (excluding .git, generated secrets, and any existing PKI/env material)"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude=.git \
      --exclude='pki/root-ca' --exclude='pki/intermediate-ca' --exclude='pki/issued' \
      --exclude='*.env' --exclude='**/.generated-secrets' \
      --exclude='ansible/inventory/host_vars/*/vault.yml' \
      "${src}/" "${dst}/"
  else
    warn "rsync not found — falling back to cp -a (Git for Windows' Git Bash doesn't bundle rsync by default; install it via MSYS2 or run this from WSL2/Linux for the cleaner path)"
    cp -a "${src}/." "${dst}/"
    rm -rf "${dst}/.git" \
      "${dst}/pki/root-ca" "${dst}/pki/intermediate-ca" "${dst}/pki/issued"
    find "${dst}" -name '*.env' -delete
    find "${dst}" -type d -name '.generated-secrets' -exec rm -rf {} +
    find "${dst}/ansible/inventory/host_vars" -mindepth 2 -name 'vault.yml' -delete 2>/dev/null || true
  fi
}

# validate_subnet <cidr>
# Validates <cidr> is an RFC1918 /24 (e.g. 10.20.30.0/24). Prints the
# validated prefix (e.g. "10.20.30") to stdout on success; dies on failure.
validate_subnet() {
  local subnet="$1"
  [[ "${subnet}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.0/24$ ]] \
    || die "subnet must be a /24 CIDR ending in .0/24, e.g. 10.20.0.0/24, got '${subnet}'"
  local prefix="${subnet%.0/24}"
  local o1 o2 o3
  IFS='.' read -r o1 o2 o3 <<< "${prefix}"
  case "${o1}" in
    10) : ;;
    172) [[ "${o2}" -ge 16 && "${o2}" -le 31 ]] || die "subnet 172.x.x.0/24 must have x in 16-31 (RFC1918)" ;;
    192) [[ "${o2}" -eq 168 ]] || die "subnet 192.x.x.0/24 must be 192.168.x.0/24 (RFC1918)" ;;
    *) die "subnet must be within RFC1918 private space (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)" ;;
  esac
  printf '%s\n' "${prefix}"
}

# rewrite_subnet <dir> <old_prefix> <new_prefix>
# Rewrites every occurrence of "<old_prefix>." to "<new_prefix>." across all
# text files under <dir>.
rewrite_subnet() {
  local dir="$1" old_prefix="$2" new_prefix="$3"
  local old_pattern="${old_prefix//./\\.}"
  local files
  files="$(grep -rlI "${old_pattern}\." "${dir}" 2>/dev/null || true)"
  local f
  for f in ${files}; do
    sed -i "s/${old_pattern}\./${new_prefix}./g" "${f}"
  done
}
