# Hypervisor Layer

This directory documents and automates the parts of the lab that live outside any guest OS:
choice of hypervisor, virtual network configuration, and VM inventory/specs.

## Choosing a platform

| Platform                         | Directory                             | Host OS | Automation                                |
| --------------------------------- | -------------------------------------- | ------- | ------------------------------------------ |
| VMware Workstation Pro (default) | [`vmware-windows/`](vmware-windows/)  | Windows | PowerShell + `vmrun`/`vmware-vdiskmanager` |
| VMware Workstation Pro           | [`vmware-linux/`](vmware-linux/)      | Linux   | Bash + `vmrun`/`vmware-vdiskmanager`       |

Both VMware paths behave identically once the VMs exist — same LAN Segment networking (see
[`networks/README.md`](networks/README.md)), same seed-data format (see
[`vms/seeds/`](vms/seeds/)), same VM specs (see [`vms/`](vms/)). Pick whichever matches the
host OS you're running VMware Workstation Pro on. `vmware-windows/` is the default,
most-referenced path this repo's other docs (`docs/DeploymentGuide.md`) assume unless stated
otherwise.

## Contents

- [`networks/README.md`](networks/README.md) — WAN/LAN virtual network design. No setup script
  needed: the lab's LAN Segment (`LAN-LAB`) is created inline while building pfSense's second
  NIC, not by a separate tool.
- [`vmware-windows/scripts/create-vms.ps1`](vmware-windows/scripts/create-vms.ps1) /
  [`vmware-linux/scripts/create-vms.sh`](vmware-linux/scripts/create-vms.sh) — `vmrun`-driven
  helper that creates VM shells for the four hosts with an unattended-install seed
  (`samba-dc01`, `docker01`, `authentik01`, `win-client01`). `pfsense01` and `linux-client01`
  are built entirely by hand in the Workstation GUI — see their entries under [`vms/`](vms/) —
  and aren't in either script.
- [`vms/`](vms/) — one spec sheet per VM (CPU/RAM/disk/NIC, OS, static IP where applicable),
  shared by every platform above.

## Why not Terraform?

The community `terraform-provider-vmworkstation` exists but is unmaintained and doesn't support
Workstation Pro 17+ cleanly. Given this is a single-host lab (not a vSphere cluster), a small
script wrapping `vmrun` directly is more reliable and easier for students to read/modify than
fighting an unmaintained provider. If you later migrate this lab to ESXi/vSphere, swap the
relevant platform directory for a proper `terraform-provider-vsphere` root module — the rest of
the repository (Ansible, Docker, PKI, Samba) is hypervisor-agnostic and needs no changes.
