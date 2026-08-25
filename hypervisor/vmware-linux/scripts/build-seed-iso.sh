#!/usr/bin/env bash
# Builds a small ISO ("seed media") from the per-VM files under hypervisor/vms/seeds/<name>/,
# so create-vms.sh can attach it as a second CD-ROM and turn an interactive OS install into an
# unattended one. Linux port of build-seed-iso.ps1 — same two seed formats, same placeholder
# guard, same idempotency rule; only the ISO-building tool differs (xorrisofs/genisoimage
# instead of IMAPI2FS, which is Windows-only).
#
# Two seed formats are supported, auto-detected by what's in the VM's seeds folder:
#
#   autounattend.xml       -> Windows Setup's own unattended-install answer file.
#   user-data + meta-data  -> cloud-init's "NoCloud" datasource, consumed by Ubuntu Server's
#                             autoinstall (Subiquity). The ISO's volume label MUST be exactly
#                             "cidata" (case-insensitive) - that literal string is how
#                             cloud-init recognises a NoCloud seed at all.
#
# Real secrets (a password hash, a plaintext local-account password) never live in the
# .example files committed to git - see hypervisor/vms/seeds/<name>/*.example. This script
# reads the filled-in *copies* you make of those files (same names, no .example suffix), which
# are gitignored, and refuses to build a seed ISO if it finds placeholder text still sitting in
# them un-replaced.
#
# Usage: ./build-seed-iso.sh --name=samba-dc01 [--seeds-dir=DIR] [--out-file=FILE]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/lib/common.sh
source "${SCRIPT_DIR}/../../../scripts/lib/common.sh"

NAME=""
SEEDS_DIR="$(cd "${SCRIPT_DIR}/../../vms/seeds" && pwd)"
OUT_FILE=""

for arg in "$@"; do
  case "${arg}" in
    --name=*) NAME="${arg#*=}" ;;
    --seeds-dir=*) SEEDS_DIR="${arg#*=}" ;;
    --out-file=*) OUT_FILE="${arg#*=}" ;;
    *) die "Unknown argument: ${arg} (expected --name=, --seeds-dir=, or --out-file=)" ;;
  esac
done

[[ -n "${NAME}" ]] || die "--name=<vm-name> is required (e.g. --name=samba-dc01)"

# xorrisofs is the actively-maintained tool and is what's verified against in this repo's own
# testing; genisoimage (the older cdrkit tool) exposes the same mkisofs-derived flags, so if
# that's what's installed instead, it works as a drop-in.
if command -v xorrisofs >/dev/null 2>&1; then
  ISO_TOOL="xorrisofs"
elif command -v genisoimage >/dev/null 2>&1; then
  ISO_TOOL="genisoimage"
else
  die "Neither xorrisofs nor genisoimage found. Install one (the xorriso or genisoimage package) to build seed ISOs."
fi

seed_dir="${SEEDS_DIR}/${NAME}"
[[ -d "${seed_dir}" ]] || die "No seed folder for '${NAME}' at ${seed_dir} — this VM has no unattended-install seed (expected for pfsense01/linux-client01 — there's nothing for this script to do for them)."

if [[ -z "${OUT_FILE}" ]]; then
  vm_dir="$(cd "${SCRIPT_DIR}/../../vms" && pwd)/${NAME}"
  # create-vms.sh normally creates this folder before calling this script; create it here too
  # so this script also works standalone, e.g. re-building a seed after editing user-data
  # without recreating the whole VM.
  mkdir -p "${vm_dir}"
  OUT_FILE="${vm_dir}/${NAME}-seed.iso"
fi

# This exact text can only survive in an un-edited .example file — if it's still present in the
# real (gitignored) file the student copied from it, they haven't filled it in yet.
placeholder_pattern='replace-with-a-mkpasswd-hash|REPLACE_ME'

assert_no_placeholder() {
  local path="$1"
  if grep -Eq "${placeholder_pattern}" "${path}"; then
    die "${path} still has a placeholder value in it (search it for 'replace-with' or 'REPLACE_ME'). Fill in the real value, then re-run this script."
  fi
}

autounattend="${seed_dir}/autounattend.xml"
user_data="${seed_dir}/user-data"
meta_data="${seed_dir}/meta-data"

if [[ -f "${autounattend}" ]]; then
  assert_no_placeholder "${autounattend}"
  files=("${autounattend}")
  volume_label="AUTOUNATTEND"
elif [[ -f "${user_data}" && -f "${meta_data}" ]]; then
  assert_no_placeholder "${user_data}"
  files=("${user_data}" "${meta_data}")
  volume_label="cidata"
else
  die "${seed_dir} has neither autounattend.xml nor a user-data+meta-data pair. Copy the .example file(s) in that folder, drop the .example suffix, and fill in the placeholder value(s) before running this script."
fi

newest_source=0
for f in "${files[@]}"; do
  mtime="$(stat -c %Y "${f}")"
  (( mtime > newest_source )) && newest_source="${mtime}"
done

if [[ -f "${OUT_FILE}" ]]; then
  out_mtime="$(stat -c %Y "${OUT_FILE}")"
  if (( out_mtime > newest_source )); then
    warn "${OUT_FILE} is already up to date — skipping."
    exit 0
  fi
fi

log "Building ${volume_label} seed ISO for ${NAME} -> ${OUT_FILE} (using ${ISO_TOOL})"

"${ISO_TOOL}" -output "${OUT_FILE}" -volid "${volume_label}" -joliet -rock "${files[@]}"

log "Done: ${OUT_FILE}"
