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
