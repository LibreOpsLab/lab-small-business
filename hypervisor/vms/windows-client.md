# Windows Desktop Client — `win-client01`

| Spec | Value                                        |
| ---- | -------------------------------------------- |
| vCPU | 2                                            |
| RAM  | 4096 MB                                      |
| Disk | 60 GB (thin)                                 |
| NIC  | LAN Segment `LAN-LAB`                        |
| ISO  | Windows 11 (23H2+)                           |
| IP   | DHCP (`10.10.10.100-199`, served by pfSense) |

## Build + install

1. In VMware Workstation/Fusion's New Virtual Machine wizard, select **Windows 11 x64** as the
   guest OS — this makes Workstation/Fusion automatically enable UEFI firmware, Secure Boot, and
   add a virtual TPM 2.0 device, all three of which Windows 11 Setup hard-requires and refuses to
   install without. Verify under VM Settings before booting if you picked a generic/other guest
   OS type instead. 2 vCPU, 4096 MB RAM, 60 GB disk (thin provisioned), Windows 11 ISO attached,
   single NIC on `LAN-LAB`.
2. Install interactively — Windows Setup's normal graphical flow (unattended installs are out of
   scope for this lab). It gets a DHCP lease from pfSense.
3. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing.

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
