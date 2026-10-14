# Desktop Hypervisor Manual Baseline — Design

## Context

This is sub-project **A** of a five-part restructuring effort (D → A → C → B → E; see
[2026-08-26-subnet-picker-tool-design.md](2026-08-26-subnet-picker-tool-design.md) for D, already
implemented). The repo's teaching goal is hands-on learning: build a piece, confirm it works,
understand what you did, connect it to what's already built, move to the next piece. The desktop
VMware path currently works against that goal — `create-vms.ps1`/`create-vms.sh` fully
unattended-install 4 of the lab's 6 VMs (`samba-dc01`, `docker01`, `authentik01`, `win-client01`)
via cloud-init/`autounattend.xml` seed ISOs, leaving nothing for the learner to actually do at the
OS-install stage. The other 2 VMs (`pfsense01`, `linux-client01`) are already hand-built through
the hypervisor GUI with an interactive OS install — that existing pattern is the target this
sub-project extends to the other 4.

## Goal

1. Remove the seed-ISO/unattended-install automation for the 4 scripted VMs; every VM in the lab
   becomes a hand-built VM with an interactive OS install, the same pattern `pfsense.md` and
   `linux-client.md` already document.
2. Introduce a single shared post-install checklist — patch, VM tools, locale, SSH keys — applied
   uniformly across the 5 general-purpose-OS VMs (not `pfsense01`, which is a BSD appliance with
   no VM-tools concept and no general-purpose SSH shell).
3. Collapse `hypervisor/vmware-windows/` and `hypervisor/vmware-linux/` into one
   `hypervisor/desktop/` directory, since the host-OS split existed only because the PowerShell
   vs. Bash automation differed — with that automation gone, the GUI instructions are identical
   regardless of host OS.
4. Update every doc that currently points at the removed automation
   (`docs/DeploymentGuide.md`, `README.md`, `hypervisor/README.md`, and the four affected
   `hypervisor/vms/*.md` pages) to the new manual flow.

## Non-goals

- **App-layer content is out of scope** (sub-project C). Every VM's existing "Post-install"
  section (`bootstrap-ad.sh`, domain-join scripts, Ansible/`site.yml` runs, Docker Compose
  bring-up) is untouched. `DeploymentGuide.md`'s steps 3, 5, 7 only get their VM-*creation*
  sentences swapped — their app-config content stays as-is.
- **Proxmox is out of scope** (sub-project B, not yet run). `hypervisor/proxmox/` and the
  `proxmox-user-data.example` cloud-init seeds stay in the repo untouched — they leave together
  when B extracts Proxmox into the separate server-automation repo. Every `vms/*.md` page's "On
  Proxmox" aside stays as-is.
- **No reflection/pedagogy narrative added at the VM-build stage.** `docs/StudentLabManual.md`'s
  "build it, then understand what you just did" style stays scoped to the app-usage phase (its
  existing "Day 1 checklist"). The VM-build docs stay procedural, matching `pfsense.md`'s
  existing tone — the why is inline as brief rationale, not a separate reflection section.
- **No explicit VirtualBox/Hyper-V/Parallels/UTM instructions.** Steps are written in
  hypervisor-agnostic language (specs, not click-paths, where possible) so they transfer, but
  concrete click-paths are given only for VMware Workstation Pro (Windows/Linux hosts) and VMware
  Fusion Pro (macOS host) — same product family, near-identical GUI.
- **`win-client01` gets SSH-key deployment, not a Windows Server VM.** The lab's Windows-client
  role and topology are unchanged; "even for windows server" in the originating request meant
  "yes, on the Windows box too, not just the Linux ones."

## Design

### Directory layout

- Delete: `hypervisor/vmware-windows/` and `hypervisor/vmware-linux/` (each directory's
  `scripts/` and `README.md`) entirely.
- Delete: `hypervisor/vms/seeds/samba-dc01/user-data.example`,
  `hypervisor/vms/seeds/samba-dc01/meta-data.example`,
  `hypervisor/vms/seeds/docker01/user-data.example`,
  `hypervisor/vms/seeds/docker01/meta-data.example`,
  `hypervisor/vms/seeds/authentik01/user-data.example`,
  `hypervisor/vms/seeds/authentik01/meta-data.example`,
  `hypervisor/vms/seeds/win-client01/autounattend.xml.example`.
- Keep: `hypervisor/vms/seeds/{samba-dc01,docker01,authentik01}/proxmox-user-data.example` — still
  needed by `hypervisor/proxmox/`'s Terraform module until sub-project B.
- New: `hypervisor/desktop/README.md` — the VM-creation preamble (VMware Workstation Pro /
  Fusion Pro GUI basics: New VM wizard, ISO attachment, LAN Segment networking — the generic
  parts currently duplicated across `vmware-windows/README.md` and `vmware-linux/README.md`,
  minus every PowerShell/Bash-specific line).
- New: `hypervisor/desktop/baseline.md` — the shared post-install checklist (below).
- `hypervisor/proxmox/` untouched.

### `hypervisor/desktop/baseline.md`

Applied after interactive OS install on `samba-dc01`, `docker01`, `authentik01`,
`linux-client01`, `win-client01`. Four steps; each documents the Linux command and, where it
differs, the Windows equivalent:

1. **Patch** — `sudo apt update && sudo apt full-upgrade -y`, reboot if the kernel updated.
   Windows: Settings → Windows Update → Check for updates, reboot if prompted.
2. **VM tools** — `sudo apt install -y open-vm-tools` (plus `open-vm-tools-desktop` on
   `linux-client01` only, for clipboard/display integration — the 3 servers are headless).
   Windows: VM menu → **Install VMware Tools**, run the mounted installer.
3. **Locale** — verify/correct with `localectl set-locale LANG=<locale>`,
   `timedatectl set-timezone <zone>`, and confirm keyboard layout — installer defaults may not
   match the learner's actual location. Windows: Settings → Time & Language.
4. **SSH keys** — for the three Ubuntu Server hosts and `linux-client01`, use Subiquity's
   native "paste a public key" step during install rather than a post-install step (this is what
   later lets the control host's Ansible runs authenticate — previously undocumented; the old
   seed's own comment called it "up to you"). For `win-client01`: enable the OpenSSH Server
   optional feature (`Settings → Apps → Optional Features` or
   `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`), then add the public key to
   `C:\ProgramData\ssh\administrators_authorized_keys` — Windows OpenSSH routes admin accounts
   through this file instead of the per-user `~/.ssh/authorized_keys` Linux uses, worth calling
   out explicitly since it trips people up.

### Per-VM doc changes

`hypervisor/vms/samba-dc.md`, `docker-server.md`, `authentik.md`, `windows-client.md`: each
current "Autoinstall" section (seed-file copy/fill instructions, `create-vms.ps1` references) is
replaced with a "Build + install" section in `pfsense.md`/`linux-client.md`'s existing style —
VM-creation specs (already present in each page's top table), then the interactive-install steps
specific to that VM. `samba-dc.md`, `docker-server.md`, `authentik.md` call out setting the
host's static IP in Subiquity's network step (the one difference from `linux-client01`'s DHCP
install); `windows-client.md` documents the interactive Windows 11 install directly (no more
`autounattend.xml`). Each section ends with: "Then apply
[`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing." Existing
"Post-install" sections and "On Proxmox" asides are untouched.

### `docs/DeploymentGuide.md`

- Intro paragraph: drop the host-OS-split framing; point at `hypervisor/desktop/README.md`
  generically. Proxmox alternative-path mention stays.
- Step 0 (Host prerequisites): remove the "cloned in two places" / PowerShell-vs-WSL2 bullet and
  the `mkpasswd`/seed-ISO bullet — `linux-client01` was always the real control host, and there's
  no seed ISO left to build.
- Steps 1-2 (pfSense, `linux-client01`): re-point "create a new VM per..." references at
  `hypervisor/desktop/`; add "apply `baseline.md`" to the end of step 2.
- Steps 3, 5, 7: swap each "fill in the seed, `create-vms.ps1` builds and boots it unattended"
  sentence for "build by hand per `vms/<name>.md`, apply `baseline.md`" — one to two sentences
  each. Every other line in these steps (app bootstrap, PKI issuance, Ansible runs, domain-join)
  is untouched.

### `README.md` (top-level) and `hypervisor/README.md`

- Top-level `README.md`'s Quick Start block: replace the PowerShell/Bash `create-vms` lines with
  a pointer to building VMs 1-6 by hand per `hypervisor/desktop/README.md` + each `vms/*.md`. The
  Proxmox `terraform apply` line stays unchanged.
- `hypervisor/README.md`: the platform table's `vmware-windows/`/`vmware-linux/` rows collapse
  into one `desktop/` row (Directory: `desktop/`, Host OS: "Windows, Linux, macOS", Automation:
  "Manual — hypervisor GUI + guided baseline"). The "Contents" and "Why not Terraform?" sections
  are updated to describe the new single directory instead of the two removed ones; the Proxmox
  row and its explanatory paragraphs are untouched.

## Testing

No test suite (bash-only repo, docs-and-scripts change). Verification is:

- `bash -n` on any remaining shell scripts touched (none expected — this sub-project is
  docs-only plus directory/file deletions).
- Link check: grep the whole repo for `vmware-windows`, `vmware-linux`, `create-vms`,
  `build-seed-iso` after the change — expect zero remaining hits outside historical
  `docs/superpowers/specs/`/`docs/superpowers/plans/` records (which are a point-in-time record,
  not live docs, and are never edited retroactively).
- Manual read-through of each edited `vms/*.md` page and `DeploymentGuide.md` end to end,
  confirming the sequence reads coherently with no dangling references to removed scripts.

## Open questions

None — this sub-project is fully scoped by the design above.
