# Scenario 3: Native Proxmox

**Goal: the same automated lab as [scenario 2](../2-nested-proxmox/), on real hardware.** No
VMware, no nesting, no Windows host preparation. Better performance, and the closest thing here
to a real small-business server.

## Steps

1. **Install Proxmox VE** on the machine from the ISO. Use the whole disk, or ZFS if you have
   two disks and want a mirror.
2. **Networks.** Create `vmbr-lan` (no physical port, no IP). For `vmbr-wan`, bridge a spare
   physical NIC, or use an SDN NAT zone. See
   [`hypervisor/proxmox/README.md`](../../hypervisor/proxmox/README.md#prerequisites).
3. **Remove the subscription defaults.** As root on the host:
   ```bash
   ./post-install.sh --dry-run
   ./post-install.sh --upgrade
   ```
   Script: [`hypervisor/proxmox/host/post-install.sh`](../../hypervisor/proxmox/host/post-install.sh).
4. **Build the lab.** Continue in [`hypervisor/proxmox/README.md`](../../hypervisor/proxmox/README.md).

Everything after step 3 is identical to scenario 2.
