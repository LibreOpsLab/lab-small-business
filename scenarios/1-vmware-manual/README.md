# Scenario 1: Native VMware VMs

**Goal: learning.** You install each base OS yourself in VMware Workstation, then run a script
for each service, one at a time, reading what it does as you go. Nested virtualisation is **not**
needed.

This is also the "hand-build first" half of the Advanced Server Security unit: week 2 hand-installs
Linux and Windows, and later weeks rebuild the same machines from code (scenario 2).

## Host OS: Windows or Linux

| | Windows host | Linux host |
|---|---|---|
| VMware | Workstation Pro | Workstation Pro |
| VM creation helper (optional) | [`create-vms.ps1`](../../hypervisor/vmware-windows/scripts/create-vms.ps1) | [`create-vms.sh`](../../hypervisor/vmware-linux/scripts/create-vms.sh) |
| Admin / control host | WSL 2 ([`docs/WSLSetup.md`](../../docs/WSLSetup.md)) or `linux-client01` | the host itself, or `linux-client01` |

Guests are the same on both: Linux servers, a Windows 11 client, and (planned) a Windows Server
member server. The two helpers behave identically once the VMs exist.

## Steps today

1. Networks: [`hypervisor/networks/README.md`](../../hypervisor/networks/README.md).
2. VM specs: [`hypervisor/vms/`](../../hypervisor/vms/).
3. The full ordered walkthrough: [`docs/DeploymentGuide.md`](../../docs/DeploymentGuide.md).

## Planned

- A numbered, step-by-step rewrite: one page per step with the command, what it does, and how to
  check it worked. See the
  [delivery plan](../../docs/superpowers/specs/2026-10-14-three-build-scenarios-design.md#delivery-plan).
- A Windows Server member server (evaluation licence) for the AD, GPO and patching weeks.
