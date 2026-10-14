# Scenario 2: Nested Proxmox

**Goal: a repeatable, heavily automated lab on a normal lab PC.** Proxmox VE runs as a VM inside
VMware Workstation. The lab guests (mostly LXC, a few VMs) are built by Terraform and Ansible
inside it.

This is the **spine lab** of the Advanced Server Security unit (ICTNWK540 + ICTNWK546). The
week-by-week capabilities it must provide are in the
[design](../../docs/superpowers/specs/2026-10-14-three-build-scenarios-design.md#course-alignment-advanced-server-security-ictnwk540--ictnwk546).

## Topology: three VMware VMs

```text
Internet - VMware NAT - pfSense - LAN Segment (LAN-LAB) - Admin PC
                                        |
                                  Proxmox VE (nested KVM + LXC)
                                        |  vmbr-lan bridged to the LAN Segment
                              docker01, authentik01, samba-dc01, Windows Server, ...
```

| VM | Size | Networks |
|----|------|----------|
| pfSense | 1 vCPU, 1 GB | NIC 1 NAT (WAN), NIC 2 LAN Segment |
| Proxmox VE | 4+ vCPU, about 20 GB RAM, 100+ GB disk, **Virtualize VT-x/EPT ticked** | LAN Segment |
| Admin PC (Ubuntu desktop or Windows 11) | 2 vCPU, 3-4 GB | LAN Segment |

## Host OS: Windows or Linux

| | Windows host | Linux host |
|---|---|---|
| Prepare for nesting | `scripts\Set-NestedVirtualisation.ps1 -Mode Disable`, restart | Nothing to switch off. Enable VT-x/AMD-V in firmware if needed |
| Check (every class) | `scripts\Set-NestedVirtualisation.ps1` | `scripts/check-nested-virtualisation.sh` |
| Undo | `-Mode Restore` | n/a |

Both print READY or NOT READY and exit 0 or 2. Windows updates and policy can switch the
protections back on, so run the check at the start of each class. The Windows script turns off
Hyper-V, Memory Integrity and Credential Guard: a deliberate lab-only trade-off, and WSL 2 and
Docker Desktop stop working until `-Mode Restore`.

## Steps

1. **Prepare the host** as in the table above, and confirm READY.
2. **Build the three VMware VMs.** pfSense and the Admin PC follow
   [`hypervisor/vms/pfsense.md`](../../hypervisor/vms/pfsense.md) and
   [`linux-client.md`](../../hypervisor/vms/linux-client.md) /
   [`windows-client.md`](../../hypervisor/vms/windows-client.md). Create the Proxmox VM with
   Debian 12 x64 as the guest OS type.
3. **Install Proxmox VE** from the ISO.
4. **Remove the subscription defaults.** On the Proxmox host, as root:

   ```bash
   ./post-install.sh --dry-run     # read what it will do
   ./post-install.sh --upgrade
   ```

   Script: [`hypervisor/proxmox/host/post-install.sh`](../../hypervisor/proxmox/host/post-install.sh).
5. **Confirm KVM** in the Proxmox shell: `egrep -c '(vmx|svm)' /proc/cpuinfo` is above 0 and the
   node summary shows no KVM warning.
6. **Build the lab guests.** Continue in
   [`hypervisor/proxmox/README.md`](../../hypervisor/proxmox/README.md). Skip its pfSense step:
   pfSense already exists as a VMware VM here.

## Guest placement

`docker01`, `authentik01` and `samba-dc01` are **VMs** (no privileged LXC, and Docker in an
unprivileged LXC is avoided). LXC is for small single-purpose services only. The Squid proxy
lives on pfSense, outside Proxmox ([`pfsense/squid.md`](../../pfsense/squid.md)).

## Not done yet

- A Proxmox provisioning script for the guests (host-side `qm`/`pct`), and the choice between it
  and Terraform. See the design's provisioning comparison.
- Still open from the course list: Windows Server member server, Proxmox Backup Server, central
  logging (Wazuh or Loki), vulnerability scanner, CIS hardening roles, incident-response drill.
- Windows Server guests run slowly under nested KVM. Plan for one at a time.
