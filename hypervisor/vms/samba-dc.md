# Samba AD DC — `samba-dc01`

| Spec                 | Value                                                             |
| -------------------- | ----------------------------------------------------------------- |
| vCPU                 | 2                                                                 |
| RAM                  | 4096 MB                                                           |
| Disk                 | 40 GB (thin)                                                      |
| NIC                  | LAN Segment `LAN-LAB`                                             |
| ISO                  | Ubuntu Server 24.04 LTS                                           |
| IP                   | `10.10.10.10/24` (static)                                         |
| Gateway              | `10.10.10.1`                                                      |
| DNS (during install) | `127.0.0.1` (will become authoritative for itself post-provision) |

## Build + install

1. In VMware Workstation/Fusion, create a new VM per the spec table above: 2 vCPU, 4096 MB RAM,
   40 GB disk (thin provisioned), Ubuntu Server 24.04 LTS ISO attached, single NIC on the
   `LAN-LAB` LAN Segment (already exists once pfSense's second NIC is set up — pick it from the
   dropdown, don't create it again).
2. Install interactively. In Subiquity's network step, set a **static** address:
   `10.10.10.10/24`, gateway `10.10.10.1`, nameserver `127.0.0.1` (this host becomes
   authoritative for itself once Samba AD is provisioned; nothing else exists yet to ask for
   `lab.internal` records). Create the `labadmin` user — it matches `ansible_user` in
   `ansible/inventory/hosts.ini`, so don't rename it without updating the inventory too. On the
   SSH step, install OpenSSH server and paste your public key rather than relying on password
   auth alone.
3. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing.

**On Proxmox**, this VM boots a cloud image instead and is configured by
[`seeds/samba-dc01/proxmox-user-data.example`](seeds/samba-dc01/proxmox-user-data.example). See
[`../proxmox/README.md`](../proxmox/README.md) for why the mechanism differs and what to fill in
before `terraform apply`.

## Post-install

Run [`samba/scripts/bootstrap-ad.sh`](../../samba/scripts/bootstrap-ad.sh) as root — see
[docs/SambaAdmin.md](../../docs/SambaAdmin.md) and
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md#3-samba-ad-domain-controller).
