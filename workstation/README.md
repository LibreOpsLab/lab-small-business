# VMware Workstation Layer

This directory documents and automates the parts of the lab that live outside any guest OS:
virtual network configuration and VM inventory/specs. VMware Workstation Pro has no first-class
declarative IaC tool (unlike ESXi/vSphere, it isn't Terraform-provider-friendly out of the box),
so this layer is PowerShell scripts wrapping `vnetlib64.exe` / `vmrun.exe` plus documented specs
— the most repeatable approach available on the free/Pro desktop product.

## Contents

- [`networks/README.md`](networks/README.md) — WAN/LAN virtual network design.
- [`scripts/configure-vmnet.ps1`](scripts/configure-vmnet.ps1) — creates the `VMnet-LAB`
  host-only network.
- [`scripts/create-vms.ps1`](scripts/create-vms.ps1) — `vmrun`-driven helper to clone a base
  VM template into each named lab VM with the correct NIC/resource settings.
- [`vms/`](vms/) — one spec sheet per VM (CPU/RAM/disk/NIC, OS, static IP where applicable).

## Why not Terraform?

The community `terraform-provider-vmworkstation` exists but is unmaintained and doesn't support
Workstation Pro 17+ cleanly. Given this is a single-host lab (not a vSphere cluster), the
PowerShell + `vmrun` approach is more reliable and easier for students to read/modify than
fighting an unmaintained provider. If you later migrate this lab to ESXi/vSphere or vSphere,
swap this directory for a proper `terraform-provider-vsphere` root module — the rest of the
repository (Ansible, Docker, PKI, Samba) is hypervisor-agnostic and needs no changes.
