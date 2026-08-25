# Proxmox VE (Terraform) Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `bpg/terraform-provider-proxmox` root module under `hypervisor/proxmox/` that
provisions `samba-dc01`, `docker01`, and `authentik01` on Proxmox VE, and document why
`pfsense01`, `linux-client01`, and `win-client01` stay manual builds there.

**Architecture:** Terraform imports an official Ubuntu 24.04 Server cloud image once, then
clones it into each of the three Linux VMs' disks, wiring Proxmox's native cloud-init
(`initialization` block) to a small per-VM `proxmox-user-data` snippet. This is a deliberately
different mechanism from every other platform in this repo — see "Why this looks different from
VMware" below — arrived at after verifying the actual Terraform provider can't attach the two
simultaneous CD-ROMs Subiquity's ISO-installer autoinstall needs.

**Tech Stack:** Terraform (`>= 1.6.0`), `bpg/proxmox` provider (`~> 0.66`), Proxmox VE 8.x.

**Spec:** [docs/superpowers/specs/2026-08-25-multi-hypervisor-support-design.md](../specs/2026-08-25-multi-hypervisor-support-design.md)
— this plan implements that spec's "Why Proxmox doesn't reuse this mechanism" and "Proxmox
(Terraform)" sections. Depends on
[docs/superpowers/plans/2026-08-25-hypervisor-rename-and-vmware-linux.md](2026-08-25-hypervisor-rename-and-vmware-linux.md)
already being applied — this plan assumes `hypervisor/` (not `workstation/`) already exists.

## Why this looks different from VMware

`bpg/terraform-provider-proxmox`'s VM resource only supports **one** `cdrom` block per VM. This
repo's Ubuntu VMs install from the Server ISO via Subiquity's `autoinstall:`-wrapped NoCloud
seed, which needs a *second*, separately-attached CD-ROM alongside the installer — the same
mechanism VMware already uses. That can't be expressed through this provider, and Proxmox's
native cloud-init drive is a distinct mechanism (built for configuring an already-installed OS
from a cloud image at first boot, not for feeding an ISO installer). So Proxmox's three
automatable VMs use the actual standard Proxmox+Terraform pattern instead — cloud image + native
cloud-init — which means:

- No ISO installer, no seed ISO, no `build-seed-iso.sh` involvement for these three VMs.
- Each gets a **new**, small `proxmox-user-data.example` (plain cloud-init format) alongside its
  existing `user-data.example`/`meta-data.example` (which are untouched — still used by VMware).
- `win-client01` has no cloud-image equivalent on Windows, so it isn't in this Terraform module
  at all — built by hand in the Proxmox web console, like `pfsense01`/`linux-client01` already
  are everywhere.

## Global Constraints

- TLS to the Proxmox API is verified against a real CA — `insecure = true` is never set in the
  provider block. `proxmox/README.md` documents trusting Proxmox's certificate properly instead.
- Domain/subnet strings (`10.10.10.`, `lab.internal`) stay literal, matching every other file in
  this repo — no interpolation from a business-name variable.
- `terraform.tfvars` (real API token) and `*.tfstate` are secrets/state, already covered by
  `.gitignore`'s existing generic Terraform patterns (`**/*.tfstate`, `**/*.tfvars` with a
  `!**/*.tfvars.example` exception) — nothing new to add there.
- No CI in this repo. `terraform fmt -check` if `terraform` is installed locally; otherwise a
  careful manual read-through is the fallback, same bar this repo already applies to
  Ansible/compose/Samba changes that can't be executed in review either.

---

## Task 1: Terraform module — provider, variables, VM resources

**Files:**
- Create: `hypervisor/proxmox/main.tf`
- Create: `hypervisor/proxmox/variables.tf`
- Create: `hypervisor/proxmox/vms.tf`
- Create: `hypervisor/proxmox/terraform.tfvars.example`
- Create: `hypervisor/vms/seeds/samba-dc01/proxmox-user-data.example`
- Create: `hypervisor/vms/seeds/docker01/proxmox-user-data.example`
- Create: `hypervisor/vms/seeds/authentik01/proxmox-user-data.example`
- Modify: `.gitignore` (one addition for the new seed-file pattern)

**Interfaces:**
- Consumes: `hypervisor/vms/seeds/<name>/proxmox-user-data` (real, gitignored, filled-in copies
  a student makes from this task's `.example` files).
- Produces: three `proxmox_virtual_environment_vm` resources (`samba-dc01`, `docker01`,
  `authentik01`) that Task 2's README walkthrough drives with `terraform apply`.

- [ ] **Step 1: Write `hypervisor/proxmox/main.tf`**

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

# TLS is verified against a real CA — insecure is never set to true. Issue Proxmox's web
# certificate from the lab's own PKI (see docs/PKI.md) and install that CA in the trust store of
# whatever machine runs `terraform apply`, or trust Proxmox's self-signed cert the same way;
# either way, the default (insecure = false) then just works without disabling verification.
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = false
}
```

- [ ] **Step 2: Write `hypervisor/proxmox/variables.tf`**

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
  description = "Datastore ID for the imported Ubuntu cloud image and cloud-init snippet files (must have both the 'Disk image' and 'Snippets' content types enabled — see proxmox/README.md)"
  type        = string
  default     = "local"
}

variable "lan_bridge" {
  description = "Linux bridge every automatable lab VM's NIC attaches to (see hypervisor/networks/README.md)"
  type        = string
  default     = "vmbr-lan"
}

variable "cloud_image_path" {
  description = "Local path to the downloaded Ubuntu 24.04 Server cloud image (see proxmox/README.md's prerequisites)"
  type        = string
  default     = "~/isos/noble-server-cloudimg-amd64.img"
}
```

- [ ] **Step 3: Write `hypervisor/proxmox/vms.tf`**

```hcl
# name -> vcpu/ram/disk/ip/dns — mirrors the VM table in
# hypervisor/vmware-linux/scripts/create-vms.sh, minus win-client01 (not automated on Proxmox —
# see hypervisor/README.md and hypervisor/vms/windows-client.md for why) and minus
# pfsense01/linux-client01 (built by hand on every platform, not just this one).
locals {
  linux_vms = {
    samba-dc01  = { vcpu = 2, ram_mb = 4096, disk_gb = 40, ip = "10.10.10.10", dns = "127.0.0.1" }
    docker01    = { vcpu = 4, ram_mb = 8192, disk_gb = 80, ip = "10.10.10.20", dns = "10.10.10.10" }
    authentik01 = { vcpu = 2, ram_mb = 4096, disk_gb = 40, ip = "10.10.10.30", dns = "10.10.10.10" }
  }
}

# Imported once, then cloned into each VM's disk below via import_from. Download the image
# yourself first (see proxmox/README.md) — Terraform only imports the local file, it doesn't
# fetch it from the internet.
resource "proxmox_virtual_environment_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node

  source_file {
    path = var.cloud_image_path
  }
}

# Each VM's cloud-init user-data, uploaded as a snippet. Built from
# hypervisor/vms/seeds/<name>/proxmox-user-data (the real, gitignored, filled-in copy of
# proxmox-user-data.example) — Terraform only uploads the file, it doesn't fill in placeholders;
# fill them in by hand before running `terraform apply` (proxmox/README.md covers this).
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  for_each     = local.linux_vms
  content_type = "snippets"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node

  source_file {
    path = "${path.module}/../vms/seeds/${each.key}/proxmox-user-data"
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

- [ ] **Step 4: Write `hypervisor/proxmox/terraform.tfvars.example`**

```hcl
proxmox_api_url   = "https://pve.lab.internal:8006/api2/json"
proxmox_api_token = "terraform@pve!lab-terraform=REPLACE_ME"
proxmox_node      = "pve"
storage_pool      = "local-lvm"
image_datastore   = "local"
lan_bridge        = "vmbr-lan"
cloud_image_path  = "/home/labadmin/isos/noble-server-cloudimg-amd64.img"
```

- [ ] **Step 5: Write the three `proxmox-user-data.example` seed files**

Same information as each VM's existing `user-data.example` (hostname, `labadmin` user, password
hash placeholder, SSH), in plain cloud-init format instead of Subiquity's `autoinstall:` wrapper
— and with network settings left out, since `vms.tf`'s `initialization.ip_config` block (Step 3)
sets those directly instead of duplicating them into the seed file.

Write `hypervisor/vms/seeds/samba-dc01/proxmox-user-data.example`:

```yaml
#cloud-config
# Plain cloud-init seed for samba-dc01 on Proxmox — NOT the same format as user-data.example.
# Proxmox's Linux VMs boot a pre-installed Ubuntu cloud image instead of the Server ISO (see
# hypervisor/proxmox/README.md for why: the Terraform provider can't attach the two CD-ROMs
# Subiquity's autoinstall needs), so cloud-init configures the already-installed OS at first
# boot here, rather than driving an interactive installer like user-data.example does — a
# genuinely different schema, even though this describes the same host. Static IP/gateway/DNS
# are set by hypervisor/proxmox/vms.tf's `initialization` block, not here — that keeps exactly
# one place per platform owning network settings instead of duplicating them into this file too.
#
# This .example file is committed to git; the real one (with your actual password hash in it)
# is not — copy this file to proxmox-user-data (same folder, no ".example") and fill in the
# placeholder below before running `terraform apply` in hypervisor/proxmox/.
hostname: samba-dc01
manage_etc_hosts: true

users:
  - name: labadmin
    # matches ansible_user in ansible/inventory/hosts.ini — see user-data.example for the full
    # explanation of why, unchanged here.
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: false
    # Generate with: mkpasswd --method=sha-512
    passwd: "$6$replace-with-a-mkpasswd-hash"

ssh_pwauth: true

package_update: true
packages:
  - openssh-server

runcmd:
  - systemctl enable --now ssh
```

Write `hypervisor/vms/seeds/docker01/proxmox-user-data.example`:

```yaml
#cloud-config
# Plain cloud-init seed for docker01 on Proxmox — see
# hypervisor/vms/seeds/samba-dc01/proxmox-user-data.example for a fully-commented walkthrough;
# this file covers only what's different (hostname).
#
# Copy this file to proxmox-user-data (drop the .example suffix) and fill in the password hash
# before running `terraform apply` in hypervisor/proxmox/.
hostname: docker01
manage_etc_hosts: true

users:
  - name: labadmin
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: false
    # Generate with: mkpasswd --method=sha-512
    passwd: "$6$replace-with-a-mkpasswd-hash"

ssh_pwauth: true

package_update: true
packages:
  - openssh-server

runcmd:
  - systemctl enable --now ssh
```

Write `hypervisor/vms/seeds/authentik01/proxmox-user-data.example`:

```yaml
#cloud-config
# Plain cloud-init seed for authentik01 on Proxmox — see
# hypervisor/vms/seeds/samba-dc01/proxmox-user-data.example for a fully-commented walkthrough;
# this file covers only what's different (hostname).
#
# Copy this file to proxmox-user-data (drop the .example suffix) and fill in the password hash
# before running `terraform apply` in hypervisor/proxmox/.
hostname: authentik01
manage_etc_hosts: true

users:
  - name: labadmin
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: false
    # Generate with: mkpasswd --method=sha-512
    passwd: "$6$replace-with-a-mkpasswd-hash"

ssh_pwauth: true

package_update: true
packages:
  - openssh-server

runcmd:
  - systemctl enable --now ssh
```

- [ ] **Step 6: Add the new seed pattern to `.gitignore`**

The existing `hypervisor/vms/seeds/**/{user-data,meta-data,autounattend.xml}` gitignore lines
(from the hypervisor-rename plan) don't cover the new `proxmox-user-data` filename.

Modify `.gitignore` (in the "Unattended-install seed data" section):

Old:
```
hypervisor/vms/seeds/**/user-data
hypervisor/vms/seeds/**/meta-data
hypervisor/vms/seeds/**/autounattend.xml
hypervisor/vms/**/*-seed.iso
```
New:
```
hypervisor/vms/seeds/**/user-data
hypervisor/vms/seeds/**/meta-data
hypervisor/vms/seeds/**/autounattend.xml
hypervisor/vms/seeds/**/proxmox-user-data
hypervisor/vms/**/*-seed.iso
```

- [ ] **Step 7: Validate**

```bash
if command -v terraform >/dev/null 2>&1; then
  terraform -chdir=hypervisor/proxmox fmt -check
  terraform -chdir=hypervisor/proxmox init -backend=false
  terraform -chdir=hypervisor/proxmox validate
else
  echo "terraform not installed — falling back to a manual read-through of the three .tf files"
  echo "against docs/superpowers/specs/2026-08-25-multi-hypervisor-support-design.md's Proxmox"
  echo "section, per this repo's no-CI convention."
fi

python3 -c "import yaml; yaml.safe_load(open('hypervisor/vms/seeds/samba-dc01/proxmox-user-data.example'))" && echo OK
python3 -c "import yaml; yaml.safe_load(open('hypervisor/vms/seeds/docker01/proxmox-user-data.example'))" && echo OK
python3 -c "import yaml; yaml.safe_load(open('hypervisor/vms/seeds/authentik01/proxmox-user-data.example'))" && echo OK
```

Expected: if `terraform` is available, `fmt -check` prints nothing (already formatted),
`init`/`validate` succeed (`init -backend=false` needs network access to download the `bpg/proxmox`
provider — if that's unavailable too, fall back to the manual read-through same as the no-`terraform`
case). All three `yaml.safe_load` calls print `OK`.

- [ ] **Step 8: Commit**

```bash
git add hypervisor/proxmox/main.tf hypervisor/proxmox/variables.tf hypervisor/proxmox/vms.tf \
  hypervisor/proxmox/terraform.tfvars.example \
  hypervisor/vms/seeds/samba-dc01/proxmox-user-data.example \
  hypervisor/vms/seeds/docker01/proxmox-user-data.example \
  hypervisor/vms/seeds/authentik01/proxmox-user-data.example \
  .gitignore
git commit -m "$(cat <<'EOF'
Add Proxmox Terraform module for samba-dc01, docker01, authentik01

Imports an Ubuntu 24.04 cloud image and clones it per VM, wiring
Proxmox's native cloud-init to a new proxmox-user-data seed per VM.
Cloud image + native cloud-init instead of the ISO+seed-ISO mechanism
every other platform uses, because bpg/terraform-provider-proxmox's
cdrom block can't express the two simultaneous CD-ROMs Subiquity's
autoinstall needs — see the spec's "Why Proxmox doesn't reuse this
mechanism" section for the full reasoning.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `hypervisor/proxmox/README.md`

The Terraform walkthrough: prerequisites (cloud image download, API token, WAN networking
choice, certificate trust), `terraform init`/`plan`/`apply`, and what's still manual.

**Files:**
- Create: `hypervisor/proxmox/README.md`

- [ ] **Step 1: Write the file**

```markdown
# Proxmox VE

Provisions `samba-dc01`, `docker01`, and `authentik01` via Terraform
(`bpg/terraform-provider-proxmox`). `pfsense01`, `linux-client01`, and `win-client01` are built
by hand through the Proxmox web console — see [`../vms/pfsense.md`](../vms/pfsense.md),
[`../vms/linux-client.md`](../vms/linux-client.md), and
[`../vms/windows-client.md`](../vms/windows-client.md) for each one's Proxmox-specific build
notes, and [`../README.md`](../README.md) for why `win-client01` can't be automated here the way
it is on VMware.

## Why cloud image + native cloud-init, not the ISO+seed-ISO mechanism VMware uses

`bpg/terraform-provider-proxmox`'s VM resource only supports one `cdrom` block per VM.
Subiquity's ISO-installer autoinstall (what every other platform in this repo uses) needs a
*second*, separately-attached CD-ROM for its seed — not expressible through this provider. So
these three VMs use the standard, well-documented Proxmox+Terraform pattern instead: import an
Ubuntu cloud image once, clone it per VM, and let Proxmox's native cloud-init configure
hostname/user/SSH at first boot. Full reasoning:
[docs/superpowers/specs/2026-08-25-multi-hypervisor-support-design.md](../../docs/superpowers/specs/2026-08-25-multi-hypervisor-support-design.md#why-proxmox-doesnt-reuse-this-mechanism).

## Prerequisites

1. **Terraform** `>= 1.6.0` on whatever machine you run `terraform apply` from (this repo's own
   `linux-client01` control host works fine, or your Proxmox host's own shell).
2. **A Proxmox API token.** Datacenter > Permissions > API Tokens > Add, for a user with at
   least `VM.Allocate`, `VM.Config.*`, `VM.PowerMgmt`, `Datastore.AllocateSpace`, and
   `Datastore.AllocateTemplate` on the target node/storage. Copy the token into
   `terraform.tfvars`'s `proxmox_api_token` (never commit that file — it's gitignored, only
   `terraform.tfvars.example` is tracked).
3. **A trusted certificate on Proxmox's web UI.** This module never sets `insecure = true`
   (see `main.tf`'s comment) — either issue Proxmox's certificate from the lab's own PKI (see
   [docs/PKI.md](../../docs/PKI.md)) and install that CA on the machine running `terraform
   apply`, or explicitly trust Proxmox's self-signed certificate the same way. Skipping TLS
   verification is not an option this repo takes for any connection to itself.
4. **The Ubuntu 24.04 Server cloud image**, downloaded to wherever `terraform.tfvars`'s
   `cloud_image_path` points:
   ```bash
   curl -fLO https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
   ```
5. **Each of the three VMs' seed file filled in:**
   ```bash
   cp ../vms/seeds/samba-dc01/proxmox-user-data.example ../vms/seeds/samba-dc01/proxmox-user-data
   cp ../vms/seeds/docker01/proxmox-user-data.example ../vms/seeds/docker01/proxmox-user-data
   cp ../vms/seeds/authentik01/proxmox-user-data.example ../vms/seeds/authentik01/proxmox-user-data
   mkpasswd --method=sha-512   # paste the output into each file's passwd field
   ```
   The real files (no `.example` suffix) are gitignored — they'll contain your actual password
   hash, which is not something to commit.
6. **WAN networking for pfSense** (built by hand, but needs a bridge to exist first — see
   [`../vms/pfsense.md`](../vms/pfsense.md) for the full build) — pick one:
   - **Dedicated bridged physical NIC** (recommended): a second physical (or USB) NIC on the
     Proxmox host, bridged as `vmbr-wan`, closest to a real deployment.
     Datacenter > *node* > System > Network > Create: Linux Bridge, bridge port = the spare
     NIC, no IP configuration (pfSense will DHCP-client on it).
   - **Proxmox SDN NAT zone**: no spare NIC needed. Datacenter > SDN > Zones > Create: Simple,
     then a matching VNet — see Proxmox's own SDN documentation for the exact steps, since this
     varies more by PVE version than a bridge does.
   - Either way, also create `vmbr-lan` (Linux Bridge, no physical port, no IP — an isolated
     internal bridge) for every other VM's NIC, mirroring the "only pfSense touches WAN" rule
     from [`../networks/README.md`](../networks/README.md).

## Bring-up

```bash
cd hypervisor/proxmox
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: proxmox_api_url, proxmox_api_token, and any values that differ from
# your Proxmox host's actual node/storage/bridge names
terraform init
terraform plan
terraform apply
```

`terraform apply` creates all three VMs; each boots the cloned cloud image and configures itself
via cloud-init within a minute or two — no interactive install step, unlike every other platform
in this repo. Confirm with `ssh labadmin@10.10.10.10` (etc.) once cloud-init finishes.

## What's still manual

Same three VMs that are manual on every platform, plus one Proxmox-specific case:

- `pfsense01` — no unattended pfSense installer exists anywhere (see
  [`../vms/pfsense.md`](../vms/pfsense.md)).
- `linux-client01` — desktop install is intentionally hands-on everywhere (see
  [`../vms/linux-client.md`](../vms/linux-client.md)).
- `win-client01` — automated on VMware, but not here: there's no Windows-cloud-image/
  native-cloud-init equivalent to fall back on the way the Linux VMs do, and the same
  single-CD-ROM provider limitation blocks the ISO+seed-ISO mechanism VMware uses. Build it by
  hand per [`../vms/windows-client.md`](../vms/windows-client.md)'s Proxmox notes.
```

- [ ] **Step 2: Verify internal links resolve**

```bash
grep -oE '\]\(\.\./[a-zA-Z0-9_./#-]+\)' hypervisor/proxmox/README.md | sed 's/.*(//; s/)//; s/#.*//' | sort -u
```

For each path printed, confirm it exists relative to `hypervisor/proxmox/` (e.g.
`../vms/pfsense.md` → `hypervisor/vms/pfsense.md`, `../../docs/superpowers/specs/...` →
`docs/superpowers/specs/...`).

- [ ] **Step 3: Commit**

```bash
git add hypervisor/proxmox/README.md
git commit -m "$(cat <<'EOF'
Add hypervisor/proxmox/README.md walkthrough

Prerequisites (API token, cert trust, cloud image, WAN bridge choice),
terraform init/plan/apply, and what's still manual on this platform.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Document Proxmox across the rest of the repo

Everywhere that currently only knows about the two VMware platforms gets a Proxmox mention or
callout — mirroring how the hypervisor-rename plan's Task 4 added the Linux-VMware mentions.

**Files:**
- Modify: `hypervisor/README.md` (add the Proxmox row to the platform picker)
- Modify: `hypervisor/networks/README.md` (add the Linux-bridge equivalent)
- Modify: `hypervisor/vms/samba-dc.md`, `docker-server.md`, `authentik.md` (note the
  `proxmox-user-data` seed variant)
- Modify: `hypervisor/vms/windows-client.md` (note it's Proxmox-manual)
- Modify: `hypervisor/vms/pfsense.md`, `linux-client.md` (add a Proxmox build note)
- Modify: `pfsense/README.md` (point at the Proxmox bridge equivalent)
- Modify: `README.md`, `CLAUDE.md`, `docs/Architecture.md`, `docs/DeploymentGuide.md`

- [ ] **Step 1: Add the Proxmox row to `hypervisor/README.md`'s platform picker**

Modify the table added by the hypervisor-rename plan's Task 4, Step 1:

Old:
```
| Platform                         | Directory                             | Host OS | Automation                                |
| --------------------------------- | -------------------------------------- | ------- | ------------------------------------------ |
| VMware Workstation Pro (default) | [`vmware-windows/`](vmware-windows/)  | Windows | PowerShell + `vmrun`/`vmware-vdiskmanager` |
| VMware Workstation Pro           | [`vmware-linux/`](vmware-linux/)      | Linux   | Bash + `vmrun`/`vmware-vdiskmanager`       |

Both VMware paths behave identically once the VMs exist — same LAN Segment networking (see
[`networks/README.md`](networks/README.md)), same seed-data format (see
[`vms/seeds/`](vms/seeds/)), same VM specs (see [`vms/`](vms/)). Pick whichever matches the
host OS you're running VMware Workstation Pro on. `vmware-windows/` is the default,
most-referenced path this repo's other docs (`docs/DeploymentGuide.md`) assume unless stated
otherwise.
```
New:
```
| Platform                         | Directory                             | Host OS | Automation                                |
| --------------------------------- | -------------------------------------- | ------- | ------------------------------------------ |
| VMware Workstation Pro (default) | [`vmware-windows/`](vmware-windows/)  | Windows | PowerShell + `vmrun`/`vmware-vdiskmanager` |
| VMware Workstation Pro           | [`vmware-linux/`](vmware-linux/)      | Linux   | Bash + `vmrun`/`vmware-vdiskmanager`       |
| Proxmox VE                       | [`proxmox/`](proxmox/)                | (n/a — Proxmox is bare-metal) | Terraform (`bpg/proxmox`)  |

The two VMware paths behave identically once the VMs exist — same LAN Segment networking (see
[`networks/README.md`](networks/README.md)), same seed-data format (see
[`vms/seeds/`](vms/seeds/)), same VM specs (see [`vms/`](vms/)). Pick whichever matches the
host OS you're running VMware Workstation Pro on. `vmware-windows/` is the default,
most-referenced path this repo's other docs (`docs/DeploymentGuide.md`) assume unless stated
otherwise.

**Proxmox is a different kind of platform, not just a different host OS**: it's a real
Type-1 hypervisor (bare-metal, no VMware/host-OS layer at all), it automates only three of the
four VMware-automated VMs (`win-client01` is manual there — see
[`proxmox/README.md`](proxmox/README.md) for why), and its Linux VMs install from a cloud image
instead of the Server ISO everyone else uses. See [`proxmox/README.md`](proxmox/README.md)
before assuming it's a drop-in swap for either VMware path.
```

- [ ] **Step 2: Add the Linux-bridge equivalent to `hypervisor/networks/README.md`**

Modify `hypervisor/networks/README.md` — after the existing "Creating the network" section
(which is VMware LAN-Segment-specific), add:

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

- [ ] **Step 3: Note the Proxmox seed variant in `hypervisor/vms/samba-dc.md`**

Modify `hypervisor/vms/samba-dc.md` (the paragraph right before "## Post-install"):

Old:
```
The real `user-data`/`meta-data` (no `.example` suffix) are gitignored — they'll contain your
actual password hash, which is not something to commit.

## Post-install
```
New:
```
The real `user-data`/`meta-data` (no `.example` suffix) are gitignored — they'll contain your
actual password hash, which is not something to commit.

**On Proxmox**, this VM doesn't use `user-data`/`meta-data` at all — it boots a cloud image and
is configured by [`seeds/samba-dc01/proxmox-user-data.example`](seeds/samba-dc01/proxmox-user-data.example)
instead. See [`../proxmox/README.md`](../proxmox/README.md) for why the mechanism differs and
what to fill in before `terraform apply`.

## Post-install
```

- [ ] **Step 4: Note the Proxmox seed variant in `hypervisor/vms/docker-server.md`**

Modify `hypervisor/vms/docker-server.md`:

Old:
```
Hosts the Traefik reverse proxy plus NextCloud, OnlyOffice, and Dovecot Compose stacks (see
[`docker/`](../../docker/)). Installs unattended from
[`seeds/docker01/user-data.example`](seeds/docker01/user-data.example) — see
[`samba-dc.md`](samba-dc.md#autoinstall) for how the seed-ISO mechanism works and the
`cp`/`mkpasswd` steps you need before running `create-vms.ps1`.

## Post-install
```
New:
```
Hosts the Traefik reverse proxy plus NextCloud, OnlyOffice, and Dovecot Compose stacks (see
[`docker/`](../../docker/)). Installs unattended from
[`seeds/docker01/user-data.example`](seeds/docker01/user-data.example) — see
[`samba-dc.md`](samba-dc.md#autoinstall) for how the seed-ISO mechanism works and the
`cp`/`mkpasswd` steps you need before running `create-vms.ps1`.

**On Proxmox**, see [`samba-dc.md`](samba-dc.md#autoinstall) for why this VM's seed mechanism
differs there — the short version: cloud image + `seeds/docker01/proxmox-user-data.example`
instead of an ISO install.

## Post-install
```

- [ ] **Step 5: Note the Proxmox seed variant in `hypervisor/vms/authentik.md`**

Modify `hypervisor/vms/authentik.md`:

Old:
```
Installs unattended from
[`seeds/authentik01/user-data.example`](seeds/authentik01/user-data.example) — see
[`samba-dc.md`](samba-dc.md#autoinstall) for how the seed-ISO mechanism works.

## Post-install
```
New:
```
Installs unattended from
[`seeds/authentik01/user-data.example`](seeds/authentik01/user-data.example) — see
[`samba-dc.md`](samba-dc.md#autoinstall) for how the seed-ISO mechanism works.

**On Proxmox**, see [`samba-dc.md`](samba-dc.md#autoinstall) for why this VM's seed mechanism
differs there — the short version: cloud image + `seeds/authentik01/proxmox-user-data.example`
instead of an ISO install.

## Post-install
```

- [ ] **Step 6: Note `win-client01` is Proxmox-manual in `hypervisor/vms/windows-client.md`**

Modify `hypervisor/vms/windows-client.md`:

Old:
```
VMware Tools (or open-vm-tools equivalent installer bundled with Workstation) should be
installed post-OS-install for clipboard/display integration.

## Post-install
```
New:
```
VMware Tools (or open-vm-tools equivalent installer bundled with Workstation) should be
installed post-OS-install for clipboard/display integration.

**On Proxmox, this VM is built by hand** through the Proxmox web console, not by Terraform.
Unlike the three Linux VMs, there's no Windows-cloud-image/native-cloud-init equivalent to fall
back on, and the same single-CD-ROM Terraform-provider limitation that pushed the Linux VMs onto
cloud images blocks the ISO+`autounattend.xml`-seed-ISO mechanism this VM uses on VMware. See
[`../proxmox/README.md`](../proxmox/README.md) for the full reasoning. Build it the same way as
[`pfsense.md`](pfsense.md) and [`linux-client.md`](linux-client.md) describe: new VM in the
Proxmox web UI, `vmbr-lan` NIC, `Win11.iso` attached, install interactively, then follow this
page's "Post-install" section once it's up.

## Post-install
```

- [ ] **Step 7: Add a Proxmox build note to `hypervisor/vms/pfsense.md`**

Modify `hypervisor/vms/pfsense.md` (its "Build (VM + both NICs)" section is
VMware-Workstation-GUI-specific — `VM Settings > Add... > Network Adapter`, `VMnet8` — so add a
Proxmox equivalent right before "## Install"):

Old:
```
   further to create.

## Install (manual — no unattended installer available for pfSense on Workstation)
```
New:
```
   further to create.

### On Proxmox

The VMware-GUI steps above don't apply — create the VM through the Proxmox web console instead:
**Datacenter > *node* > Create VM**, same specs (2 vCPU, 2048 MB RAM, 20 GB disk), pfSense CE
ISO attached. NIC 1 on `vmbr-wan`, NIC 2 on `vmbr-lan` — both bridges are prerequisites you
create once, per [`../proxmox/README.md`](../proxmox/README.md)'s WAN-networking section, before
building this VM. Everything from "## Install" onward is identical regardless of hypervisor.

## Install (manual — no unattended installer available for pfSense on Workstation)
```

- [ ] **Step 8: Add a Proxmox build note to `hypervisor/vms/linux-client.md`**

Modify `hypervisor/vms/linux-client.md` (its "Build + install" section's step 1 is also
VMware-GUI-specific):

Old:
```
2. Install interactively (Ubuntu Desktop's installer is graphical; unattended desktop installs
   are out of scope for a lab teaching manual desktop use). It gets a DHCP lease from pfSense.

## Set up as the control host
```
New:
```
2. Install interactively (Ubuntu Desktop's installer is graphical; unattended desktop installs
   are out of scope for a lab teaching manual desktop use). It gets a DHCP lease from pfSense.

**On Proxmox**, create the VM through the Proxmox web console instead of the VMware GUI in step
1 above — same specs, single NIC on `vmbr-lan` (created once per
[`../proxmox/README.md`](../proxmox/README.md), not per VM). Step 2 is identical regardless of
hypervisor.

## Set up as the control host
```

- [ ] **Step 9: Point `pfsense/README.md` at the Proxmox bridge equivalent**

Modify `pfsense/README.md:9-10`:

Old:
```
**The files below are an optional shortcut, not the default first-run path.**
[`docs/DeploymentGuide.md`](../docs/DeploymentGuide.md#1-pfsense--fully-manual) and
[`hypervisor/vms/pfsense.md`](../hypervisor/vms/pfsense.md) walk through configuring pfSense
entirely by hand — start there. Come back to `config.xml.template` once you're comfortable with
the manual flow and want a reviewed, reusable baseline for future rebuilds.
```
New:
```
**The files below are an optional shortcut, not the default first-run path.**
[`docs/DeploymentGuide.md`](../docs/DeploymentGuide.md#1-pfsense--fully-manual) and
[`hypervisor/vms/pfsense.md`](../hypervisor/vms/pfsense.md) walk through configuring pfSense
entirely by hand — start there (that page covers both the VMware and Proxmox build steps; only
the DHCP/DNS/firewall configuration below is hypervisor-agnostic). Come back to
`config.xml.template` once you're comfortable with the manual flow and want a reviewed, reusable
baseline for future rebuilds.
```

- [ ] **Step 10: Mention Proxmox in `README.md`**

Modify `README.md:43` (repository layout tree — already updated by the hypervisor-rename plan to
mention "VMware Workstation: Windows or Linux"):

Old:
```
├── hypervisor/      VM inventory, network config, provisioning notes (VMware Workstation: Windows or Linux)
```
New:
```
├── hypervisor/      VM inventory, network config, provisioning notes (VMware Workstation or Proxmox VE)
```

Modify `README.md`'s Quick Start block (already updated to show both VMware variants):

Old:
```
# 2. Remaining VM shells
#    Windows host, elevated PowerShell:
hypervisor\vmware-windows\scripts\create-vms.ps1
#    ...or a Linux host:
./hypervisor/vmware-linux/scripts/create-vms.sh
```
New:
```
# 2. Remaining VM shells
#    Windows host, elevated PowerShell:
hypervisor\vmware-windows\scripts\create-vms.ps1
#    ...or a Linux host:
./hypervisor/vmware-linux/scripts/create-vms.sh
#    ...or Proxmox VE (see hypervisor/proxmox/README.md — automates 3 of the 4 VMs, not 4):
cd hypervisor/proxmox && terraform apply
```

- [ ] **Step 11: Mention Proxmox in `CLAUDE.md`**

Modify `CLAUDE.md:7-9` (already updated by the hypervisor-rename plan):

Old:
```
A self-contained, IaC-driven homelab simulating a small organisation's IT estate on VMware
Workstation (Windows or Linux host — see [hypervisor/README.md](hypervisor/README.md)):
pfSense, Samba AD, an internal PKI, Authentik SSO, a Docker application platform, and
Windows/Linux endpoints. It's a **teaching artifact** — code quality and doc clarity are
```
New:
```
A self-contained, IaC-driven homelab simulating a small organisation's IT estate on VMware
Workstation (Windows or Linux) or Proxmox VE — see
[hypervisor/README.md](hypervisor/README.md) for the trade-offs between them: pfSense, Samba
AD, an internal PKI, Authentik SSO, a Docker application platform, and Windows/Linux endpoints.
It's a **teaching artifact** — code quality and doc clarity are
```

- [ ] **Step 12: Mention Proxmox in `docs/Architecture.md`**

Modify `docs/Architecture.md:9` (already updated by the hypervisor-rename plan):

Old:
```
containerised applications — end to end, on a single VMware Workstation host (Windows or
Linux — see [hypervisor/README.md](../hypervisor/README.md)).
```
New:
```
containerised applications — end to end, on a single VMware Workstation host or a Proxmox VE
node — see [hypervisor/README.md](../hypervisor/README.md) for the trade-offs between them.
```

Modify `docs/Architecture.md:123` (repository layout tree, already updated):

Old:
```
├── hypervisor/      VM inventory, network config, provisioning notes (VMware Workstation: Windows or Linux)
```
New:
```
├── hypervisor/      VM inventory, network config, provisioning notes (VMware Workstation or Proxmox VE)
```

- [ ] **Step 13: Mention Proxmox in `docs/DeploymentGuide.md`**

Modify `docs/DeploymentGuide.md:4-5` (already updated by the hypervisor-rename plan):

Old:
```
Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro 17+ on the host (Windows or Linux — see
[hypervisor/README.md](../hypervisor/README.md) for the Linux path) and Ubuntu Server 24.04
LTS for all Linux VMs unless stated otherwise.
```
New:
```
Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro 17+ on the host (Windows or Linux) and Ubuntu
Server 24.04 LTS for all Linux VMs, unless you're on Proxmox VE instead — see
[hypervisor/README.md](../hypervisor/README.md) for the trade-offs, and
[hypervisor/proxmox/README.md](../hypervisor/proxmox/README.md) for that path's own sequence
(cloud image, not an ISO install, for three of the four automatable VMs).
```

- [ ] **Step 14: Verify links and commit**

```bash
grep -c "proxmox" hypervisor/README.md hypervisor/networks/README.md hypervisor/vms/samba-dc.md \
  hypervisor/vms/docker-server.md hypervisor/vms/authentik.md hypervisor/vms/windows-client.md \
  hypervisor/vms/pfsense.md hypervisor/vms/linux-client.md pfsense/README.md \
  README.md CLAUDE.md docs/Architecture.md docs/DeploymentGuide.md
```

Expected: every file in the list prints a nonzero count (each was touched).

```bash
git add hypervisor/README.md hypervisor/networks/README.md hypervisor/vms/samba-dc.md \
  hypervisor/vms/docker-server.md hypervisor/vms/authentik.md hypervisor/vms/windows-client.md \
  hypervisor/vms/pfsense.md hypervisor/vms/linux-client.md pfsense/README.md \
  README.md CLAUDE.md docs/Architecture.md docs/DeploymentGuide.md
git commit -m "$(cat <<'EOF'
Document Proxmox VE across the repo's docs

Adds the Proxmox row to hypervisor/README.md's platform picker and
points every doc that only knew about the two VMware platforms at
proxmox/README.md too, including the vms/*.md pages whose build steps
or seed mechanism genuinely differ there (pfsense.md, linux-client.md,
windows-client.md, and the three Linux VMs' cloud-init seed variant).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Done criteria for this plan

- `hypervisor/proxmox/{main,variables,vms}.tf` exist, are internally consistent (variable names
  used match variable names declared), and pass `terraform fmt -check`/`validate` if Terraform
  is available, or a careful manual read-through if not.
- Three new `proxmox-user-data.example` seed files exist, are valid YAML, and match their
  VMware siblings' hostname/user/password-hash-placeholder content (network settings
  deliberately excluded, since Terraform owns those for this platform).
- Every doc that previously assumed "VMware Workstation, Windows or Linux" was the complete
  platform list now also mentions Proxmox, with accurate scope (3 of 4 VMs automated, not 4).
- A reader who only has a Proxmox box, no VMware license, can follow `hypervisor/README.md` →
  `hypervisor/proxmox/README.md` and the relevant `vms/*.md` pages to bring up the whole lab.
