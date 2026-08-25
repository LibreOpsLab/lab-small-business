# VMware Workstation VM Helpers (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the VMware Workstation VM layer's already-partial autoinstall support into
actually-unattended installs — real seed-data files (not inline doc YAML a student hand-copies),
a script that builds the seed ISO, and `create-vms.ps1` wired to attach it automatically — plus
fix the latent vTPM/UEFI gap that would otherwise block `win-client01`'s Windows 11 install.

**Architecture:** Each autoinstall-capable VM gets a committed `.example` seed-data template
(cloud-init NoCloud `user-data`+`meta-data` for the three Ubuntu Server hosts, Windows Setup's
`autounattend.xml` for `win-client01`) that a student copies and fills in with real secrets — the
filled copy is gitignored, mirroring this repo's existing `.env.example`/`.env` convention. A new
`build-seed-iso.ps1` turns that filled copy into an ISO; `create-vms.ps1` calls it automatically
and attaches the result as a second CD-ROM.

**Tech Stack:** PowerShell (`.ps1`), cloud-init `autoinstall` YAML, Windows unattend XML, VMware
`.vmx` config, IMAPI2 (Windows' built-in disc-image COM API — no extra tool install required).

**Spec:** [docs/superpowers/specs/2026-08-16-cross-platform-vm-helpers-design.md](../specs/2026-08-16-cross-platform-vm-helpers-design.md)

## Global Constraints

- Domain/subnet strings are literal, not templated: `lab.internal`, `10.10.0.x` appear as plain
  text (CLAUDE.md — this is what lets `scripts/provision-business.sh` rebase them later).
- Secrets never committed: every real seed-data file (containing a password hash or similar) is
  gitignored; only its `.example` template is committed (CLAUDE.md's `.env.example`/`.env`
  pattern, applied here).
- No CI in this repo. Validation for `.ps1` changes is careful manual read-through — this
  environment has no `pwsh` (confirmed: `which pwsh` finds nothing), so nothing here can be
  executed and observed the way the YAML/XML seed files can. Flag this plainly rather than
  claiming a check that didn't happen. YAML validates with `python3 -c "import yaml; ..."`
  (`pyyaml` confirmed installed); XML validates with `xmllint --noout` (confirmed installed).
- Every new/touched doc explains _why_, not just _what_ — this is a teaching artifact
  (CLAUDE.md, and explicitly requested this session).
- Follow existing patterns exactly: table-driven `$VMs` array in `create-vms.ps1`, per-VM spec
  sheets under `workstation/vms/*.md`, `Write-Host`-with-`[script-name]`-prefix logging style
  already used in `configure-vmnet.ps1`/`create-vms.ps1`.

---

## Task 1: `samba-dc01` seed data + gitignore convention

**Files:**

- Create: `workstation/vms/seeds/samba-dc01/user-data.example`
- Create: `workstation/vms/seeds/samba-dc01/meta-data.example`
- Modify: `.gitignore` (add seed-data + built-ISO ignore rules)
- Modify: `workstation/vms/samba-dc.md` (point at the real files instead of inline YAML)

**Interfaces:**

- Produces: the `workstation/vms/seeds/<name>/{user-data,meta-data}.example` naming convention
  that Tasks 2–3 follow, and the `workstation/vms/seeds/<name>/{user-data,meta-data}` (no
  `.example` — gitignored, student-filled) pair that Task 5's `build-seed-iso.ps1` reads.

- [ ] **Step 1: Add the gitignore rules for seed data and built seed ISOs**

Add this block to `.gitignore` immediately after the existing "VMware Workstation artifacts"
section (after the `workstation/vms/**/*.log` line):

```gitignore
# --- Unattended-install seed data (real secrets students fill in — .example files are
# --- safe to commit, the filled copies are not) ---
workstation/vms/seeds/**/user-data
workstation/vms/seeds/**/meta-data
workstation/vms/seeds/**/autounattend.xml
workstation/vms/**/*-seed.iso
```

- [ ] **Step 2: Write `workstation/vms/seeds/samba-dc01/user-data.example`**

```yaml
#cloud-config
# NoCloud seed for samba-dc01 — consumed by Ubuntu Server's autoinstall (Subiquity) via a
# second, read-only CD attached alongside the Ubuntu Server ISO. Subiquity looks for a NoCloud
# datasource (this file + meta-data next to it, on a disc labeled "cidata") before falling
# back to the normal interactive installer — that's the entire mechanism "unattended install"
# rests on here.
#
# This .example file is committed to git; the real one (with your actual password hash in it)
# is not — copy this file to user-data (same folder, no ".example") and fill in the
# placeholder below before running workstation/scripts/create-vms.ps1. That script calls
# workstation/scripts/build-seed-iso.ps1 automatically, which builds the seed ISO from your
# filled-in copy and refuses to run if it still finds the placeholder untouched.
#
# Reference: https://ubuntu.com/server/docs/install/autoinstall-reference
autoinstall:
  version: 1

  # `identity` sets the first (and, for this lab, only) local account created during install.
  # `labadmin` matches ansible_user in ansible/inventory/hosts.ini — Ansible logs in as this
  # account for every playbook run from step 5 onward, so don't rename it without updating the
  # inventory too.
  identity:
    hostname: samba-dc01
    username: labadmin
    # Generate with: mkpasswd --method=sha-512   (the `mkpasswd` command ships in the `whois`
    # package on Debian/Ubuntu — install it on whatever machine you run this from, it doesn't
    # need to be a lab VM).
    password: "$6$replace-with-a-mkpasswd-hash"

  # Static IP, not DHCP: samba-dc01 becomes the DNS server for lab.internal once
  # samba/scripts/bootstrap-ad.sh runs (docs/DeploymentGuide.md#3-samba-ad-domain-controller),
  # so it can't depend on a DHCP server it will itself eventually be authoritative in front of.
  # IP/gateway match docs/Architecture.md's component inventory — if you ever change one, change
  # both, and update ansible/inventory/hosts.ini too.
  network:
    network:
      version: 2
      ethernets:
        # ens160 is the interface name VMware's e1000e NIC emulation presents to Ubuntu Server
        # guests in practice. If your install boots and this doesn't match (check with `ip a`
        # from the installer's shell — Ctrl+Alt+F2 during install), edit this before retrying.
        ens160:
          addresses: [10.10.0.10/24]
          gateway4: 10.10.0.1
          nameservers:
            # 127.0.0.1 during install only — this host becomes authoritative for itself once
            # Samba AD is provisioned; nothing else exists yet to ask for lab.internal records.
            addresses: [127.0.0.1]

  ssh:
    install-server: true
    # Password auth stays on for this lab's bootstrap — there's no SSH-key distribution wired
    # into this seed. Whatever SSH trust you use to reach this host as `labadmin` afterwards
    # (interactive password login, or a key you add yourself post-install) is up to you; see
    # docs/DeploymentGuide.md for what happens next.
    allow-pw: true

  packages:
    - openssh-server

  # Subiquity's package install doesn't start the SSH server itself — this explicitly enables
  # it in the *installed* system. ("in-target" is curtin's term for "run this inside the new
  # root filesystem, not the live installer environment" — a command without it would enable
  # SSH in the temporary installer, which is thrown away at reboot and achieves nothing.)
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
```

- [ ] **Step 3: Write `workstation/vms/seeds/samba-dc01/meta-data.example`**

```yaml
# cloud-init's NoCloud datasource requires meta-data to exist alongside user-data, even though
# nothing here is strictly load-bearing for this lab. instance-id is what cloud-init uses to
# decide "have I already processed this seed" on reboot — change it if you ever need to force
# cloud-init to reprocess an unchanged user-data file.
instance-id: samba-dc01
local-hostname: samba-dc01
```

- [ ] **Step 4: Validate both files parse as YAML**

Run:

```bash
python3 -c "import yaml; yaml.safe_load(open('workstation/vms/seeds/samba-dc01/user-data.example'))" && echo OK
python3 -c "import yaml; yaml.safe_load(open('workstation/vms/seeds/samba-dc01/meta-data.example'))" && echo OK
```

Expected: `OK` printed twice, no exception.

- [ ] **Step 5: Cross-check the IP against the source of truth**

Run:

```bash
grep -n "10.10.0.10" docs/Architecture.md ansible/inventory/hosts.ini workstation/vms/seeds/samba-dc01/user-data.example
```

Expected: all three files show `10.10.0.10` for `samba-dc01` — confirms no typo before this
number gets baked into a seed ISO later.

- [ ] **Step 6: Update `workstation/vms/samba-dc.md` to point at the real files**

Replace the "## Autoinstall" section (currently the inline ` ```yaml ` block) with:

````markdown
## Autoinstall

Ubuntu Server's `autoinstall` (Subiquity) installs this host with zero prompts, driven by a
seed file `create-vms.ps1` attaches automatically as a second CD-ROM — see
[`workstation/scripts/build-seed-iso.ps1`](../scripts/build-seed-iso.ps1) for how that seed
gets built, and [`seeds/samba-dc01/user-data.example`](seeds/samba-dc01/user-data.example) for
what it contains (heavily commented — worth reading even if you don't need to change it).

Before running `create-vms.ps1`:

```bash
cp workstation/vms/seeds/samba-dc01/user-data.example workstation/vms/seeds/samba-dc01/user-data
cp workstation/vms/seeds/samba-dc01/meta-data.example workstation/vms/seeds/samba-dc01/meta-data
mkpasswd --method=sha-512   # paste the output into user-data's password field
```
````

The real `user-data`/`meta-data` (no `.example` suffix) are gitignored — they'll contain your
actual password hash, which is not something to commit.

````

- [ ] **Step 7: Commit**

```bash
git add .gitignore workstation/vms/seeds/samba-dc01/ workstation/vms/samba-dc.md
git commit -m "$(cat <<'EOF'
Add real cloud-init seed for samba-dc01, replacing inline doc YAML

Establishes the .example-template / gitignored-real-file convention that
docker01, authentik01, and win-client01 follow next.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
````

---

## Task 2: `docker01` seed data

**Files:**

- Create: `workstation/vms/seeds/docker01/user-data.example`
- Create: `workstation/vms/seeds/docker01/meta-data.example`
- Modify: `workstation/vms/docker-server.md`

**Interfaces:**

- Consumes: the `.example` convention from Task 1.
- Produces: nothing new consumed elsewhere — same shape as Task 1's output, different IP/DNS.

- [ ] **Step 1: Write `workstation/vms/seeds/docker01/user-data.example`**

Same structure as `samba-dc01`'s, with these differences (full file, not a diff — write it out
completely):

```yaml
#cloud-config
# NoCloud seed for docker01 — see workstation/vms/seeds/samba-dc01/user-data.example for a
# fully-commented walkthrough of this mechanism; comments here cover only what's different.
#
# Copy this file to user-data (drop the .example suffix) and fill in the password hash before
# running workstation/scripts/create-vms.ps1.
autoinstall:
  version: 1
  identity:
    hostname: docker01
    username: labadmin
    # Generate with: mkpasswd --method=sha-512
    password: "$6$replace-with-a-mkpasswd-hash"
  network:
    network:
      version: 2
      ethernets:
        ens160:
          addresses: [10.10.0.20/24]
          gateway4: 10.10.0.1
          # Unlike samba-dc01, this host installs *after* Samba AD is already up
          # (docs/DeploymentGuide.md's ordering), so it can point straight at the real DNS
          # server instead of 127.0.0.1.
          nameservers:
            addresses: [10.10.0.10]
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - openssh-server
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
```

- [ ] **Step 2: Write `workstation/vms/seeds/docker01/meta-data.example`**

```yaml
instance-id: docker01
local-hostname: docker01
```

- [ ] **Step 3: Validate both files parse as YAML**

Run:

```bash
python3 -c "import yaml; yaml.safe_load(open('workstation/vms/seeds/docker01/user-data.example'))" && echo OK
python3 -c "import yaml; yaml.safe_load(open('workstation/vms/seeds/docker01/meta-data.example'))" && echo OK
```

Expected: `OK` printed twice.

- [ ] **Step 4: Cross-check the IP**

Run: `grep -n "10.10.0.20" docs/Architecture.md ansible/inventory/hosts.ini workstation/vms/seeds/docker01/user-data.example`
Expected: all three agree.

- [ ] **Step 5: Update `workstation/vms/docker-server.md`**

Replace the sentence `Autoinstall seed is the same pattern as samba-dc.md with addresses:
[10.10.0.20/24] and nameservers.addresses: [10.10.0.10].` with:

```markdown
Installs unattended from [`seeds/docker01/user-data.example`](seeds/docker01/user-data.example)
— see [`samba-dc.md`](samba-dc.md#autoinstall) for how the seed-ISO mechanism works and the
`cp`/`mkpasswd` steps you need before running `create-vms.ps1`.
```

- [ ] **Step 6: Commit**

```bash
git add workstation/vms/seeds/docker01/ workstation/vms/docker-server.md
git commit -m "$(cat <<'EOF'
Add real cloud-init seed for docker01

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `authentik01` seed data

**Files:**

- Create: `workstation/vms/seeds/authentik01/user-data.example`
- Create: `workstation/vms/seeds/authentik01/meta-data.example`
- Modify: `workstation/vms/authentik.md`

**Interfaces:** Same shape as Task 2, IP `10.10.0.30`.

- [ ] **Step 1: Write `workstation/vms/seeds/authentik01/user-data.example`**

```yaml
#cloud-config
# NoCloud seed for authentik01 — see workstation/vms/seeds/samba-dc01/user-data.example for a
# fully-commented walkthrough; comments here cover only what's different.
#
# Copy this file to user-data (drop the .example suffix) and fill in the password hash before
# running workstation/scripts/create-vms.ps1.
autoinstall:
  version: 1
  identity:
    hostname: authentik01
    username: labadmin
    # Generate with: mkpasswd --method=sha-512
    password: "$6$replace-with-a-mkpasswd-hash"
  network:
    network:
      version: 2
      ethernets:
        ens160:
          addresses: [10.10.0.30/24]
          gateway4: 10.10.0.1
          nameservers:
            addresses: [10.10.0.10]
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - openssh-server
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
```

- [ ] **Step 2: Write `workstation/vms/seeds/authentik01/meta-data.example`**

```yaml
instance-id: authentik01
local-hostname: authentik01
```

- [ ] **Step 3: Validate both files parse as YAML**

Run:

```bash
python3 -c "import yaml; yaml.safe_load(open('workstation/vms/seeds/authentik01/user-data.example'))" && echo OK
python3 -c "import yaml; yaml.safe_load(open('workstation/vms/seeds/authentik01/meta-data.example'))" && echo OK
```

Expected: `OK` printed twice.

- [ ] **Step 4: Cross-check the IP**

Run: `grep -n "10.10.0.30" docs/Architecture.md ansible/inventory/hosts.ini workstation/vms/seeds/authentik01/user-data.example`
Expected: all three agree.

- [ ] **Step 5: Update `workstation/vms/authentik.md`**

Replace `Autoinstall seed follows the same pattern as samba-dc.md with addresses:
[10.10.0.30/24].` with:

```markdown
Installs unattended from
[`seeds/authentik01/user-data.example`](seeds/authentik01/user-data.example) — see
[`samba-dc.md`](samba-dc.md#autoinstall) for how the seed-ISO mechanism works.
```

- [ ] **Step 6: Commit**

```bash
git add workstation/vms/seeds/authentik01/ workstation/vms/authentik.md
git commit -m "$(cat <<'EOF'
Add real cloud-init seed for authentik01

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `win-client01` autounattend answer file

**Files:**

- Create: `workstation/vms/seeds/win-client01/autounattend.xml.example`
- Modify: `workstation/vms/windows-client.md`

**Interfaces:**

- Produces: `workstation/vms/seeds/win-client01/autounattend.xml` (the filled, gitignored copy)
  that Task 5's `build-seed-iso.ps1` auto-detects (it checks for `autounattend.xml` before
  falling back to the `user-data`/`meta-data` pair).

- [ ] **Step 1: Write `workstation/vms/seeds/win-client01/autounattend.xml.example`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  Unattended-install answer file for win-client01 — Windows Setup's equivalent of the
  cloud-init seeds used for the Ubuntu hosts (see samba-dc01's user-data.example for that
  mechanism). Windows Setup looks for a file named exactly "autounattend.xml" at the root of
  any attached disc — that's the whole trigger, no volume-label requirement like cloud-init's
  "cidata".

  Copy this file to autounattend.xml (drop the .example suffix) in this same folder and set a
  real password below before running workstation/scripts/create-vms.ps1 — the real file is
  gitignored, same reasoning as the cloud-init seeds.

  This only gets win-client01 to a logged-in-capable desktop with a local labadmin account.
  Domain join is still the separate, manual step already documented in windows-client.md
  (samba/scripts/join-windows-client.ps1) — unattended domain join isn't attempted here because
  it would need the domain-join credential embedded in this file, and that credential is far
  more sensitive than a throwaway local lab password.

  Reference: https://learn.microsoft.com/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs
-->
<unattend xmlns="urn:schemas-microsoft-com:unattend"
          xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">

  <!-- windowsPE pass: runs from the Windows PE environment the installer boots into, before
       Windows itself is copied to disk. Governs disk partitioning and which image gets
       installed from the .wim on the ISO. -->
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage>
        <UILanguage>en-US</UILanguage>
      </SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
      <!-- Non-US students: change all four locale values above to your own, e.g. en-AU. -->
    </component>

    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserData>
        <AcceptEula>true</AcceptEula>
      </UserData>

      <!-- Wipes the disk create-vms.ps1 just created (which is always blank — a freshly
           vmware-vdiskmanager'd disk, never a real one) and lays down a standard
           EFI/MSR/Windows three-partition layout. WillShowUI="Never" is what makes this run
           with zero prompts instead of asking "where do you want to install Windows?". -->
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Type>EFI</Type>
              <Size>260</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Type>MSR</Type>
              <Size>16</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>3</Order>
              <Type>Primary</Type>
              <Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Label>System</Label>
              <Format>FAT32</Format>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order>
              <PartitionID>2</PartitionID>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>3</Order>
              <PartitionID>3</PartitionID>
              <Label>Windows</Label>
              <Letter>C</Letter>
              <Format>NTFS</Format>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
        <WillShowUI>Never</WillShowUI>
      </DiskConfiguration>

      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add">
              <!-- Windows 11 ISOs bundle multiple editions (Home/Pro/Education/...) in one
                   install.wim, selected by index. Index 6 is commonly "Windows 11 Pro" on the
                   official Microsoft consumer ISO, but this varies by ISO/media source — if
                   Setup fails at this step, boot the ISO manually once, open a command prompt
                   (Shift+F10), and run:
                     dism /Get-WimInfo /WimFile:D:\sources\install.wim
                   to list the real indexes for your specific ISO, then fix the value below. -->
              <Key>/IMAGE/INDEX</Key>
              <Value>6</Value>
            </MetaData>
          </InstallFrom>
          <InstallToAvailablePartition>false</InstallToAvailablePartition>
          <WillShowUI>Never</WillShowUI>
        </OSImage>
        <InstallToAvailablePartition>false</InstallToAvailablePartition>
      </ImageInstall>

      <UserData>
        <ProductKey>
          <!-- Left blank deliberately: a blank key installs in evaluation/unactivated mode,
               which is fine for a lab. Add a real key here if you have one, or activate later
               from within Windows. -->
          <WillShowUI>Never</WillShowUI>
        </ProductKey>
      </UserData>
    </component>
  </settings>

  <!-- specialize pass: runs once, early in the first real boot of the installed system. -->
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>win-client01</ComputerName>
      <TimeZone>UTC</TimeZone>
      <!-- Set this to your own timezone (e.g. "AUS Eastern Standard Time") if you'd rather not
           deal with UTC in the desktop clock — see the "Microsoft Time Zone Index Values" doc
           linked at the top of this file for the exact string format Windows expects. -->
    </component>
  </settings>

  <!-- oobeSystem pass: the "Out Of Box Experience" screens a real Windows install would
       otherwise stop and ask a human to click through. Everything here exists to skip that. -->
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Home</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
        <SkipUserOOBE>true</SkipUserOOBE>
        <SkipMachineOOBE>true</SkipMachineOOBE>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>labadmin</Name>
            <Group>Administrators</Group>
            <Password>
              <!-- REPLACE_ME before use — this is a plaintext-in-this-file placeholder, which
                   is exactly why the real autounattend.xml (no .example suffix) is gitignored
                   and never committed. build-seed-iso.ps1 refuses to build a seed ISO while
                   this literal string is still here. -->
              <Value>REPLACE_ME</Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <!-- No AutoLogon element on purpose: this account has local admin rights, so requiring a
           password at the login screen (rather than auto-logging in) is the safer default for
           a lab machine other people in a classroom might also sit down at. -->
    </component>
  </settings>

</unattend>
```

- [ ] **Step 2: Validate the XML is well-formed**

Run: `xmllint --noout workstation/vms/seeds/win-client01/autounattend.xml.example && echo OK`
Expected: `OK`, no parse errors.

- [ ] **Step 3: Update `workstation/vms/windows-client.md`**

Replace the file's body (everything after the spec table) with:

````markdown
Installs unattended from
[`seeds/win-client01/autounattend.xml.example`](seeds/win-client01/autounattend.xml.example) —
Windows Setup's equivalent of the cloud-init seeds used for the Ubuntu hosts (see
[`samba-dc.md`](samba-dc.md#autoinstall) for that mechanism; the answer file itself explains
the Windows-specific parts inline).

Before running `create-vms.ps1`:

```bash
cp workstation/vms/seeds/win-client01/autounattend.xml.example \
   workstation/vms/seeds/win-client01/autounattend.xml
# then edit autounattend.xml and replace REPLACE_ME with a real password
```
````

`create-vms.ps1` also now configures this VM with UEFI firmware, Secure Boot, and a virtual
TPM 2.0 — Windows 11 Setup hard-requires all three and refuses to install without them, so
without this the VM would fail at the very first Setup screen regardless of the answer file.

## Post-install

1. Confirm DNS is being served correctly: `Resolve-DnsName lab.internal` should return
   `10.10.0.10`.
2. Run [`samba/scripts/join-windows-client.ps1`](../../samba/scripts/join-windows-client.ps1)
   elevated to join the domain into `OU=Windows,OU=Workstations,OU=LAB`.
3. After reboot and domain logon, CA trust and any other GPO-managed settings apply
   automatically (or force with `gpupdate /force`) — see
   [pki/gpo/deploy-root-ca.ps1](../../pki/gpo/deploy-root-ca.ps1) and
   [docs/PKI.md](../../docs/PKI.md#trust-deployment).

See [docs/StudentLabManual.md](../../docs/StudentLabManual.md) for the exercises students run
from this VM.

````

- [ ] **Step 4: Commit**

```bash
git add workstation/vms/seeds/win-client01/ workstation/vms/windows-client.md
git commit -m "$(cat <<'EOF'
Add autounattend.xml for win-client01's unattended Windows 11 install

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
````

---

## Task 5: `build-seed-iso.ps1`

**Files:**

- Create: `workstation/scripts/build-seed-iso.ps1`

**Interfaces:**

- Consumes: `workstation/vms/seeds/<Name>/{user-data,meta-data}` or
  `workstation/vms/seeds/<Name>/autounattend.xml` (real, gitignored files — Tasks 1–4 establish
  the `.example` templates these are copied from).
- Produces: `workstation/vms/<Name>/<Name>-seed.iso`, which Task 6's `create-vms.ps1` attaches
  as `ide1:1`.

- [ ] **Step 1: Write `workstation/scripts/build-seed-iso.ps1`**

```powershell
<#
.SYNOPSIS
    Builds a small ISO ("seed media") from the per-VM files under workstation/vms/seeds/<name>/,
    so create-vms.ps1 can attach it as a second CD-ROM and turn an interactive OS install into
    an unattended one.

.DESCRIPTION
    Two seed formats are supported, auto-detected by what's in the VM's seeds folder:

      - autounattend.xml       -> Windows Setup's own unattended-install answer file.
      - user-data + meta-data  -> cloud-init's "NoCloud" datasource, consumed by Ubuntu
                                   Server's autoinstall (Subiquity). The ISO's volume label
                                   MUST be exactly "cidata" (case-insensitive) — that literal
                                   string is how cloud-init recognises a NoCloud seed at all.

    Real secrets (a password hash, a plaintext local-account password) never live in the
    .example files committed to git — see workstation/vms/seeds/<name>/*.example. This script
    reads the filled-in *copies* you make of those files (same names, no .example suffix),
    which are gitignored, and refuses to build a seed ISO if it finds placeholder text still
    sitting in them un-replaced. That check exists because a seed ISO built from an untouched
    placeholder would boot the VM with a password hash that's sitting in this repo's public git
    history — not a mistake worth being possible to make by accident.

.PARAMETER Name
    VM name matching a subfolder of workstation/vms/seeds/ (e.g. "samba-dc01").

.PARAMETER SeedsDir
    Directory containing per-VM seed subfolders (default: workstation/vms/seeds, next to this
    script).

.PARAMETER OutFile
    Where to write the built ISO. Defaults to workstation/vms/<Name>/<Name>-seed.iso — the same
    folder create-vms.ps1 creates for the VM's .vmx/.vmdk, since that's where create-vms.ps1
    expects to find it.

.EXAMPLE
    .\build-seed-iso.ps1 -Name samba-dc01
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Name,
    [string]$SeedsDir = (Resolve-Path (Join-Path $PSScriptRoot "..\vms\seeds")).Path,
    [string]$OutFile
)

$ErrorActionPreference = "Stop"

$seedDir = Join-Path $SeedsDir $Name
if (-not (Test-Path $seedDir)) {
    throw "No seed folder for '$Name' at $seedDir — this VM has no unattended-install seed " +
          "(expected for pfsense01/linux-client01 — there's nothing for this script to do for them)."
}

if (-not $OutFile) {
    $vmDir = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\vms")).Path $Name
    # create-vms.ps1 normally creates this folder before calling this script; create it here
    # too so this script also works standalone, e.g. re-building a seed after editing user-data
    # without recreating the whole VM.
    New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
    $OutFile = Join-Path $vmDir "$Name-seed.iso"
}

# This exact text can only survive in an un-edited .example file — if it's still present in the
# real (gitignored) file the student copied from it, they haven't filled it in yet.
$placeholderPattern = 'replace-with-a-mkpasswd-hash|REPLACE_ME'

function Assert-NoPlaceholder {
    param([string]$Path)
    if ((Get-Content -Path $Path -Raw) -match $placeholderPattern) {
        throw "$Path still has a placeholder value in it (search it for 'replace-with' or " +
              "'REPLACE_ME'). Fill in the real value, then re-run this script."
    }
}

# Auto-detect which seed format this VM uses.
$autounattend = Join-Path $seedDir "autounattend.xml"
$userData     = Join-Path $seedDir "user-data"
$metaData     = Join-Path $seedDir "meta-data"

if (Test-Path $autounattend) {
    Assert-NoPlaceholder $autounattend
    $files = @($autounattend)
    $volumeLabel = "AUTOUNATTEND"
} elseif ((Test-Path $userData) -and (Test-Path $metaData)) {
    Assert-NoPlaceholder $userData
    $files = @($userData, $metaData)
    $volumeLabel = "cidata"
} else {
    throw "$seedDir has neither autounattend.xml nor a user-data+meta-data pair. Copy the " +
          ".example file(s) in that folder, drop the .example suffix, and fill in the " +
          "placeholder value(s) before running this script."
}

$newestSource = ($files | Get-Item | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
if ((Test-Path $OutFile) -and ((Get-Item $OutFile).LastWriteTime -gt $newestSource)) {
    Write-Host "[build-seed-iso] $OutFile is already up to date — skipping." -ForegroundColor Yellow
    return
}

Write-Host "[build-seed-iso] Building $volumeLabel seed ISO for $Name -> $OutFile" -ForegroundColor Cyan

# IMAPI2 is Windows' built-in disc-image API — the same one Explorer's own "Burn disc image"
# feature uses. Using it here means this script needs nothing beyond a stock Windows install;
# the alternative (the Windows ADK's oscdimg.exe) would mean "install the ADK" becomes a new
# prerequisite just to build a handful of tiny text files onto a disc.
$fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$fsi.FileSystemsToCreate = 3  # ISO9660 (1) bitwise-or Joliet (2): readable by both Linux and Windows tooling
$fsi.VolumeName = $volumeLabel
foreach ($file in $files) {
    # AddTree takes either a file or a directory path; given a single file it just adds that
    # file to the current directory item, which is all that's needed here — each seed folder
    # only ever contains the exact files listed in $files, so there's nothing to recurse into.
    $fsi.Root.AddTree($file, $false) | Out-Null
}

$result = $fsi.CreateResultImage()
$adoStream = New-Object -ComObject ADODB.Stream
$adoStream.Type = 1  # adTypeBinary
$adoStream.Open()
$adoStream.LoadFromStream($result.ImageStream)
if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
$adoStream.SaveToFile($OutFile, 2)  # adSaveCreateOverWrite
$adoStream.Close()

Write-Host "[build-seed-iso] Done: $OutFile" -ForegroundColor Green
```

- [ ] **Step 2: Manual review pass (this environment has no `pwsh` to execute it)**

Read the script back and confirm, by inspection:

- Every `Join-Path`/`Test-Path`/`Get-Item` call has a matching variable defined above it.
- The `if (Test-Path $autounattend) { ... } elseif (...) { ... } else { throw ... }` block
  covers all three cases (Windows seed present, cloud-init seed present, neither) with no
  fall-through gap.
- Braces balance: run `grep -c '{' workstation/scripts/build-seed-iso.ps1` and
  `grep -c '}' workstation/scripts/build-seed-iso.ps1` and confirm the counts match (a cheap
  sanity check, not a substitute for real syntax validation — note this limitation in the PR/commit
  description rather than implying the script has been test-run).

- [ ] **Step 3: Set executable-adjacent conventions and commit**

This is a `.ps1`, not a `.sh` — CLAUDE.md's `chmod +x` convention is POSIX-specific and doesn't
apply here; skip it.

```bash
git add workstation/scripts/build-seed-iso.ps1
git commit -m "$(cat <<'EOF'
Add build-seed-iso.ps1 to turn seed-data files into attachable ISOs

Builds a NoCloud (cloud-init) or autounattend.xml seed ISO via IMAPI2 — no
external tool (e.g. the Windows ADK) required. Not yet wired into
create-vms.ps1 (next task).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Wire `build-seed-iso.ps1` into `create-vms.ps1` + fix `win-client01`'s vTPM/UEFI gap

**Files:**

- Modify: `workstation/scripts/create-vms.ps1`

**Interfaces:**

- Consumes: `build-seed-iso.ps1 -Name <vm.Name>` (Task 5) and
  `workstation/vms/seeds/<vm.Name>/` (Tasks 1–4) to decide whether a VM gets a seed CD-ROM.

- [ ] **Step 1: Replace the `$VMs` table**

Replace the existing table (lines ~38–45) with this — adds `Firmware`/`Vtpm`/`GuestOS` fields.
Every VM except `win-client01` keeps today's exact values (`Firmware = "bios"`, `Vtpm = $false`,
`GuestOS = "ubuntu-64"`) so this is a no-op for them; `win-client01` gets what Windows 11 Setup
actually requires:

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

- [ ] **Step 2: Add seed-ISO detection/build and firmware/vTPM line-building inside the `foreach` loop**

Insert this block immediately after the existing `$nicLines` loop (right before the `@" ... "@`
heredoc that writes the `.vmx`):

```powershell
    # Unattended-install seed media: workstation/vms/seeds/<name>/ only exists for hosts that
    # support an unattended install (Ubuntu Server autoinstall, Windows autounattend). pfSense
    # and the Linux desktop client have no seed folder, so this is a no-op for them — they boot
    # straight into the normal interactive installer, exactly as before this change.
    $seedFolder = Join-Path $VmDir "seeds\$($vm.Name)"
    $cdromLines = ""
    if (Test-Path $seedFolder) {
        Write-Host "[create-vms] $($vm.Name) has an unattended-install seed — building it..." -ForegroundColor Cyan
        & (Join-Path $PSScriptRoot "build-seed-iso.ps1") -Name $vm.Name
        $seedIso = Join-Path $vmFolder "$($vm.Name)-seed.iso"
        $cdromLines = "ide1:1.present = `"TRUE`"`nide1:1.deviceType = `"cdrom-image`"`nide1:1.fileName = `"$seedIso`"`n"
    }

    # win-client01 is the only entry with Firmware = "efi": Windows 11 Setup hard-requires
    # UEFI + Secure Boot + a TPM 2.0 and refuses to install without them. Every other VM here
    # gets none of these lines — same BIOS/no-vTPM behavior as before this change.
    $firmwareLines = ""
    if ($vm.Firmware -eq "efi") {
        $firmwareLines += "firmware = `"efi`"`n"
        $firmwareLines += "uefi.secureBoot.enabled = `"TRUE`"`n"
    }
    if ($vm.Vtpm) {
        $firmwareLines += "vtpm.present = `"TRUE`"`n"
    }
```

- [ ] **Step 3: Splice the new lines into the `.vmx` heredoc and use `$vm.GuestOS`**

Replace the heredoc's `$nicLines` line and its final `guestOS = "ubuntu-64"` line:

```powershell
    @"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "$($vm.Name)"
numvcpus = "$($vm.VCPU)"
memsize = "$($vm.RamMB)"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$($vm.Name).vmdk"
ide1:0.present = "TRUE"
ide1:0.deviceType = "cdrom-image"
ide1:0.fileName = "$isoPath"
$cdromLines$nicLines$firmwareLines
guestOS = "$($vm.GuestOS)"
"@ | Set-Content -Path $vmx -Encoding ASCII
```

- [ ] **Step 4: Update the `.SYNOPSIS`/`.DESCRIPTION` comment block at the top of the file**

Replace:

```
    Creates the lab's VM shells (disk + .vmx) via vmrun/vmware-vdiskmanager, ready for OS
    installation. Does not install any OS — pfSense and Windows still require interactive
    install; Ubuntu hosts can be handed an autoinstall/cloud-init seed ISO (see each VM's
    spec sheet under workstation/vms/) for unattended installation.
```

with:

```
    Creates the lab's VM shells (disk + .vmx) via vmrun/vmware-vdiskmanager, ready for OS
    installation. For any VM with a workstation/vms/seeds/<name>/ folder (every host except
    pfsense01 and linux-client01), also builds and attaches an unattended-install seed ISO via
    build-seed-iso.ps1 — those VMs install with zero prompts once booted. pfSense has no
    unattended installer to target; the Linux desktop client's install is intentionally manual
    (see linux-client.md).
```

- [ ] **Step 5: Manual review pass (no `pwsh` available in this environment to execute it)**

Read the full modified file back and confirm:

- `$cdromLines`, `$nicLines`, and `$firmwareLines` are each defined before the heredoc that
  references them, for every code path (including the `Test-Path $seedFolder` being false, and
  `$vm.Firmware` not being `"efi"`).
- The `$VMs` table's `GuestOS` field is present on all six entries — a missing one would throw a
  null-property error when `$vm.GuestOS` is read.
- `$firmwareLines` is empty for every VM except `win-client01` (confirm — that's the whole
  point of the `Firmware`/`Vtpm` fields only being set to non-default values on that one entry).
  `$cdromLines`, by contrast, is **expected to be non-empty** for `samba-dc01`, `docker01`, and
  `authentik01` too, since Tasks 1–3 already created their `workstation/vms/seeds/<name>/`
  folders — those three VMs picking up a seed CD-ROM is the actual point of this task, not a
  regression to catch.

- [ ] **Step 6: Commit**

```bash
git add workstation/scripts/create-vms.ps1
git commit -m "$(cat <<'EOF'
Wire seed-ISO building into create-vms.ps1; fix win-client01 vTPM/UEFI gap

create-vms.ps1 now calls build-seed-iso.ps1 automatically for any VM with a
seeds/ folder and attaches the result as a second CD-ROM, making the Ubuntu
autoinstall and Windows autounattend seeds from earlier tasks actually take
effect. Also fixes a latent bug: win-client01 was being created as a BIOS VM
with no vTPM, which Windows 11 Setup refuses to install onto regardless of
this project — it now gets EFI firmware, Secure Boot, and a virtual TPM 2.0.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Update `docs/DeploymentGuide.md` for the now-unattended flow

**Files:**

- Modify: `docs/DeploymentGuide.md`

**Interfaces:** None — pure documentation, consumed only by a student reading it.

- [ ] **Step 1: Update step 3 (Samba AD Domain Controller)**

Replace:

```markdown
## 3. Samba AD Domain Controller

1. Create `samba-dc01` per [`workstation/vms/samba-dc.md`](../workstation/vms/samba-dc.md)
   (2 vCPU, 4 GB RAM, 40 GB disk, static `10.10.0.10`, gateway `10.10.0.1`).
2. Install Ubuntu Server 24.04 (unattended install seed available at
   `workstation/vms/samba-dc.md#autoinstall`).
3. `sudo samba/scripts/bootstrap-ad.sh` — provisions the domain (see
   [SambaAdmin.md](SambaAdmin.md)).
```

with:

```markdown
## 3. Samba AD Domain Controller

1. Fill in `samba-dc01`'s install seed (see
   [`workstation/vms/samba-dc.md#autoinstall`](../workstation/vms/samba-dc.md#autoinstall) —
   copy the `.example` files, generate a password hash with `mkpasswd`).
2. `workstation/scripts/create-vms.ps1` creates `samba-dc01`'s VM shell (2 vCPU, 4 GB RAM,
   40 GB disk, static `10.10.0.10`, gateway `10.10.0.1`) and builds/attaches its seed ISO
   automatically. Boot it — Ubuntu Server installs with no prompts and reboots into a running
   system with SSH up.
3. `sudo samba/scripts/bootstrap-ad.sh` — provisions the domain (see
   [SambaAdmin.md](SambaAdmin.md)).
```

- [ ] **Step 2: Update step 5 (Docker application server + Authentik)**

Replace the first bullet of step 5:

```markdown
1. Create `docker01` (`10.10.0.20`) and `authentik01` (`10.10.0.30`) per
   [`workstation/vms/docker-server.md`](../workstation/vms/docker-server.md) and
   [`workstation/vms/authentik.md`](../workstation/vms/authentik.md).
```

with:

```markdown
1. Fill in `docker01`'s and `authentik01`'s install seeds (same `.example`-copy-and-fill
   pattern as `samba-dc01` — see
   [`workstation/vms/docker-server.md`](../workstation/vms/docker-server.md) and
   [`workstation/vms/authentik.md`](../workstation/vms/authentik.md)), then boot them — both
   install unattended the same way `samba-dc01` did in step 3.
```

- [ ] **Step 3: Add a note to step 0 (Host prerequisites) about the new dependency**

Append a bullet to the "## 0. Host prerequisites" list:

```markdown
- `mkpasswd` (from the `whois` package — WSL2 has it, or any Debian/Ubuntu machine) to generate
  password hashes for the Ubuntu Server autoinstall seeds used in steps 3 and 5. No extra tool
  is needed to build the seed ISOs themselves — `workstation/scripts/build-seed-iso.ps1` uses
  IMAPI2, which ships with Windows.
```

- [ ] **Step 4: Read the full file back and confirm cross-references still resolve**

Run:

```bash
grep -n "workstation/vms/samba-dc.md\|workstation/vms/docker-server.md\|workstation/vms/authentik.md" docs/DeploymentGuide.md
```

Expected: the links point at files that exist (`workstation/vms/samba-dc.md` etc. — confirmed
present from Tasks 1–3, unchanged filenames).

- [ ] **Step 5: Commit**

```bash
git add docs/DeploymentGuide.md
git commit -m "$(cat <<'EOF'
Update DeploymentGuide.md for the now-unattended VM install flow

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Notes for whoever executes this plan

- Tasks 1–4 can run in any order relative to each other (independent files); Task 5 depends on
  the naming convention Task 1 establishes but not on Tasks 1–4's content; Task 6 depends on
  Task 5 existing; Task 7 depends on Tasks 1–3's doc changes being in place so its cross-links
  resolve. Sequential order as written is the simplest path.
- The PowerShell in Tasks 5–6 cannot be executed in this development environment (confirmed no
  `pwsh`). Say so plainly wherever this comes up — a real Windows + VMware Workstation smoke
  test (`create-vms.ps1` end to end, confirming both an Ubuntu host and `win-client01` actually
  boot into their unattended installs) is the first real validation these two tasks get, and is
  worth doing before relying on this for a real class.
