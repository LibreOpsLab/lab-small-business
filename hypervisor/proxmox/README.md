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
