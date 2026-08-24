# LAN Segment Networking + Manual-First Build Sequence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken `vnetlib`-driven host-only `VMnet2` network with a VMware LAN
Segment (`LAN-LAB`), make pfSense and the `linux-client01` admin desktop fully manual GUI
builds, reposition `linux-client01` as the Ansible/PKI control host in place of WSL2, and
demote the pfSense config-template automation to an optional shortcut.

**Architecture:** No new code — this is a coordinated edit across VM-automation scripts and
docs so they describe one consistent build: pfSense (manual, dual-homed NAT+LAN Segment) →
`linux-client01` (manual, becomes the control host) → the four remaining VMs
(`samba-dc01`/`docker01`/`authentik01`/`win-client01`, still automated by `create-vms.ps1`) →
Ansible/PKI from `linux-client01`.

**Tech Stack:** PowerShell (`create-vms.ps1`), Markdown docs, one Mermaid diagram.

**Spec:** [docs/superpowers/specs/2026-08-24-lan-segment-manual-first-design.md](../specs/2026-08-24-lan-segment-manual-first-design.md)

## Global Constraints

- No CI in this repo. Validate every `.ps1` change by careful reading — there is no `pwsh`
  available in this dev environment to syntax-check PowerShell, so get it right by inspection
  (per `CLAUDE.md`'s "get the syntax right the first time" guidance for scripts that can't be
  run from here).
- The LAN Segment's name is `LAN-LAB`, exactly, everywhere it's referenced (scripts, docs,
  diagram labels) — treat it as a literal on par with the existing `VMnet2`/`VMnet8` literals.
- Domain/subnet strings (`lab.internal`, `10.10.0.0/24`, etc.) are unrelated to this change and
  must not be touched — this plan doesn't touch anything `scripts/provision-business.sh`'s sed
  sweep targets.
- Every relative Markdown link and `#anchor` this plan's tasks touch must still resolve after
  the edit — each task's verification step includes a grep for stale references.
- Section numbers in `docs/DeploymentGuide.md` for steps 3 ("Samba AD Domain Controller"), 4
  ("PKI bootstrap"), 5 ("Docker application server + Authentik"), 6 ("Applications"), 7
  ("Endpoints"), and 8 ("Validation") **must not change** — three other files
  (`workstation/vms/samba-dc.md`, `workstation/vms/docker-server.md`,
  `docker/wordpress/README.md`) link to those exact anchors, and this plan deliberately
  preserves them by construction (old step 1 "Networking" is absorbed into pfSense's step, and
  a new `linux-client01` step is inserted, keeping the total count and downstream numbers
  unchanged — only "pfSense" moves from step 2 to step 1).

---

### Task 1: Remove `vnetlib`-based networking script, rewrite the LAN Segment doc

**Files:**
- Delete: `workstation/scripts/configure-vmnet.ps1`
- Modify: `workstation/networks/README.md` (full rewrite)

**Interfaces:**
- Produces: the LAN Segment name `LAN-LAB` that every later task references.

- [ ] **Step 1: Delete the vnetlib script**

```bash
git rm workstation/scripts/configure-vmnet.ps1
```

- [ ] **Step 2: Rewrite `workstation/networks/README.md`**

Replace the entire file with:

```markdown
# Virtual Network Design

| Network | VMware type            | Purpose                                         | Subnet                  | DHCP                                      |
| ------- | ----------------------- | ------------------------------------------------ | ----------------------- | ------------------------------------------ |
| WAN     | `VMnet8` (NAT, built-in) | Host internet access for pfSense's WAN leg only | Host-assigned NAT range | VMware NAT DHCP (default)                 |
| LAN     | LAN Segment `LAN-LAB`   | All lab traffic                                 | `10.10.0.0/24`          | **Disabled** — pfSense is the DHCP server |

## Rules

- **Only pfSense has a NIC on `VMnet8`.** No other VM should ever be bridged to WAN or have
  internet access except through pfSense's NAT/firewall rules — this is what makes the
  firewall rules in [Security.md](../../docs/Security.md) meaningful.
- **`LAN-LAB` has no built-in DHCP service to disable.** Unlike a host-only `VMnetN`, a LAN
  Segment is a named, per-VM virtual switch with no host-adapter binding and no VMware DHCP
  service of its own — there's nothing to turn off, and no Virtual Network Editor entry to
  manage. pfSense is the only DHCP server on `LAN-LAB` by construction, not by configuration.
- **pfSense's LAN interface is `10.10.0.1/24`**, statically assigned during pfSense install
  (no DHCP client on the LAN side, obviously — it _is_ the DHCP server).

## Creating the network

There's no setup script for this — a LAN Segment doesn't need one. It's created the first time
you reference it, which happens naturally while building pfSense's second NIC (see
[`workstation/vms/pfsense.md`](../vms/pfsense.md)):

1. In pfSense's VM Settings, **Add... > Network Adapter**.
2. Set **Network connection** to **Custom: Specific virtual network**, open the network
   dropdown, and choose **LAN Segments... > Add...** (exact wording varies slightly by
   Workstation version — look for "LAN Segments" in the network-connection picker).
3. Name it `LAN-LAB`. This creates the segment and assigns this NIC to it in one step.

Every other lab VM's NIC then picks `LAN-LAB` from the same dropdown — it already exists after
step 3 above, so there's nothing further to create for any other VM.

(This document previously described a `configure-vmnet.ps1` script wrapping VMware's
`vnetlib.exe`/`vnetlib64.exe` to create a host-only `VMnet2` network. That approach is gone —
Broadcom has confirmed `vnetlib` is broken in recent Workstation releases, and LAN Segments
need no equivalent tool at all.)
```

- [ ] **Step 3: Verify no dangling references to the deleted script or the old network**

```bash
grep -rn "configure-vmnet" --include="*.md" --include="*.ps1" . | grep -v "docs/superpowers/specs\|docs/superpowers/plans"
```

Expected: no output (all remaining references to `configure-vmnet.ps1` live only in the spec
and plan documents under `docs/superpowers/`, which are historical records and stay as-is).

- [ ] **Step 4: Commit**

```bash
git add workstation/networks/README.md
git commit -m "Replace vnetlib-driven host-only VMnet2 with a LAN Segment

vnetlib.exe/vnetlib64.exe is confirmed broken by Broadcom in recent Workstation
releases. LAN Segments need no vnetlib call, no Virtual Network Editor entry, and
have no built-in DHCP service to disable."
```

---

### Task 2: Update `create-vms.ps1` for the LAN Segment and the two manual-build VMs

**Files:**
- Modify: `workstation/scripts/create-vms.ps1`

**Interfaces:**
- Consumes: LAN Segment name `LAN-LAB` from Task 1.
- Produces: VM shells for exactly `samba-dc01`, `docker01`, `authentik01`, `win-client01` —
  later tasks' docs describe this as the automated set, with `pfsense01`/`linux-client01`
  called out as manual builds outside this script.

- [ ] **Step 1: Replace the header docstring and parameters**

Old (`workstation/scripts/create-vms.ps1:1-29`):

```powershell
<#
.SYNOPSIS
    Creates the lab's VM shells (disk + .vmx) via vmrun/vmware-vdiskmanager, ready for OS
    installation. For any VM with a workstation/vms/seeds/<name>/ folder (every host except
    pfsense01 and linux-client01), also builds and attaches an unattended-install seed ISO via
    build-seed-iso.ps1 — those VMs install with zero prompts once booted. pfSense has no
    unattended installer to target; the Linux desktop client's install is intentionally manual
    (see linux-client.md).

.DESCRIPTION
    Reads the VM table below (mirrors docs/Architecture.md's component inventory) and, for
    each VM, creates a new virtual disk and a minimal .vmx with the right CPU/RAM/NIC
    settings, then registers it with vmrun so it shows up in the Workstation Library.

.PARAMETER VmDir
    Directory under which each VM's folder will be created (default: this repo's
    workstation/vms/<name>/).

.EXAMPLE
    .\create-vms.ps1 -IsoDir C:\ISOs
#>
[CmdletBinding()]
param(
    [string]$VmDir = (Resolve-Path (Join-Path $PSScriptRoot "..\vms")).Path,
    [string]$IsoDir = "C:\ISOs",
    [string]$VmwarePath = "$Env:ProgramFiles(x86)\VMware\VMware Workstation",
    [string]$LanNetwork = "VMnet2",
    [string]$WanNetwork = "VMnet8"
)
```

New:

```powershell
<#
.SYNOPSIS
    Creates the lab's VM shells (disk + .vmx) via vmrun/vmware-vdiskmanager, ready for OS
    installation, for the four hosts with an unattended install seed
    (samba-dc01, docker01, authentik01, win-client01) — each one's
    workstation/vms/seeds/<name>/ folder gets built into a seed ISO via build-seed-iso.ps1 and
    attached, so it installs with zero prompts once booted. pfsense01 and linux-client01 are
    built entirely by hand in the Workstation GUI (see their respective vms/*.md) and are not
    in this script's table.

.DESCRIPTION
    Reads the VM table below (mirrors docs/Architecture.md's component inventory) and, for
    each VM, creates a new virtual disk and a minimal .vmx with the right CPU/RAM/NIC
    settings on the lab's LAN Segment, then registers it with vmrun so it shows up in the
    Workstation Library.

.PARAMETER VmDir
    Directory under which each VM's folder will be created (default: this repo's
    workstation/vms/<name>/).

.PARAMETER LanNetwork
    Name of the VMware LAN Segment every VM's NIC is attached to (default: "LAN-LAB", created
    the first time it's referenced from pfSense's NIC2 — see workstation/vms/pfsense.md). Every
    VM this script creates has exactly one NIC, on this network; pfSense is the only VM with a
    WAN-facing NIC, and it's built by hand, not by this script.

.EXAMPLE
    .\create-vms.ps1 -IsoDir C:\ISOs
#>
[CmdletBinding()]
param(
    [string]$VmDir = (Resolve-Path (Join-Path $PSScriptRoot "..\vms")).Path,
    [string]$IsoDir = "C:\ISOs",
    [string]$VmwarePath = "$Env:ProgramFiles(x86)\VMware\VMware Workstation",
    [string]$LanNetwork = "LAN-LAB"
)
```

- [ ] **Step 2: Trim the `$VMs` table**

Old (`workstation/scripts/create-vms.ps1:39-50`):

```powershell
# name, vcpu, ramMB, diskGB, nics (array of network names), iso, firmware/vtpm, guest OS type
$VMs = @(
    @{ Name = "pfsense01";      VCPU = 2; RamMB = 2048;  DiskGB = 20;  Nics = @($WanNetwork, $LanNetwork); Iso = "pfSense-CE.iso";           Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "samba-dc01";     VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork);               Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "docker01";       VCPU = 4; RamMB = 8192;  DiskGB = 80;  Nics = @($LanNetwork);               Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "authentik01";    VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork);               Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "linux-client01"; VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork);               Iso = "ubuntu-desktop-24.04.iso"; Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    # Windows 11 Setup hard-blocks installation without a detected TPM 2.0 and UEFI firmware —
    # this is the fix for that; every other VM above is untouched (still BIOS, no vTPM, exactly
    # as before this change).
    @{ Name = "win-client01";   VCPU = 2; RamMB = 4096;  DiskGB = 60;  Nics = @($LanNetwork);               Iso = "Win11.iso";                Firmware = "efi";  Vtpm = $true;  GuestOS = "windows11-64" }
)
```

New:

```powershell
# name, vcpu, ramMB, diskGB, nics (array of network names), iso, firmware/vtpm, guest OS type
$VMs = @(
    @{ Name = "samba-dc01";     VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork); Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "docker01";       VCPU = 4; RamMB = 8192;  DiskGB = 80;  Nics = @($LanNetwork); Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "authentik01";    VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork); Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    # Windows 11 Setup hard-blocks installation without a detected TPM 2.0 and UEFI firmware —
    # this is the fix for that; every other VM above is untouched (still BIOS, no vTPM, exactly
    # as before this change).
    @{ Name = "win-client01";   VCPU = 2; RamMB = 4096;  DiskGB = 60;  Nics = @($LanNetwork); Iso = "Win11.iso";                Firmware = "efi";  Vtpm = $true;  GuestOS = "windows11-64" }
)
```

- [ ] **Step 3: Update the seed-folder comment**

Old (`workstation/scripts/create-vms.ps1:73-76`):

```powershell
    # Unattended-install seed media: workstation/vms/seeds/<name>/ only exists for hosts that
    # support an unattended install (Ubuntu Server autoinstall, Windows autounattend). pfSense
    # and the Linux desktop client have no seed folder, so this is a no-op for them — they boot
    # straight into the normal interactive installer, exactly as before this change.
```

New:

```powershell
    # Unattended-install seed media: every VM left in this script's table has a
    # workstation/vms/seeds/<name>/ folder (Ubuntu Server autoinstall or Windows autounattend) —
    # pfsense01 and linux-client01 are built by hand and never reach this script at all.
```

- [ ] **Step 4: Update the closing summary**

Old (`workstation/scripts/create-vms.ps1:120-122`):

```powershell
Write-Host ""
Write-Host "All VM shells created. See workstation/vms/*.md for per-VM install notes" -ForegroundColor Green
Write-Host "(autoinstall seeds for Ubuntu hosts, manual steps for pfSense/Windows)."
```

New:

```powershell
Write-Host ""
Write-Host "All VM shells created. See workstation/vms/*.md for per-VM install notes." -ForegroundColor Green
Write-Host "pfsense01 and linux-client01 are built by hand in the Workstation GUI - not by this script."
```

- [ ] **Step 5: Verify by reading**

There's no `pwsh` in this dev environment to run a syntax check, so read the full file back and
confirm: `$WanNetwork` and `pfsense01`/`linux-client01` no longer appear anywhere in it, and
every `Nics = @($LanNetwork)` line only references the single remaining network parameter.

```bash
grep -n "WanNetwork\|pfsense01\|linux-client01\|VMnet2" workstation/scripts/create-vms.ps1
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add workstation/scripts/create-vms.ps1
git commit -m "Trim create-vms.ps1 to the four seed-driven VMs, default to LAN-LAB

pfsense01 and linux-client01 are now fully manual GUI builds (see their vms/*.md
docs) and drop out of this script's table; -WanNetwork is removed since no
remaining entry is dual-homed."
```

---

### Task 3: Rewrite `workstation/vms/pfsense.md` as a full manual build walkthrough

**Files:**
- Modify: `workstation/vms/pfsense.md` (full rewrite)

**Interfaces:**
- Consumes: `LAN-LAB` (Task 1), the firewall-rule values from `docs/Security.md`'s
  "Firewall recommendations (pfSense)" table.
- Produces: the manual build/config steps that `docs/DeploymentGuide.md` step 1 (Task 7) links
  to.

- [ ] **Step 1: Replace the entire file**

```markdown
# pfSense — `pfsense01`

| Spec   | Value                                       |
| ------ | ------------------------------------------- |
| vCPU   | 2                                           |
| RAM    | 2048 MB                                     |
| Disk   | 20 GB (thin)                                |
| NIC 1  | NAT (`VMnet8`, VMware's built-in default)   |
| NIC 2  | LAN Segment `LAN-LAB`                       |
| ISO    | pfSense CE (latest stable)                  |
| LAN IP | `10.10.0.1/24` (static, set during install) |
| WAN    | DHCP from VMware NAT                        |

Built entirely by hand — no PowerShell script creates this VM or its network. This is
deliberate: it's the first VM in the lab, and building it manually is what creates `LAN-LAB`,
the LAN Segment every other VM's NIC will use.

## Build (VM + both NICs)

1. **File > New Virtual Machine**, custom hardware: 2 vCPU, 2048 MB RAM, 20 GB disk (thin
   provisioned), pfSense CE ISO attached as the CD/DVD drive.
2. **NIC 1**: leave it on Workstation's default **NAT** network connection (`VMnet8`) — this
   ships with Workstation and needs no setup.
3. **NIC 2**: VM Settings > **Add... > Network Adapter** > Network connection: **Custom:
   Specific virtual network** > open the network dropdown > **LAN Segments... > Add...** >
   name it `LAN-LAB`. This both creates the LAN Segment and assigns this NIC to it. Every other
   lab VM's NIC will pick `LAN-LAB` from the same dropdown once it exists — there's nothing
   further to create.

## Install (manual — no unattended installer available for pfSense on Workstation)

1. Boot from ISO, run the installer with the default ZFS/UFS choice (UFS is fine for a lab).
2. At "Assign Interfaces": WAN = the NIC on `VMnet8`, LAN = the NIC on `LAN-LAB`.
3. Set LAN IPv4 address to `10.10.0.1/24`. Leave LAN DHCP off for now — the next step
   configures it by hand.
4. Reboot into the installed system.

## Post-install (manual GUI configuration)

From the console or GUI (`https://10.10.0.1`), configure:

- **DHCP server (LAN)**: pool `10.10.0.100`–`10.10.0.199`, DNS server `10.10.0.10`, domain name
  `lab.internal`, gateway `10.10.0.1`.
- **DNS Resolver (Unbound)**: enabled, LAN-only access; forward `lab.internal` to `10.10.0.10`
  (Samba AD's DNS) and everything else to the WAN interface's upstream DNS — see
  [dns-architecture.md](../../diagrams/dns-architecture.md).
- **Firewall rules**: allow LAN → `10.10.0.10` (ports 53, 88, 123, 135, 137-139, 389, 445, 464,
  636, 3268-3269); allow LAN → `10.10.0.20` (80, 443, 587, 465, 993); allow LAN → `10.10.0.30`
  (443); block `10.10.0.30` → `10.10.0.10:389` (forces LDAPS); allow LAN → WAN (80, 443, 53,
  outbound only); default deny + log. Full rationale in
  [Security.md](../../docs/Security.md#firewall-recommendations-pfsense).

Then, optionally, run
[`pfsense/scripts/pfsense-post-install.sh`](../../pfsense/scripts/pfsense-post-install.sh) over
SSH for the package installs (`pfSense-pkg-Cron`, `pfSense-pkg-Notes`) it automates.

Once you're comfortable configuring pfSense by hand, `pfsense/config/config.xml.template`
(imported via **Diagnostics > Backup & Restore > Restore**) captures everything above as a
reviewed, reusable baseline for future rebuilds — see
[`pfsense/README.md`](../../pfsense/README.md). It's an optional shortcut for later, not where
to start.

See [docs/DeploymentGuide.md](../../docs/DeploymentGuide.md#1-pfsense--fully-manual) for the
full sequence in context.
```

- [ ] **Step 2: Verify**

```bash
grep -n "VMnet2\|config.xml.template.*Restore.*after filling" workstation/vms/pfsense.md
```

Expected: no output (the old `VMnet2` NIC row and the old "import as the default path" framing
are both gone).

- [ ] **Step 3: Commit**

```bash
git add workstation/vms/pfsense.md
git commit -m "Rewrite pfsense.md as a full manual build + config walkthrough

Covers creating the VM, both NICs (NAT + the new LAN-LAB LAN Segment), the
interactive install, and hand-configuring DHCP/DNS/firewall — the templated
config.xml.template path is now an explicitly optional shortcut, not the
default."
```

---

### Task 4: Rewrite `workstation/vms/linux-client.md` as the control-host build doc

**Files:**
- Modify: `workstation/vms/linux-client.md` (full rewrite)

**Interfaces:**
- Consumes: `LAN-LAB` (Task 1).
- Produces: the control-host setup steps that `docs/DeploymentGuide.md` step 2 (Task 7) and
  `docs/WSLSetup.md` (Task 8) both link to.

- [ ] **Step 1: Replace the entire file**

```markdown
# Linux Desktop Client / Control Host — `linux-client01`

| Spec | Value                                       |
| ---- | -------------------------------------------- |
| vCPU | 2                                            |
| RAM  | 4096 MB                                      |
| Disk | 40 GB (thin)                                 |
| NIC  | LAN Segment `LAN-LAB`                        |
| ISO  | Ubuntu Desktop 24.04 LTS                     |
| IP   | DHCP (`10.10.0.100-199`, served by pfSense)  |

Built by hand, right after pfSense — no PowerShell script creates this VM. It plays two roles:
it's the **control host** that drives every scripted step from here on (Ansible, the PKI
scripts, `samba-tool`), replacing the need for WSL2 on the Windows host; and later, once AD
exists, it also joins the domain as a lab endpoint like any other client.

## Build + install

1. **File > New Virtual Machine**, custom hardware: 2 vCPU, 4096 MB RAM, 40 GB disk (thin
   provisioned), Ubuntu Desktop 24.04 ISO attached, single NIC on the `LAN-LAB` LAN Segment
   (already exists once pfSense's second NIC is set up — pick it from the same network
   dropdown, don't create it again).
2. Install interactively (Ubuntu Desktop's installer is graphical; unattended desktop installs
   are out of scope for a lab teaching manual desktop use). It gets a DHCP lease from pfSense.

## Set up as the control host

```bash
sudo apt update && sudo apt install -y ansible openssl git rsync samba-common-bin whois \
    python3 python3-pip openssh-client
git clone <this-repo-url> ~/lab-small-business
cd ~/lab-small-business
ansible --version   # confirm ansible-core 2.16+
```

From here on, every `ansible-playbook`, `openssl`, and `samba-tool` command in
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md) runs from this VM.

## Domain join (later — once AD exists)

```bash
sudo samba/scripts/join-linux-client.sh
```

Then run [`ansible/playbooks/05-pki-trust.yml`](../../ansible/playbooks/05-pki-trust.yml)
against this host (or follow the manual `update-ca-certificates` steps in
[docs/PKI.md](../../docs/PKI.md#trust-deployment)) so HTTPS to `*.lab.internal` is trusted
without a browser warning.

See [docs/StudentLabManual.md](../../docs/StudentLabManual.md) for the exercises students run
from this VM.
```

- [ ] **Step 2: Verify**

```bash
grep -n "VMnet2" workstation/vms/linux-client.md
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add workstation/vms/linux-client.md
git commit -m "Reposition linux-client01 as the lab's control host

Built manually right after pfSense (not automated, not last), repo cloned onto
it, and documented as the Ansible/PKI/samba-tool control host in place of WSL2.
Domain-join content is unchanged, just moved under its own later section."
```

---

### Task 5: Update the remaining VM spec sheets' NIC row

**Files:**
- Modify: `workstation/vms/samba-dc.md:8`
- Modify: `workstation/vms/docker-server.md:8`
- Modify: `workstation/vms/authentik.md:8`
- Modify: `workstation/vms/windows-client.md:8`

**Interfaces:**
- Consumes: `LAN-LAB` (Task 1).

- [ ] **Step 1: `workstation/vms/samba-dc.md`**

Old line 8: `| NIC                  | `VMnet2`                                                          |`

New line 8: `| NIC                  | LAN Segment `LAN-LAB`                                             |`

- [ ] **Step 2: `workstation/vms/docker-server.md`**

Old line 8: `| NIC     | `VMnet2`                                 |`

New line 8: `| NIC     | LAN Segment `LAN-LAB`                    |`

- [ ] **Step 3: `workstation/vms/authentik.md`**

Old line 8: `| NIC     | `VMnet2`                 |`

New line 8: `| NIC     | LAN Segment `LAN-LAB`    |`

- [ ] **Step 4: `workstation/vms/windows-client.md`**

Old line 8: `| NIC  | `VMnet2`                                    |`

New line 8: `| NIC  | LAN Segment `LAN-LAB`                       |`

Table column alignment (dashes/padding) doesn't need to be pixel-perfect — Markdown tables
render correctly regardless of padding — but keep it reasonably tidy while editing each row.

- [ ] **Step 5: Verify**

```bash
grep -rn "VMnet2" workstation/vms/samba-dc.md workstation/vms/docker-server.md workstation/vms/authentik.md workstation/vms/windows-client.md
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add workstation/vms/samba-dc.md workstation/vms/docker-server.md workstation/vms/authentik.md workstation/vms/windows-client.md
git commit -m "Update remaining VM spec sheets' NIC row to the LAN-LAB LAN Segment"
```

---

### Task 6: Relabel the LAN segment in `diagrams/network-topology.md`

**Files:**
- Modify: `diagrams/network-topology.md:3-6,16`

- [ ] **Step 1: Replace the intro paragraph**

Old (`diagrams/network-topology.md:3-6`):

```markdown
VMware Workstation hosts two virtual networks: a NAT/Bridged **WAN** segment (host internet
access only, no lab services bound to it) and a host-only **LAN** segment (`10.10.0.0/24`)
that carries all lab traffic. pfSense is the only VM with a leg on both networks and is the
default gateway, DHCP relay point, and firewall for the LAN.
```

New:

```markdown
VMware Workstation hosts two virtual networks: pfSense's WAN leg on the built-in **NAT**
network (`VMnet8`) and a **LAN Segment** named `LAN-LAB` (`10.10.0.0/24`) that carries all lab
traffic. pfSense is the only VM with a leg on both networks and is the default gateway, DHCP
relay point, and firewall for the LAN.
```

- [ ] **Step 2: Relabel the Mermaid subgraph**

Old (`diagrams/network-topology.md:16`):

```
        subgraph LAN_SEG["LAN — VMnet-LAB (Host-only), 10.10.0.0/24"]
```

New:

```
        subgraph LAN_SEG["LAN — LAN Segment 'LAN-LAB', 10.10.0.0/24"]
```

Use a single quote around `LAN-LAB`, not a double quote — Mermaid's `["..."]` label syntax
uses double quotes as the delimiter, so a nested double quote would break parsing.

- [ ] **Step 3: Verify**

```bash
grep -n "VMnet-LAB\|host-only\|Host-only" diagrams/network-topology.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add diagrams/network-topology.md
git commit -m "Relabel network-topology.md's LAN segment from VMnet-LAB (Host-only) to LAN-LAB"
```

---

### Task 7: Restructure `docs/DeploymentGuide.md` steps 0-2 and 7

**Files:**
- Modify: `docs/DeploymentGuide.md`

**Interfaces:**
- Consumes: `LAN-LAB`, the manual pfSense build (Task 3), the control-host build (Task 4).
- Produces: step numbers 3-6 and 8 are **unchanged** (see Global Constraints) — this task only
  touches steps 0, 1, 2, and 7.

- [ ] **Step 1: Replace "0. Host prerequisites"**

Old (`docs/DeploymentGuide.md:7-21`):

```markdown
## 0. Host prerequisites

- VMware Workstation Pro installed, virtualization enabled in host BIOS.
- Ubuntu Server 24.04 LTS ISO, Windows 11 ISO, pfSense CE ISO, Ubuntu Desktop 24.04 ISO
  downloaded to the host.
- `ansible` (2.16+), `openssl` (3.x), and an SSH client available as the **control host** for
  everything from step 3 onward — this needs to be WSL2, not Git Bash or PowerShell alone;
  Ansible does not support Windows as a control node. See
  [docs/WSLSetup.md](WSLSetup.md) for installing WSL2, the networking fix it needs to reach
   `VMnet2` (this trips up almost everyone on first try), and cloning this repository inside
  it — do that clone (not a separate Windows-side one) before continuing.
- `mkpasswd` (from the `whois` package — WSL2 has it, or any Debian/Ubuntu machine) to generate
  password hashes for the Ubuntu Server autoinstall seeds used in steps 3 and 5. No extra tool
  is needed to build the seed ISOs themselves — `workstation/scripts/build-seed-iso.ps1` uses
  IMAPI2, which ships with Windows.
```

New:

```markdown
## 0. Host prerequisites

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
  is needed to build the seed ISOs themselves — `workstation/scripts/build-seed-iso.ps1` uses
  IMAPI2, which ships with Windows.
```

- [ ] **Step 2: Replace "1. Networking" and "2. pfSense" with a single merged "1. pfSense" step**

Old (`docs/DeploymentGuide.md:23-50`):

```markdown
## 1. Networking (VMware Workstation)

Create the two virtual networks described in
[workstation/networks/README.md](../workstation/networks/README.md) using
[`workstation/scripts/configure-vmnet.ps1`](../workstation/scripts/configure-vmnet.ps1)
(elevated PowerShell, wraps VMware's `vnetlib.exe` or `vnetlib64.exe`):

```powershell
workstation\scripts\configure-vmnet.ps1
```

This creates `VMnet8` (NAT, WAN) as-is (Workstation ships it by default) and a new host-only
`VMnet2` network with **DHCP disabled** (pfSense will be the DHCP server) bound to
`10.10.0.0/24`.

## 2. pfSense

1. Create the VM per [`workstation/vms/pfsense.md`](../workstation/vms/pfsense.md) (2 vCPU,
   2 GB RAM, 20 GB disk, NIC1→VMnet8/WAN, NIC2→VMnet2/LAN).
2. Install pfSense interactively (only manual-install step in the whole lab — pfSense has no
   unattended installer for Workstation). Assign WAN=NIC1, LAN=NIC2, LAN IP `10.10.0.1/24`.
3. From the pfSense console/GUI, import
   [`pfsense/config/config.xml.template`](../pfsense/config/config.xml.template)
   (`Diagnostics > Backup & Restore > Restore`) after filling in the placeholders described in
   [`pfsense/README.md`](../pfsense/README.md) (WAN type, DHCP range, DNS forwarder target).
4. Run [`pfsense/scripts/pfsense-post-install.sh`](../pfsense/scripts/pfsense-post-install.sh)
   over SSH to apply anything not expressible in `config.xml` (package installs via `pkg`,
   `pfSsh.php`-driven tweaks).
```

New:

```markdown
## 1. pfSense — fully manual

There's no networking-setup script to run before this step — the lab's LAN Segment is created
inline while building this VM, not as a separate stage.

1. In VMware Workstation, create a new VM per
   [`workstation/vms/pfsense.md`](../workstation/vms/pfsense.md): 2 vCPU, 2 GB RAM, 20 GB disk,
   pfSense CE ISO attached.
2. NIC1: leave as VMware's default **NAT** (`VMnet8` — ships with Workstation, needs no setup).
   NIC2: **Add... > Network Adapter > Custom: Specific virtual network > LAN Segments... >
   Add...**, name it `LAN-LAB`. This is the only place `LAN-LAB` gets created — every other lab
   VM's NIC picks it from the same dropdown once it exists.
3. Install pfSense interactively (the one genuinely manual OS install in the whole lab). At
   "Assign Interfaces": WAN = the NIC on `VMnet8`, LAN = the NIC on `LAN-LAB`. Set LAN IPv4 to
   `10.10.0.1/24`; leave LAN DHCP off until the next step.
4. From the pfSense GUI (`https://10.10.0.1`), configure by hand:
   - **DHCP server (LAN)**: pool `10.10.0.100`–`10.10.0.199`, DNS server `10.10.0.10`, domain
     name `lab.internal`, gateway `10.10.0.1`.
   - **DNS Resolver (Unbound)**: enabled, LAN-only access; forward `lab.internal` to
     `10.10.0.10` (Samba AD's DNS) and everything else to the WAN interface's upstream DNS —
     see [dns-architecture.md](../diagrams/dns-architecture.md).
   - **Firewall rules**: allow LAN → `10.10.0.10` (53, 88, 123, 135, 137-139, 389, 445, 464,
     636, 3268-3269); allow LAN → `10.10.0.20` (80, 443, 587, 465, 993); allow LAN →
     `10.10.0.30` (443); block `10.10.0.30` → `10.10.0.10:389` (forces LDAPS); allow LAN → WAN
     (80, 443, 53, outbound only); default deny + log. Full rationale in
     [Security.md](Security.md#firewall-recommendations-pfsense).
5. Run [`pfsense/scripts/pfsense-post-install.sh`](../pfsense/scripts/pfsense-post-install.sh)
   over SSH for the package installs it automates (optional — see below).

Once you're comfortable with the manual flow,
[`pfsense/config/config.xml.template`](../pfsense/config/config.xml.template) (imported via
**Diagnostics > Backup & Restore > Restore**) captures everything above as a reviewed, reusable
baseline for future rebuilds — see [`pfsense/README.md`](../pfsense/README.md). It's an
optional shortcut, not where to start.
```

- [ ] **Step 3: Insert a new "2. Admin desktop" step**

Insert immediately after the "1. pfSense — fully manual" section written in Step 2 above (i.e.
before the section currently headed `## 3. Samba AD Domain Controller`, which stays unchanged):

```markdown
## 2. Admin desktop — `linux-client01` (control host)

This VM plays two roles: it's your **control host** for every scripted step from here on
(replacing the need for WSL2), and later — once AD exists — it also joins the domain as a lab
endpoint like any other client.

1. Create a new VM per [`workstation/vms/linux-client.md`](../workstation/vms/linux-client.md):
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

- [ ] **Step 4: Update the "recommended interim host" note in step 4 (PKI bootstrap)**

Old (`docs/DeploymentGuide.md:68-69`, unchanged section number, only this sentence changes):

```markdown
Run from any host with `openssl` 3.x (recommended: `docker01` once it exists, or your
workstation host in the interim):
```

New:

```markdown
Run from any host with `openssl` 3.x (recommended: `docker01` once it exists, or
`linux-client01` — the control host — in the interim):
```

- [ ] **Step 5: Replace "7. Endpoints"**

Old (`docs/DeploymentGuide.md:141-153`):

```markdown
## 7. Endpoints

1. `linux-client01`: install Ubuntu Desktop 24.04, then
   `sudo samba/scripts/join-linux-client.sh` (joins domain, configures SSSD, installs the CA
   chain via `ansible-playbook playbooks/05-pki-trust.yml --limit linux-client01` or manually
   per [PKI.md](PKI.md)).
2. `win-client01`: install Windows 11, confirm DNS is `10.10.0.10` (DHCP-served), then run
   [`samba/scripts/join-windows-client.ps1`](../samba/scripts/join-windows-client.ps1) elevated.
   GPOs (including CA trust) apply automatically on next `gpupdate`/reboot.
3. On each client, run the desktop app provisioning scripts — see
   [docs/DesktopApps.md](DesktopApps.md) and [`desktop-apps/`](../desktop-apps/) — to install
   NextCloud Desktop Sync, OnlyOffice Desktop Editors, Betterbird (autoconfigured), and a
   Stirling PDF app shortcut.
```

New:

```markdown
## 7. Endpoints

`linux-client01` already exists (built manually in step 2). `win-client01`'s VM shell and
unattended Windows 11 install are handled by `workstation/scripts/create-vms.ps1` — see
[`workstation/vms/windows-client.md`](../workstation/vms/windows-client.md) for the
`autounattend.xml` setup needed before running it, then boot it once ready. What's left for
both clients is joining the domain:

1. `linux-client01`: `sudo samba/scripts/join-linux-client.sh` (joins domain, configures SSSD,
   installs the CA chain via `ansible-playbook playbooks/05-pki-trust.yml --limit
   linux-client01` or manually per [PKI.md](PKI.md)).
2. `win-client01`: confirm DNS is `10.10.0.10` (DHCP-served), then run
   [`samba/scripts/join-windows-client.ps1`](../samba/scripts/join-windows-client.ps1) elevated.
   GPOs (including CA trust) apply automatically on next `gpupdate`/reboot.
3. On each client, run the desktop app provisioning scripts — see
   [docs/DesktopApps.md](DesktopApps.md) and [`desktop-apps/`](../desktop-apps/) — to install
   NextCloud Desktop Sync, OnlyOffice Desktop Editors, Betterbird (autoconfigured), and a
   Stirling PDF app shortcut.
```

This last change (calling out that `win-client01`'s VM/OS install is already handled by
`create-vms.ps1`, not a manual "install Windows 11" step) corrects a pre-existing inconsistency
in this same section — `win-client01` has had an `autounattend.xml` seed since the
`2026-08-16-cross-platform-vm-helpers-design.md` work, but this section's wording was never
updated to say so. It's in scope here because this task is already rewriting this exact
section.

- [ ] **Step 6: Verify**

```bash
grep -n "^## " docs/DeploymentGuide.md
```

Expected output (headings, in order — note the grep pattern `^## ` only matches two-hash
headings, so the `### 6a.` sub-heading correctly does not appear here):

```
## 0. Host prerequisites
## 1. pfSense — fully manual
## 2. Admin desktop — `linux-client01` (control host)
## 3. Samba AD Domain Controller
## 4. PKI bootstrap
## 5. Docker application server + Authentik
## 6. Applications
## 7. Endpoints
## 8. Validation
## One-shot re-runs
## Beyond one business (optional)
```

Then confirm no stale references remain:

```bash
grep -n "configure-vmnet\|VMnet2\|WSL2, not Git Bash or PowerShell alone" docs/DeploymentGuide.md
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add docs/DeploymentGuide.md
git commit -m "Restructure DeploymentGuide.md: manual pfSense/admin-desktop, drop WSL2 default

Step 1 (Networking) is absorbed into a fully-manual pfSense step; a new step 2
builds linux-client01 as the control host, replacing WSL2 as the default.
Downstream step numbers (3 Samba AD, 4 PKI, 5 Docker+Authentik, 6 Applications,
7 Endpoints, 8 Validation) are unchanged so existing #anchor links elsewhere in
the repo keep resolving. Step 7 also now correctly describes win-client01's
already-automated unattended install instead of calling it a manual step."
```

---

### Task 8: Demote `docs/WSLSetup.md` to an optional appendix; update `README.md`

**Files:**
- Modify: `docs/WSLSetup.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: the control-host framing from Task 7.

- [ ] **Step 1: Replace `docs/WSLSetup.md`'s intro**

Old (`docs/WSLSetup.md:1-8`):

```markdown
# WSL2 Setup (Control Host)

This lab is deployed from Windows (VMware Workstation host), but the actual deployment
tooling — Ansible, the PKI shell scripts, `samba-tool` invocations, `rsync` — needs a real
Linux environment. This doc covers setting up WSL2 as that environment: why it's needed (not
just Git Bash), how to configure its networking so it can actually reach the lab's LAN, and
how to point VS Code at it. Referenced from
[docs/DeploymentGuide.md](DeploymentGuide.md#0-host-prerequisites).
```

New:

```markdown
# WSL2 as an alternative control host

This lab's default control host is `linux-client01` (see
[docs/DeploymentGuide.md](DeploymentGuide.md#2-admin-desktop--linux-client01-control-host)) — a
VM built inside the lab's own LAN Segment, so it needs no special networking setup to reach the
rest of the lab.

If you'd rather drive the deployment tooling — Ansible, the PKI shell scripts, `samba-tool`
invocations, `rsync` — from the Windows host instead, via WSL2, this doc covers what that path
needs: why WSL2 (not Git Bash), how to configure its networking so it can reach the lab's
`LAN-LAB` LAN Segment, and how to point VS Code at it.
```

- [ ] **Step 2: Update the closing sentence of "Why WSL2, not Git Bash"**

Old (`docs/WSLSetup.md:32-33`):

```markdown
Keep Git Bash for what it's good at (quick single-script runs, `git` itself); use WSL2 for
everything under [`docs/DeploymentGuide.md`](DeploymentGuide.md)'s steps 3 onward.
```

New:

```markdown
Keep Git Bash for what it's good at (quick single-script runs, `git` itself); if you're taking
this path instead of `linux-client01`, use WSL2 for everything
[`docs/DeploymentGuide.md`](DeploymentGuide.md) documents from step 3 onward.
```

- [ ] **Step 3: Fix the LAN Segment references in the "Networking" section**

Old (`docs/WSLSetup.md:60-64`, within the "Networking: the part that actually trips people up"
section):

```markdown
This is the one genuinely non-obvious step. By default, WSL2 puts itself behind its **own**
NAT'd virtual switch — separate from VMware Workstation's `VMnet-LAB` host-only network
(`10.10.0.0/24`) that pfSense and every lab VM live on. Concretely: **out of the box, your WSL2
shell cannot reach `10.10.0.1` (pfSense) at all**, even though the Windows host it's running on
can. Every `ansible-playbook` run and every `ssh samba-dc01.lab.internal` from WSL depends on
fixing this first.
```

New:

```markdown
This is the one genuinely non-obvious step. By default, WSL2 puts itself behind its **own**
NAT'd virtual switch — separate from VMware Workstation's `LAN-LAB` LAN Segment
(`10.10.0.0/24`) that pfSense and every lab VM live on. Concretely: **out of the box, your WSL2
shell cannot reach `10.10.0.1` (pfSense) at all**, even though the Windows host it's running on
can. Every `ansible-playbook` run and every `ssh samba-dc01.lab.internal` from WSL depends on
fixing this first.
```

Old (`docs/WSLSetup.md:69-71`, in the "mirrored networking mode" subsection):

```markdown
Mirrored mode makes WSL2 share the Windows host's network interfaces directly — including
VMware's `VMnet-LAB` adapter — instead of running behind its own NAT. This is the simplest
correct fix and needs no manual routes or port proxies.
```

New:

```markdown
Mirrored mode makes WSL2 share the Windows host's network interfaces directly — including
whichever adapter VMware assigned to the `LAN-LAB` LAN Segment — instead of running behind its
own NAT. This is the simplest correct fix and needs no manual routes or port proxies.
```

Old (`docs/WSLSetup.md:88-92`):

```markdown
```bash
ping -c 2 10.10.0.1        # pfSense LAN IP - should respond
ip addr                     # you should see the same adapters Windows itself has, including
                             # the one VMware assigned VMnet-LAB
```
```

New:

```markdown
```bash
ping -c 2 10.10.0.1        # pfSense LAN IP - should respond
ip addr                     # you should see the same adapters Windows itself has, including
                             # the one VMware assigned the LAN-LAB LAN Segment
```
```

- [ ] **Step 4: Verify**

```bash
grep -n "VMnet-LAB\|WSL2 Setup (Control Host)" docs/WSLSetup.md
```

Expected: no output.

- [ ] **Step 5: Update `README.md`'s documentation index row**

Old (`README.md:62`):

```markdown
| [WSLSetup.md](docs/WSLSetup.md)                 | Setting up WSL2 as the Ansible control host, and why it's needed                                      |
```

New:

```markdown
| [WSLSetup.md](docs/WSLSetup.md)                 | Optional: driving the build from WSL2 on the Windows host instead of the linux-client01 admin VM     |
```

- [ ] **Step 6: Update `README.md`'s Quick start block**

Old (`README.md:85-102`):

```markdown
## Quick start

```bash
# 1. Networking + VMs (Windows host, elevated PowerShell)
workstation\scripts\configure-vmnet.ps1
workstation\scripts\create-vms.ps1

# 2. pfSense, Samba AD, endpoints — see docs/DeploymentGuide.md for the full sequence
#    (pfSense install and OS installs are interactive; everything after is scripted)

# 3. PKI + identity + application layers, once VMs exist and are reachable over SSH
make pki-init
make pki-issue-all
make deploy   # wraps scripts/deploy-all.sh: runs ansible/playbooks/site.yml end to end
```

See [docs/DeploymentGuide.md](docs/DeploymentGuide.md) for the complete step-by-step, including
the manual steps that have no scriptable equivalent (pfSense install, Windows install).
```

New:

```markdown
## Quick start

```bash
# 1. pfSense + admin desktop (VMware Workstation GUI, fully manual — see
#    docs/DeploymentGuide.md steps 1-2). Building pfSense's second NIC is what creates the
#    LAN-LAB LAN Segment every other VM's NIC uses.

# 2. Remaining VM shells (Windows host, elevated PowerShell)
workstation\scripts\create-vms.ps1

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

- [ ] **Step 7: Verify**

```bash
grep -n "configure-vmnet" README.md
```

Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add docs/WSLSetup.md README.md
git commit -m "Demote WSLSetup.md to an optional appendix, update README's quick start

linux-client01 is now the documented default control host; WSL2 stays
available as an alternative for anyone who'd rather drive the build from the
Windows host. README's quick start and doc index are updated to match."
```

---

### Task 9: Mark the pfSense config template/script as an optional shortcut

**Files:**
- Modify: `pfsense/README.md`

- [ ] **Step 1: Add a note near the top of the file**

Old (`pfsense/README.md:1-7`):

```markdown
# pfSense

pfSense is the perimeter firewall, DHCP server, and DNS forwarder for the LAN. It is not
Ansible-managed (see [workstation/README.md](../workstation/README.md#why-not-terraform) for
the equivalent rationale — pfSense's config is XML-based and doesn't lend itself to idempotent
CLI automation the way Linux does).
```

New:

```markdown
# pfSense

pfSense is the perimeter firewall, DHCP server, and DNS forwarder for the LAN. It is not
Ansible-managed (see [workstation/README.md](../workstation/README.md#why-not-terraform) for
the equivalent rationale — pfSense's config is XML-based and doesn't lend itself to idempotent
CLI automation the way Linux does).

**The files below are an optional shortcut, not the default first-run path.**
[`docs/DeploymentGuide.md`](../docs/DeploymentGuide.md#1-pfsense--fully-manual) and
[`workstation/vms/pfsense.md`](../workstation/vms/pfsense.md) walk through configuring pfSense
entirely by hand — start there. Come back to `config.xml.template` once you're comfortable with
the manual flow and want a reviewed, reusable baseline for future rebuilds.
```

- [ ] **Step 2: Verify**

```bash
grep -n "optional shortcut" pfsense/README.md
```

Expected: one match, the sentence added above.

- [ ] **Step 3: Commit**

```bash
git add pfsense/README.md
git commit -m "Note pfsense/README.md's config template as an optional shortcut

The manual build/config walkthrough in DeploymentGuide.md and pfsense.md is
now the documented default; config.xml.template + pfsense-post-install.sh
are for once that's familiar, not the starting point."
```

---

## Final check (after all 9 tasks)

- [ ] Run the full stale-reference sweep across the whole repo:

```bash
grep -rn "configure-vmnet\|vnetlib\|VMnet2\|VMnet-LAB" --include="*.md" --include="*.ps1" . \
  | grep -v "docs/superpowers/specs\|docs/superpowers/plans"
```

Expected: no output. (Only the spec and this plan, both historical records, still mention the
old approach — that's correct and expected.)

- [ ] Confirm every script touched is still tracked executable where applicable:

```bash
git ls-files -s workstation/scripts/create-vms.ps1
```

Expected: mode `100755` (unchanged from before this plan — `create-vms.ps1` was already
executable and this plan doesn't change that).
