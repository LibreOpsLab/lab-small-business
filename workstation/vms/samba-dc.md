# Samba AD DC — `samba-dc01`

| Spec | Value |
|---|---|
| vCPU | 2 |
| RAM | 4096 MB |
| Disk | 40 GB (thin) |
| NIC | `VMnet-LAB` |
| ISO | Ubuntu Server 24.04 LTS |
| IP | `10.10.0.10/24` (static) |
| Gateway | `10.10.0.1` |
| DNS (during install) | `127.0.0.1` (will become authoritative for itself post-provision) |

## Autoinstall

Ubuntu Server's `autoinstall` (Subiquity) supports an unattended install via a `user-data`
cloud-init file on a second CD/USB. Minimal example — save as `user-data` on an ISO/USB
alongside an empty `meta-data` file, attach as a second CD-ROM at boot:

```yaml
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: samba-dc01
    username: labadmin
    password: "$6$replace-with-a-mkpasswd-hash"
  network:
    network:
      version: 2
      ethernets:
        ens160:
          addresses: [10.10.0.10/24]
          gateway4: 10.10.0.1
          nameservers:
            addresses: [127.0.0.1]
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - openssh-server
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
```

Generate the password hash with `mkpasswd --method=sha-512` (from the `whois` package).

## Post-install

Run [`samba/scripts/bootstrap-ad.sh`](../../samba/scripts/bootstrap-ad.sh) as root — see
[docs/SambaAdmin.md](../../docs/SambaAdmin.md) and
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md#3-samba-ad-domain-controller).
