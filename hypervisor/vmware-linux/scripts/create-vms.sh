#!/usr/bin/env bash
# Creates the lab's VM shells (disk + .vmx) via vmrun/vmware-vdiskmanager, ready for OS
# installation, for the four hosts with an unattended-install seed (samba-dc01, docker01,
# authentik01, win-client01) — each one's hypervisor/vms/seeds/<name>/ folder gets built into a
# seed ISO via build-seed-iso.sh and attached, so it installs with zero prompts once booted.
# pfsense01 and linux-client01 are built entirely by hand in the Workstation GUI (see their
# respective vms/*.md) and are not in this script's table. Linux port of create-vms.ps1 — same
# VM table, same .vmx content, same vmrun/vmware-vdiskmanager calls; only the shell differs.
#
# Usage: ./create-vms.sh [--vm-dir=DIR] [--iso-dir=DIR] [--vmware-path=DIR] [--lan-network=NAME]
#
#   --vm-dir       Directory under which each VM's folder is created (default: this repo's
#                  hypervisor/vms/<name>/).
#   --iso-dir      Directory holding the OS install ISOs referenced below (default: ~/isos).
#   --vmware-path  Directory containing vmrun and vmware-vdiskmanager (default: /usr/bin — some
#                  installs put them under /usr/lib/vmware/bin instead).
#   --lan-network  Name of the VMware LAN Segment every VM's NIC is attached to (default:
#                  "LAN-LAB", created the first time it's referenced from pfSense's NIC2 — see
#                  hypervisor/vms/pfsense.md). Every VM this script creates has exactly one NIC,
#                  on this network; pfSense is the only VM with a WAN-facing NIC, and it's built
#                  by hand, not by this script.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/lib/common.sh
source "${SCRIPT_DIR}/../../../scripts/lib/common.sh"

VM_DIR="$(cd "${SCRIPT_DIR}/../../vms" && pwd)"
ISO_DIR="${HOME}/isos"
VMWARE_PATH="/usr/bin"
LAN_NETWORK="LAN-LAB"

for arg in "$@"; do
  case "${arg}" in
    --vm-dir=*) VM_DIR="${arg#*=}" ;;
    --iso-dir=*) ISO_DIR="${arg#*=}" ;;
    --vmware-path=*) VMWARE_PATH="${arg#*=}" ;;
    --lan-network=*) LAN_NETWORK="${arg#*=}" ;;
    *) die "Unknown argument: ${arg} (expected --vm-dir=, --iso-dir=, --vmware-path=, or --lan-network=)" ;;
  esac
done

VMRUN="${VMWARE_PATH}/vmrun"
VDISKMAN="${VMWARE_PATH}/vmware-vdiskmanager"

for exe in "${VMRUN}" "${VDISKMAN}"; do
  [[ -x "${exe}" ]] || die "Required tool not found or not executable: ${exe}. Adjust --vmware-path (some installs put these under /usr/lib/vmware/bin instead of /usr/bin)."
done

# name|vcpu|ramMB|diskGB|iso|firmware|vtpm|guestOS — mirrors create-vms.ps1's $VMs table exactly,
# minus the NIC column (every VM here has exactly one NIC, on $LAN_NETWORK).
VMS=(
  "samba-dc01|2|4096|40|ubuntu-server-24.04.iso|bios|false|ubuntu-64"
  "docker01|4|8192|80|ubuntu-server-24.04.iso|bios|false|ubuntu-64"
  "authentik01|2|4096|40|ubuntu-server-24.04.iso|bios|false|ubuntu-64"
  # Windows 11 Setup hard-blocks installation without a detected TPM 2.0 and UEFI firmware —
  # this is the fix for that; every other VM above is untouched (still BIOS, no vTPM, exactly
  # as before this change).
  "win-client01|2|4096|60|Win11.iso|efi|true|windows11-64"
)

for entry in "${VMS[@]}"; do
  IFS='|' read -r name vcpu ram_mb disk_gb iso firmware vtpm guest_os <<< "${entry}"

  vm_folder="${VM_DIR}/${name}"
  vmx="${vm_folder}/${name}.vmx"
  vmdk="${vm_folder}/${name}.vmdk"

  if [[ -f "${vmx}" ]]; then
    warn "${name} already exists at ${vmx} — skipping."
    continue
  fi

  log "Creating ${name} (${vcpu} vCPU, ${ram_mb}MB RAM, ${disk_gb}GB disk)..."
  mkdir -p "${vm_folder}"

  "${VDISKMAN}" -c -s "${disk_gb}GB" -a lsilogic -t 1 "${vmdk}"

  iso_path="${ISO_DIR}/${iso}"
  nic_lines="$(printf 'ethernet0.present = "TRUE"\nethernet0.connectionType = "custom"\nethernet0.vnet = "%s"\nethernet0.virtualDev = "e1000e"\n' "${LAN_NETWORK}")"

  # Unattended-install seed media: every VM left in this script's table has a
  # hypervisor/vms/seeds/<name>/ folder (Ubuntu Server autoinstall or Windows autounattend) —
  # pfsense01 and linux-client01 are built by hand and never reach this script at all.
  seed_folder="${VM_DIR}/seeds/${name}"
  cdrom_lines=""
  if [[ -d "${seed_folder}" ]]; then
    log "${name} has an unattended-install seed — building it..."
    "${SCRIPT_DIR}/build-seed-iso.sh" --name="${name}"
    seed_iso="${vm_folder}/${name}-seed.iso"
    cdrom_lines="$(printf 'ide1:1.present = "TRUE"\nide1:1.deviceType = "cdrom-image"\nide1:1.fileName = "%s"\n' "${seed_iso}")"
  fi

  # win-client01 is the only entry with firmware=efi: Windows 11 Setup hard-requires UEFI +
  # Secure Boot + a TPM 2.0 and refuses to install without them. Every other VM here gets none
  # of these lines — same BIOS/no-vTPM behavior as before this change.
  firmware_lines=""
  if [[ "${firmware}" == "efi" ]]; then
    firmware_lines+=$'firmware = "efi"\nuefi.secureBoot.enabled = "TRUE"\n'
  fi
  if [[ "${vtpm}" == "true" ]]; then
    firmware_lines+=$'vtpm.present = "TRUE"\n'
  fi

  cat > "${vmx}" <<VMX
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "${name}"
numvcpus = "${vcpu}"
memsize = "${ram_mb}"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "${name}.vmdk"
ide1:0.present = "TRUE"
ide1:0.deviceType = "cdrom-image"
ide1:0.fileName = "${iso_path}"
${cdrom_lines}${nic_lines}${firmware_lines}
guestOS = "${guest_os}"
VMX

  log "${name} VM shell ready at ${vmx}"
  log "Boot with: \"${VMRUN}\" start \"${vmx}\" gui"
done

echo ""
log "All VM shells created. See hypervisor/vms/*.md for per-VM install notes."
log "pfsense01 and linux-client01 are built by hand in the Workstation GUI - not by this script."
