# Windows Desktop Client — `win-client01`

| Spec | Value                                       |
| ---- | ------------------------------------------- |
| vCPU | 2                                           |
| RAM  | 4096 MB                                     |
| Disk | 60 GB (thin)                                |
| NIC  | LAN Segment `LAN-LAB`                       |
| ISO  | Windows 11 (23H2+)                          |
| IP   | DHCP (`10.10.10.100-199`, served by pfSense) |

Installs unattended from
[`seeds/win-client01/autounattend.xml.example`](seeds/win-client01/autounattend.xml.example) —
Windows Setup's equivalent of the cloud-init seeds used for the Ubuntu hosts (see
[`samba-dc.md`](samba-dc.md#autoinstall) for that mechanism; the answer file itself explains
the Windows-specific parts inline).

Before running `create-vms.ps1` (Windows) or `create-vms.sh` (Linux):

```bash
cp hypervisor/vms/seeds/win-client01/autounattend.xml.example \
   hypervisor/vms/seeds/win-client01/autounattend.xml
# then edit autounattend.xml and replace REPLACE_ME with a real password
```

`create-vms.ps1` also now configures this VM with UEFI firmware, Secure Boot, and a virtual
TPM 2.0 — Windows 11 Setup hard-requires all three and refuses to install without them, so
without this the VM would fail at the very first Setup screen regardless of the answer file.

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

1. Confirm DNS is being served correctly: `Resolve-DnsName lab.internal` should return
   `10.10.10.10`.
2. Run [`samba/scripts/join-windows-client.ps1`](../../samba/scripts/join-windows-client.ps1)
   elevated to join the domain into `OU=Windows,OU=Workstations,OU=LAB`.
3. After reboot and domain logon, CA trust and any other GPO-managed settings apply
   automatically (or force with `gpupdate /force`) — see
   [pki/gpo/deploy-root-ca.ps1](../../pki/gpo/deploy-root-ca.ps1) and
   [docs/PKI.md](../../docs/PKI.md#trust-deployment).

See [docs/StudentLabManual.md](../../docs/StudentLabManual.md) for the exercises students run
from this VM.
