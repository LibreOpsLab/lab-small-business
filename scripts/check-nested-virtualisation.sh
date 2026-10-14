#!/usr/bin/env bash
# Read-only check: can this Linux host give VMware Workstation guests hardware virtualisation
# (VT-x/EPT or AMD-V/RVI), so Proxmox VE can run KVM inside a VMware VM?
#
# Linux counterpart of scripts/Set-NestedVirtualisation.ps1 -Mode Check. Unlike Windows, nothing
# has to be switched off here, so this script only reports and explains. Exit 0 = ready,
# 2 = not ready. Run it at the start of each class.
#
# Not yet run on a lab Linux host: confirm in the lab spike.

set -euo pipefail

# Same helpers as scripts/lib/common.sh (kept inline so the file can be copied on its own).
log()  { printf '\033[1;34m[nested]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[nested][warn]\033[0m %s\n' "$*" >&2; }

ready=1
problem() { warn "$*"; ready=0; }

log "1. CPU virtualisation flag"
if grep -qE '(^|\s)vmx(\s|$)' /proc/cpuinfo; then
  vendor=intel; module=kvm_intel; log "   Intel VT-x present (vmx)"
elif grep -qE '(^|\s)svm(\s|$)' /proc/cpuinfo; then
  vendor=amd; module=kvm_amd; log "   AMD-V present (svm)"
else
  vendor=none; module=""
  problem "   No vmx/svm flag. Enable VT-x/AMD-V in firmware (BIOS/UEFI), then reboot."
fi

log "2. KVM kernel module and nested support"
if [ -n "${module}" ]; then
  if [ -e /dev/kvm ]; then
    log "   /dev/kvm present"
  else
    problem "   /dev/kvm missing. Try: sudo modprobe ${module}"
  fi
  nested_file="/sys/module/${module}/parameters/nested"
  if [ -r "${nested_file}" ]; then
    nested="$(cat "${nested_file}")"
    case "${nested}" in
      1|Y|y) log "   ${module} nested = ${nested}" ;;
      *) problem "   ${module} nested = ${nested}. Enable: echo 'options ${module} nested=1' | sudo tee /etc/modprobe.d/kvm-nested.conf, then reload the module or reboot." ;;
    esac
  else
    log "   ${module} not loaded, so KVM is not in use by the host (fine for VMware)."
  fi
fi

log "3. VMware Workstation"
if command -v vmware >/dev/null 2>&1; then
  log "   $(vmware --version 2>/dev/null || echo 'vmware found')"
else
  warn "   vmware not found on PATH (install Workstation Pro, or ignore on a headless check)."
fi
log "   In each Proxmox VM: Settings > Processors > tick Virtualize Intel VT-x/EPT or AMD-V/RVI."
log "   (If that VM's .vmx lacks vhv.enable = \"TRUE\", it is off.)"

echo
if [ "${ready}" -eq 1 ]; then
  log "READY: this host can offer hardware virtualisation to a VMware guest."
  exit 0
fi
warn "NOT READY: fix the lines above, then run this again."
exit 2
