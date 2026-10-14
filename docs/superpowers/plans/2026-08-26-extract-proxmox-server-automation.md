# Extract Proxmox into lab-scale-business Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `hypervisor/proxmox/` out of `lab-small-business` into a new, separate local repo `lab-scale-business`, with a README/ROADMAP framing it as the dedicated automation-first path, and remove every Proxmox reference from `lab-small-business`.

**Architecture:** Create `/home/andy/Development/lab-scale-business` as a fresh `git init` repo with `terraform/` (the moved, slightly re-pathed Terraform module) and `seeds/` (the 3 moved cloud-init seed examples), plus new `README.md`/`ROADMAP.md`/`.gitignore`. Back in `lab-small-business`, delete `hypervisor/proxmox/` and the now-fully-empty `hypervisor/vms/seeds/` tree, strip every "On Proxmox" aside from the 6 `hypervisor/vms/*.md` pages, convert `hypervisor/README.md`'s platform table to prose (one platform left), and remove Proxmox mentions from 6 other files.

**Tech Stack:** Terraform (HCL) + Markdown. No Ansible/shell/compose changes.

**Spec:** [docs/superpowers/specs/2026-08-26-extract-proxmox-server-automation-design.md](../specs/2026-08-26-extract-proxmox-server-automation-design.md)

## Global Constraints

- The new repo is `git init`-ed locally only — no `gh repo create`, no `git push`, no remote added. Publishing is the user's decision.
- No functional change to any Terraform resource. The only edits to `.tf` files are: one path (`vms.tf`'s cloud-init snippet source, `../vms/seeds/` → `../seeds/`) and comments that referenced now-nonexistent files.
- `lab-small-business`'s `hypervisor/desktop/` path (sub-project A) is untouched beyond `hypervisor/README.md`'s table/prose conversion.
- New repo content is written now; publishing/pushing it is out of scope for this plan.

---

### Task 1: Scaffold the `lab-scale-business` repo and move Terraform + seeds

**Files (in the new repo, `/home/andy/Development/lab-scale-business/`):**
- Create: `terraform/main.tf` (copied verbatim from `hypervisor/proxmox/main.tf`)
- Create: `terraform/terraform.tfvars.example` (copied verbatim from `hypervisor/proxmox/terraform.tfvars.example`)
- Create: `terraform/variables.tf` (adapted — 2 comments re-pathed)
- Create: `terraform/vms.tf` (adapted — 1 path fixed, comments re-pathed)
- Create: `seeds/samba-dc01/proxmox-user-data.example`, `seeds/docker01/proxmox-user-data.example`, `seeds/authentik01/proxmox-user-data.example` (copied verbatim)
- Create: `.gitignore`

**Interfaces:** None — this task only touches the new repo, which nothing else in `lab-small-business` depends on.

- [ ] **Step 1: Create the directory structure and `git init`**

```bash
mkdir -p /home/andy/Development/lab-scale-business/terraform
mkdir -p /home/andy/Development/lab-scale-business/seeds/samba-dc01
mkdir -p /home/andy/Development/lab-scale-business/seeds/docker01
mkdir -p /home/andy/Development/lab-scale-business/seeds/authentik01
cd /home/andy/Development/lab-scale-business
git init
```

- [ ] **Step 2: Copy the two unchanged Terraform files and the three seed examples verbatim**

```bash
cd /home/andy/Development/lab-small-business
cp hypervisor/proxmox/main.tf /home/andy/Development/lab-scale-business/terraform/main.tf
cp hypervisor/proxmox/terraform.tfvars.example /home/andy/Development/lab-scale-business/terraform/terraform.tfvars.example
cp hypervisor/vms/seeds/samba-dc01/proxmox-user-data.example /home/andy/Development/lab-scale-business/seeds/samba-dc01/proxmox-user-data.example
cp hypervisor/vms/seeds/docker01/proxmox-user-data.example /home/andy/Development/lab-scale-business/seeds/docker01/proxmox-user-data.example
cp hypervisor/vms/seeds/authentik01/proxmox-user-data.example /home/andy/Development/lab-scale-business/seeds/authentik01/proxmox-user-data.example
```

- [ ] **Step 3: Write `terraform/variables.tf` (2 comments re-pathed, otherwise identical)**

```hcl
variable "proxmox_api_url" {
  description = "Proxmox API endpoint, e.g. https://pve.lab.internal:8006/api2/json"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in 'user@realm!token-id=uuid' form"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Target Proxmox node name"
  type        = string
  default     = "pve"
}

variable "storage_pool" {
  description = "Datastore ID for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "image_datastore" {
  description = "Datastore ID for the imported Ubuntu cloud image and cloud-init snippet files (must have both the 'Disk image' and 'Snippets' content types enabled — see README.md)"
  type        = string
  default     = "local"
}

variable "lan_bridge" {
  description = "Linux bridge every automatable VM's NIC attaches to — a bridge with no physical port and no IP configuration, created once from the Proxmox web UI (Datacenter > node > System > Network > Create: Linux Bridge). See README.md's networking prerequisites."
  type        = string
  default     = "vmbr-lan"
}

variable "cloud_image_path" {
  description = "Local path to the downloaded Ubuntu 24.04 Server cloud image (see README.md's prerequisites)"
  type        = string
  default     = "~/isos/noble-server-cloudimg-amd64.img"
}
```

Save to `/home/andy/Development/lab-scale-business/terraform/variables.tf`.

- [ ] **Step 4: Write `terraform/vms.tf` (path fixed, comments re-pathed, resources unchanged)**

```hcl
# name -> vcpu/ram/disk/ip/dns for the 3 VMs this module automates. win-client01, pfsense01, and
# linux-client01 are built by hand through the Proxmox web console instead — see README.md.
locals {
  linux_vms = {
    samba-dc01  = { vcpu = 2, ram_mb = 4096, disk_gb = 40, ip = "10.10.10.10", dns = "127.0.0.1" }
    docker01    = { vcpu = 4, ram_mb = 8192, disk_gb = 80, ip = "10.10.10.20", dns = "10.10.10.10" }
    authentik01 = { vcpu = 2, ram_mb = 4096, disk_gb = 40, ip = "10.10.10.30", dns = "10.10.10.10" }
  }
}

# Imported once, then cloned into each VM's disk below via import_from. Download the image
# yourself first (see README.md) — Terraform only imports the local file, it doesn't fetch it
# from the internet.
resource "proxmox_virtual_environment_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node

  source_file {
    path = var.cloud_image_path
  }
}

# Each VM's cloud-init user-data, uploaded as a snippet. Built from
# seeds/<name>/proxmox-user-data (the real, gitignored, filled-in copy of
# proxmox-user-data.example) — Terraform only uploads the file, it doesn't fill in placeholders;
# fill them in by hand before running `terraform apply` (README.md covers this).
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  for_each     = local.linux_vms
  content_type = "snippets"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node

  source_file {
    path = "${path.module}/../seeds/${each.key}/proxmox-user-data"
  }
}

resource "proxmox_virtual_environment_vm" "linux" {
  for_each  = local.linux_vms
  name      = each.key
  node_name = var.proxmox_node

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.vcpu
  }

  memory {
    dedicated = each.value.ram_mb
  }

  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    import_from  = proxmox_virtual_environment_file.ubuntu_cloud_image.id
    size         = each.value.disk_gb
    file_format  = "raw"
  }

  network_device {
    bridge = var.lan_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id      = var.storage_pool
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data[each.key].id

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "10.10.10.1"
      }
    }

    dns {
      servers = [each.value.dns]
    }
  }
}
```

Save to `/home/andy/Development/lab-scale-business/terraform/vms.tf`.

- [ ] **Step 5: Write `.gitignore`**

```gitignore
# --- Terraform ---
**/.terraform/
**/*.tfstate
**/*.tfstate.backup
**/*.tfvars
!**/*.tfvars.example

# --- Cloud-init seed data (real secrets you fill in — .example files are safe to commit) ---
seeds/**/proxmox-user-data
```

Save to `/home/andy/Development/lab-scale-business/.gitignore`.

- [ ] **Step 6: Verify the copied files are byte-identical to their source, and the new files are valid**

```bash
diff hypervisor/proxmox/main.tf /home/andy/Development/lab-scale-business/terraform/main.tf
diff hypervisor/proxmox/terraform.tfvars.example /home/andy/Development/lab-scale-business/terraform/terraform.tfvars.example
diff hypervisor/vms/seeds/samba-dc01/proxmox-user-data.example /home/andy/Development/lab-scale-business/seeds/samba-dc01/proxmox-user-data.example
diff hypervisor/vms/seeds/docker01/proxmox-user-data.example /home/andy/Development/lab-scale-business/seeds/docker01/proxmox-user-data.example
diff hypervisor/vms/seeds/authentik01/proxmox-user-data.example /home/andy/Development/lab-scale-business/seeds/authentik01/proxmox-user-data.example
```
Expected: no output from any `diff` (files identical).

```bash
cd /home/andy/Development/lab-scale-business/terraform
terraform fmt -check -diff || echo "terraform not installed or formatting differs — review manually"
```
Expected: `terraform fmt -check` passes, or (if Terraform isn't installed in this environment) a manual read confirming valid HCL syntax in `variables.tf` and `vms.tf`.

---

### Task 2: Write the new repo's `README.md` and `ROADMAP.md`, commit

**Files (in `/home/andy/Development/lab-scale-business/`):**
- Create: `README.md`
- Create: `ROADMAP.md`

**Interfaces:** None.

- [ ] **Step 1: Write `README.md`**

```markdown
# lab-scale-business

Terraform-driven, automated provisioning for a small-business IT environment on Proxmox VE:
Active Directory, PKI, SSO, and a Docker application platform — the same environment
[`lab-small-business`](https://github.com/LibreOpsLab/lab-small-business) teaches hands-on,
built here for people who want it running with as few manual steps as possible instead.

**Current scope**: `terraform apply` provisions 3 of the environment's 6 VMs (`samba-dc01`,
`docker01`, `authentik01`) — Ubuntu Server cloud images, cloud-init configured, zero interactive
install steps. `pfsense01`, `linux-client01`, and `win-client01` are still built by hand (see
"What's still manual" below); the app layer (Samba AD, PKI, Docker Compose stacks, Authentik) is
not yet automated — see [ROADMAP.md](ROADMAP.md) for what that looks like and why it isn't built
yet.

This project started as `lab-small-business`'s `hypervisor/proxmox/` directory, extracted here
because that repo deliberately moved to a guided, hands-on build process for its default
(VMware/Fusion) path — the two are different products for different audiences now, not two
options inside one repo.

## Why cloud image + native cloud-init, not an ISO installer

`bpg/terraform-provider-proxmox`'s VM resource only supports one `cdrom` block per VM.
Ubuntu Server's ISO-installer autoinstall needs a *second*, separately-attached CD-ROM for its
seed — not expressible through this provider. So these three VMs use the standard, well-
documented Proxmox+Terraform pattern instead: import an Ubuntu cloud image once, clone it per
VM, and let Proxmox's native cloud-init configure hostname/user/SSH at first boot.

## Prerequisites

1. **Terraform** `>= 1.6.0` on whatever machine you run `terraform apply` from.
2. **A Proxmox API token.** Datacenter > Permissions > API Tokens > Add, for a user with at
   least `VM.Allocate`, `VM.Config.*`, `VM.PowerMgmt`, `Datastore.AllocateSpace`, and
   `Datastore.AllocateTemplate` on the target node/storage. Copy the token into
   `terraform.tfvars`'s `proxmox_api_token` (never commit that file — it's gitignored, only
   `terraform.tfvars.example` is tracked).
3. **A trusted certificate on Proxmox's web UI.** This module never sets `insecure = true` (see
   `terraform/main.tf`'s comment) — issue Proxmox's certificate from a real CA (or your own
   internal PKI, if you're pairing this with a `lab-small-business`-style environment) and
   install that CA on the machine running `terraform apply`, or explicitly trust Proxmox's
   self-signed certificate the same way. Skipping TLS verification is not an option this project
   takes for any connection to itself.
4. **The Ubuntu 24.04 Server cloud image**, downloaded to wherever `terraform.tfvars`'s
   `cloud_image_path` points:
   ```bash
   curl -fLO https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
   ```
5. **Each of the three VMs' seed file filled in:**
   ```bash
   cp seeds/samba-dc01/proxmox-user-data.example seeds/samba-dc01/proxmox-user-data
   cp seeds/docker01/proxmox-user-data.example seeds/docker01/proxmox-user-data
   cp seeds/authentik01/proxmox-user-data.example seeds/authentik01/proxmox-user-data
   mkpasswd --method=sha-512   # paste the output into each file's passwd field
   ```
   The real files (no `.example` suffix) are gitignored — they'll contain your actual password
   hash, which is not something to commit.
6. **WAN networking for `pfsense01`** (built by hand, but needs a bridge to exist first) — pick
   one:
   - **Dedicated bridged physical NIC** (recommended): a second physical (or USB) NIC on the
     Proxmox host, bridged as `vmbr-wan`, closest to a real deployment. Datacenter > *node* >
     System > Network > Create: Linux Bridge, bridge port = the spare NIC, no IP configuration
     (pfSense will DHCP-client on it).
   - **Proxmox SDN NAT zone**: no spare NIC needed. Datacenter > SDN > Zones > Create: Simple,
     then a matching VNet — see Proxmox's own SDN documentation for the exact steps, since this
     varies more by PVE version than a bridge does.
   - Either way, also create `vmbr-lan` (Linux Bridge, no physical port, no IP — an isolated
     internal bridge) for every other VM's NIC.

## Bring-up

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: proxmox_api_url, proxmox_api_token, and any values that differ from
# your Proxmox host's actual node/storage/bridge names
terraform init
terraform plan
terraform apply
```

`terraform apply` creates all three VMs; each boots the cloned cloud image and configures itself
via cloud-init within a minute or two. Confirm with `ssh labadmin@10.10.10.10` (etc.) once
cloud-init finishes.

## What's still manual

- **`pfsense01`** (perimeter firewall/DHCP/DNS, 2 vCPU/2048 MB RAM/20 GB disk) — no unattended
  pfSense installer exists on any platform. Create the VM through the Proxmox web console
  (Datacenter > *node* > Create VM), pfSense CE ISO attached, NIC 1 on `vmbr-wan`, NIC 2 on
  `vmbr-lan`, then install interactively.
- **`linux-client01`** (admin/control desktop, 2 vCPU/4096 MB RAM/40 GB disk, DHCP) — desktop
  installs are hands-on by design; Ubuntu Desktop ISO, single NIC on `vmbr-lan`, install
  interactively.
- **`win-client01`** (Windows 11 desktop, 2 vCPU/4096 MB RAM/60 GB disk, DHCP) — no Windows
  equivalent to the cloud-image/cloud-init mechanism the 3 Linux VMs use, and the same single-
  `cdrom`-block provider limitation blocks an ISO+answer-file approach too. Windows 11 ISO,
  single NIC on `vmbr-lan`, install interactively (note Windows 11 Setup's UEFI/Secure Boot/vTPM
  2.0 requirement — set these under the VM's hardware options before booting).

`lab-small-business`'s `hypervisor/vms/{pfsense,linux-client,windows-client}.md` document the
same three builds in full teaching depth, if you want the click-by-click version.

See [ROADMAP.md](ROADMAP.md) for what's planned to close these gaps and automate the app layer.
```

- [ ] **Step 2: Write `ROADMAP.md`**

```markdown
# Roadmap

This project currently automates VM *provisioning* for 3 of 6 VMs (see `README.md`). The
longer-term goal — "build a small-business IT environment in a box" — needs more than that.
None of what follows is built yet; this is a plan, not a status report.

## Full app-layer automation

`terraform apply` should be able to lead all the way to a running environment — AD provisioned,
PKI issued and trusted, Docker apps up, Authentik configured — with no manual steps in between.
The building blocks mostly exist already, in `lab-small-business`'s `ansible/` tree
(`docker_engine`, `common`, `fail2ban`, `pki_trust`, `sssd_client` roles), and could be vendored
or referenced here, triggered automatically after `terraform apply` finishes (e.g. via a
`local-exec` provisioner, or a wrapper script that waits for cloud-init to finish then invokes
Ansible directly).

Samba AD provisioning specifically needs its own automation here — `lab-small-business`
deliberately removed its Ansible-driven AD role as redundant with that repo's guided manual
build (see its `docs/superpowers/specs/2026-08-26-app-layer-guided-stages-design.md`), but
there's no manual path in *this* project to be redundant with, so re-introducing that automation
(or writing a fresh equivalent) is in scope here.

## ESXi support

A second automated platform, alongside Proxmox — likely via `terraform-provider-vsphere` (see
`lab-small-business`'s `hypervisor/README.md`'s historical note on why VMware Workstation itself
never got a Terraform module: the community `terraform-provider-vmworkstation` is unmaintained,
but vSphere/ESXi has first-class, actively-maintained provider support). Scope and design not
yet started.

## `win-client01` automation

Blocked on the same root cause on both current/future platforms: no Terraform-expressible way to
feed Windows Setup an unattended-install answer file without a second CD-ROM device, which
neither `bpg/terraform-provider-proxmox` nor (likely) `terraform-provider-vsphere` support. Worth
revisiting if either provider adds multi-CD-ROM support, or if a non-ISO Windows provisioning
path (e.g. a pre-built, sysprepped template) fits this project's goals.
```

- [ ] **Step 3: Commit the new repo's initial content**

```bash
cd /home/andy/Development/lab-scale-business
git add -A
git status --short
git commit -m "$(cat <<'EOF'
Initial commit: Terraform module extracted from lab-small-business

Provisions samba-dc01/docker01/authentik01 on Proxmox VE via cloud image +
native cloud-init. pfSense, linux-client01, and win-client01 are still
built by hand (see README.md). Full app-layer automation and ESXi support
are documented in ROADMAP.md as future work, not yet built.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
git log --oneline
```

---

### Task 3: Delete Proxmox from `lab-small-business`

**Files:**
- Delete: `hypervisor/proxmox/` (all 5 files)
- Delete: `hypervisor/vms/seeds/` (entire tree — `samba-dc01/`, `docker01/`, `authentik01/`, `win-client01/`)
- Modify: `.gitignore`

**Interfaces:** None — Task 4's edits to `hypervisor/vms/*.md` don't depend on this deletion having happened first, but doing it first makes Task 4's "no remaining reference" checks meaningful.

- [ ] **Step 1: Delete the directories**

```bash
cd /home/andy/Development/lab-small-business
rm -rf hypervisor/proxmox
rm -rf hypervisor/vms/seeds
```

- [ ] **Step 2: Remove the now-dead "Unattended-install seed data" block from `.gitignore`**

Find:
```
# --- Unattended-install seed data (real secrets students fill in — .example files are
# --- safe to commit, the filled copies are not) ---
hypervisor/vms/seeds/**/user-data
hypervisor/vms/seeds/**/meta-data
hypervisor/vms/seeds/**/autounattend.xml
hypervisor/vms/seeds/**/proxmox-user-data
hypervisor/vms/**/*-seed.iso
```

Replace with nothing (delete the block entirely, including its blank line before the next
section) — `hypervisor/vms/seeds/` no longer exists, and the `*-seed.iso` pattern was for
`build-seed-iso.ps1`/`.sh` output, both already removed in sub-project A.

- [ ] **Step 3: Verify**

```bash
ls hypervisor/proxmox 2>&1
ls hypervisor/vms/seeds 2>&1
grep -n "seeds\|proxmox" .gitignore
```
Expected: both `ls` calls report "No such file or directory"; the `grep` finds nothing.

- [ ] **Step 4: Commit**

```bash
git add -A hypervisor/proxmox hypervisor/vms/seeds .gitignore
git status --short
git commit -m "$(cat <<'EOF'
Remove hypervisor/proxmox/ — extracted to the new lab-scale-business repo

Also removes hypervisor/vms/seeds/ (now fully empty — its VMware-side files
were already removed in sub-project A) and the matching dead .gitignore
patterns.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Remove "On Proxmox" asides from the 6 `hypervisor/vms/*.md` pages

**Files:**
- Modify: `hypervisor/vms/pfsense.md`
- Modify: `hypervisor/vms/linux-client.md`
- Modify: `hypervisor/vms/samba-dc.md`
- Modify: `hypervisor/vms/docker-server.md`
- Modify: `hypervisor/vms/authentik.md`
- Modify: `hypervisor/vms/windows-client.md`

**Interfaces:** None.

- [ ] **Step 1: `hypervisor/vms/pfsense.md`**

Find:
```markdown
### On Proxmox

The VMware-GUI steps above don't apply — create the VM through the Proxmox web console instead:
**Datacenter > *node* > Create VM**, same specs (2 vCPU, 2048 MB RAM, 20 GB disk), pfSense CE
ISO attached. NIC 1 on `vmbr-wan`, NIC 2 on `vmbr-lan` — both bridges are prerequisites you
create once, per [`../proxmox/README.md`](../proxmox/README.md)'s WAN-networking section, before
building this VM. Everything from "## Install" onward is identical regardless of hypervisor.
```

Replace with nothing (delete the section and the blank line before it).

- [ ] **Step 2: `hypervisor/vms/linux-client.md`**

Find:
```markdown
**On Proxmox**, create the VM through the Proxmox web console instead of the VMware GUI in step
1 above — same specs, single NIC on `vmbr-lan` (created once per
[`../proxmox/README.md`](../proxmox/README.md), not per VM). Step 2 is identical regardless of
hypervisor.
```

Replace with nothing (delete the paragraph and the blank line before it).

- [ ] **Step 3: `hypervisor/vms/samba-dc.md`**

Find:
```markdown
**On Proxmox**, this VM boots a cloud image instead and is configured by
[`seeds/samba-dc01/proxmox-user-data.example`](seeds/samba-dc01/proxmox-user-data.example). See
[`../proxmox/README.md`](../proxmox/README.md) for why the mechanism differs and what to fill in
before `terraform apply`.
```

Replace with nothing (delete the paragraph and the blank line before it).

- [ ] **Step 4: `hypervisor/vms/docker-server.md`**

Find:
```markdown
**On Proxmox**, this VM boots a cloud image instead and is configured by
[`seeds/docker01/proxmox-user-data.example`](seeds/docker01/proxmox-user-data.example). See
[`../proxmox/README.md`](../proxmox/README.md) for why the mechanism differs and what to fill in
before `terraform apply`.
```

Replace with nothing (delete the paragraph and the blank line before it).

- [ ] **Step 5: `hypervisor/vms/authentik.md`**

Find:
```markdown
**On Proxmox**, this VM boots a cloud image instead and is configured by
[`seeds/authentik01/proxmox-user-data.example`](seeds/authentik01/proxmox-user-data.example).
See [`../proxmox/README.md`](../proxmox/README.md) for why the mechanism differs and what to
fill in before `terraform apply`.
```

Replace with nothing (delete the paragraph and the blank line before it).

- [ ] **Step 6: `hypervisor/vms/windows-client.md`**

Find:
```markdown
**On Proxmox**, build through the Proxmox web console instead of the VMware GUI — same specs,
`vmbr-lan` NIC, `Win11.iso` attached. See [`../proxmox/README.md`](../proxmox/README.md). Install
and baseline steps above are identical regardless of hypervisor.
```

Replace with nothing (delete the paragraph and the blank line before it).

- [ ] **Step 7: Verify each file still reads coherently and no Proxmox references remain**

```bash
grep -n "Proxmox\|proxmox" hypervisor/vms/*.md
```
Expected: no output.

```bash
for f in hypervisor/vms/pfsense.md hypervisor/vms/linux-client.md hypervisor/vms/samba-dc.md \
         hypervisor/vms/docker-server.md hypervisor/vms/authentik.md hypervisor/vms/windows-client.md; do
  echo "=== $f ==="; tail -8 "$f"; echo
done
```
Read the output and confirm each file ends cleanly (no orphaned heading, no double-blank-line
artifact from the deletion) leading into its "## Post-install" section.

- [ ] **Step 8: Commit**

```bash
git add hypervisor/vms/pfsense.md hypervisor/vms/linux-client.md hypervisor/vms/samba-dc.md \
        hypervisor/vms/docker-server.md hypervisor/vms/authentik.md hypervisor/vms/windows-client.md
git commit -m "$(cat <<'EOF'
Remove "On Proxmox" asides from the 6 VM pages

Each page is now VMware/Fusion-only, matching hypervisor/proxmox/'s removal
in the previous commit.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Rewrite `hypervisor/README.md`'s platform section as prose

**Files:**
- Modify: `hypervisor/README.md`

**Interfaces:** None.

- [ ] **Step 1: Replace the "Choosing a platform" table and its surrounding paragraphs**

Find:
```markdown
## Choosing a platform

| Platform                                | Directory              | Host OS                       | Automation                                |
| --------------------------------------- | ---------------------- | ------------------------------ | ----------------------------------------- |
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
```

Replace with:
```markdown
## The platform

VMware Workstation Pro (Windows/Linux) or Fusion Pro (macOS) — see [`desktop/`](desktop/).
Every VM is hand-built through the hypervisor's own GUI: New VM wizard, interactive OS install,
then a shared post-install baseline (patch, VM tools, locale, SSH keys). This is deliberate:
building each VM by hand is where the actual learning happens in a teaching lab like this one —
see ["Why hand-built, not scripted?"](#why-hand-built-not-scripted) below.

The lab's default subnet (`10.10.10.0/24`) is a suggested starter, not a requirement — see
`scripts/set-subnet.sh` in the repo root if you need a different one before building VMs.
```

- [ ] **Step 2: Update the "Why hand-built, not scripted?" section's closing sentence**

Find:
```markdown
Earlier versions of this repo drove VM creation on the desktop path with a `vmrun`-scripted
helper (PowerShell on Windows, Bash on Linux). That automation is gone by design: in a teaching
lab, watching a script create a VM teaches nothing, while clicking through the New VM wizard
yourself — and understanding why each setting is what it is — is the point. If you want the
"spin up a whole environment in a box" automated experience instead, that's what the Proxmox
path is for.
```

Replace with:
```markdown
Earlier versions of this repo drove VM creation on the desktop path with a `vmrun`-scripted
helper (PowerShell on Windows, Bash on Linux). That automation is gone by design: in a teaching
lab, watching a script create a VM teaches nothing, while clicking through the New VM wizard
yourself — and understanding why each setting is what it is — is the point. If you want the
"spin up a whole environment in a box" automated experience instead, that's a separate project,
`lab-scale-business` — a Terraform-driven take on this same environment, deliberately kept out
of this repo so the two don't get tangled together.
```

- [ ] **Step 3: Verify**

```bash
grep -n "Proxmox\|proxmox" hypervisor/README.md
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add hypervisor/README.md
git commit -m "$(cat <<'EOF'
Convert hypervisor/README.md's platform table to prose

With Proxmox extracted, a "choosing a platform" comparison table has
nothing left to compare - describes the one remaining desktop path
directly instead, and points to lab-scale-business (by name, not yet
published) for anyone who wants the automated alternative.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Remove `hypervisor/networks/README.md`'s "Proxmox equivalent" section, and remaining small edits

**Files:**
- Modify: `hypervisor/networks/README.md`
- Modify: `docs/DeploymentGuide.md`
- Modify: `docs/Architecture.md`
- Modify: `README.md`
- Modify: `pfsense/README.md`
- Modify: `CLAUDE.md`

**Interfaces:** None.

- [ ] **Step 1: `hypervisor/networks/README.md`**

Find:
```markdown

## Proxmox equivalent

Proxmox has no LAN Segment concept — the equivalent is a Linux bridge with no physical port and
no IP configuration, created once from the Proxmox web UI (Datacenter > *node* > System >
Network > Create: Linux Bridge) and named `vmbr-lan`. Every automatable VM's `network_device`
block in `../proxmox/vms.tf` attaches to it by default (the `lan_bridge` variable). pfSense's
WAN leg needs a second bridge, `vmbr-wan` — see [`../proxmox/README.md`](../proxmox/README.md)'s
prerequisites for the two ways to wire that one up (dedicated physical NIC vs. Proxmox's SDN NAT
zone), since unlike VMware's `VMnet8`, Proxmox has no built-in NAT-with-DHCP network to fall
back on.
```

Replace with nothing (delete the section, including its leading blank line, so the file ends
after the `vnetlib` historical note).

- [ ] **Step 2: `docs/DeploymentGuide.md`**

Find:
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

Replace with:
```markdown
Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro (Windows/Linux) or Fusion Pro (macOS) and Ubuntu
Server 24.04 LTS for all Linux VMs. Every VM is hand-built through the hypervisor's own GUI —
see [hypervisor/desktop/README.md](../hypervisor/desktop/README.md).
```

- [ ] **Step 3: `docs/Architecture.md`**

Find:
```markdown
This repository defines a self-contained, IaC-driven homelab that simulates a small
organisation's IT estate: perimeter firewall, Active Directory, identity federation, a Docker
application platform, and both Windows and Linux endpoints. It exists to teach realistic
sysadmin/DevOps workflows — domain administration, PKI, IAM/SSO, reverse proxying,
containerised applications — end to end, on a single VMware Workstation host or a Proxmox VE
node — see [hypervisor/README.md](../hypervisor/README.md) for the trade-offs between them.
```

Replace with:
```markdown
This repository defines a self-contained, IaC-driven homelab that simulates a small
organisation's IT estate: perimeter firewall, Active Directory, identity federation, a Docker
application platform, and both Windows and Linux endpoints. It exists to teach realistic
sysadmin/DevOps workflows — domain administration, PKI, IAM/SSO, reverse proxying,
containerised applications — end to end, on a single VMware Workstation/Fusion Pro host — see
[hypervisor/README.md](../hypervisor/README.md).
```

Find:
```markdown
├── hypervisor/      VM inventory, network config, provisioning notes (VMware Workstation or Proxmox VE)
```

Replace with:
```markdown
├── hypervisor/      VM inventory, network config, provisioning notes (VMware Workstation/Fusion Pro)
```

- [ ] **Step 4: `README.md`**

Find:
```markdown
├── hypervisor/      VM inventory, network config, provisioning notes (VMware Workstation or Proxmox VE)
```

Replace with:
```markdown
├── hypervisor/      VM inventory, network config, provisioning notes (VMware Workstation/Fusion Pro)
```

Find:
```markdown
# 2. Remaining VMs — same hypervisor GUI, hand-built, one per hypervisor/vms/*.md:
#    samba-dc01, docker01, authentik01, win-client01. Apply hypervisor/desktop/baseline.md
#    (patch, VM tools, locale, SSH keys) to each after its OS install.
#    ...or Proxmox VE instead (see hypervisor/proxmox/README.md — automates 3 of the 4 VMs):
cd hypervisor/proxmox && terraform apply
```

Replace with:
```markdown
# 2. Remaining VMs — same hypervisor GUI, hand-built, one per hypervisor/vms/*.md:
#    samba-dc01, docker01, authentik01, win-client01. Apply hypervisor/desktop/baseline.md
#    (patch, VM tools, locale, SSH keys) to each after its OS install.
```

- [ ] **Step 5: `pfsense/README.md`**

Find:
```markdown
**The files below are an optional shortcut, not the default first-run path.**
[`docs/DeploymentGuide.md`](../docs/DeploymentGuide.md#1-pfsense--fully-manual) and
[`hypervisor/vms/pfsense.md`](../hypervisor/vms/pfsense.md) walk through configuring pfSense
entirely by hand — start there (that page covers both the VMware and Proxmox build steps; only
the DHCP/DNS/firewall configuration below is hypervisor-agnostic). Come back to
`config.xml.template` once you're comfortable with the manual flow and want a reviewed, reusable
baseline for future rebuilds.
```

Replace with:
```markdown
**The files below are an optional shortcut, not the default first-run path.**
[`docs/DeploymentGuide.md`](../docs/DeploymentGuide.md#1-pfsense--fully-manual) and
[`hypervisor/vms/pfsense.md`](../hypervisor/vms/pfsense.md) walk through configuring pfSense
entirely by hand — start there. Come back to `config.xml.template` once you're comfortable with
the manual flow and want a reviewed, reusable baseline for future rebuilds.
```

- [ ] **Step 6: `CLAUDE.md`**

Find:
```markdown
A self-contained, IaC-driven homelab simulating a small organisation's IT estate on VMware
Workstation (Windows or Linux) or Proxmox VE — see
[hypervisor/README.md](hypervisor/README.md) for the trade-offs between them: pfSense, Samba
AD, an internal PKI, Authentik SSO, a Docker application platform, and Windows/Linux endpoints.
```

Replace with:
```markdown
A self-contained, IaC-driven homelab simulating a small organisation's IT estate on VMware
Workstation Pro (Windows/Linux) or Fusion Pro (macOS) — see
[hypervisor/README.md](hypervisor/README.md). Covers pfSense, Samba AD, an internal PKI,
Authentik SSO, a Docker application platform, and Windows/Linux endpoints.
```

- [ ] **Step 7: Verify no Proxmox references remain anywhere live**

```bash
grep -rln "proxmox\|Proxmox\|PVE\b" --include="*.md" --include="*.sh" --include="*.ps1" --include="*.yml" --include="*.tf" . 2>/dev/null | grep -v '^\./docs/superpowers/\|^docs/superpowers/'
```
Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add hypervisor/networks/README.md docs/DeploymentGuide.md docs/Architecture.md README.md \
        pfsense/README.md CLAUDE.md
git commit -m "$(cat <<'EOF'
Remove remaining Proxmox mentions across the doc set

hypervisor/networks/README.md's "Proxmox equivalent" section, and one
sentence/line each in DeploymentGuide.md, Architecture.md, README.md,
pfsense/README.md, and CLAUDE.md.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Repo-wide verification sweep

**Files:** None modified — verification only.

**Interfaces:**
- Consumes: every file touched in Tasks 3-6, and the new repo from Tasks 1-2.
- Produces: nothing — this is the plan's final confirmation step.

- [ ] **Step 1: Confirm zero live Proxmox references in `lab-small-business`**

```bash
cd /home/andy/Development/lab-small-business
grep -rln "proxmox\|Proxmox\|PVE\b" . 2>/dev/null | grep -v '^\./\.git/\|^\./docs/superpowers/\|^docs/superpowers/'
```
Expected: no output.

- [ ] **Step 2: Confirm the new repo is self-contained and committed**

```bash
cd /home/andy/Development/lab-scale-business
git log --oneline
git status --short
find . -type f -not -path './.git/*' | sort
```
Expected: one commit, clean working tree, and the file list matches Task 1/2's Create list
(`.gitignore`, `README.md`, `ROADMAP.md`, `terraform/{main.tf,variables.tf,vms.tf,
terraform.tfvars.example}`, `seeds/{samba-dc01,docker01,authentik01}/proxmox-user-data.example`).

- [ ] **Step 3: Full-repo shell syntax sweep on `lab-small-business` (confirms deletions didn't break anything)**

```bash
cd /home/andy/Development/lab-small-business
for f in $(find . -name "*.sh" -not -path "./.git/*"); do bash -n "$f" || echo "FAILED: $f"; done
```
Expected: no `FAILED:` lines.

- [ ] **Step 4: Read through `hypervisor/README.md` end to end**

Confirm the new prose section reads coherently in place of the removed table, and the "Why
hand-built, not scripted?" section's closing sentence correctly names `lab-scale-business`
without a broken link.
