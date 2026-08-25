# Multi-Hypervisor VM Provisioning — Design

## Context

The lab's `workstation/` layer assumes one specific host setup: VMware Workstation Pro on
Windows, driven by PowerShell (`create-vms.ps1`, `build-seed-iso.ps1`) wrapping `vmrun.exe` /
`vmware-vdiskmanager.exe` / IMAPI2. `workstation/README.md` frames this explicitly as a
VMware-Workstation-specific layer and even suggests "if you migrate to ESXi/vSphere, swap this
directory for a `terraform-provider-vsphere` root module" — i.e. the repo already anticipated
other hypervisors would eventually show up here.

Goal: let readers run the lab on VMware Workstation Pro for **Linux**, or on **Proxmox VE**, for
those who want "a full LAB" beyond a single Windows desktop host. Windows/VMware/PowerShell stays
the default, documented path — nothing about it changes except its new location.

This is a **teaching artifact** (`CLAUDE.md`). New scripts and Terraform explain *why*, not just
*what*; new docs explain the underlying concept (what a Linux bridge is and why pfSense needs one
per network, why Proxmox's native cloud-init needs no seed-ISO step, why Windows still does) —
not just list commands.

## Scope

Two independent subsystems, designed together (they share the directory rename and the seed-data
architecture) but implemented in sequence:

1. **VMware Workstation Pro on Linux** — a bash port of the existing PowerShell pair. Low risk:
   same tool (`vmrun`), same LAN Segment networking model, same seed-ISO approach.
2. **Proxmox VE** — a `bpg/terraform-provider-proxmox` root module. Higher-value for a "full LAB"
   (Proxmox is a real Type-1 hypervisor) but a genuinely different provisioning model: no
   `vmrun`, Linux bridges instead of LAN Segments, and native cloud-init support that removes the
   seed-ISO step entirely for the three Ubuntu VMs.

Both reuse the same `vms/*.md` spec sheets and `vms/seeds/<name>/` cloud-init/autounattend
content as the existing VMware/Windows path — that content is the single source of truth
regardless of hypervisor.

## Directory layout

`workstation/` is renamed to `hypervisor/` and split by platform. VM specs and seed data move
as-is into a shared `vms/` subtree, unchanged in content:

```
hypervisor/
├── README.md                    # platform picker: which of the three to use, and why
├── networks/README.md           # LAN Segment (VMware) vs Linux bridge (Proxmox), side by side
├── vmware-windows/
│   └── scripts/
│       ├── create-vms.ps1       # existing script, moved as-is, unchanged
│       └── build-seed-iso.ps1   # existing script, moved as-is, unchanged
├── vmware-linux/
│   └── scripts/
│       ├── create-vms.sh        # new — bash port
│       └── build-seed-iso.sh    # new — bash port
├── proxmox/
│   ├── README.md                # WAN options, VirtIO driver prerequisite, terraform walkthrough
│   ├── main.tf
│   ├── vms.tf
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   └── scripts/
│       └── build-autounattend-iso.sh   # new — only Windows needs this on Proxmox
└── vms/                         # UNCHANGED in content — moved from workstation/vms/
    ├── pfsense.md
    ├── samba-dc.md
    ├── docker-server.md
    ├── authentik.md
    ├── linux-client.md
    ├── windows-client.md
    └── seeds/<name>/{user-data,meta-data,autounattend.xml}.example
```

`vms/*.md` spec sheets stay hypervisor-agnostic (CPU/RAM/disk/role/IP), with a short per-platform
notes callout only where values genuinely differ (e.g. VirtIO vs. e1000e NIC driver naming).

### Files/paths to repoint (`workstation/` → `hypervisor/`)

`CLAUDE.md`, `README.md`, `docs/Architecture.md`, `docs/DeploymentGuide.md`, `pfsense/README.md`,
`docs/superpowers/plans/2026-08-16-vmware-vm-helpers.md`,
`docs/superpowers/plans/2026-08-24-lan-segment-manual-first.md`,
`docs/superpowers/specs/2026-08-16-cross-platform-vm-helpers-design.md`,
`docs/superpowers/specs/2026-08-24-lan-segment-manual-first-design.md` (historical spec/plan docs
get their links fixed but are not rewritten otherwise — they're a record of past decisions, not
live docs), plus `.gitignore`'s `workstation/vms/**/*-seed.iso` line →
`hypervisor/vms/**/*-seed.iso`.

## Shared seed-data architecture (unchanged, now with three consumers)

`hypervisor/vms/seeds/<name>/{user-data,meta-data,autounattend.xml}.example` remains the single
source of truth. Each platform's tooling wraps that same content differently:

| Platform            | Ubuntu VMs (samba-dc01, docker01, authentik01)         | win-client01                                  |
| -------------------- | -------------------------------------------------------- | ---------------------------------------------- |
| VMware (Win or Linux) | `user-data`+`meta-data` → NoCloud ISO (`cidata` label)  | `autounattend.xml` → ISO (`AUTOUNATTEND` label) |
| Proxmox              | `user-data`+`meta-data` → uploaded as a Terraform-managed cloud-init **snippet**, referenced by the VM's `initialization` block — no ISO built at all | `autounattend.xml` → ISO, built by `build-autounattend-iso.sh`, uploaded via Terraform's file resource |

Editing one seed file is enough regardless of which hypervisor you deploy to. The
placeholder-guard (refusing to build seed media from an un-filled-in `.example` copy — the same
`replace-with-a-mkpasswd-hash|REPLACE_ME` check `build-seed-iso.ps1` already does) is reused
verbatim in every new script that builds seed media (`build-seed-iso.sh`,
`build-autounattend-iso.sh`); Proxmox's native-cloud-init path re-implements the same guard in
Terraform-adjacent tooling since it never shells out to a build script for those three VMs.

## VMware Workstation on Linux

- `create-vms.sh` mirrors `create-vms.ps1`: the same VM table (name/vcpu/ram/disk/nic/iso/
  firmware/vtpm/guest-os), the same generated `.vmx` content, the same `vmrun`/
  `vmware-vdiskmanager` calls. Default tool path `/usr/bin/vmrun` (override via `--vmware-path`).
  Sources `scripts/lib/common.sh` for `log`/`die`/`require_cmd` (that helper library already
  exists at the repo root and isn't VMware/Windows-specific), starts `set -euo pipefail`, tracked
  executable (`chmod +x`).
- `build-seed-iso.sh` auto-detects the same two seed formats the same way, runs the same
  placeholder guard, and builds the ISO with `genisoimage` (`-o out.iso -V cidata -J -R` for
  NoCloud; `-V AUTOUNATTEND` for Windows) instead of IMAPI2FS. Same idempotency rule (skip if the
  output is newer than its source files).
- `pfsense01` and `linux-client01` stay excluded from `create-vms.sh`'s table — same manual-build
  behavior as the Windows script.
- Networking is unchanged: Workstation Pro for Linux has LAN Segments too, so
  `hypervisor/networks/README.md`'s existing instructions apply with only a one-line "GUI wording
  may differ slightly on Linux" note, not a rewrite.

## Proxmox (Terraform)

**Why Terraform, not a `qm`-wrapping shell script:** `workstation/README.md`'s existing "Why not
Terraform?" reasoning is specific to VMware Workstation's *unmaintained* community provider —
Proxmox has an actively-maintained one (`bpg/terraform-provider-proxmox`). Given this repo is
"IaC-driven" and treats doc/code clarity as the product, hand-rolling `qm`/`pvesh` calls here
would be a step backward from what's actually available, and Terraform is the pattern students
will meet in real Proxmox shops.

**Module (`hypervisor/proxmox/`):**

- `main.tf` — provider block pointed at the Proxmox API, authenticated via API token.
  **TLS is verified against a real CA — `insecure = true` is never used**, consistent with
  CLAUDE.md's certificate-validation rule. `proxmox/README.md` documents issuing Proxmox's web
  cert from the lab's own PKI (preferred) or explicitly trusting its self-signed one via a CA
  file, not skipping verification.
- `variables.tf` — API URL/token, target node name, storage pool names (disks, ISO images,
  snippets), bridge names (`vmbr-wan`, `vmbr-lan`).
- `vms.tf` — `for_each` over a map matching the same VM-table shape used by the PowerShell/bash
  scripts (name/vcpu/ram/disk/bridge/machine-type/bios/vtpm). Only `samba-dc01`, `docker01`,
  `authentik01`, `win-client01` are enumerated — `pfsense01` and `linux-client01` are excluded
  from the module entirely and built by hand in the Proxmox web UI, mirroring today's VMware
  exclusion and CLAUDE.md's "pfSense is config-template-plus-instructions, not fully automated."
- `terraform.tfvars.example` committed; real `terraform.tfvars` (holds the API token) and
  `*.tfstate` are already covered by `.gitignore`'s existing generic Terraform patterns.

**Linux VMs** (`samba-dc01`, `docker01`, `authentik01`) use Proxmox's native cloud-init: their
`user-data`/`meta-data` are uploaded as Terraform-managed snippet files
(`proxmox_virtual_environment_file`, `content_type = "snippets"`) and wired directly into the VM
resource's `initialization` block. No ISO-building step for these three at all — simpler than
every other platform in this repo.

**win-client01** needs real install media, same as elsewhere: `q35` machine type, OVMF +
`efi-disk`, `tpm-state: v2.0`, VirtIO SCSI/net (standard practice on Proxmox for performance —
requires a `virtio-win.iso` mounted as a second boot-time CD-ROM alongside `Win11.iso`, documented
as a prerequisite in `proxmox/README.md` next to where `Win11.iso` is already required). Its
`autounattend.xml` seed is built locally by `build-autounattend-iso.sh` (same placeholder guard,
reusing the VMware-Linux script's ISO-building logic) and then uploaded to Proxmox ISO storage by
Terraform's file resource — documented as a two-step "run this script once, then `terraform
apply`," the same shape `create-vms.ps1` already uses when it calls `build-seed-iso.ps1` inline.

**WAN networking:** `proxmox/README.md` documents both options a reader might have, since Proxmox
has no VMware-VMnet8-style built-in NAT:

- **Dedicated bridged physical NIC** (`vmbr-wan`) — primary/recommended path, closest to a real
  deployment, pfSense does real DHCP-client-on-WAN against the reader's actual router. Requires a
  spare physical (or USB) NIC on the Proxmox box.
- **Proxmox SDN NAT zone** — alternative for single-NIC boxes, no spare hardware needed.

`vmbr-lan` is the isolated internal bridge every other VM's NIC attaches to, mirroring the
existing "only pfSense touches WAN" rule from `hypervisor/networks/README.md`.

## Explicitly out of scope

- No change to post-install automation (Ansible roles, `bootstrap-ad.sh`, etc.) — this project
  only covers "blank VM/Terraform apply" through "OS installed, reachable over SSH/WinRM," exactly
  where the existing post-install automation already picks up, regardless of hypervisor.
- No macOS or VirtualBox support — not requested; if wanted later, the seed-data architecture
  already generalizes to a fourth platform directory without rework.
- No Proxmox clustering — single-node only, consistent with `docs/Architecture.md`'s existing
  single-host framing.
- `pfsense01` stays fully manual on every platform — no unattended pfSense installer exists
  (already stated in `CLAUDE.md` and `pfsense/README.md`; unchanged by this project).

## Validation

No CI in this repo (`CLAUDE.md`). Same bar as everywhere else here:

- `bash -n` on every new/touched `.sh` (`create-vms.sh`, `build-seed-iso.sh`,
  `build-autounattend-iso.sh`), `chmod +x` on each (scripts are tracked executable).
- `terraform fmt -check` and `terraform validate` on `hypervisor/proxmox/` (no live Proxmox API
  available in this environment to `plan`/`apply` against — reviewed for correctness by reading,
  same caveat this repo already applies to Ansible/compose/Samba changes).
- Manual read-through of the PowerShell-derived bash logic — no local `.ps1`/`.sh` diffing tool,
  so each port is checked line-by-line against its PowerShell source for behavioral parity.
- Every IP/hostname in any new or moved file cross-checked against `docs/Architecture.md`'s
  component inventory.
- `grep -rl "workstation/"` across the repo re-run after the rename to confirm zero remaining
  stale links.
