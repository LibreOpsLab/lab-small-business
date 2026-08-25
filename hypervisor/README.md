# VMware Workstation Layer

This directory documents and automates the parts of the lab that live outside any guest OS:
virtual network configuration and VM inventory/specs. VMware Workstation Pro has no first-class
declarative IaC tool (unlike ESXi/vSphere, it isn't Terraform-provider-friendly out of the box),
so this layer is a PowerShell script wrapping VMware's `vmrun.exe` / `vmware-vdiskmanager.exe`
plus documented specs — the most repeatable approach available on the free/Pro desktop product.

## Contents

- [`networks/README.md`](networks/README.md) — WAN/LAN virtual network design. No setup script
  needed: the lab's LAN Segment (`LAN-LAB`) is created inline while building pfSense's second
  NIC, not by a separate tool.
- [`scripts/create-vms.ps1`](scripts/create-vms.ps1) — `vmrun`-driven helper that creates VM
  shells for the four hosts with an unattended-install seed (`samba-dc01`, `docker01`,
  `authentik01`, `win-client01`). `pfsense01` and `linux-client01` are built entirely by hand in
  the Workstation GUI — see their entries under [`vms/`](vms/) — and aren't in this script.
- [`vms/`](vms/) — one spec sheet per VM (CPU/RAM/disk/NIC, OS, static IP where applicable).

## Why not Terraform?

The community `terraform-provider-vmworkstation` exists but is unmaintained and doesn't support
Workstation Pro 17+ cleanly. Given this is a single-host lab (not a vSphere cluster), the
PowerShell + `vmrun` approach is more reliable and easier for students to read/modify than
fighting an unmaintained provider. If you later migrate this lab to ESXi/vSphere or vSphere,
swap this directory for a proper `terraform-provider-vsphere` root module — the rest of the
repository (Ansible, Docker, PKI, Samba) is hypervisor-agnostic and needs no changes.
