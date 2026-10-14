# Scenario 2: Nested Proxmox

**Goal: a repeatable, heavily automated lab on a normal lab PC.** Each student builds **their
own** Proxmox VE as a VM inside VMware Workstation. Linux servers and small services run inside
it; Windows machines do not.

This is the **spine lab** of the Advanced Server Security unit (ICTNWK540 + ICTNWK546). The
week-by-week capabilities it must provide are in the
[design](../../docs/superpowers/specs/2026-10-14-three-build-scenarios-design.md#course-alignment-advanced-server-security-ictnwk540--ictnwk546).

## Topology

**Windows machines are native VMware VMs, never nested.** Windows under nested KVM is slow, and
nothing about Windows needs Proxmox. Only the Linux servers and LXC services go inside Proxmox.
Every machine, Windows or Linux, joins the Samba AD domain.

```text
Internet - VMware NAT - pfSense (+ Squid) - LAN Segment (LAN-LAB) ----+---- Windows Server (member)
                                                                      +---- Windows 11 client
                                                                      +---- Linux client / admin PC
                                                                      +---- scanner01 (on demand)
                                                                      +---- Proxmox VE (nested)
                                                                                |  vmbr-lan
                                                       samba-dc01, docker01, authentik01 (VMs)
                                                       PBS and small services (LXC)
```

A shared classroom server is an optional extra, never a dependency. Where one exists, see
[scenario 3](../3-native-proxmox/README.md#shared-class-server).

## Reference lab PC and sizing

Measured on a representative lab PC (`docs/InfoDump.txt` at the time of writing):

| Item | Value |
|---|---|
| CPU | Intel Core i5-14400: 6 performance + 4 efficiency cores, 16 threads |
| RAM | 32 GB (31.7 GB visible). About 8.6 GB was free after one hour of normal use |
| OS | Windows 11 Education 26200, **domain-joined** (`cite.wa.edu.au`) |
| Virtualisation | Firmware VT-x on, no hypervisor running, VBS off, VMware network adapters present |
| Disk | Assume more than 200 GB free (not measured). Record the free space and disk type in the lab spike |

Budget: reserve **6 GB for Windows itself** (campus agents and browser included), leaving about
**26 GB for VMs**. Estimates; replace them with the spike's measurements.

| VM | Where | vCPU | RAM | Disk (thin) | Runs |
|---|---|---|---|---|---|
| pfSense (+ Squid) | VMware | 1 | 1 GB | 8 GB | Always |
| Windows Server (member) | VMware | 2 | 4 GB | 50 GB | From week 7 |
| Windows 11 client | VMware | 2 | 4 GB | 50 GB | From week 7 |
| Linux client / admin PC | VMware | 2 | 3 GB | 30 GB | Always |
| scanner01 (Greenbone) | VMware | 2 | 6 GB | 40 GB | Scan weeks only; delete the VM afterwards |
| **Proxmox VE** | VMware | 6 | **14 GB** | 120 GB + 40 GB backup disk | Always |
| inside Proxmox: `samba-dc01` | VM | 2 | 2 GB | 25 GB | Always |
| inside Proxmox: `docker01` | VM | 2 | 6 GB | 60 GB | Always |
| inside Proxmox: `authentik01` | VM | 2 | 2.5 GB | 25 GB | Always |
| inside Proxmox: PBS | LXC | 1 | 1.5 GB | 8 GB + 40 GB datastore | Always |
| Proxmox host overhead | n/a | n/a | 1.5 GB | n/a | n/a |

The guests inside Proxmox total about 12 GB plus 1.5 GB overhead, which fills the 14 GB. There is
no headroom, so:

- **Run only what the week needs.** Windows Server and Windows 11 stay off until week 7. In scan
  weeks, power off the Windows 11 and Linux clients (7 GB) to make room for `scanner01` (6 GB).
- **Lean `docker01`.** OnlyOffice is the heaviest stack. Remove `onlyoffice` from
  `docker_compose_stacks` if RAM is short; nothing else depends on it.
- In Workstation, Edit > Preferences > Memory: choose **Fit all virtual machine memory into
  reserved host RAM**, so a busy lab slows a VM instead of making Windows swap.
- Disks are thin-provisioned (do not preallocate). Allocated totals are about 340 GB, but real use
  stays near 150 GB, which fits the assumed 200 GB. Delete `scanner01` after the scan weeks.
- Keep the 40 GB backup disk as a **separate virtual disk file**, ideally on the external drive,
  so a backup does not share a failure with the thing it protects.
- vCPU total is 13 of 16 threads, which is fine. RAM is the constraint, not CPU.

## Host OS: Windows or Linux

| | Windows host | Linux host |
|---|---|---|
| Prepare for nesting | `scripts\Set-NestedVirtualisation.ps1 -Mode Disable`, restart | Nothing to switch off. Enable VT-x/AMD-V in firmware if needed |
| Check (every class) | `scripts\Set-NestedVirtualisation.ps1` | `scripts/check-nested-virtualisation.sh` |
| Undo | `-Mode Restore` | n/a |

Both print READY or NOT READY and exit 0 or 2. Windows updates and **domain Group Policy** can
switch the protections back on (the reference PC is domain-joined), so run the check at the start
of each class. The Windows script turns off Hyper-V, Memory Integrity and Credential Guard: a
deliberate lab-only trade-off, and WSL 2 and Docker Desktop stop working until `-Mode Restore`.

## Steps

1. **Prepare the host** as in the table above, and confirm READY.
2. **Build the VMware VMs.** pfSense, the clients and Windows Server follow
   [`hypervisor/vms/`](../../hypervisor/vms/) with the shared
   [baseline](../../hypervisor/desktop/baseline.md). Create the Proxmox VM with Debian 12 x64 as
   the guest OS type and **Virtualize Intel VT-x/EPT** ticked.
3. **Install Proxmox VE** from the ISO.
4. **Remove the subscription defaults.** On the Proxmox host, as root:

   ```bash
   ./post-install.sh --dry-run     # read what it will do
   ./post-install.sh --upgrade
   ```

   Script: [`hypervisor/proxmox/host/post-install.sh`](../../hypervisor/proxmox/host/post-install.sh).
5. **Confirm KVM** in the Proxmox shell: `egrep -c '(vmx|svm)' /proc/cpuinfo` is above 0 and the
   node summary shows no KVM warning.
6. **Build the guests inside Proxmox** with Terraform: [`hypervisor/proxmox/README.md`](../../hypervisor/proxmox/README.md). Then install PBS with `guests/pbs-install.sh`.

## Guest placement

`docker01`, `authentik01` and `samba-dc01` are **VMs** (no privileged LXC). LXC is for small
single-purpose services such as PBS. The Squid proxy lives on pfSense
([`pfsense/squid.md`](../../pfsense/squid.md)).

**Set every VM's processor type to `host`** (Terraform does this; do it by hand for any VM you
create yourself). See [`hypervisor/proxmox/README.md`](../../hypervisor/proxmox/README.md#things-that-surprise-people).

## Lab spike results

Reported by the lab owner on a lab PC, 14 October 2026. Everything below works as intended.

| Check | Result |
|---|---|
| Windows host prepared for nesting (`Set-NestedVirtualisation.ps1`) | Confirmed |
| Proxmox VE runs inside VMware Workstation with KVM available | Confirmed |
| LXC container reaches the LAN, pings, and installs packages | Confirmed |
| Linux VM boots inside Proxmox | Confirmed, **after setting the processor type to `host`**. It would not start with the default. Now the default for all VMs |

Not yet reported, so treat as untested on real hardware: `post-install.sh`,
`create-terraform-user.sh`, the Terraform module, `pbs-install.sh`, the Linux-host check script,
Windows Server and the scanner, and the memory figures in the sizing table (record real use).

## Not done yet

See the design's gap table and delivery plan.
