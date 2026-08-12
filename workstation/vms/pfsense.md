# pfSense — `pfsense01`

| Spec   | Value                                       |
| ------ | ------------------------------------------- |
| vCPU   | 2                                           |
| RAM    | 2048 MB                                     |
| Disk   | 20 GB (thin)                                |
| NIC 1  | `VMnet8` (WAN, NAT)                         |
| NIC 2  | `VMnet-LAB` (LAN)                           |
| ISO    | pfSense CE (latest stable)                  |
| LAN IP | `10.10.0.1/24` (static, set during install) |
| WAN    | DHCP from VMware NAT                        |

## Install (manual — no unattended installer available for pfSense on Workstation)

1. Boot from ISO, run the installer with default ZFS/UFS choice (UFS is fine for a lab).
2. At "Assign Interfaces": WAN = the NIC on `VMnet8`, LAN = the NIC on `VMnet-LAB`.
3. Set LAN IPv4 address to `10.10.0.1/24`, do **not** enable LAN DHCP yet (config import in
   the next step sets the full DHCP scope).
4. Reboot into the installed system.

## Post-install

1. From the console or GUI (`https://10.10.0.1`), go to **Diagnostics > Backup & Restore >
   Restore** and import [`pfsense/config/config.xml.template`](../../pfsense/config/config.xml.template)
   after filling in its placeholders (see [`pfsense/README.md`](../../pfsense/README.md)).
2. Run [`pfsense/scripts/pfsense-post-install.sh`](../../pfsense/scripts/pfsense-post-install.sh)
   over SSH for anything not expressible in `config.xml` (package installs).

See [docs/DeploymentGuide.md](../../docs/DeploymentGuide.md#2-pfsense) for the full sequence
in context.
