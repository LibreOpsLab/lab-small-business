# Authentik IAM — `authentik01`

| Spec    | Value                    |
| ------- | ------------------------ |
| vCPU    | 2                        |
| RAM     | 4096 MB                  |
| Disk    | 40 GB (thin)             |
| NIC     | `VMnet2`                 |
| ISO     | Ubuntu Server 24.04 LTS  |
| IP      | `10.10.0.30/24` (static) |
| Gateway | `10.10.0.1`              |
| DNS     | `10.10.0.10`             |

Kept on its own VM (rather than co-located on `docker01`) so the identity plane's failure
domain is isolated from the application plane — see
[docs/Architecture.md#trade-offs-and-scope](../../docs/Architecture.md#trade-offs-and-scope).
Installs unattended from
[`seeds/authentik01/user-data.example`](seeds/authentik01/user-data.example) — see
[`samba-dc.md`](samba-dc.md#autoinstall) for how the seed-ISO mechanism works.

## Post-install

```bash
ansible-playbook ansible/playbooks/00-common-hardening.yml --limit authentik01
ansible-playbook ansible/playbooks/04-linux-client-join.yml --limit authentik01
ansible-playbook ansible/playbooks/05-pki-trust.yml --limit authentik01
ansible-playbook ansible/playbooks/03-authentik.yml --limit authentik01
```

See [docs/AuthentikAdmin.md](../../docs/AuthentikAdmin.md).
