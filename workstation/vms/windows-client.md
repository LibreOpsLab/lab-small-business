# Windows Desktop Client — `win-client01`

| Spec | Value                                       |
| ---- | ------------------------------------------- |
| vCPU | 2                                           |
| RAM  | 4096 MB                                     |
| Disk | 60 GB (thin)                                |
| NIC  | `VMnet2`                                    |
| ISO  | Windows 11 (23H2+)                          |
| IP   | DHCP (`10.10.0.100-199`, served by pfSense) |

Installs unattended from
[`seeds/win-client01/autounattend.xml.example`](seeds/win-client01/autounattend.xml.example) —
Windows Setup's equivalent of the cloud-init seeds used for the Ubuntu hosts (see
[`samba-dc.md`](samba-dc.md#autoinstall) for that mechanism; the answer file itself explains
the Windows-specific parts inline).

Before running `create-vms.ps1`:

```bash
cp workstation/vms/seeds/win-client01/autounattend.xml.example \
   workstation/vms/seeds/win-client01/autounattend.xml
# then edit autounattend.xml and replace REPLACE_ME with a real password
```

`create-vms.ps1` also now configures this VM with UEFI firmware, Secure Boot, and a virtual
TPM 2.0 — Windows 11 Setup hard-requires all three and refuses to install without them, so
without this the VM would fail at the very first Setup screen regardless of the answer file.

VMware Tools (or open-vm-tools equivalent installer bundled with Workstation) should be
installed post-OS-install for clipboard/display integration.

## Post-install

1. Confirm DNS is being served correctly: `Resolve-DnsName lab.internal` should return
   `10.10.0.10`.
2. Run [`samba/scripts/join-windows-client.ps1`](../../samba/scripts/join-windows-client.ps1)
   elevated to join the domain into `OU=Windows,OU=Workstations,OU=LAB`.
3. After reboot and domain logon, CA trust and any other GPO-managed settings apply
   automatically (or force with `gpupdate /force`) — see
   [pki/gpo/deploy-root-ca.ps1](../../pki/gpo/deploy-root-ca.ps1) and
   [docs/PKI.md](../../docs/PKI.md#trust-deployment).

See [docs/StudentLabManual.md](../../docs/StudentLabManual.md) for the exercises students run
from this VM.
