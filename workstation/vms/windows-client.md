# Windows Desktop Client — `win-client01`

| Spec | Value                                       |
| ---- | ------------------------------------------- |
| vCPU | 2                                           |
| RAM  | 4096 MB                                     |
| Disk | 60 GB (thin)                                |
| NIC  | `VMnet-LAB`                                 |
| ISO  | Windows 11 (23H2+)                          |
| IP   | DHCP (`10.10.0.100-199`, served by pfSense) |

Install interactively. VMware Tools (or open-vm-tools equivalent installer bundled with
Workstation) should be installed post-OS-install for clipboard/display integration.

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
