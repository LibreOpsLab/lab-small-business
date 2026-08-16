# Cross-Platform VM Provisioning Helpers — Design

## Context

The lab currently assumes VMware Workstation Pro on the host (see `docs/DeploymentGuide.md`,
`workstation/`). That layer already has real automation:

- `workstation/scripts/configure-vmnet.ps1` — creates the `VMnet-LAB` host-only network
  (`10.10.0.0/24`, DHCP disabled).
- `workstation/scripts/create-vms.ps1` — creates each VM's disk + `.vmx` shell (CPU/RAM/NIC from
  a table matching `docs/Architecture.md`'s component inventory) and registers it with `vmrun`.
- `workstation/vms/*.md` — one spec sheet per VM. For Ubuntu Server hosts, each embeds an inline
  `autoinstall` YAML snippet a student is expected to copy into a file by hand and burn onto a
  seed ISO/USB themselves.

Goal: extend this to VirtualBox (Windows/macOS/Linux) and Proxmox, with VMware/Windows staying
the default, documented path — and, while doing so, close the automation gap that already exists
in the VMware layer (the inline-YAML-a-student-copies-by-hand pattern isn't actually unattended).

This is a **teaching artifact** (see `CLAUDE.md`). Every new script carries comments explaining
*why*, not just *what*; every new doc explains the underlying concept (what a cloud-init NoCloud
datasource is, why Windows 11 needs vTPM/UEFI, why pfSense can't be unattended) rather than only
listing steps.

## Scope of this spec

- **Phase 1 (fully specified, implemented now):** VMware Workstation improvements — real seed
  files, an ISO-builder script, `create-vms.ps1` updates, doc updates.
- **Phase 2 (sketched only, brainstormed separately before implementation):** VirtualBox layer.
- **Phase 3 (sketched only, brainstormed separately before implementation):** Proxmox layer.

Phases 2 and 3 are intentionally left at architecture-sketch depth — each is a fairly independent
subsystem, and the right level of per-OS detail (VirtualBox's networking model, Proxmox's
bridge/cloud-init setup) is easier to get right after Phase 1 has been built and reviewed once.

## Directory layout

```
workstation/                    (existing — improved in Phase 1)
  networks/README.md
  scripts/
    configure-vmnet.ps1         (existing, unchanged)
    create-vms.ps1              (updated)
    build-seed-iso.ps1          (new)
  vms/
    pfsense.md                  (unchanged — no unattended installer exists)
    samba-dc.md                 (updated — points at real seed file)
    docker-server.md            (updated)
    authentik.md                (updated)
    linux-client.md             (unchanged — desktop install intentionally manual)
    windows-client.md           (updated — autounattend + vTPM/UEFI)
    seeds/
      samba-dc01/user-data, meta-data
      docker01/user-data, meta-data
      authentik01/user-data, meta-data
      win-client01/autounattend.xml

virtualbox/                     (Phase 2 — not built in this pass)
  networks/README.md
  scripts/
  vms/

proxmox/                        (Phase 3 — not built in this pass)
  scripts/
  vms/
```

`workstation/vms/*.md` keep their existing role-based names (they already don't match instance
names 1:1 — e.g. `samba-dc.md` documents `samba-dc01`); the new `seeds/<instance-name>/` subtree
uses full instance names so `build-seed-iso.ps1` and `create-vms.ps1` can look a VM up by the same
`Name` field already used in `create-vms.ps1`'s `$VMs` table, with no name-mapping logic needed.

## Shared seed-data architecture

This is the piece Phase 2/3 will reuse unchanged, so it's designed platform-agnostic even though
only the VMware consumer is built now.

**Format:** cloud-init's "NoCloud" datasource — a `user-data` + `meta-data` pair, mountable as
readable-only ISO-9660 media, is the same input Ubuntu's `autoinstall` (Subiquity) already
consumes and the same thing the existing inline YAML in `samba-dc.md` etc. already targets. No
new format is being introduced — the gap is only that today it's an inline doc snippet with no
tooling to turn it into bootable seed media.

**Files, per autoinstall-capable VM** (`samba-dc01`, `docker01`, `authentik01`):

- `workstation/vms/seeds/<name>/user-data` — real file, checked in, heavily commented. Contains
  the placeholders that already exist informally in the docs today (SSH key, `mkpasswd`-generated
  password hash) plus the per-VM static IP/hostname from `docs/Architecture.md`'s addressing
  table.
- `workstation/vms/seeds/<name>/meta-data` — empty (cloud-init requires the file to exist, not
  that it contain anything, for the NoCloud datasource to be recognized).

**`win-client01` gets `autounattend.xml`** instead — Windows Setup's own unattended-install
mechanism, not cloud-init. Same idea (real file, placeholders, mounted as a second disc at
install time), different format because Windows Setup doesn't speak cloud-init.

**Seed media is built per-host-OS**, since "how do I make an ISO" differs:

- Windows: IMAPI2 (the `IMAPI2FS.MsftFileSystemImage` COM object), built into Windows — no
  Windows ADK / `oscdimg` install required. The seed disc doesn't need to be bootable, just
  readable, so IMAPI2's plain data-disc mode is sufficient.
- (Phase 2/3, sketch) Linux: `genisoimage` or `xorriso`. macOS: `hdiutil makehybrid`.

`build-seed-iso.ps1` wraps the Windows (IMAPI2) case now; the script is written so a Phase 2/3
Linux/macOS equivalent is a small, separate, parallel script rather than a refactor of this one —
consistent with this repo's one-real-script-per-concern style.

## Phase 1: VMware Workstation

### New files

- `workstation/scripts/build-seed-iso.ps1` — given a VM name, finds
  `workstation/vms/seeds/<name>/`, builds a NoCloud (or, for `win-client01`, a plain
  `autounattend.xml`) ISO via IMAPI2, writes it next to the VM's `.vmx`
  (`workstation/vms/<name>/<name>-seed.iso`). Idempotent: skips if the seed ISO already exists
  and is newer than its source files. Heavily commented — this script is as much a teaching
  artifact about "what is a seed ISO and why does cloud-init need one" as it is a working tool.
- `workstation/vms/seeds/<name>/user-data` + `meta-data` for `samba-dc01`, `docker01`,
  `authentik01` — same content the docs already describe inline today, moved into real files,
  with comments explaining each cloud-init stanza (`identity`, `network`, `ssh`, `late-commands`).
- `workstation/vms/seeds/win-client01/autounattend.xml` — commented answer file covering
  hostname, local admin creation matching the `labadmin` pattern used elsewhere, and enabling
  WinRM/SSH-if-available so it's reachable for the domain-join step that already exists
  (`join-windows-client.ps1`).

### Updated files

- `workstation/scripts/create-vms.ps1`:
  - After creating each VM's `.vmx`, call `build-seed-iso.ps1` for any VM that has a
    `workstation/vms/seeds/<name>/` directory, and attach the resulting ISO as a second CD-ROM
    (`ide1:1`) — the first (`ide1:0`) stays the OS installer ISO as it is today.
  - Add `firmware = "efi"` and `vtpm.present = "TRUE"` for `win-client01` specifically. **This is
    a real, currently-latent bug fix**, not scope creep: Windows 11 Setup refuses to install
    without a detected TPM 2.0 + UEFI, and the current script produces a BIOS VM with no vTPM —
    today's "install interactively" path would hit this wall regardless of this project. Comment
    in the script explains why this VM (and only this one) gets these two lines.
  - `pfsense01` and `linux-client01` are untouched — no seed directory exists for them, so the
    existing behavior (OS ISO only, interactive install) is preserved exactly.
- `workstation/vms/samba-dc.md`, `docker-server.md`, `authentik.md`: replace the inline YAML
  block with a pointer to the real `seeds/<name>/user-data` file, plus 2-3 sentences on *why*
  this mechanism exists (what NoCloud is, why `create-vms.ps1` now attaches it automatically) —
  teaching content, not just "see this file."
- `workstation/vms/windows-client.md`: replace "install interactively" with a pointer to
  `autounattend.xml`, and add the vTPM/UEFI explanation (why Win11 needs it, why it wasn't there
  before).
- `docs/DeploymentGuide.md`: steps 3/5 (Samba DC, Docker/Authentik hosts) and the endpoints step
  updated to reflect that OS install is now unattended by default — student boots the VM and
  waits, rather than following an install wizard. Manual GUI fallback stays documented (not every
  student wants unattended, and it's a good thing to understand either way).
- `docs/Architecture.md`: no structural change needed — component inventory/addressing table is
  unchanged, this phase only changes *how* the existing VMs get installed.

### Explicitly out of scope for Phase 1

- `pfsense01` stays fully manual — no unattended installer exists for pfSense (already stated in
  `CLAUDE.md` and `pfsense/README.md`; this project doesn't change that).
- `linux-client01` stays fully manual — desktop install is intentionally hands-on per the
  existing doc ("unattended desktop installs are out of scope for a lab teaching manual desktop
  use").
- No change to post-install automation (Ansible roles, `bootstrap-ad.sh`, etc.) — this project is
  entirely about getting from "blank VM" to "OS installed, reachable over SSH/WinRM," which is
  exactly where the existing post-install automation already picks up.

## Phase 2 (sketch): VirtualBox

Hand-rolled `VBoxManage`-driven scripts, one pair mirroring `configure-vmnet.ps1` /
`create-vms.ps1`, reusing the Phase 1 seed-data files unchanged (only the ISO-build step and the
VM-creation commands differ; the `user-data`/`autounattend.xml` content is platform-agnostic by
design). Scripts are bash (Linux/macOS) with a thin, equivalent PowerShell version for Windows,
rather than one Vagrant abstraction layer — this keeps the same "teach the underlying CLI tool"
approach the VMware layer already takes, and keeps VirtualBox's per-OS quirks visible instead of
hidden.

**Open questions for the Phase 2 brainstorm** (not resolved here):

- VirtualBox 7 changed host-only networking (`vboxmanage hostonlyif` vs. the newer NatNetwork /
  DHCP-server config) — behavior and default paths differ across Windows/macOS/Linux enough that
  the network script likely needs real per-OS branches, not just path substitution.
- Whether `VBoxManage unattended` (VirtualBox's own built-in unattended-install command, which
  exists as an alternative to hand-built seed ISOs) is a better fit than reusing the Phase 1
  ISO-based approach.

## Phase 3 (sketch): Proxmox

Bash scripts using `qm create` + Proxmox's native cloud-init drive support (`qm set --cicustom`),
reusing the same `user-data` files directly — Proxmox understands cloud-init datasources natively,
so this phase, unlike VirtualBox/VMware, needs no seed-ISO-building step at all. `pfsense01` stays
manual (no official pfSense cloud image exists).

**Open questions for the Phase 3 brainstorm** (not resolved here):

- Proxmox host bridge/VLAN configuration needed to reproduce the WAN/LAN split that
  `VMnet8`/`VMnet-LAB` provide on Workstation.
- Whether to target a single Proxmox node (matches "single host lab" framing used elsewhere in
  this repo) or leave room for a cluster — recommend single-node only, consistent with
  `docs/Architecture.md`'s existing framing, but worth confirming explicitly in that brainstorm.

## Validation

No CI in this repo (per `CLAUDE.md`). Same bar as everywhere else here:

- `bash -n` on every new/touched `.sh` (none in Phase 1 — it's all PowerShell/YAML/XML this
  phase, but the convention still applies to Phase 2/3's bash scripts).
- Manual, careful read-through of the PowerShell changes (no local syntax-checker available for
  `.ps1` in this environment).
- Every IP/hostname in every new seed file cross-checked against `docs/Architecture.md`'s
  component inventory and `ansible/inventory/hosts.ini` — a typo'd static IP here is the kind of
  bug that only surfaces confusingly, much later, at the Ansible step.
- Idempotency preserved: `create-vms.ps1` already skips VMs whose `.vmx` exists;
  `build-seed-iso.ps1` follows the same "skip if already built and up to date" pattern.
