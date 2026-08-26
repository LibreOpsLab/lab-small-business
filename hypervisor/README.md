# Hypervisor Layer

This directory documents the parts of the lab that live outside any guest OS: choice of
hypervisor, virtual network configuration, and VM inventory/specs.

## Choosing a platform

| Platform                                | Directory              | Host OS                       | Automation                                |
| --------------------------------------- | ---------------------- | ----------------------------- | ----------------------------------------- |
| VMware Workstation/Fusion Pro (default) | [`desktop/`](desktop/) | Windows, Linux, macOS         | Manual — hypervisor GUI + guided baseline |
| Proxmox VE                              | [`proxmox/`](proxmox/) | (n/a — Proxmox is bare-metal) | Terraform (`bpg/proxmox`)                 |

Every VM on the `desktop/` path is hand-built through the hypervisor's own GUI — New VM wizard,
interactive OS install, then a shared post-install baseline (patch, VM tools, locale, SSH keys).
This is deliberate: building each VM by hand is where the actual learning happens in a teaching
lab like this one — see ["Why hand-built, not scripted?"](#why-hand-built-not-scripted) below.
`desktop/` is the default, most-referenced path this repo's other docs
(`docs/DeploymentGuide.md`) assume unless stated otherwise.

**Proxmox is a different kind of platform, not just a different host OS**: it's a real
Type-1 hypervisor (bare-metal, no VMware/host-OS layer at all), and it takes the opposite
approach — automated via Terraform, for anyone who wants a fast, repeatable "environment in a
box" rather than a guided build. It automates only three of the four VMs the desktop path hand-
builds (`win-client01` is manual there too — see [`proxmox/README.md`](proxmox/README.md) for
why), and its Linux VMs install from a cloud image instead of the Server ISO the desktop path
uses. See [`proxmox/README.md`](proxmox/README.md) before assuming it's a drop-in swap for the
desktop path.

Whichever platform you pick, the lab's default subnet (`10.10.10.0/24`) is a suggested
starter, not a requirement — see `scripts/set-subnet.sh` in the repo root if you need a
different one before building VMs.

## Contents

- [`networks/README.md`](networks/README.md) — WAN/LAN virtual network design. No setup script
  needed: the lab's LAN Segment (`LAN-LAB`) is created inline while building pfSense's second
  NIC, not by a separate tool.
- [`desktop/README.md`](desktop/README.md) — VMware Workstation Pro (Windows/Linux) / Fusion Pro
  (macOS) basics: the New VM wizard, ISO attachment, and where LAN Segment networking comes from.
- [`desktop/baseline.md`](desktop/baseline.md) — the shared post-install checklist (patch, VM
  tools, locale, SSH keys) applied to every VM except `pfsense01`.
- [`vms/`](vms/) — one spec sheet per VM (CPU/RAM/disk/NIC, OS, static IP where applicable, and
  build/install steps), shared by every platform above.

## Why hand-built, not scripted?

Earlier versions of this repo drove VM creation on the desktop path with a `vmrun`-scripted
helper (PowerShell on Windows, Bash on Linux). That automation is gone by design: in a teaching
lab, watching a script create a VM teaches nothing, while clicking through the New VM wizard
yourself — and understanding why each setting is what it is — is the point. If you want the
"spin up a whole environment in a box" automated experience instead, that's what the Proxmox
path is for.
