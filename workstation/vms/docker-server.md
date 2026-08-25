# Docker Application Server — `docker01`

| Spec    | Value                                    |
| ------- | ---------------------------------------- |
| vCPU    | 4                                        |
| RAM     | 8192 MB                                  |
| Disk    | 80 GB (thin) — NextCloud/mail data grows |
| NIC     | LAN Segment `LAN-LAB`                    |
| ISO     | Ubuntu Server 24.04 LTS                  |
| IP      | `10.10.10.20/24` (static)                |
| Gateway | `10.10.10.1`                             |
| DNS     | `10.10.10.10`                            |

Hosts the Traefik reverse proxy plus NextCloud, OnlyOffice, and Dovecot Compose stacks (see
[`docker/`](../../docker/)). Installs unattended from
[`seeds/docker01/user-data.example`](seeds/docker01/user-data.example) — see
[`samba-dc.md`](samba-dc.md#autoinstall) for how the seed-ISO mechanism works and the
`cp`/`mkpasswd` steps you need before running `create-vms.ps1`.

## Post-install

Handled entirely by Ansible — do not install Docker manually. From the control host:

```bash
ansible-playbook ansible/playbooks/00-common-hardening.yml --limit docker01
ansible-playbook ansible/playbooks/04-linux-client-join.yml --limit docker01
ansible-playbook ansible/playbooks/05-pki-trust.yml --limit docker01
ansible-playbook ansible/playbooks/02-docker-server.yml --limit docker01
```

(`site.yml` runs all of these in order for every host in inventory — see
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md#5-docker-application-server--authentik).)
