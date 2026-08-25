# Hypervisor Rename + VMware Workstation on Linux — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename `workstation/` to `hypervisor/`, split it into per-platform subdirectories, and
add a bash port of the existing PowerShell VM-provisioning pair so the lab can be built on
VMware Workstation Pro for Linux, not just Windows.

**Architecture:** `hypervisor/vmware-windows/scripts/` holds the existing PowerShell scripts
(moved, paths fixed, otherwise unchanged). `hypervisor/vmware-linux/scripts/` gets new bash
equivalents (`create-vms.sh`, `build-seed-iso.sh`) that behave identically — same VM table, same
`.vmx` output, same `vmrun`/`vmware-vdiskmanager` calls, same seed-ISO formats — just Linux
tooling (`xorrisofs`/`genisoimage` instead of IMAPI2FS) and shell instead of PowerShell.
`hypervisor/vms/` (specs + seed data) stays shared, unchanged in content, moved as-is.

**Tech Stack:** Bash (`set -euo pipefail`, this repo's `scripts/lib/common.sh` helpers), `vmrun`
/ `vmware-vdiskmanager` (VMware Workstation Pro for Linux), `xorrisofs` (falls back to
`genisoimage` if that's what's installed).

**Spec:** [docs/superpowers/specs/2026-08-25-multi-hypervisor-support-design.md](../specs/2026-08-25-multi-hypervisor-support-design.md)
— this plan implements that spec's "Directory layout" and "VMware Workstation on Linux"
sections. The spec's "Proxmox (Terraform)" section is a separate plan, built on top of this one.

## Global Constraints

- Every shell script starts `set -euo pipefail` and sources `scripts/lib/common.sh` for
  `log`/`warn`/`die`/`require_cmd` rather than redeclaring those helpers.
- Scripts are tracked executable (`chmod +x`) and syntax-checked with `bash -n` before being
  considered done (no CI in this repo — this is the manual bar).
- Domain/subnet strings (`lab.internal`, `10.10.10.`, `LAN-LAB`) stay literal, not templated, in
  every script and doc this plan touches — consistent with `scripts/provision-business.sh`'s
  global-sed rebasing approach.
- No secrets in this plan's scope (no `.env`, no vault, no PKI material) — nothing here needs a
  `.gitignore` addition beyond the mechanical path rename in Task 1.

---

## Task 1: Rename `workstation/` → `hypervisor/`, split VMware scripts into `vmware-windows/`

Purely mechanical: nothing changes behaviorally, every existing link/path that pointed at
`workstation/...` now points at the equivalent `hypervisor/...` location, and nothing is broken.
No new content, no mention of Linux support yet (that's Task 4, once Linux support exists to
mention).

**Files:**

- Move: `workstation/` → `hypervisor/` (git mv, whole tree)
- Move: `hypervisor/scripts/` → `hypervisor/vmware-windows/scripts/` (git mv)
- Modify: `hypervisor/vmware-windows/scripts/create-vms.ps1` (path-default + comment fixes)
- Modify: `hypervisor/vmware-windows/scripts/build-seed-iso.ps1` (path-default + comment fixes)
- Modify: `hypervisor/vms/samba-dc.md` (link + cp-command paths)
- Modify: `hypervisor/vms/windows-client.md` (cp-command paths)
- Modify: `CLAUDE.md`, `README.md`, `docs/Architecture.md`, `docs/DeploymentGuide.md`,
  `pfsense/README.md`, `.gitignore`

**Interfaces:**

- Produces: `hypervisor/vmware-windows/scripts/create-vms.ps1`,
  `hypervisor/vmware-windows/scripts/build-seed-iso.ps1`, `hypervisor/vms/seeds/<name>/` — the
  exact paths Task 2/3's bash scripts and Task 4's doc updates reference.

- [ ] **Step 1: Move the directory tree**

```bash
git mv workstation hypervisor
mkdir -p hypervisor/vmware-windows
git mv hypervisor/scripts hypervisor/vmware-windows/scripts
git status
```

Expected: `hypervisor/README.md`, `hypervisor/networks/README.md`,
`hypervisor/vmware-windows/scripts/create-vms.ps1`,
`hypervisor/vmware-windows/scripts/build-seed-iso.ps1`, `hypervisor/vms/*.md`,
`hypervisor/vms/seeds/**` all show as renames (`R`) in `git status`, not delete+add — confirms
history is preserved.

- [ ] **Step 2: Fix `create-vms.ps1`'s self-referential paths**

The script now sits one directory deeper (`hypervisor/vmware-windows/scripts/` instead of
`hypervisor/scripts/`), so its `..\vms` default no longer reaches `hypervisor/vms` — it needs a
second `..`.

Modify `hypervisor/vmware-windows/scripts/create-vms.ps1:6`:

Old:

```
    workstation/vms/seeds/<name>/ folder gets built into a seed ISO via build-seed-iso.ps1 and
```

New:

```
    hypervisor/vms/seeds/<name>/ folder gets built into a seed ISO via build-seed-iso.ps1 and
```

Modify `hypervisor/vmware-windows/scripts/create-vms.ps1:32`:

Old:

```
    [string]$VmDir = (Resolve-Path (Join-Path $PSScriptRoot "..\vms")).Path,
```

New:

```
    [string]$VmDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\vms")).Path,
```

Modify `hypervisor/vmware-windows/scripts/create-vms.ps1:79-80`:

Old:

```
    # Unattended-install seed media: every VM left in this script's table has a
    # workstation/vms/seeds/<name>/ folder (Ubuntu Server autoinstall or Windows autounattend) —
```

New:

```
    # Unattended-install seed media: every VM left in this script's table has a
    # hypervisor/vms/seeds/<name>/ folder (Ubuntu Server autoinstall or Windows autounattend) —
```

Modify `hypervisor/vmware-windows/scripts/create-vms.ps1:125`:

Old:

```
Write-Host "All VM shells created. See workstation/vms/*.md for per-VM install notes." -ForegroundColor Green
```

New:

```
Write-Host "All VM shells created. See hypervisor/vms/*.md for per-VM install notes." -ForegroundColor Green
```

- [ ] **Step 3: Fix `build-seed-iso.ps1`'s self-referential paths**

Same reason as Step 2 — one directory deeper now.

Modify `hypervisor/vmware-windows/scripts/build-seed-iso.ps1:3`:

Old:

```
    Builds a small ISO ("seed media") from the per-VM files under workstation/vms/seeds/<name>/,
```

New:

```
    Builds a small ISO ("seed media") from the per-VM files under hypervisor/vms/seeds/<name>/,
```

Modify `hypervisor/vmware-windows/scripts/build-seed-iso.ps1:17`:

Old:

```
    .example files committed to git - see workstation/vms/seeds/<name>/*.example. This script
```

New:

```
    .example files committed to git - see hypervisor/vms/seeds/<name>/*.example. This script
```

Modify `hypervisor/vmware-windows/scripts/build-seed-iso.ps1:25`:

Old:

```
.PARAMETER SeedsDir
    Directory containing per-VM seed subfolders (default: workstation/vms/seeds, next to this
```

New:

```
.PARAMETER SeedsDir
    Directory containing per-VM seed subfolders (default: hypervisor/vms/seeds, next to this
```

Modify `hypervisor/vmware-windows/scripts/build-seed-iso.ps1:32-33`:

Old:

```
.PARAMETER OutFile
    Where to write the built ISO. Defaults to workstation/vms/<Name>/<Name>-seed.iso - the same
```

New:

```
.PARAMETER OutFile
    Where to write the built ISO. Defaults to hypervisor/vms/<Name>/<Name>-seed.iso - the same
```

Modify `hypervisor/vmware-windows/scripts/build-seed-iso.ps1:42`:

Old:

```
    [string]$SeedsDir = (Resolve-Path (Join-Path $PSScriptRoot "..\vms\seeds")).Path,
```

New:

```
    [string]$SeedsDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\vms\seeds")).Path,
```

Modify `hypervisor/vmware-windows/scripts/build-seed-iso.ps1:55`:

Old:

```
    $vmDir = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\vms")).Path $Name
```

New:

```
    $vmDir = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..\vms")).Path $Name
```

- [ ] **Step 4: Fix `hypervisor/vms/samba-dc.md`'s paths**

The script it links to is now under `vmware-windows/scripts/`, one level further from `vms/`
than before.

Modify `hypervisor/vms/samba-dc.md:17-18`:

Old:

```
seed file `create-vms.ps1` attaches automatically as a second CD-ROM — see
[`workstation/scripts/build-seed-iso.ps1`](../scripts/build-seed-iso.ps1) for how that seed
```

New:

```
seed file `create-vms.ps1` attaches automatically as a second CD-ROM — see
[`hypervisor/vmware-windows/scripts/build-seed-iso.ps1`](../vmware-windows/scripts/build-seed-iso.ps1) for how that seed
```

Modify `hypervisor/vms/samba-dc.md:25-26`:

Old:

```
cp workstation/vms/seeds/samba-dc01/user-data.example workstation/vms/seeds/samba-dc01/user-data
cp workstation/vms/seeds/samba-dc01/meta-data.example workstation/vms/seeds/samba-dc01/meta-data
```

New:

```
cp hypervisor/vms/seeds/samba-dc01/user-data.example hypervisor/vms/seeds/samba-dc01/user-data
cp hypervisor/vms/seeds/samba-dc01/meta-data.example hypervisor/vms/seeds/samba-dc01/meta-data
```

- [ ] **Step 5: Fix `hypervisor/vms/windows-client.md`'s paths**

Modify `hypervisor/vms/windows-client.md:21-22`:

Old:

```
cp workstation/vms/seeds/win-client01/autounattend.xml.example \
   workstation/vms/seeds/win-client01/autounattend.xml
```

New:

```
cp hypervisor/vms/seeds/win-client01/autounattend.xml.example \
   hypervisor/vms/seeds/win-client01/autounattend.xml
```

- [ ] **Step 6: Fix `CLAUDE.md`**

Modify `CLAUDE.md:32`:

Old:

```
- `pki/`, `samba/`, `authentik/`, `ansible/`, `scripts/`, `desktop-apps/`, `workstation/`,
  `pfsense/` — see `docs/Architecture.md`'s repository layout section for what each owns.
```

New:

```
- `pki/`, `samba/`, `authentik/`, `ansible/`, `scripts/`, `desktop-apps/`, `hypervisor/`,
  `pfsense/` — see `docs/Architecture.md`'s repository layout section for what each owns.
```

- [ ] **Step 7: Fix `README.md`**

Modify `README.md:43` (repository layout tree):

Old:

```
├── workstation/     VMware Workstation VM inventory, network config, provisioning notes
```

New:

```
├── hypervisor/      VMware Workstation VM inventory, network config, provisioning notes
```

Modify `README.md`'s Quick Start block (the `workstation\scripts\create-vms.ps1` line):

Old:

```
workstation\scripts\create-vms.ps1
```

New:

```
hypervisor\vmware-windows\scripts\create-vms.ps1
```

- [ ] **Step 8: Fix `docs/Architecture.md`**

Modify `docs/Architecture.md:123` (repository layout tree):

Old:

```
├── workstation/     VMware Workstation VM inventory, network config, provisioning notes
```

New:

```
├── hypervisor/      VMware Workstation VM inventory, network config, provisioning notes
```

- [ ] **Step 9: Fix `docs/DeploymentGuide.md`**

This file has nine `workstation/` occurrences. Three of them (lines 22, 91, 178) point at the
PowerShell scripts, which now live one directory deeper under `vmware-windows/scripts/` — a
blind `workstation/` → `hypervisor/` substitution would turn
`workstation/scripts/create-vms.ps1` into `hypervisor/scripts/create-vms.ps1`, a path that
doesn't exist. Fix those three first, specifically, then blind-replace the rest (all
`workstation/vms/...` references, which map 1:1 with no added nesting):

```bash
sed -i 's#workstation/scripts/#hypervisor/vmware-windows/scripts/#g' docs/DeploymentGuide.md
sed -i 's#workstation/#hypervisor/#g' docs/DeploymentGuide.md
grep -n "workstation/" docs/DeploymentGuide.md
```

Expected: the final `grep` prints nothing (zero remaining matches). Spot-check line 22 now
reads `` `hypervisor/vmware-windows/scripts/build-seed-iso.ps1` `` (not
`hypervisor/scripts/...`).

- [ ] **Step 10: Fix `pfsense/README.md`**

Same situation — two plain path references (lines 4, 10, 20).

```bash
sed -i 's#workstation/#hypervisor/#g' pfsense/README.md
grep -n "workstation/" pfsense/README.md
```

Expected: no output.

- [ ] **Step 11: Fix `.gitignore`**

Modify `.gitignore:37-48`:

Old:

```
# --- VMware Workstation artifacts ---
workstation/vms/**/*.vmdk
workstation/vms/**/*.nvram
workstation/vms/**/*.vmsd
workstation/vms/**/*.vmx.lck/
workstation/vms/**/*.log

# --- Unattended-install seed data (real secrets students fill in — .example files are
# --- safe to commit, the filled copies are not) ---
workstation/vms/seeds/**/user-data
workstation/vms/seeds/**/meta-data
workstation/vms/seeds/**/autounattend.xml
workstation/vms/**/*-seed.iso
```

New:

```
# --- VMware Workstation artifacts ---
hypervisor/vms/**/*.vmdk
hypervisor/vms/**/*.nvram
hypervisor/vms/**/*.vmsd
hypervisor/vms/**/*.vmx.lck/
hypervisor/vms/**/*.log

# --- Unattended-install seed data (real secrets students fill in — .example files are
# --- safe to commit, the filled copies are not) ---
hypervisor/vms/seeds/**/user-data
hypervisor/vms/seeds/**/meta-data
hypervisor/vms/seeds/**/autounattend.xml
hypervisor/vms/**/*-seed.iso
```

- [ ] **Step 12: Verify no stale references remain, and syntax-check the moved scripts**

```bash
grep -rn "workstation/" --include="*.md" --include="*.ps1" --include="*.sh" . \
  | grep -v "docs/superpowers/plans/2026-08-16-vmware-vm-helpers.md" \
  | grep -v "docs/superpowers/plans/2026-08-24-lan-segment-manual-first.md" \
  | grep -v "docs/superpowers/specs/2026-08-16-cross-platform-vm-helpers-design.md" \
  | grep -v "docs/superpowers/specs/2026-08-24-lan-segment-manual-first-design.md"
```

Expected: no output (the four excluded files are historical transcripts, deliberately left
unchanged per the spec's "Not touched" note — everything else must be clean).

PowerShell has no local syntax-checker in this environment — confirm by reading both moved
scripts in full and checking brace/quote balance instead:

```bash
grep -c '{' hypervisor/vmware-windows/scripts/create-vms.ps1
grep -c '}' hypervisor/vmware-windows/scripts/create-vms.ps1
grep -c '{' hypervisor/vmware-windows/scripts/build-seed-iso.ps1
grep -c '}' hypervisor/vmware-windows/scripts/build-seed-iso.ps1
```

Expected: each pair of counts matches.

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Rename workstation/ to hypervisor/, split VMware scripts into vmware-windows/

Prepares for VMware-Workstation-on-Linux and Proxmox as additional
provisioning backends, per docs/superpowers/specs/2026-08-25-multi-hypervisor-support-design.md.
Purely mechanical: no behavior changes, all internal links repointed.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `hypervisor/vmware-linux/scripts/build-seed-iso.sh`

Bash port of `build-seed-iso.ps1`: same two seed formats (autounattend.xml vs.
user-data+meta-data), same placeholder guard, same idempotency rule. Only the ISO-building tool
differs — `xorrisofs` (falls back to `genisoimage` if that's what's on `$PATH` instead; both
share the same `mkisofs`-derived CLI, so one code path handles either).

**Files:**

- Create: `hypervisor/vmware-linux/scripts/build-seed-iso.sh`

**Interfaces:**

- Consumes: `hypervisor/vms/seeds/<name>/{autounattend.xml | user-data,meta-data}` (real,
  gitignored files a student creates from the committed `.example` copies).
- Produces: `hypervisor/vms/<name>/<name>-seed.iso`, which Task 3's `create-vms.sh` attaches as
  a second CD-ROM.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Builds a small ISO ("seed media") from the per-VM files under hypervisor/vms/seeds/<name>/,
# so create-vms.sh can attach it as a second CD-ROM and turn an interactive OS install into an
# unattended one. Linux port of build-seed-iso.ps1 — same two seed formats, same placeholder
# guard, same idempotency rule; only the ISO-building tool differs (xorrisofs/genisoimage
# instead of IMAPI2FS, which is Windows-only).
#
# Two seed formats are supported, auto-detected by what's in the VM's seeds folder:
#
#   autounattend.xml       -> Windows Setup's own unattended-install answer file.
#   user-data + meta-data  -> cloud-init's "NoCloud" datasource, consumed by Ubuntu Server's
#                             autoinstall (Subiquity). The ISO's volume label MUST be exactly
#                             "cidata" (case-insensitive) - that literal string is how
#                             cloud-init recognises a NoCloud seed at all.
#
# Real secrets (a password hash, a plaintext local-account password) never live in the
# .example files committed to git - see hypervisor/vms/seeds/<name>/*.example. This script
# reads the filled-in *copies* you make of those files (same names, no .example suffix), which
# are gitignored, and refuses to build a seed ISO if it finds placeholder text still sitting in
# them un-replaced.
#
# Usage: ./build-seed-iso.sh --name=samba-dc01 [--seeds-dir=DIR] [--out-file=FILE]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/lib/common.sh
source "${SCRIPT_DIR}/../../../scripts/lib/common.sh"

NAME=""
SEEDS_DIR="$(cd "${SCRIPT_DIR}/../../vms/seeds" && pwd)"
OUT_FILE=""

for arg in "$@"; do
  case "${arg}" in
    --name=*) NAME="${arg#*=}" ;;
    --seeds-dir=*) SEEDS_DIR="${arg#*=}" ;;
    --out-file=*) OUT_FILE="${arg#*=}" ;;
    *) die "Unknown argument: ${arg} (expected --name=, --seeds-dir=, or --out-file=)" ;;
  esac
done

[[ -n "${NAME}" ]] || die "--name=<vm-name> is required (e.g. --name=samba-dc01)"

# xorrisofs is the actively-maintained tool and is what's verified against in this repo's own
# testing; genisoimage (the older cdrkit tool) exposes the same mkisofs-derived flags, so if
# that's what's installed instead, it works as a drop-in.
if command -v xorrisofs >/dev/null 2>&1; then
  ISO_TOOL="xorrisofs"
elif command -v genisoimage >/dev/null 2>&1; then
  ISO_TOOL="genisoimage"
else
  die "Neither xorrisofs nor genisoimage found. Install one (the xorriso or genisoimage package) to build seed ISOs."
fi

seed_dir="${SEEDS_DIR}/${NAME}"
[[ -d "${seed_dir}" ]] || die "No seed folder for '${NAME}' at ${seed_dir} — this VM has no unattended-install seed (expected for pfsense01/linux-client01 — there's nothing for this script to do for them)."

if [[ -z "${OUT_FILE}" ]]; then
  vm_dir="$(cd "${SCRIPT_DIR}/../../vms" && pwd)/${NAME}"
  # create-vms.sh normally creates this folder before calling this script; create it here too
  # so this script also works standalone, e.g. re-building a seed after editing user-data
  # without recreating the whole VM.
  mkdir -p "${vm_dir}"
  OUT_FILE="${vm_dir}/${NAME}-seed.iso"
fi

# This exact text can only survive in an un-edited .example file — if it's still present in the
# real (gitignored) file the student copied from it, they haven't filled it in yet.
placeholder_pattern='replace-with-a-mkpasswd-hash|REPLACE_ME'

assert_no_placeholder() {
  local path="$1"
  if grep -Eq "${placeholder_pattern}" "${path}"; then
    die "${path} still has a placeholder value in it (search it for 'replace-with' or 'REPLACE_ME'). Fill in the real value, then re-run this script."
  fi
}

autounattend="${seed_dir}/autounattend.xml"
user_data="${seed_dir}/user-data"
meta_data="${seed_dir}/meta-data"

if [[ -f "${autounattend}" ]]; then
  assert_no_placeholder "${autounattend}"
  files=("${autounattend}")
  volume_label="AUTOUNATTEND"
elif [[ -f "${user_data}" && -f "${meta_data}" ]]; then
  assert_no_placeholder "${user_data}"
  files=("${user_data}" "${meta_data}")
  volume_label="cidata"
else
  die "${seed_dir} has neither autounattend.xml nor a user-data+meta-data pair. Copy the .example file(s) in that folder, drop the .example suffix, and fill in the placeholder value(s) before running this script."
fi

newest_source=0
for f in "${files[@]}"; do
  mtime="$(stat -c %Y "${f}")"
  (( mtime > newest_source )) && newest_source="${mtime}"
done

if [[ -f "${OUT_FILE}" ]]; then
  out_mtime="$(stat -c %Y "${OUT_FILE}")"
  if (( out_mtime > newest_source )); then
    warn "${OUT_FILE} is already up to date — skipping."
    exit 0
  fi
fi

log "Building ${volume_label} seed ISO for ${NAME} -> ${OUT_FILE} (using ${ISO_TOOL})"

"${ISO_TOOL}" -output "${OUT_FILE}" -volid "${volume_label}" -joliet -rock "${files[@]}"

log "Done: ${OUT_FILE}"
```

- [ ] **Step 2: Make it executable and syntax-check it**

```bash
chmod +x hypervisor/vmware-linux/scripts/build-seed-iso.sh
bash -n hypervisor/vmware-linux/scripts/build-seed-iso.sh
```

Expected: no output from `bash -n` (syntax OK).

- [ ] **Step 3: Lint it**

```bash
shellcheck hypervisor/vmware-linux/scripts/build-seed-iso.sh
```

Expected: no warnings (or only the expected `SC1091` "not following" note for the sourced
`common.sh`, which is fine — `shellcheck source=` above already tells it where to look, but
CI-less local runs may not resolve it; if it fully resolves, expect a clean pass).

- [ ] **Step 4: Manual dry-run test**

Exercise the placeholder guard and the successful-build path against dummy seed data, without
touching the real (gitignored) `hypervisor/vms/seeds/` tree:

```bash
tmp="$(mktemp -d)"
mkdir -p "${tmp}/seeds/testvm01"
printf '#cloud-config\npassword: REPLACE_ME\n' > "${tmp}/seeds/testvm01/user-data"
printf 'instance-id: testvm01\n' > "${tmp}/seeds/testvm01/meta-data"

# 1. Placeholder guard should refuse to build.
if hypervisor/vmware-linux/scripts/build-seed-iso.sh --name=testvm01 --seeds-dir="${tmp}/seeds" --out-file="${tmp}/testvm01-seed.iso"; then
  echo "FAIL: should have refused to build with a placeholder present"
else
  echo "OK: refused to build with placeholder present"
fi

# 2. Fill in the placeholder, then it should build successfully.
sed -i 's/REPLACE_ME/dummy-hash-value/' "${tmp}/seeds/testvm01/user-data"
hypervisor/vmware-linux/scripts/build-seed-iso.sh --name=testvm01 --seeds-dir="${tmp}/seeds" --out-file="${tmp}/testvm01-seed.iso"
file "${tmp}/testvm01-seed.iso"

rm -rf "${tmp}"
```

Expected: step 1 prints "OK: refused to build with placeholder present"; step 2's `file` output
reads `ISO 9660 CD-ROM filesystem data 'cidata'` (or similar, confirming the `cidata` volume
label cloud-init requires).

- [ ] **Step 5: Commit**

```bash
git add hypervisor/vmware-linux/scripts/build-seed-iso.sh
git commit -m "$(cat <<'EOF'
Add build-seed-iso.sh — Linux port of build-seed-iso.ps1

Same two seed formats, same placeholder guard, same idempotency rule as
the Windows script; builds via xorrisofs/genisoimage instead of IMAPI2FS.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `hypervisor/vmware-linux/scripts/create-vms.sh`

Bash port of `create-vms.ps1`: same VM table (name/vcpu/ram/disk/iso/firmware/vtpm/guest-os),
same generated `.vmx` content, same `vmrun`/`vmware-vdiskmanager` calls, same "skip if it
already exists" idempotency, same call-out to the seed-ISO builder for VMs that have one.

**Files:**

- Create: `hypervisor/vmware-linux/scripts/create-vms.sh`

**Interfaces:**

- Consumes: `hypervisor/vmware-linux/scripts/build-seed-iso.sh --name=<NAME> [flags]` (Task 2).
- Produces: `hypervisor/vms/<name>/<name>.vmx` + `.vmdk`, ready for `vmrun start ... gui`.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Creates the lab's VM shells (disk + .vmx) via vmrun/vmware-vdiskmanager, ready for OS
# installation, for the four hosts with an unattended-install seed (samba-dc01, docker01,
# authentik01, win-client01) — each one's hypervisor/vms/seeds/<name>/ folder gets built into a
# seed ISO via build-seed-iso.sh and attached, so it installs with zero prompts once booted.
# pfsense01 and linux-client01 are built entirely by hand in the Workstation GUI (see their
# respective vms/*.md) and are not in this script's table. Linux port of create-vms.ps1 — same
# VM table, same .vmx content, same vmrun/vmware-vdiskmanager calls; only the shell differs.
#
# Usage: ./create-vms.sh [--vm-dir=DIR] [--iso-dir=DIR] [--vmware-path=DIR] [--lan-network=NAME]
#
#   --vm-dir       Directory under which each VM's folder is created (default: this repo's
#                  hypervisor/vms/<name>/).
#   --iso-dir      Directory holding the OS install ISOs referenced below (default: ~/isos).
#   --vmware-path  Directory containing vmrun and vmware-vdiskmanager (default: /usr/bin — some
#                  installs put them under /usr/lib/vmware/bin instead).
#   --lan-network  Name of the VMware LAN Segment every VM's NIC is attached to (default:
#                  "LAN-LAB", created the first time it's referenced from pfSense's NIC2 — see
#                  hypervisor/vms/pfsense.md). Every VM this script creates has exactly one NIC,
#                  on this network; pfSense is the only VM with a WAN-facing NIC, and it's built
#                  by hand, not by this script.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/lib/common.sh
source "${SCRIPT_DIR}/../../../scripts/lib/common.sh"

VM_DIR="$(cd "${SCRIPT_DIR}/../../vms" && pwd)"
ISO_DIR="${HOME}/isos"
VMWARE_PATH="/usr/bin"
LAN_NETWORK="LAN-LAB"

for arg in "$@"; do
  case "${arg}" in
    --vm-dir=*) VM_DIR="${arg#*=}" ;;
    --iso-dir=*) ISO_DIR="${arg#*=}" ;;
    --vmware-path=*) VMWARE_PATH="${arg#*=}" ;;
    --lan-network=*) LAN_NETWORK="${arg#*=}" ;;
    *) die "Unknown argument: ${arg} (expected --vm-dir=, --iso-dir=, --vmware-path=, or --lan-network=)" ;;
  esac
done

VMRUN="${VMWARE_PATH}/vmrun"
VDISKMAN="${VMWARE_PATH}/vmware-vdiskmanager"

for exe in "${VMRUN}" "${VDISKMAN}"; do
  [[ -x "${exe}" ]] || die "Required tool not found or not executable: ${exe}. Adjust --vmware-path (some installs put these under /usr/lib/vmware/bin instead of /usr/bin)."
done

# name|vcpu|ramMB|diskGB|iso|firmware|vtpm|guestOS — mirrors create-vms.ps1's $VMs table exactly,
# minus the NIC column (every VM here has exactly one NIC, on $LAN_NETWORK).
VMS=(
  "samba-dc01|2|4096|40|ubuntu-server-24.04.iso|bios|false|ubuntu-64"
  "docker01|4|8192|80|ubuntu-server-24.04.iso|bios|false|ubuntu-64"
  "authentik01|2|4096|40|ubuntu-server-24.04.iso|bios|false|ubuntu-64"
  # Windows 11 Setup hard-blocks installation without a detected TPM 2.0 and UEFI firmware —
  # this is the fix for that; every other VM above is untouched (still BIOS, no vTPM, exactly
  # as before this change).
  "win-client01|2|4096|60|Win11.iso|efi|true|windows11-64"
)

for entry in "${VMS[@]}"; do
  IFS='|' read -r name vcpu ram_mb disk_gb iso firmware vtpm guest_os <<< "${entry}"

  vm_folder="${VM_DIR}/${name}"
  vmx="${vm_folder}/${name}.vmx"
  vmdk="${vm_folder}/${name}.vmdk"

  if [[ -f "${vmx}" ]]; then
    warn "${name} already exists at ${vmx} — skipping."
    continue
  fi

  log "Creating ${name} (${vcpu} vCPU, ${ram_mb}MB RAM, ${disk_gb}GB disk)..."
  mkdir -p "${vm_folder}"

  "${VDISKMAN}" -c -s "${disk_gb}GB" -a lsilogic -t 1 "${vmdk}"

  iso_path="${ISO_DIR}/${iso}"
  nic_lines="$(printf 'ethernet0.present = "TRUE"\nethernet0.connectionType = "custom"\nethernet0.vnet = "%s"\nethernet0.virtualDev = "e1000e"\n' "${LAN_NETWORK}")"

  # Unattended-install seed media: every VM left in this script's table has a
  # hypervisor/vms/seeds/<name>/ folder (Ubuntu Server autoinstall or Windows autounattend) —
  # pfsense01 and linux-client01 are built by hand and never reach this script at all.
  seed_folder="${VM_DIR}/seeds/${name}"
  cdrom_lines=""
  if [[ -d "${seed_folder}" ]]; then
    log "${name} has an unattended-install seed — building it..."
    "${SCRIPT_DIR}/build-seed-iso.sh" --name="${name}"
    seed_iso="${vm_folder}/${name}-seed.iso"
    cdrom_lines="$(printf 'ide1:1.present = "TRUE"\nide1:1.deviceType = "cdrom-image"\nide1:1.fileName = "%s"\n' "${seed_iso}")"
  fi

  # win-client01 is the only entry with firmware=efi: Windows 11 Setup hard-requires UEFI +
  # Secure Boot + a TPM 2.0 and refuses to install without them. Every other VM here gets none
  # of these lines — same BIOS/no-vTPM behavior as before this change.
  firmware_lines=""
  if [[ "${firmware}" == "efi" ]]; then
    firmware_lines+=$'firmware = "efi"\nuefi.secureBoot.enabled = "TRUE"\n'
  fi
  if [[ "${vtpm}" == "true" ]]; then
    firmware_lines+=$'vtpm.present = "TRUE"\n'
  fi

  cat > "${vmx}" <<VMX
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "${name}"
numvcpus = "${vcpu}"
memsize = "${ram_mb}"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "${name}.vmdk"
ide1:0.present = "TRUE"
ide1:0.deviceType = "cdrom-image"
ide1:0.fileName = "${iso_path}"
${cdrom_lines}${nic_lines}${firmware_lines}
guestOS = "${guest_os}"
VMX

  log "${name} VM shell ready at ${vmx}"
  log "Boot with: \"${VMRUN}\" start \"${vmx}\" gui"
done

echo ""
log "All VM shells created. See hypervisor/vms/*.md for per-VM install notes."
log "pfsense01 and linux-client01 are built by hand in the Workstation GUI - not by this script."
```

- [ ] **Step 2: Make it executable and syntax-check it**

```bash
chmod +x hypervisor/vmware-linux/scripts/create-vms.sh
bash -n hypervisor/vmware-linux/scripts/create-vms.sh
```

Expected: no output.

- [ ] **Step 3: Lint it**

```bash
shellcheck hypervisor/vmware-linux/scripts/create-vms.sh
```

Expected: clean, or only the same sourced-file note as Task 2.

- [ ] **Step 4: Manual dry-run test of the VM-table loop and `.vmx` generation**

`vmrun`/`vmware-vdiskmanager` aren't installed in this environment, so stub them out to verify
the surrounding logic (argument parsing, table iteration, `.vmx` content, seed-ISO invocation)
without needing real VMware tooling:

```bash
tmp="$(mktemp -d)"
mkdir -p "${tmp}/bin"
# Stub tools: vdiskmanager just needs to "succeed" and leave a file behind; vmrun is never
# actually invoked by this script (only echoed in the final "Boot with:" message).
cat > "${tmp}/bin/vmware-vdiskmanager" <<'STUB'
#!/usr/bin/env bash
touch "${*: -1}"
STUB
cat > "${tmp}/bin/vmrun" <<'STUB'
#!/usr/bin/env bash
true
STUB
chmod +x "${tmp}/bin/vmware-vdiskmanager" "${tmp}/bin/vmrun"

mkdir -p "${tmp}/vms/seeds/samba-dc01"
touch "${tmp}/vms/seeds/samba-dc01/user-data" "${tmp}/vms/seeds/samba-dc01/meta-data"

hypervisor/vmware-linux/scripts/create-vms.sh \
  --vm-dir="${tmp}/vms" --iso-dir="${tmp}/isos" --vmware-path="${tmp}/bin"

cat "${tmp}/vms/samba-dc01/samba-dc01.vmx"
grep -q 'ethernet0.vnet = "LAN-LAB"' "${tmp}/vms/samba-dc01/samba-dc01.vmx" && echo "OK: LAN network line present"
grep -q 'firmware = "efi"' "${tmp}/vms/docker01/docker01.vmx" && echo "FAIL: docker01 should not have EFI firmware" || echo "OK: docker01 has no EFI firmware line"
grep -q 'firmware = "efi"' "${tmp}/vms/win-client01/win-client01.vmx" && echo "OK: win-client01 has EFI firmware"

rm -rf "${tmp}"
```

Expected: the printed `.vmx` looks like a valid VMX file (matches the structure in Step 1's
heredoc); all three `grep`-based checks print their "OK" line.

- [ ] **Step 5: Commit**

```bash
git add hypervisor/vmware-linux/scripts/create-vms.sh
git commit -m "$(cat <<'EOF'
Add create-vms.sh — Linux port of create-vms.ps1

Same VM table, same .vmx generation, same vmrun/vmware-vdiskmanager
calls as the Windows script; calls build-seed-iso.sh for unattended
installs exactly as create-vms.ps1 calls build-seed-iso.ps1.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Document the Linux path

Now that `vmware-linux/` has working scripts, update every doc that only mentioned the Windows
path so readers on Linux know it exists. This is the only task in this plan that adds new prose
(everything in Tasks 1-3 was rename/port work).

**Files:**

- Modify: `hypervisor/README.md` (full rewrite — platform picker)
- Modify: `hypervisor/networks/README.md` (one clause)
- Modify: `hypervisor/vms/samba-dc.md`, `hypervisor/vms/windows-client.md` (mention both scripts)
- Modify: `README.md`, `CLAUDE.md`, `docs/Architecture.md`, `docs/DeploymentGuide.md`

- [ ] **Step 1: Rewrite `hypervisor/README.md` as a platform picker**

```markdown
# Hypervisor Layer

This directory documents and automates the parts of the lab that live outside any guest OS:
choice of hypervisor, virtual network configuration, and VM inventory/specs.

## Choosing a platform

| Platform                         | Directory                            | Host OS | Automation                                 |
| -------------------------------- | ------------------------------------ | ------- | ------------------------------------------ |
| VMware Workstation Pro (default) | [`vmware-windows/`](vmware-windows/) | Windows | PowerShell + `vmrun`/`vmware-vdiskmanager` |
| VMware Workstation Pro           | [`vmware-linux/`](vmware-linux/)     | Linux   | Bash + `vmrun`/`vmware-vdiskmanager`       |

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
```

- [ ] **Step 2: Add the host-OS clause to `hypervisor/networks/README.md`**

Modify `hypervisor/networks/README.md:26-28`:

Old:

```
2. Set **Network connection** to **Custom: Specific virtual network**, open the network
   dropdown, and choose **LAN Segments... > Add...** (exact wording varies slightly by
   Workstation version — look for "LAN Segments" in the network-connection picker).
```

New:

```
2. Set **Network connection** to **Custom: Specific virtual network**, open the network
   dropdown, and choose **LAN Segments... > Add...** (exact wording varies slightly by
   Workstation version and host OS — look for "LAN Segments" in the network-connection picker
   on both Windows and Linux).
```

- [ ] **Step 3: Mention both scripts in `hypervisor/vms/samba-dc.md`**

Modify `hypervisor/vms/samba-dc.md:16-22`:

Old:

```
Ubuntu Server's `autoinstall` (Subiquity) installs this host with zero prompts, driven by a
seed file `create-vms.ps1` attaches automatically as a second CD-ROM — see
[`hypervisor/vmware-windows/scripts/build-seed-iso.ps1`](../vmware-windows/scripts/build-seed-iso.ps1) for how that seed
gets built, and [`seeds/samba-dc01/user-data.example`](seeds/samba-dc01/user-data.example) for
what it contains (heavily commented — worth reading even if you don't need to change it).

Before running `create-vms.ps1`:
```

New:

```
Ubuntu Server's `autoinstall` (Subiquity) installs this host with zero prompts, driven by a
seed file `create-vms.ps1`/`create-vms.sh` attaches automatically as a second CD-ROM — see
[`build-seed-iso.ps1`](../vmware-windows/scripts/build-seed-iso.ps1) (Windows) or
[`build-seed-iso.sh`](../vmware-linux/scripts/build-seed-iso.sh) (Linux) for how that seed gets
built, and [`seeds/samba-dc01/user-data.example`](seeds/samba-dc01/user-data.example) for what
it contains (heavily commented — worth reading even if you don't need to change it).

Before running `create-vms.ps1` (Windows) or `create-vms.sh` (Linux):
```

- [ ] **Step 4: Mention both scripts in `hypervisor/vms/windows-client.md`**

Modify `hypervisor/vms/windows-client.md:18`:

Old:

```
Before running `create-vms.ps1`:
```

New:

```
Before running `create-vms.ps1` (Windows) or `create-vms.sh` (Linux):
```

- [ ] **Step 5: Update `README.md`'s repo-layout description and Quick Start**

Modify `README.md:43`:

Old:

```
├── hypervisor/      VMware Workstation VM inventory, network config, provisioning notes
```

New:

```
├── hypervisor/      VM inventory, network config, provisioning notes (VMware Workstation: Windows or Linux)
```

Modify `README.md`'s Quick Start block:

Old:

```
# 2. Remaining VM shells (Windows host, elevated PowerShell)
hypervisor\vmware-windows\scripts\create-vms.ps1
```

New:

```
# 2. Remaining VM shells
#    Windows host, elevated PowerShell:
hypervisor\vmware-windows\scripts\create-vms.ps1
#    ...or a Linux host:
./hypervisor/vmware-linux/scripts/create-vms.sh
```

- [ ] **Step 6: Update `CLAUDE.md`'s "What this is" section**

Modify `CLAUDE.md:7-9`:

Old:

```
A self-contained, IaC-driven homelab simulating a small organisation's IT estate on VMware
Workstation: pfSense, Samba AD, an internal PKI, Authentik SSO, a Docker application platform,
and Windows/Linux endpoints. It's a **teaching artifact** — code quality and doc clarity are
```

New:

```
A self-contained, IaC-driven homelab simulating a small organisation's IT estate on VMware
Workstation (Windows or Linux host — see [hypervisor/README.md](hypervisor/README.md)):
pfSense, Samba AD, an internal PKI, Authentik SSO, a Docker application platform, and
Windows/Linux endpoints. It's a **teaching artifact** — code quality and doc clarity are
```

- [ ] **Step 7: Update `docs/Architecture.md`'s Purpose and repo-layout description**

Modify `docs/Architecture.md:9`:

Old:

```
containerised applications — end to end, on a single VMware Workstation host.
```

New:

```
containerised applications — end to end, on a single VMware Workstation host (Windows or
Linux — see [hypervisor/README.md](../hypervisor/README.md)).
```

Modify `docs/Architecture.md:123`:

Old:

```
├── hypervisor/      VMware Workstation VM inventory, network config, provisioning notes
```

New:

```
├── hypervisor/      VM inventory, network config, provisioning notes (VMware Workstation: Windows or Linux)
```

- [ ] **Step 8: Update `docs/DeploymentGuide.md`'s host-prerequisites line**

Modify `docs/DeploymentGuide.md:4-5`:

Old:

```
Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro 17+ on the host and Ubuntu Server 24.04 LTS for
all Linux VMs unless stated otherwise.
```

New:

```
Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro 17+ on the host (Windows or Linux — see
[hypervisor/README.md](../hypervisor/README.md) for the Linux path) and Ubuntu Server 24.04
LTS for all Linux VMs unless stated otherwise.
```

- [ ] **Step 9: Verify links resolve and commit**

```bash
grep -rn "hypervisor/README.md\|vmware-linux/scripts\|vmware-windows/scripts" \
  CLAUDE.md README.md docs/Architecture.md docs/DeploymentGuide.md \
  hypervisor/README.md hypervisor/networks/README.md hypervisor/vms/samba-dc.md hypervisor/vms/windows-client.md
```

Expected: every referenced path (`hypervisor/README.md`, `hypervisor/vmware-linux/scripts/`,
`hypervisor/vmware-windows/scripts/`) exists on disk — spot-check a couple with `ls`.

```bash
git add hypervisor/README.md hypervisor/networks/README.md hypervisor/vms/samba-dc.md \
  hypervisor/vms/windows-client.md README.md CLAUDE.md docs/Architecture.md docs/DeploymentGuide.md
git commit -m "$(cat <<'EOF'
Document the VMware-Workstation-on-Linux path across the repo's docs

Adds hypervisor/README.md as a platform picker and points every doc
that assumed Windows-only at the new Linux scripts too.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Done criteria for this plan

- `hypervisor/` exists, `workstation/` does not (`git status` clean, history preserved via `git mv`).
- `hypervisor/vmware-windows/scripts/*.ps1` and `hypervisor/vmware-linux/scripts/*.sh` both
  exist, are syntactically valid, and produce equivalent `.vmx` output for the same VM table.
- `grep -rn "workstation/" .` (excluding `.git/` and the four named historical plan/spec docs)
  returns nothing.
- `hypervisor/README.md` explains both VMware platforms; every top-level doc that mentioned the
  Windows path now also mentions the Linux one.
- The Proxmox plan (next) can assume this renamed, working structure exists.
