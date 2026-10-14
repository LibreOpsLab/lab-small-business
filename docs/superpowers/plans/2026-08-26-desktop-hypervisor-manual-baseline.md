# Desktop Hypervisor Manual Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the seed-ISO/unattended-install automation for `samba-dc01`, `docker01`, `authentik01`, `win-client01`; every VM in the lab becomes hand-built through the hypervisor GUI with an interactive OS install, followed by a shared post-install baseline (patch, VM tools, locale, SSH keys), matching the pattern `pfsense.md`/`linux-client.md` already use.

**Architecture:** Delete `hypervisor/vmware-windows/`, `hypervisor/vmware-linux/`, and the VMware-specific seed example files. Add `hypervisor/desktop/` (a single directory replacing the host-OS split, since there's no more per-host-OS automation to differ by) containing `README.md` (VM-creation preamble) and `baseline.md` (the shared checklist). Rewrite the four affected `hypervisor/vms/*.md` pages' install sections, add a baseline pointer to `linux-client.md`, and update every doc that references the removed automation (`docs/DeploymentGuide.md`, `README.md`, `hypervisor/README.md`).

**Tech Stack:** Markdown documentation only — no code, no test framework. Verification is link/reference greps and read-throughs.

**Spec:** [docs/superpowers/specs/2026-08-26-desktop-hypervisor-manual-baseline-design.md](../specs/2026-08-26-desktop-hypervisor-manual-baseline-design.md)

## Global Constraints

- Proxmox (`hypervisor/proxmox/`) and its 3 `proxmox-user-data.example` seed files are untouched — out of scope (sub-project B).
- App-layer content (every VM's existing "Post-install" section, `DeploymentGuide.md` steps' bootstrap/Ansible/Docker content) is untouched — out of scope (sub-project C).
- No reflection/pedagogy prompts added — VM-build docs stay procedural, matching `pfsense.md`'s existing tone.
- Concrete click-paths are given only for VMware Workstation Pro (Windows/Linux) and VMware Fusion Pro (macOS) — no VirtualBox/Hyper-V/Parallels/UTM instructions.
- `win-client01` gets SSH-key deployment added to its baseline — no new Windows Server VM.

---

### Task 1: Delete the removed automation

**Files:**
- Delete: `hypervisor/vmware-windows/scripts/build-seed-iso.ps1`
- Delete: `hypervisor/vmware-windows/scripts/create-vms.ps1`
- Delete: `hypervisor/vmware-linux/scripts/build-seed-iso.sh`
- Delete: `hypervisor/vmware-linux/scripts/create-vms.sh`
- Delete: `hypervisor/vms/seeds/samba-dc01/user-data.example`
- Delete: `hypervisor/vms/seeds/samba-dc01/meta-data.example`
- Delete: `hypervisor/vms/seeds/docker01/user-data.example`
- Delete: `hypervisor/vms/seeds/docker01/meta-data.example`
- Delete: `hypervisor/vms/seeds/authentik01/user-data.example`
- Delete: `hypervisor/vms/seeds/authentik01/meta-data.example`
- Delete: `hypervisor/vms/seeds/win-client01/autounattend.xml.example`

**Interfaces:** None — pure deletion, no other task depends on these files existing.

- [ ] **Step 1: Delete the two automation directories and the VMware-specific seed files**

```bash
rm -rf hypervisor/vmware-windows hypervisor/vmware-linux
rm -f hypervisor/vms/seeds/samba-dc01/user-data.example \
      hypervisor/vms/seeds/samba-dc01/meta-data.example \
      hypervisor/vms/seeds/docker01/user-data.example \
      hypervisor/vms/seeds/docker01/meta-data.example \
      hypervisor/vms/seeds/authentik01/user-data.example \
      hypervisor/vms/seeds/authentik01/meta-data.example \
      hypervisor/vms/seeds/win-client01/autounattend.xml.example
```

- [ ] **Step 2: Verify the Proxmox seeds survived and win-client01's seed dir is now empty**

Run:
```bash
find hypervisor/vms/seeds -type f | sort
find hypervisor/vms/seeds/win-client01 -type d
```
Expected: only the 3 `proxmox-user-data.example` files remain under `samba-dc01/`, `docker01/`, `authentik01/`; `hypervisor/vms/seeds/win-client01/` is now an empty directory (kept, not deleted — Proxmox doesn't use it, but removing an otherwise-empty directory isn't necessary and leaving it is harmless).

- [ ] **Step 3: Commit**

```bash
git add -A hypervisor/vmware-windows hypervisor/vmware-linux hypervisor/vms/seeds
git status --short
git commit -m "$(cat <<'EOF'
Remove vmrun-driven VM automation and its VMware-specific seed files

samba-dc01, docker01, authentik01, and win-client01 no longer install
unattended — every VM in the lab is now hand-built through the hypervisor
GUI with an interactive OS install (hypervisor/vms/*.md, next commits).
Proxmox's cloud-init seeds are untouched; Proxmox extraction is a separate,
later sub-project.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: New `hypervisor/desktop/` directory

**Files:**
- Create: `hypervisor/desktop/README.md`
- Create: `hypervisor/desktop/baseline.md`

**Interfaces:**
- Produces: `../desktop/baseline.md` and `../desktop/README.md` as link targets Task 3's `vms/*.md` rewrites and Task 4's `DeploymentGuide.md` edits point to. Task 3/4 must use these exact relative paths.

- [ ] **Step 1: Write `hypervisor/desktop/README.md`**

```markdown
# Desktop Hypervisor — VMware Workstation Pro / Fusion Pro

This is the default platform for the lab: every VM is hand-built through the hypervisor's own
GUI, on whatever host OS you're running it on. There's no automation layer here (see
[`../README.md`](../README.md#why-hand-built-not-scripted) for why) — building each VM yourself,
and understanding why each setting is what it is, is the point of a teaching lab.

## Requirements

- **Windows or Linux host**: VMware Workstation Pro 17+.
- **macOS host**: VMware Fusion Pro 13+.

Both are the same product family with a near-identical GUI — every instruction in
[`../vms/`](../vms/) applies to either without modification. Virtualization must be enabled in
your host's BIOS/UEFI firmware.

## Building a VM

Every VM's spec sheet under [`../vms/`](../vms/) has its own "Build + install" section with the
exact CPU/RAM/disk/ISO to use, but the wizard steps themselves are the same each time:

1. **File > New Virtual Machine**, choose **Custom** hardware configuration.
2. Set vCPU, RAM, and disk (thin/dynamically-allocated) per the VM's spec table.
3. Attach the VM's ISO as the CD/DVD drive.
4. NIC: **Custom: Specific virtual network**, then pick `LAN-LAB` from the network dropdown.
   `LAN-LAB` is created exactly once, inline, while building `pfsense01`'s second NIC — see
   [`../vms/pfsense.md`](../vms/pfsense.md). Every other VM's NIC just picks it from the same
   dropdown; there's nothing further to create.
5. Install the guest OS interactively, then apply [`baseline.md`](baseline.md) before moving on
   to that VM's own "Post-install" section.

See [`../networks/README.md`](../networks/README.md) for the WAN/LAN network design this all
sits on top of.
```

- [ ] **Step 2: Write `hypervisor/desktop/baseline.md`**

```markdown
# Desktop VM Baseline

Applied once, right after the interactive OS install, to every general-purpose-OS VM in the lab
— `samba-dc01`, `docker01`, `authentik01`, `linux-client01`, `win-client01`. **Not** `pfsense01`:
it's a BSD appliance with its own package manager, no VM-tools concept, and no general-purpose
SSH shell — see [`../vms/pfsense.md`](../vms/pfsense.md) for its own (much shorter) post-install
steps instead.

## 1. Patch

```bash
sudo apt update && sudo apt full-upgrade -y
```

Reboot if the kernel was updated (`sudo reboot`) — Subiquity's installer usually leaves you on a
current kernel, but package updates released since the ISO was built are still worth applying
before doing anything else with the VM.

**Windows** (`win-client01` only): Settings → Windows Update → Check for updates, reboot if
prompted.

## 2. VM tools

```bash
sudo apt install -y open-vm-tools
```

On `linux-client01` only, also install `open-vm-tools-desktop` for clipboard sharing and better
display resolution handling — the three servers are headless and don't need it.

**Windows**: VM menu → **Install VMware Tools** (or **Reinstall VMware Tools**), then run the
installer from the mounted virtual CD.

## 3. Locale

Installer defaults don't always match where you actually are. Verify and correct:

```bash
localectl status                              # check current locale/keyboard
sudo localectl set-locale LANG=en_AU.UTF-8    # or whichever locale is correct for you
sudo timedatectl set-timezone Australia/Perth # or your actual timezone
```

**Windows**: Settings → Time & Language — check region, language, and time zone.

## 4. SSH keys

This is what lets the control host's (`linux-client01`) Ansible runs authenticate against
`samba-dc01`, `docker01`, and `authentik01` later — without it, every `ansible-playbook` run in
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md) from step 5 onward has nothing to log
in with.

**The three Ubuntu Server hosts and `linux-client01`**: use Subiquity's own "Import SSH
identity" / paste-a-public-key step during install, rather than doing this after the fact — it's
built into the installer's SSH configuration screen. If you already finished the install without
doing this, append your public key to `~/.ssh/authorized_keys` for the `labadmin` account
instead.

**`win-client01`**: enable the OpenSSH Server optional feature —

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
```

— then add your public key to `C:\ProgramData\ssh\administrators_authorized_keys` (**not**
`~\.ssh\authorized_keys`): Windows' OpenSSH server routes any account in the local
Administrators group through this file instead of the per-user one Linux uses. Its ACL must
restrict access to Administrators and SYSTEM only, or the OpenSSH service refuses to use it —
from an elevated PowerShell prompt:

```powershell
icacls.exe "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
```
```

- [ ] **Step 3: Verify both files render sensibly and links resolve**

Run:
```bash
grep -c '^#' hypervisor/desktop/README.md hypervisor/desktop/baseline.md
ls hypervisor/vms/pfsense.md hypervisor/networks/README.md hypervisor/README.md
```
Expected: both files have at least one heading; the three linked files exist (confirming the relative links `../vms/pfsense.md`, `../networks/README.md`, `../README.md` resolve).

- [ ] **Step 4: Commit**

```bash
git add hypervisor/desktop/
git commit -m "$(cat <<'EOF'
Add hypervisor/desktop/ with a VM-creation guide and shared baseline

README.md documents the New VM wizard click-path (Workstation Pro on
Windows/Linux, Fusion Pro on macOS) common to every VM. baseline.md is the
patch/VM-tools/locale/SSH-key checklist applied after each VM's interactive
OS install, replacing the unattended-install seeds removed in the previous
commit.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Rewrite the five `hypervisor/vms/*.md` pages

**Files:**
- Modify: `hypervisor/vms/samba-dc.md`
- Modify: `hypervisor/vms/docker-server.md`
- Modify: `hypervisor/vms/authentik.md`
- Modify: `hypervisor/vms/windows-client.md`
- Modify: `hypervisor/vms/linux-client.md`

**Interfaces:**
- Consumes: `hypervisor/desktop/baseline.md` (Task 2) — every page links to it as `../desktop/baseline.md`.
- Produces: nothing consumed by later tasks (Task 4/5 reference these files by their existing top-level filenames and headings only, not by any new anchor).

- [ ] **Step 1: Rewrite `hypervisor/vms/samba-dc.md`**

Replace the file's content (keep the existing top table and "## Post-install" section unchanged) — replace everything between the table and "## Post-install" with:

```markdown
## Build + install

1. In VMware Workstation/Fusion, create a new VM per the spec table above: 2 vCPU, 4096 MB RAM,
   40 GB disk (thin provisioned), Ubuntu Server 24.04 LTS ISO attached, single NIC on the
   `LAN-LAB` LAN Segment (already exists once pfSense's second NIC is set up — pick it from the
   dropdown, don't create it again).
2. Install interactively. In Subiquity's network step, set a **static** address:
   `10.10.10.10/24`, gateway `10.10.10.1`, nameserver `127.0.0.1` (this host becomes
   authoritative for itself once Samba AD is provisioned; nothing else exists yet to ask for
   `lab.internal` records). Create the `labadmin` user — it matches `ansible_user` in
   `ansible/inventory/hosts.ini`, so don't rename it without updating the inventory too. On the
   SSH step, install OpenSSH server and paste your public key rather than relying on password
   auth alone.
3. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing.

**On Proxmox**, this VM boots a cloud image instead and is configured by
[`seeds/samba-dc01/proxmox-user-data.example`](seeds/samba-dc01/proxmox-user-data.example). See
[`../proxmox/README.md`](../proxmox/README.md) for why the mechanism differs and what to fill in
before `terraform apply`.
```

The full file (for reference — this is what it should look like after the edit):

```markdown
# Samba AD DC — `samba-dc01`

| Spec                 | Value                                                             |
| -------------------- | ----------------------------------------------------------------- |
| vCPU                 | 2                                                                 |
| RAM                  | 4096 MB                                                           |
| Disk                 | 40 GB (thin)                                                      |
| NIC                  | LAN Segment `LAN-LAB`                                             |
| ISO                  | Ubuntu Server 24.04 LTS                                           |
| IP                   | `10.10.10.10/24` (static)                                         |
| Gateway              | `10.10.10.1`                                                      |
| DNS (during install) | `127.0.0.1` (will become authoritative for itself post-provision) |

## Build + install

1. In VMware Workstation/Fusion, create a new VM per the spec table above: 2 vCPU, 4096 MB RAM,
   40 GB disk (thin provisioned), Ubuntu Server 24.04 LTS ISO attached, single NIC on the
   `LAN-LAB` LAN Segment (already exists once pfSense's second NIC is set up — pick it from the
   dropdown, don't create it again).
2. Install interactively. In Subiquity's network step, set a **static** address:
   `10.10.10.10/24`, gateway `10.10.10.1`, nameserver `127.0.0.1` (this host becomes
   authoritative for itself once Samba AD is provisioned; nothing else exists yet to ask for
   `lab.internal` records). Create the `labadmin` user — it matches `ansible_user` in
   `ansible/inventory/hosts.ini`, so don't rename it without updating the inventory too. On the
   SSH step, install OpenSSH server and paste your public key rather than relying on password
   auth alone.
3. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing.

**On Proxmox**, this VM boots a cloud image instead and is configured by
[`seeds/samba-dc01/proxmox-user-data.example`](seeds/samba-dc01/proxmox-user-data.example). See
[`../proxmox/README.md`](../proxmox/README.md) for why the mechanism differs and what to fill in
before `terraform apply`.

## Post-install

Run [`samba/scripts/bootstrap-ad.sh`](../../samba/scripts/bootstrap-ad.sh) as root — see
[docs/SambaAdmin.md](../../docs/SambaAdmin.md) and
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md#3-samba-ad-domain-controller).
```

- [ ] **Step 2: Rewrite `hypervisor/vms/docker-server.md`**

Full file content:

```markdown
# Docker Application Server — `docker01`

| Spec    | Value                                    |
| ------- | ----------------------------------------- |
| vCPU    | 4                                         |
| RAM     | 8192 MB                                   |
| Disk    | 80 GB (thin) — NextCloud/mail data grows  |
| NIC     | LAN Segment `LAN-LAB`                     |
| ISO     | Ubuntu Server 24.04 LTS                   |
| IP      | `10.10.10.20/24` (static)                 |
| Gateway | `10.10.10.1`                              |
| DNS     | `10.10.10.10`                             |

Hosts the Traefik reverse proxy plus NextCloud, OnlyOffice, and Dovecot Compose stacks (see
[`docker/`](../../docker/)).

## Build + install

1. In VMware Workstation/Fusion, create a new VM per the spec table above: 4 vCPU, 8192 MB RAM,
   80 GB disk (thin provisioned), Ubuntu Server 24.04 LTS ISO attached, single NIC on `LAN-LAB`.
2. Install interactively. In Subiquity's network step, set a static address `10.10.10.20/24`,
   gateway `10.10.10.1`, nameserver `10.10.10.10`. Create the `labadmin` user (matches
   `ansible_user` in `ansible/inventory/hosts.ini`). On the SSH step, install OpenSSH server and
   paste your public key.
3. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing.

**On Proxmox**, this VM boots a cloud image instead and is configured by
[`seeds/docker01/proxmox-user-data.example`](seeds/docker01/proxmox-user-data.example). See
[`../proxmox/README.md`](../proxmox/README.md) for why the mechanism differs and what to fill in
before `terraform apply`.

## Post-install

Handled entirely by Ansible — do not install Docker manually. From the control host:

```bash
ansible-playbook ansible/playbooks/00-common-hardening.yml --limit docker01
ansible-playbook ansible/playbooks/04-linux-client-join.yml --limit docker01
ansible-playbook ansible/playbooks/05-pki-trust.yml --limit docker01
ansible-playbook ansible/playbooks/02-docker-server.yml --limit docker01
```

(`site.yml` runs all of these in order for every host in inventory — see
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md#5-docker-application-server--authentik).)
```

- [ ] **Step 3: Rewrite `hypervisor/vms/authentik.md`**

Full file content:

```markdown
# Authentik IAM — `authentik01`

| Spec    | Value                     |
| ------- | ------------------------- |
| vCPU    | 2                         |
| RAM     | 4096 MB                   |
| Disk    | 40 GB (thin)              |
| NIC     | LAN Segment `LAN-LAB`     |
| ISO     | Ubuntu Server 24.04 LTS   |
| IP      | `10.10.10.30/24` (static) |
| Gateway | `10.10.10.1`              |
| DNS     | `10.10.10.10`             |

Kept on its own VM (rather than co-located on `docker01`) so the identity plane's failure
domain is isolated from the application plane — see
[docs/Architecture.md#trade-offs-and-scope](../../docs/Architecture.md#trade-offs-and-scope).

## Build + install

1. In VMware Workstation/Fusion, create a new VM per the spec table above: 2 vCPU, 4096 MB RAM,
   40 GB disk (thin provisioned), Ubuntu Server 24.04 LTS ISO attached, single NIC on `LAN-LAB`.
2. Install interactively. In Subiquity's network step, set a static address `10.10.10.30/24`,
   gateway `10.10.10.1`, nameserver `10.10.10.10`. Create the `labadmin` user (matches
   `ansible_user` in `ansible/inventory/hosts.ini`). On the SSH step, install OpenSSH server and
   paste your public key.
3. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing.

**On Proxmox**, this VM boots a cloud image instead and is configured by
[`seeds/authentik01/proxmox-user-data.example`](seeds/authentik01/proxmox-user-data.example).
See [`../proxmox/README.md`](../proxmox/README.md) for why the mechanism differs and what to
fill in before `terraform apply`.

## Post-install

```bash
ansible-playbook ansible/playbooks/00-common-hardening.yml --limit authentik01
ansible-playbook ansible/playbooks/04-linux-client-join.yml --limit authentik01
ansible-playbook ansible/playbooks/05-pki-trust.yml --limit authentik01
ansible-playbook ansible/playbooks/03-authentik.yml --limit authentik01
```

See [docs/AuthentikAdmin.md](../../docs/AuthentikAdmin.md).
```

- [ ] **Step 4: Rewrite `hypervisor/vms/windows-client.md`**

Full file content:

```markdown
# Windows Desktop Client — `win-client01`

| Spec | Value                                        |
| ---- | --------------------------------------------- |
| vCPU | 2                                             |
| RAM  | 4096 MB                                       |
| Disk | 60 GB (thin)                                  |
| NIC  | LAN Segment `LAN-LAB`                         |
| ISO  | Windows 11 (23H2+)                            |
| IP   | DHCP (`10.10.10.100-199`, served by pfSense)  |

## Build + install

1. In VMware Workstation/Fusion's New Virtual Machine wizard, select **Windows 11 x64** as the
   guest OS — this makes Workstation/Fusion automatically enable UEFI firmware, Secure Boot, and
   add a virtual TPM 2.0 device, all three of which Windows 11 Setup hard-requires and refuses to
   install without. Verify under VM Settings before booting if you picked a generic/other guest
   OS type instead. 2 vCPU, 4096 MB RAM, 60 GB disk (thin provisioned), Windows 11 ISO attached,
   single NIC on `LAN-LAB`.
2. Install interactively — Windows Setup's normal graphical flow (unattended installs are out of
   scope for this lab). It gets a DHCP lease from pfSense.
3. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing.

**On Proxmox**, build through the Proxmox web console instead of the VMware GUI — same specs,
`vmbr-lan` NIC, `Win11.iso` attached. See [`../proxmox/README.md`](../proxmox/README.md). Install
and baseline steps above are identical regardless of hypervisor.

## Post-install

1. Confirm DNS is being served correctly: `Resolve-DnsName lab.internal` should return
   `10.10.10.10`.
2. Run [`samba/scripts/join-windows-client.ps1`](../../samba/scripts/join-windows-client.ps1)
   elevated to join the domain into `OU=Windows,OU=Workstations,OU=LAB`.
3. After reboot and domain logon, CA trust and any other GPO-managed settings apply
   automatically (or force with `gpupdate /force`) — see
   [pki/gpo/deploy-root-ca.ps1](../../pki/gpo/deploy-root-ca.ps1) and
   [docs/PKI.md](../../docs/PKI.md#trust-deployment).

See [docs/StudentLabManual.md](../../docs/StudentLabManual.md) for the exercises students run
from this VM.
```

- [ ] **Step 5: Add the baseline pointer to `hypervisor/vms/linux-client.md`**

`linux-client01` is already hand-built (this page needs no restructuring), but it's one of the
5 VMs `baseline.md` applies to, and every other VM's page now says so explicitly — add the same
pointer here for consistency. In the existing "## Build + install" section, after its step 2
("Install interactively...It gets a DHCP lease from pfSense."), add a new step 3:

```markdown
3. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing.
```

- [ ] **Step 6: Verify no stale references remain in these five files**

Run:
```bash
grep -n "create-vms\|autoinstall\|autounattend\|vmware-windows\|vmware-linux\|mkpasswd" \
  hypervisor/vms/samba-dc.md hypervisor/vms/docker-server.md hypervisor/vms/authentik.md \
  hypervisor/vms/windows-client.md hypervisor/vms/linux-client.md
```
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add hypervisor/vms/samba-dc.md hypervisor/vms/docker-server.md hypervisor/vms/authentik.md \
        hypervisor/vms/windows-client.md hypervisor/vms/linux-client.md
git commit -m "$(cat <<'EOF'
Rewrite VM pages for hand-built installs, matching pfsense.md/linux-client.md

samba-dc.md, docker-server.md, authentik.md, and windows-client.md's
"Autoinstall" sections (seed-file copy/fill, create-vms.ps1 references) are
replaced with "Build + install" sections: VM creation via the hypervisor
GUI, interactive OS install with static IP/labadmin/SSH-key setup where
applicable, then a pointer to the new shared baseline.md. linux-client.md
gets the same baseline.md pointer added for consistency. Proxmox asides and
every "Post-install" (app-layer) section are unchanged.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Update `docs/DeploymentGuide.md`

**Files:**
- Modify: `docs/DeploymentGuide.md`

**Interfaces:**
- Consumes: `hypervisor/desktop/README.md`, `hypervisor/desktop/baseline.md` (Task 2), and the rewritten `hypervisor/vms/*.md` pages (Task 3).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Rewrite the intro paragraph**

Find:
```markdown
Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro 17+ on the host (Windows or Linux) and Ubuntu
Server 24.04 LTS for all Linux VMs, unless you're on Proxmox VE instead — see
[hypervisor/README.md](../hypervisor/README.md) for the trade-offs, and
[hypervisor/proxmox/README.md](../hypervisor/proxmox/README.md) for that path's own sequence
(cloud image, not an ISO install, for three of the four automatable VMs).
```

Replace with:
```markdown
Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro (Windows/Linux) or Fusion Pro (macOS) and Ubuntu
Server 24.04 LTS for all Linux VMs, unless you're on Proxmox VE instead — see
[hypervisor/README.md](../hypervisor/README.md) for the trade-offs, and
[hypervisor/proxmox/README.md](../hypervisor/proxmox/README.md) for that path's own sequence
(cloud image, not an ISO install, for three of the four VMs Proxmox automates). Every VM on the
desktop-hypervisor path is hand-built through the hypervisor's own GUI — see
[hypervisor/desktop/README.md](../hypervisor/desktop/README.md).
```

- [ ] **Step 2: Rewrite step 0 (Host prerequisites)**

Find:
```markdown
## 0. Host prerequisites

- This lab defaults to the `10.10.10.0/24` subnet. If that collides with your home/office
  network, or you just want a different range, run `scripts/set-subnet.sh <new-cidr>` now
  (before building any VMs) and do the rest of this guide from the resulting copy — see the
  script's header comment for usage.
- VMware Workstation Pro installed, virtualization enabled in host BIOS.
- Ubuntu Server 24.04 LTS ISO, Windows 11 ISO, pfSense CE ISO, Ubuntu Desktop 24.04 ISO
  downloaded to the host.
- This repo ends up cloned in **two** places: once on the Windows host (to run the
  PowerShell/`vmrun` scripts from step 3 onward), and once on `linux-client01` (built in step
  2 below), which is the **control host** for everything from step 3 onward — Ansible, the PKI
  scripts, and `samba-tool` all need a real POSIX environment, and Ansible does not support
  Windows as a control node at all. Because `linux-client01` lives on the lab's own LAN
  Segment, it needs no extra networking setup to reach the other lab VMs. See
  [docs/WSLSetup.md](WSLSetup.md) only if you'd rather drive the build from WSL2 on the
  Windows host instead.
- `mkpasswd` (from the `whois` package, installed on `linux-client01` in step 2) to generate
  password hashes for the Ubuntu Server autoinstall seeds used in steps 3 and 5. No extra tool
  is needed to build the seed ISOs themselves — `hypervisor/vmware-windows/scripts/build-seed-iso.ps1` uses
  IMAPI2, which ships with Windows.
```

Replace with:
```markdown
## 0. Host prerequisites

- This lab defaults to the `10.10.10.0/24` subnet. If that collides with your home/office
  network, or you just want a different range, run `scripts/set-subnet.sh <new-cidr>` now
  (before building any VMs) and do the rest of this guide from the resulting copy — see the
  script's header comment for usage.
- VMware Workstation Pro (Windows/Linux) or Fusion Pro (macOS) installed, virtualization enabled
  in host BIOS/firmware.
- Ubuntu Server 24.04 LTS ISO, Windows 11 ISO, pfSense CE ISO, Ubuntu Desktop 24.04 ISO
  downloaded to the host.
- `linux-client01` (built in step 2 below) is the **control host** for everything from step 3
  onward — Ansible, the PKI scripts, and `samba-tool` all need a real POSIX environment, and
  Ansible does not support Windows as a control node at all. Because `linux-client01` lives on
  the lab's own LAN Segment, it needs no extra networking setup to reach the other lab VMs. See
  [docs/WSLSetup.md](WSLSetup.md) only if you'd rather drive the build from WSL2 on a Windows
  host instead.
```

- [ ] **Step 3: Update step 1 (pfSense)**

Find:
```markdown
1. In VMware Workstation, create a new VM per
   [`hypervisor/vms/pfsense.md`](../hypervisor/vms/pfsense.md): 2 vCPU, 2 GB RAM, 20 GB disk,
   pfSense CE ISO attached.
```

Replace with:
```markdown
1. In VMware Workstation/Fusion, create a new VM per
   [`hypervisor/vms/pfsense.md`](../hypervisor/vms/pfsense.md): 2 vCPU, 2 GB RAM, 20 GB disk,
   pfSense CE ISO attached.
```

- [ ] **Step 4: Update step 2 (`linux-client01`)**

Find:
```markdown
1. Create a new VM per [`hypervisor/vms/linux-client.md`](../hypervisor/vms/linux-client.md):
   2 vCPU, 4 GB RAM, 40 GB disk, single NIC on `LAN-LAB`, Ubuntu Desktop 24.04 ISO attached.
2. Install Ubuntu Desktop interactively — it gets a DHCP lease from pfSense once step 1 above
   is done.
3. Clone this repository onto it and install the tooling the rest of the guide needs:

   ```bash
   sudo apt update && sudo apt install -y ansible openssl git rsync samba-common-bin whois \
       python3 python3-pip openssh-client
   git clone <this-repo-url> ~/lab-small-business
   cd ~/lab-small-business
   ansible --version   # confirm ansible-core 2.16+
   ```

From here on, "control host" in this guide means **this VM** — every `ansible-playbook`,
`openssl`, and `samba-tool` command from step 3 onward runs from here, not from the Windows
host. (If you'd rather drive the build from WSL2 on the Windows host instead, see
[docs/WSLSetup.md](WSLSetup.md) — the LAN Segment reachability fix it documents is the only
extra step that path needs.)
```

Replace with:
```markdown
1. Create a new VM per [`hypervisor/vms/linux-client.md`](../hypervisor/vms/linux-client.md):
   2 vCPU, 4 GB RAM, 40 GB disk, single NIC on `LAN-LAB`, Ubuntu Desktop 24.04 ISO attached.
2. Install Ubuntu Desktop interactively — it gets a DHCP lease from pfSense once step 1 above
   is done.
3. Apply [`hypervisor/desktop/baseline.md`](../hypervisor/desktop/baseline.md).
4. Clone this repository onto it and install the tooling the rest of the guide needs:

   ```bash
   sudo apt update && sudo apt install -y ansible openssl git rsync samba-common-bin whois \
       python3 python3-pip openssh-client
   git clone <this-repo-url> ~/lab-small-business
   cd ~/lab-small-business
   ansible --version   # confirm ansible-core 2.16+
   ```

From here on, "control host" in this guide means **this VM** — every `ansible-playbook`,
`openssl`, and `samba-tool` command from step 3 onward runs from here, not from your hypervisor
host machine. (If you'd rather drive the build from WSL2 on a Windows host instead, see
[docs/WSLSetup.md](WSLSetup.md) — the LAN Segment reachability fix it documents is the only
extra step that path needs.)
```

- [ ] **Step 5: Update step 3 (Samba AD Domain Controller)**

Find:
```markdown
1. Fill in `samba-dc01`'s install seed (see
   [`hypervisor/vms/samba-dc.md#autoinstall`](../hypervisor/vms/samba-dc.md#autoinstall) —
   copy the `.example` files, generate a password hash with `mkpasswd`).
2. `hypervisor/vmware-windows/scripts/create-vms.ps1` creates `samba-dc01`'s VM shell (2 vCPU, 4 GB RAM,
   40 GB disk, static `10.10.10.10`, gateway `10.10.10.1`) and builds/attaches its seed ISO
   automatically. Boot it — Ubuntu Server installs with no prompts and reboots into a running
   system with SSH up.
3. `sudo samba/scripts/bootstrap-ad.sh` — provisions the domain (see
   [SambaAdmin.md](SambaAdmin.md)).
4. `sudo samba/scripts/create-ous.sh && sudo samba/scripts/create-groups.sh && sudo samba/scripts/create-users.sh`
5. `samba/scripts/health-check.sh` — confirm green before proceeding.
```

Replace with:
```markdown
1. Build and install `samba-dc01` by hand, then apply the baseline — see
   [`hypervisor/vms/samba-dc.md`](../hypervisor/vms/samba-dc.md) for the VM spec, static IP, and
   `labadmin`/SSH-key setup.
2. `sudo samba/scripts/bootstrap-ad.sh` — provisions the domain (see
   [SambaAdmin.md](SambaAdmin.md)).
3. `sudo samba/scripts/create-ous.sh && sudo samba/scripts/create-groups.sh && sudo samba/scripts/create-users.sh`
4. `samba/scripts/health-check.sh` — confirm green before proceeding.
```

- [ ] **Step 6: Update step 5 (Docker application server + Authentik)**

Find:
```markdown
1. Fill in `docker01`'s and `authentik01`'s install seeds (same `.example`-copy-and-fill
   pattern as `samba-dc01` — see
   [`hypervisor/vms/docker-server.md`](../hypervisor/vms/docker-server.md) and
   [`hypervisor/vms/authentik.md`](../hypervisor/vms/authentik.md)), then boot them — both
   install unattended the same way `samba-dc01` did in step 3.
2. From your control host, populate `ansible/inventory/hosts.ini` (already templated with these
   IPs) and run:
```

Replace with:
```markdown
1. Build and install `docker01` and `authentik01` by hand, then apply the baseline to each —
   see [`hypervisor/vms/docker-server.md`](../hypervisor/vms/docker-server.md) and
   [`hypervisor/vms/authentik.md`](../hypervisor/vms/authentik.md) for VM specs, static IPs, and
   `labadmin`/SSH-key setup.
2. From your control host, populate `ansible/inventory/hosts.ini` (already templated with these
   IPs) and run:
```

- [ ] **Step 7: Update step 7 (Endpoints)**

Find:
```markdown
`linux-client01` already exists (built manually in step 2). `win-client01`'s VM shell and
unattended Windows 11 install are handled by `hypervisor/vmware-windows/scripts/create-vms.ps1` — see
[`hypervisor/vms/windows-client.md`](../hypervisor/vms/windows-client.md) for the
`autounattend.xml` setup needed before running it, then boot it once ready. What's left for
both clients is joining the domain:
```

Replace with:
```markdown
`linux-client01` already exists (built manually in step 2). Build and install `win-client01` by
hand, then apply the baseline — see
[`hypervisor/vms/windows-client.md`](../hypervisor/vms/windows-client.md) for the VM spec (note
its UEFI/Secure Boot/vTPM requirement) and install steps. What's left for both clients is
joining the domain:
```

- [ ] **Step 8: Verify no stale references remain**

Run:
```bash
grep -n "create-vms\|build-seed-iso\|vmware-windows\|vmware-linux\|mkpasswd\|autoinstall\|autounattend" \
  docs/DeploymentGuide.md
```
Expected: no output.

- [ ] **Step 9: Commit**

```bash
git add docs/DeploymentGuide.md
git commit -m "$(cat <<'EOF'
Update DeploymentGuide.md for the hand-built VM flow

Steps 0-2 (host prereqs, pfSense, linux-client01) drop the PowerShell/WSL2
framing and point at hypervisor/desktop/. Steps 3, 5, 7's VM-creation
sentences are swapped for "build by hand, apply baseline.md" \u2014 their
app-config content (bootstrap-ad.sh, PKI, Ansible, domain-join) is
unchanged.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Update `README.md` and `hypervisor/README.md`

**Files:**
- Modify: `README.md`
- Modify: `hypervisor/README.md`

**Interfaces:**
- Consumes: `hypervisor/desktop/README.md`, `hypervisor/desktop/baseline.md` (Task 2).
- Produces: nothing consumed by later tasks — this is the plan's last content-editing task.

- [ ] **Step 1: Rewrite `README.md`'s Quick start block**

Find:
```markdown
## Quick start

```bash
# 1. pfSense + admin desktop (VMware Workstation GUI, fully manual — see
#    docs/DeploymentGuide.md steps 1-2). Building pfSense's second NIC is what creates the
#    LAN-LAB LAN Segment every other VM's NIC uses.

# 2. Remaining VM shells
#    Windows host, elevated PowerShell:
hypervisor\vmware-windows\scripts\create-vms.ps1
#    ...or a Linux host:
./hypervisor/vmware-linux/scripts/create-vms.sh
#    ...or Proxmox VE (see hypervisor/proxmox/README.md — automates 3 of the 4 VMs, not 4):
cd hypervisor/proxmox && terraform apply

# 3. Samba AD, endpoints — see docs/DeploymentGuide.md for the full sequence (OS installs for
#    the four VMs above are unattended; domain-join for the two clients is manual)

# 4. PKI + identity + application layers, once VMs exist and are reachable over SSH — run
#    from linux-client01, the control host (docs/DeploymentGuide.md step 2)
make pki-init
make pki-issue-all
make deploy   # wraps scripts/deploy-all.sh: runs ansible/playbooks/site.yml end to end
```

See [docs/DeploymentGuide.md](docs/DeploymentGuide.md) for the complete step-by-step, including
the manual steps that have no scriptable equivalent (pfSense and linux-client01 builds, Windows
domain join).
```

Replace with:
```markdown
## Quick start

```bash
# 1. pfSense + admin desktop (VMware Workstation/Fusion GUI, fully manual — see
#    docs/DeploymentGuide.md steps 1-2). Building pfSense's second NIC is what creates the
#    LAN-LAB LAN Segment every other VM's NIC uses.

# 2. Remaining VMs — same hypervisor GUI, hand-built, one per hypervisor/vms/*.md:
#    samba-dc01, docker01, authentik01, win-client01. Apply hypervisor/desktop/baseline.md
#    (patch, VM tools, locale, SSH keys) to each after its OS install.
#    ...or Proxmox VE instead (see hypervisor/proxmox/README.md — automates 3 of the 4 VMs):
cd hypervisor/proxmox && terraform apply

# 3. Samba AD, endpoints — see docs/DeploymentGuide.md for the full sequence (every OS install
#    above is interactive; domain-join for the two clients is manual)

# 4. PKI + identity + application layers, once VMs exist and are reachable over SSH — run
#    from linux-client01, the control host (docs/DeploymentGuide.md step 2)
make pki-init
make pki-issue-all
make deploy   # wraps scripts/deploy-all.sh: runs ansible/playbooks/site.yml end to end
```

See [docs/DeploymentGuide.md](docs/DeploymentGuide.md) for the complete step-by-step, including
every hand-built VM (all six, on the desktop-hypervisor path) and the Windows domain join.
```

- [ ] **Step 2: Rewrite `hypervisor/README.md`**

Replace the entire file with:

```markdown
# Hypervisor Layer

This directory documents the parts of the lab that live outside any guest OS: choice of
hypervisor, virtual network configuration, and VM inventory/specs.

## Choosing a platform

| Platform                                | Directory               | Host OS                       | Automation                                |
| ---------------------------------------- | ------------------------ | ------------------------------ | ------------------------------------------ |
| VMware Workstation/Fusion Pro (default) | [`desktop/`](desktop/)   | Windows, Linux, macOS         | Manual — hypervisor GUI + guided baseline |
| Proxmox VE                              | [`proxmox/`](proxmox/)   | (n/a — Proxmox is bare-metal) | Terraform (`bpg/proxmox`)                 |

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
```

- [ ] **Step 3: Verify no stale references remain**

Run:
```bash
grep -n "create-vms\|build-seed-iso\|vmware-windows\|vmware-linux" README.md hypervisor/README.md
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add README.md hypervisor/README.md
git commit -m "$(cat <<'EOF'
Update README.md and hypervisor/README.md for the hand-built desktop path

Top-level Quick Start drops the PowerShell/Bash create-vms invocations.
hypervisor/README.md's platform table collapses vmware-windows/+
vmware-linux/ into one desktop/ row, and its "Why not Terraform?" section
becomes "Why hand-built, not scripted?", explaining the deliberate choice
to make VM creation manual on the teaching (desktop) path while keeping
Proxmox automated for the "environment in a box" audience.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Repo-wide verification sweep

**Files:** None modified — verification only.

**Interfaces:**
- Consumes: every file touched in Tasks 1-5.
- Produces: nothing — this is the plan's final confirmation step.

- [ ] **Step 1: Confirm no live doc references the removed automation**

Run:
```bash
grep -rln "vmware-windows\|vmware-linux\|create-vms\.\(ps1\|sh\)\|build-seed-iso" \
  --include="*.md" --include="*.sh" --include="*.ps1" . 2>/dev/null | grep -v '^\./docs/superpowers/'
```
Expected: no output (the only remaining hits, if any, are historical records under
`docs/superpowers/specs/` or `docs/superpowers/plans/`, which are excluded above and are never
edited retroactively).

- [ ] **Step 2: Confirm the seed directory's final state**

Run: `find hypervisor/vms/seeds -type f | sort`
Expected: exactly 3 files, all named `proxmox-user-data.example`, under `samba-dc01/`,
`docker01/`, `authentik01/`.

- [ ] **Step 3: Confirm the new desktop/ directory and deleted directories**

Run:
```bash
ls hypervisor/desktop/
ls hypervisor/vmware-windows 2>&1
ls hypervisor/vmware-linux 2>&1
```
Expected: `hypervisor/desktop/` lists `README.md` and `baseline.md`; both `ls` calls on the
removed directories report "No such file or directory".

- [ ] **Step 4: Full-repo shell syntax sweep (nothing should have changed here, but confirms Task 1's deletions didn't break anything else)**

Run:
```bash
for f in $(find . -name "*.sh" -not -path "./.git/*"); do bash -n "$f" || echo "FAILED: $f"; done
```
Expected: no `FAILED:` lines.
