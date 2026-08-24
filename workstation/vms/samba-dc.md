# Samba AD DC — `samba-dc01`

| Spec                 | Value                                                             |
| -------------------- | ----------------------------------------------------------------- |
| vCPU                 | 2                                                                 |
| RAM                  | 4096 MB                                                           |
| Disk                 | 40 GB (thin)                                                      |
| NIC                  | `VMnet2`                                                          |
| ISO                  | Ubuntu Server 24.04 LTS                                           |
| IP                   | `10.10.0.10/24` (static)                                          |
| Gateway              | `10.10.0.1`                                                       |
| DNS (during install) | `127.0.0.1` (will become authoritative for itself post-provision) |

## Autoinstall

Ubuntu Server's `autoinstall` (Subiquity) installs this host with zero prompts, driven by a
seed file `create-vms.ps1` attaches automatically as a second CD-ROM — see
[`workstation/scripts/build-seed-iso.ps1`](../scripts/build-seed-iso.ps1) for how that seed
gets built, and [`seeds/samba-dc01/user-data.example`](seeds/samba-dc01/user-data.example) for
what it contains (heavily commented — worth reading even if you don't need to change it).

Before running `create-vms.ps1`:

```bash
cp workstation/vms/seeds/samba-dc01/user-data.example workstation/vms/seeds/samba-dc01/user-data
cp workstation/vms/seeds/samba-dc01/meta-data.example workstation/vms/seeds/samba-dc01/meta-data
mkpasswd --method=sha-512   # paste the output into user-data's password field
```

The real `user-data`/`meta-data` (no `.example` suffix) are gitignored — they'll contain your
actual password hash, which is not something to commit.

## Post-install

Run [`samba/scripts/bootstrap-ad.sh`](../../samba/scripts/bootstrap-ad.sh) as root — see
[docs/SambaAdmin.md](../../docs/SambaAdmin.md) and
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md#3-samba-ad-domain-controller).
