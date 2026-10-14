# Scenario 3: Native Proxmox

**Goal: the same automated lab as [scenario 2](../2-nested-proxmox/), on real hardware.** No
VMware, no nesting, no Windows host preparation. Better performance, and the closest thing here
to a real small-business server.

## Sizing

| Item | Minimum | Comfortable |
|---|---|---|
| CPU | 8 cores with VT-x/AMD-V | 12+ cores |
| RAM | 32 GB | 64 GB |
| Disk | 500 GB SSD | 1 TB SSD, plus a separate disk for the PBS datastore |
| NICs | 1 (WAN via SDN NAT) | 2 (a physical NIC for `vmbr-wan`) |

Without nesting, Windows Server and Windows 11 run fine as Proxmox VMs, so everything can live on
the host: pfSense (+ Squid), Windows Server, Windows 11, the three Linux VMs, PBS, and the
scanner. Sizes per guest are in the [scenario 2 table](../2-nested-proxmox/README.md#reference-lab-pc-and-sizing);
the 14 GB squeeze there does not apply, so everything can run at once on 32 GB with care and
comfortably on 64 GB.

## Steps

1. **Install Proxmox VE** on the machine from the ISO. Use the whole disk, or ZFS if you have
   two disks and want a mirror.
2. **Networks.** Create `vmbr-lan` (no physical port, no IP). For `vmbr-wan`, bridge a spare
   physical NIC, or use an SDN NAT zone.
3. **Remove the subscription defaults.** As root on the host:

   ```bash
   ./post-install.sh --dry-run
   ./post-install.sh --upgrade
   ```

   Script: [`hypervisor/proxmox/host/post-install.sh`](../../hypervisor/proxmox/host/post-install.sh).
4. **Create the Terraform API user** with `create-terraform-user.sh` (same folder as `post-install.sh`).
5. **Build the lab** with Terraform: [`hypervisor/proxmox/README.md`](../../hypervisor/proxmox/README.md).

Everything after step 3 matches scenario 2, except pfSense and the Windows machines become
Proxmox VMs.

## Shared class server

If the class has a shared Proxmox server, it hosts the **infrastructure** (servers, PBS,
monitoring, scanner). Each student then builds a **client PC in VMware on their own lab PC** and
connects it to the shared network. Nothing in scenario 2 depends on this.

Open design questions before building it:

- **Isolation.** Students share one set of servers, so one student's AD change affects everyone.
  The likely answer is one "business" per student (own domain and subnet, via
  [`scripts/provision-business.sh`](../../scripts/provision-business.sh)) on its own VLAN.
- **Reachability.** A student's VMware VM must reach its VLAN: a VLAN-capable bridged network,
  or a VPN. Campus networks often block both.
- **Capacity.** Count one full set of guests per student against the server's RAM.
