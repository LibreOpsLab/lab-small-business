# Hypervisor Layer

This directory documents the parts of the lab that live outside any guest OS: choice of
hypervisor, virtual network configuration, and VM inventory/specs.

## The platform

VMware Workstation Pro (Windows/Linux) or Fusion Pro (macOS) — see [`desktop/`](desktop/).
Every VM is hand-built through the hypervisor's own GUI: New VM wizard, interactive OS install,
then a shared post-install baseline (patch, VM tools, locale, SSH keys). This is deliberate:
building each VM by hand is where the actual learning happens in a teaching lab like this one —
see ["Why hand-built, not scripted?"](#why-hand-built-not-scripted) below.

The lab's default subnet (`10.10.10.0/24`) is a suggested starter, not a requirement — see
`scripts/set-subnet.sh` in the repo root if you need a different one before building VMs.

## Contents

- [`networks/README.md`](networks/README.md) — WAN/LAN virtual network design. No setup script
  needed: the lab's LAN Segment (`LAN-LAB`) is created inline while building pfSense's second
  NIC, not by a separate tool.
- [`desktop/README.md`](desktop/README.md) — VMware Workstation Pro (Windows/Linux) / Fusion Pro
  (macOS) basics: the New VM wizard, ISO attachment, and where LAN Segment networking comes from.
- [`desktop/baseline.md`](desktop/baseline.md) — the shared post-install checklist (patch, VM
  tools, locale, SSH keys) applied to every VM except `pfsense01`.
- [`vms/`](vms/) — one spec sheet per VM (CPU/RAM/disk/NIC, OS, static IP where applicable, and
  build/install steps).

## Why hand-built, not scripted?

Earlier versions of this repo drove VM creation on the desktop path with a `vmrun`-scripted
helper (PowerShell on Windows, Bash on Linux). That automation is gone by design: in a teaching
lab, watching a script create a VM teaches nothing, while clicking through the New VM wizard
yourself — and understanding why each setting is what it is — is the point. If you want the
"spin up a whole environment in a box" automated experience instead, that's a separate project,
`lab-scale-business` — a Terraform-driven take on this same environment, deliberately kept out
of this repo so the two don't get tangled together.
