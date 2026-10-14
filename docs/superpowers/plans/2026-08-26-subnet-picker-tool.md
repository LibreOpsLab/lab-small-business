# Subnet Picker Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user pick a different subnet than the repo's shipped `10.10.10.0/24` default via a small standalone tool, `scripts/set-subnet.sh`, and fix a bug where `scripts/provision-business.sh`'s subnet rewrite currently does nothing.

**Architecture:** Extract the copy-repo and subnet-validate/rewrite logic that `provision-business.sh` already has (buggy) into a new sourced library, `scripts/lib/business-rebase.sh`. Both `provision-business.sh` (refactored to use it) and the new `scripts/set-subnet.sh` call the shared functions. Neither script gains new external dependencies — same `bash`/`rsync`/`sed`/`grep` toolchain already used throughout `scripts/`.

**Tech Stack:** Bash (`set -euo pipefail`), `scripts/lib/common.sh` for `log`/`warn`/`die`, `rsync` with `cp -a` fallback, `grep -rlI` + `sed -i` for text rewriting. No test framework in this repo — validation is `bash -n` syntax checks plus manual dry runs into scratch directories, per `CLAUDE.md`.

**Spec:** [docs/superpowers/specs/2026-08-26-subnet-picker-tool-design.md](../specs/2026-08-26-subnet-picker-tool-design.md)

## Global Constraints

- Every shell script starts `set -euo pipefail` and sources `scripts/lib/common.sh` (directly or transitively) instead of re-declaring `log()`/`warn()`/`die()`.
- New/touched scripts are tracked executable (`chmod +x`).
- No apostrophes inside `${VAR:?message}` parameter expansions (none used here, but keep it in mind if editing die-message strings).
- No interactive prompts — flag/positional-arg driven only.
- The repo's default subnet prefix is `10.10.10` — this is the one and only "old prefix" both tools rebase away from; no auto-detection of an already-rebased copy's current subnet.
- `bash -n path/to/script.sh` must pass for every script touched or added, per `CLAUDE.md`'s validation convention.

---

### Task 1: `scripts/lib/business-rebase.sh` — shared copy/validate/rewrite functions

**Files:**
- Create: `scripts/lib/business-rebase.sh`

**Interfaces:**
- Consumes: `log()`, `warn()`, `die()` from `scripts/lib/common.sh` (sourced internally).
- Produces (for Tasks 2 and 3 to consume):
  - `REPO_DEFAULT_SUBNET_PREFIX` — readonly string constant, `"10.10.10"`.
  - `copy_repo <src> <dst>` — copies `<src>` into `<dst>`, excluding `.git`, PKI key material, and secrets. No return value; dies via `die()` on unrecoverable errors from underlying commands (propagated by `set -e`).
  - `validate_subnet <cidr>` — validates `<cidr>` is an RFC1918 `/24` (e.g. `10.20.30.0/24`). Prints the validated prefix (e.g. `10.20.30`) to stdout on success. Dies via `die()` on invalid input.
  - `rewrite_subnet <dir> <old_prefix> <new_prefix>` — rewrites every occurrence of `<old_prefix>.` to `<new_prefix>.` across all text files under `<dir>`. No return value.

- [ ] **Step 1: Write `scripts/lib/business-rebase.sh`**

```bash
#!/usr/bin/env bash
# Shared logic for scripts that rebase this repo's identity onto a fresh copy:
# scripts/provision-business.sh (full domain/netbios/subnet rebase) and
# scripts/set-subnet.sh (subnet-only rebase). Sourced, not executed directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# The repo's checked-in default subnet prefix. Both provision-business.sh and
# set-subnet.sh rebase away from this fixed value — neither auto-detects the
# current subnet of an already-rebased copy.
readonly REPO_DEFAULT_SUBNET_PREFIX="10.10.10"

# copy_repo <src> <dst>
# Copies <src> into <dst>, excluding .git, PKI key material, and secrets.
copy_repo() {
  local src="$1" dst="$2"
  mkdir -p "${dst}"
  log "Copying repository (excluding .git, generated secrets, and any existing PKI/env material)"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude=.git \
      --exclude='pki/root-ca' --exclude='pki/intermediate-ca' --exclude='pki/issued' \
      --exclude='*.env' --exclude='**/.generated-secrets' \
      --exclude='ansible/inventory/host_vars/*/vault.yml' \
      "${src}/" "${dst}/"
  else
    warn "rsync not found — falling back to cp -a (Git for Windows' Git Bash doesn't bundle rsync by default; install it via MSYS2 or run this from WSL2/Linux for the cleaner path)"
    cp -a "${src}/." "${dst}/"
    rm -rf "${dst}/.git" \
      "${dst}/pki/root-ca" "${dst}/pki/intermediate-ca" "${dst}/pki/issued"
    find "${dst}" -name '*.env' -delete
    find "${dst}" -type d -name '.generated-secrets' -exec rm -rf {} +
    find "${dst}/ansible/inventory/host_vars" -mindepth 2 -name 'vault.yml' -delete 2>/dev/null || true
  fi
}

# validate_subnet <cidr>
# Validates <cidr> is an RFC1918 /24 (e.g. 10.20.30.0/24). Prints the
# validated prefix (e.g. "10.20.30") to stdout on success; dies on failure.
validate_subnet() {
  local subnet="$1"
  [[ "${subnet}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.0/24$ ]] \
    || die "subnet must be a /24 CIDR ending in .0/24, e.g. 10.20.0.0/24, got '${subnet}'"
  local prefix="${subnet%.0/24}"
  local o1 o2 o3
  IFS='.' read -r o1 o2 o3 <<< "${prefix}"
  case "${o1}" in
    10) : ;;
    172) [[ "${o2}" -ge 16 && "${o2}" -le 31 ]] || die "subnet 172.x.x.0/24 must have x in 16-31 (RFC1918)" ;;
    192) [[ "${o2}" -eq 168 ]] || die "subnet 192.x.x.0/24 must be 192.168.x.0/24 (RFC1918)" ;;
    *) die "subnet must be within RFC1918 private space (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)" ;;
  esac
  printf '%s\n' "${prefix}"
}

# rewrite_subnet <dir> <old_prefix> <new_prefix>
# Rewrites every occurrence of "<old_prefix>." to "<new_prefix>." across all
# text files under <dir>.
rewrite_subnet() {
  local dir="$1" old_prefix="$2" new_prefix="$3"
  local old_pattern="${old_prefix//./\\.}"
  local files
  files="$(grep -rlI "${old_pattern}\." "${dir}" 2>/dev/null || true)"
  local f
  for f in ${files}; do
    sed -i "s/${old_pattern}\./${new_prefix}./g" "${f}"
  done
}
```

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/lib/business-rebase.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manual sanity check of `validate_subnet`**

Run:
```bash
bash -c 'source scripts/lib/business-rebase.sh; validate_subnet "10.20.30.0/24"'
bash -c 'source scripts/lib/business-rebase.sh; validate_subnet "192.168.5.0/24"'
bash -c 'source scripts/lib/business-rebase.sh; validate_subnet "8.8.8.0/24"' ; echo "exit=$?"
bash -c 'source scripts/lib/business-rebase.sh; validate_subnet "not-a-subnet"' ; echo "exit=$?"
```
Expected: first prints `10.20.30`, second prints `192.168.5`, third and fourth print a `[lab][error]` message to stderr and exit non-zero (`die` calls `exit 1`).

- [ ] **Step 4: `chmod +x` and commit**

```bash
chmod +x scripts/lib/business-rebase.sh
git add scripts/lib/business-rebase.sh
git commit -m "$(cat <<'EOF'
Add scripts/lib/business-rebase.sh with shared copy/validate/rewrite helpers

Extracts the repo-copy and subnet-validate/rewrite logic that
provision-business.sh will be refactored to use, plus set-subnet.sh (next
commits). Sourced, not executed directly.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Refactor `scripts/provision-business.sh` to use the shared library (bug fix)

**Files:**
- Modify: `scripts/provision-business.sh:1-145` (full rewrite of the file, same external CLI/behavior)

**Interfaces:**
- Consumes: `REPO_DEFAULT_SUBNET_PREFIX`, `copy_repo()`, `validate_subnet()`, `rewrite_subnet()` from `scripts/lib/business-rebase.sh` (Task 1). `log()`/`warn()`/`die()` transitively via `common.sh`.
- Produces: no change to external behavior — same flags (`--name --domain --netbios --subnet --output --force --allow-local-tld`), same output messages, same generated files. The only observable change: the subnet in copied files is now actually rewritten (previously silently broken).

- [ ] **Step 1: Rewrite `scripts/provision-business.sh`**

```bash
#!/usr/bin/env bash
# Clones this repository into a new directory with its domain, realm, NetBIOS name, and
# subnet re-based to new values — i.e. it turns "the lab" into "a business". Used both to
# simply rename the single default lab, and to stamp out additional independent businesses
# for the multi-business federation model (see docs/MultiBusiness.md).
#
# Each output is a fully independent copy: its own PKI (regenerated from scratch — CA key
# material is gitignored so nothing is carried over), its own Ansible inventory, its own
# Docker stacks. Nothing here talks to another business until you explicitly bridge them via
# the federation/ tooling.
#
# If you only need a different subnet — no domain/NetBIOS rename — use the lighter-weight
# scripts/set-subnet.sh instead.
#
# Usage:
#   ./scripts/provision-business.sh --name businessb --domain businessb.internal \
#       --netbios BIZB --subnet 10.20.0.0/24 [--output ../businessb-lab] [--force]
#
# Constraints (validated below, with rationale):
#   --domain   Exactly two DNS labels (e.g. "acme.internal", "bizb.lan") — the repo's LDAP
#              DNs are generated as DC=<label1>,DC=<label2> and a 3+ label domain would need
#              a 3+ component DN throughout, which this sed-based rename doesn't attempt.
#              Refuses a ".local" TLD by default — see docs/Architecture.md#domain-and-subnet-naming.
#   --netbios  1-15 chars, uppercase letters/digits/hyphens (NetBIOS name limit).
#   --subnet   A /24 in RFC1918 space. If you intend to bridge two businesses over IPSec
#              (docs/MultiBusiness.md), their subnets MUST NOT overlap — this script warns
#              but does not track other businesses' subnets for you; keep a note of what
#              you've allocated (the federation registry in scripts/federation/ does this
#              once businesses are registered for peering).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/business-rebase.sh"

NAME=""
DOMAIN=""
NETBIOS=""
SUBNET=""
OUTPUT=""
FORCE=0
ALLOW_LOCAL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --netbios) NETBIOS="$2"; shift 2 ;;
    --subnet) SUBNET="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --allow-local-tld) ALLOW_LOCAL=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${NAME}" && -n "${DOMAIN}" && -n "${NETBIOS}" && -n "${SUBNET}" ]] || \
  die "Usage: $0 --name <business> --domain <two-label-domain> --netbios <NETBIOS> --subnet <a.b.c.0/24> [--output <dir>] [--force]"

# --- Validate domain: exactly two labels, not .local unless explicitly allowed ---
DOMAIN_LABEL_COUNT="$(awk -F. '{print NF}' <<< "${DOMAIN}")"
[[ "${DOMAIN_LABEL_COUNT}" -eq 2 ]] || die "--domain must have exactly two labels (e.g. acme.internal), got '${DOMAIN}' (${DOMAIN_LABEL_COUNT} labels). See the script header comment for why."
DOMAIN_LABEL1="${DOMAIN%%.*}"
DOMAIN_LABEL2="${DOMAIN#*.}"
if [[ "${DOMAIN_LABEL2}" == "local" && "${ALLOW_LOCAL}" -eq 0 ]]; then
  die "--domain ends in .local, which conflicts with mDNS (see docs/Architecture.md#domain-and-subnet-naming). Pass --allow-local-tld to override anyway."
fi
REALM="$(tr '[:lower:]' '[:upper:]' <<< "${DOMAIN}")"

# --- Validate NetBIOS: 1-15 chars, uppercase alnum/hyphen ---
[[ "${NETBIOS}" =~ ^[A-Z0-9-]{1,15}$ ]] || die "--netbios must be 1-15 uppercase letters/digits/hyphens, got '${NETBIOS}'"

# --- Validate subnet: RFC1918 /24 ---
SUBNET_PREFIX="$(validate_subnet "${SUBNET}")"
if [[ "${SUBNET_PREFIX}" == "${REPO_DEFAULT_SUBNET_PREFIX}" ]]; then
  warn "--subnet matches the base lab's default (${REPO_DEFAULT_SUBNET_PREFIX}.0/24). Fine for a standalone rename, but if this business will be IPSec-bridged to another running instance of the base lab, they'll collide — pick a distinct /24."
fi

OUTPUT="${OUTPUT:-${REPO_ROOT}/../${NAME}-lab}"
if [[ -e "${OUTPUT}" && "$(ls -A "${OUTPUT}" 2>/dev/null)" && "${FORCE}" -eq 0 ]]; then
  die "${OUTPUT} already exists and is non-empty — pass --force to overwrite, or choose a different --output."
fi

log "Provisioning '${NAME}': domain=${DOMAIN} realm=${REALM} netbios=${NETBIOS} subnet=${SUBNET} -> ${OUTPUT}"

copy_repo "${REPO_ROOT}" "${OUTPUT}"

log "Rewriting domain/realm references (lab.internal -> ${DOMAIN}, LAB.INTERNAL -> ${REALM})"
FILES="$(grep -rlI "lab\.internal\|LAB\.INTERNAL\|DC=lab,DC=internal\|\bLAB\b" "${OUTPUT}" 2>/dev/null || true)"
for f in ${FILES}; do
  sed -i \
    -e "s/lab\.internal/${DOMAIN}/g" \
    -e "s/LAB\.INTERNAL/${REALM}/g" \
    -e "s/DC=lab,DC=internal/DC=${DOMAIN_LABEL1},DC=${DOMAIN_LABEL2}/g" \
    -e "s/\bLAB\b/${NETBIOS}/g" \
    "${f}"
done

log "Rewriting subnet references (${REPO_DEFAULT_SUBNET_PREFIX}.0/24 -> ${SUBNET})"
rewrite_subnet "${OUTPUT}" "${REPO_DEFAULT_SUBNET_PREFIX}" "${SUBNET_PREFIX}"

log "Writing provenance banner into ${OUTPUT}/README.md"
{
  echo "> **Derived business instance.** Generated $(date -u +%FT%TZ) from"
  echo "> lab-small-business by \`scripts/provision-business.sh\` with:"
  echo "> domain=\`${DOMAIN}\`, realm=\`${REALM}\`, netbios=\`${NETBIOS}\`, subnet=\`${SUBNET}\`."
  echo "> This copy has its own PKI, secrets, and inventory — nothing is shared with the"
  echo "> source repo or any other business instance unless explicitly bridged. See"
  echo "> docs/MultiBusiness.md."
  echo ""
  cat "${OUTPUT}/README.md"
} > "${OUTPUT}/README.md.new"
mv "${OUTPUT}/README.md.new" "${OUTPUT}/README.md"

log "Done. ${OUTPUT} is a standalone lab instance for '${NAME}'."
log "Next steps:"
log "  cd ${OUTPUT}"
log "  git init && git add -A && git commit -m 'Initial provision: ${NAME}'   # optional, own history"
log "  make pki-init && make pki-issue-all   # this business needs its OWN CA, not a copy of anyone else's"
log "  make deploy"
log "To later bridge this business to another via IPSec/VPN, see docs/MultiBusiness.md and scripts/federation/."
```

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/provision-business.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manual dry run into a scratch directory**

```bash
rm -rf /tmp/provision-test && \
./scripts/provision-business.sh --name testbiz --domain testbiz.internal \
  --netbios TESTBIZ --subnet 10.50.60.0/24 --output /tmp/provision-test
grep -rl "10\.50\.60\." /tmp/provision-test | wc -l
grep -rl "10\.10\.10\." /tmp/provision-test | grep -v '\.git' | wc -l
```
Expected: the first `grep` count is > 0 (subnet rewrite fired — this is the bug fix verification: before this change, this count would have been 0 since the rewrite matched the stale `10.10.0.` pattern instead). The second count is 0 (no leftover default-subnet references in text files).

- [ ] **Step 4: Clean up scratch directory and commit**

```bash
rm -rf /tmp/provision-test
git add scripts/provision-business.sh
git commit -m "$(cat <<'EOF'
Refactor provision-business.sh onto scripts/lib/business-rebase.sh, fixing
the subnet-rewrite bug

The subnet grep/sed sweep hardcoded the stale 10.10.0. pattern from before
the repo's 2026-08-24 migration to 10.10.10.0/24, so it silently rewrote
nothing. Now sourced from the shared library (also used by the new
set-subnet.sh), which uses the correct current default.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `scripts/set-subnet.sh` — new subnet-only rebase tool

**Files:**
- Create: `scripts/set-subnet.sh`

**Interfaces:**
- Consumes: `REPO_DEFAULT_SUBNET_PREFIX`, `copy_repo()`, `validate_subnet()`, `rewrite_subnet()` from `scripts/lib/business-rebase.sh` (Task 1).
- Produces: a standalone CLI tool, `scripts/set-subnet.sh <new-subnet-cidr> [--output <dir>] [--force]` — no other task depends on calling this programmatically.

- [ ] **Step 1: Write `scripts/set-subnet.sh`**

```bash
#!/usr/bin/env bash
# Rebases this repo's subnet (only) onto a fresh copy — for anyone who wants a different
# subnet than the shipped 10.10.10.0/24 default without renaming domain/NetBIOS identity.
# For a full business rename (domain + netbios + subnet), see provision-business.sh instead.
#
# Usage:
#   ./scripts/set-subnet.sh 10.20.30.0/24 [--output ../lab-small-business-30] [--force]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/business-rebase.sh"

[[ $# -ge 1 ]] || die "Usage: $0 <new-subnet-cidr> [--output <dir>] [--force]"
SUBNET="$1"
shift

OUTPUT=""
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

NEW_PREFIX="$(validate_subnet "${SUBNET}")"

if [[ "${NEW_PREFIX}" == "${REPO_DEFAULT_SUBNET_PREFIX}" ]]; then
  die "subnet ${SUBNET} matches the repo's current default (${REPO_DEFAULT_SUBNET_PREFIX}.0/24) — nothing to do."
fi

LAST_OCTET="${NEW_PREFIX##*.}"
OUTPUT="${OUTPUT:-${REPO_ROOT}/../$(basename "${REPO_ROOT}")-${LAST_OCTET}}"
if [[ -e "${OUTPUT}" && "$(ls -A "${OUTPUT}" 2>/dev/null)" && "${FORCE}" -eq 0 ]]; then
  die "${OUTPUT} already exists and is non-empty — pass --force to overwrite, or choose a different --output."
fi

log "Rebasing subnet ${REPO_DEFAULT_SUBNET_PREFIX}.0/24 -> ${SUBNET} -> ${OUTPUT}"

copy_repo "${REPO_ROOT}" "${OUTPUT}"
rewrite_subnet "${OUTPUT}" "${REPO_DEFAULT_SUBNET_PREFIX}" "${NEW_PREFIX}"

log "Writing provenance banner into ${OUTPUT}/README.md"
{
  echo "> **Subnet-rebased instance.** Generated $(date -u +%FT%TZ) from"
  echo "> lab-small-business by \`scripts/set-subnet.sh\` with subnet=\`${SUBNET}\`"
  echo "> (was \`${REPO_DEFAULT_SUBNET_PREFIX}.0/24\`). Domain, realm, and NetBIOS name are"
  echo "> unchanged from the source repo — for a full business rename, see"
  echo "> \`scripts/provision-business.sh\` instead."
  echo ""
  cat "${OUTPUT}/README.md"
} > "${OUTPUT}/README.md.new"
mv "${OUTPUT}/README.md.new" "${OUTPUT}/README.md"

log "Done. ${OUTPUT} uses subnet ${SUBNET}."
log "Next steps:"
log "  cd ${OUTPUT}"
log "  Continue docs/DeploymentGuide.md from this copy."
```

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/set-subnet.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Manual dry run into a scratch directory, including default-output-path check**

```bash
rm -rf /tmp/set-subnet-test && \
./scripts/set-subnet.sh 10.20.30.0/24 --output /tmp/set-subnet-test
grep -rl "10\.20\.30\." /tmp/set-subnet-test | wc -l
grep -rl "10\.10\.10\." /tmp/set-subnet-test | grep -v '\.git' | wc -l
head -8 /tmp/set-subnet-test/README.md
```
Expected: first `grep` count > 0, second count is 0, and the `README.md` head shows the "Subnet-rebased instance." provenance banner.

Then verify the no-`--output` default path and the same-subnet guard:
```bash
rm -rf /tmp/set-subnet-test /tmp/lab-small-business-30 /tmp/lab-small-business 2>/dev/null || true
REPO_ROOT_FOR_TEST="$(pwd)"
cp -a "${REPO_ROOT_FOR_TEST}" /tmp/lab-small-business
cd /tmp/lab-small-business
./scripts/set-subnet.sh 10.20.30.0/24
ls -d /tmp/lab-small-business-30
cd "${REPO_ROOT_FOR_TEST}"
./scripts/set-subnet.sh 10.10.10.0/24 ; echo "exit=$?"
rm -rf /tmp/lab-small-business /tmp/lab-small-business-30
```
Expected: `/tmp/lab-small-business-30` exists after the first run (default-output-path derivation works); the second invocation (same subnet as current default) dies with a "nothing to do" message and non-zero exit.

- [ ] **Step 4: `chmod +x` and commit**

```bash
chmod +x scripts/set-subnet.sh
git add scripts/set-subnet.sh
git commit -m "$(cat <<'EOF'
Add scripts/set-subnet.sh for subnet-only repo rebases

Lets a user pick a different subnet than the shipped 10.10.10.0/24 default
without going through provision-business.sh's full domain/NetBIOS rename.
Built on scripts/lib/business-rebase.sh (previous commits).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Documentation integration

**Files:**
- Modify: `docs/DeploymentGuide.md` (add a subnet-choice bullet to section "## 0. Host prerequisites")
- Modify: `hypervisor/README.md` (add a one-line pointer)
- Modify: `docs/Architecture.md:22-25` (extend the existing `provision-business.sh` sentence to also mention `set-subnet.sh`)

**Interfaces:**
- Consumes: nothing (docs-only; references the CLI built in Task 3).
- Produces: nothing consumed by later tasks — this is the last task in the plan.

- [ ] **Step 1: Add a subnet-choice bullet to `docs/DeploymentGuide.md`'s "## 0. Host prerequisites"**

In [docs/DeploymentGuide.md](../../docs/DeploymentGuide.md), find the "## 0. Host prerequisites" section's bullet list (starts with "- VMware Workstation Pro installed..."). Add a new bullet immediately after the section heading, before the existing first bullet:

```markdown
- This lab defaults to the `10.10.10.0/24` subnet. If that collides with your home/office
  network, or you just want a different range, run `scripts/set-subnet.sh <new-cidr>` now
  (before building any VMs) and do the rest of this guide from the resulting copy — see the
  script's header comment for usage.
```

- [ ] **Step 2: Add a pointer to `hypervisor/README.md`**

In [hypervisor/README.md](../../hypervisor/README.md), after the "## Choosing a platform" table's introductory paragraph (the "The two VMware paths behave identically..." paragraph, ending "...before assuming it's a drop-in swap for either VMware path." at line 26), add:

```markdown

Whichever platform you pick, the lab's default subnet (`10.10.10.0/24`) is a suggested
starter, not a requirement — see `scripts/set-subnet.sh` in the repo root if you need a
different one before building VMs.
```

- [ ] **Step 3: Extend `docs/Architecture.md`'s domain/subnet section**

In [docs/Architecture.md](../../docs/Architecture.md), the sentence at lines 22-25 currently reads:

```markdown
Every hostname, DN, and cert SAN in this repository derives from
`lab_domain`/`lab_realm` (Ansible) or the equivalent shell variables (scripts), so the whole
tree can be re-based onto a different domain/realm/NetBIOS/subnet with
[`scripts/provision-business.sh`](../scripts/provision-business.sh) — see
[docs/MultiBusiness.md](MultiBusiness.md) for why you'd want more than one.
```

Replace it with:

```markdown
Every hostname, DN, and cert SAN in this repository derives from
`lab_domain`/`lab_realm` (Ansible) or the equivalent shell variables (scripts), so the whole
tree can be re-based onto a different domain/realm/NetBIOS/subnet with
[`scripts/provision-business.sh`](../scripts/provision-business.sh) — see
[docs/MultiBusiness.md](MultiBusiness.md) for why you'd want more than one. If you only need a
different subnet, [`scripts/set-subnet.sh`](../scripts/set-subnet.sh) does just that without
the domain/NetBIOS rename.
```

- [ ] **Step 4: Verify links and commit**

```bash
grep -n "set-subnet.sh" docs/DeploymentGuide.md hypervisor/README.md docs/Architecture.md
git add docs/DeploymentGuide.md hypervisor/README.md docs/Architecture.md
git commit -m "$(cat <<'EOF'
Document scripts/set-subnet.sh across the deployment flow

Points to the new subnet-only rebase tool from the deployment guide's
prerequisites step, the hypervisor platform-choice doc, and Architecture.md's
domain/subnet-naming section.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Full-repo syntax sweep

**Files:**
- None modified — verification only.

**Interfaces:**
- Consumes: all scripts touched in Tasks 1-3.
- Produces: nothing — this is the plan's final confirmation step.

- [ ] **Step 1: Run the repo-wide syntax sweep from `CLAUDE.md`**

Run:
```bash
for f in $(find . -name "*.sh" -not -path "./.git/*"); do bash -n "$f" || echo "FAILED: $f"; done
```
Expected: no `FAILED:` lines printed.

- [ ] **Step 2: Confirm executable bits on the two new scripts**

Run: `git ls-files -s scripts/lib/business-rebase.sh scripts/set-subnet.sh`
Expected: both show mode `100755`.
