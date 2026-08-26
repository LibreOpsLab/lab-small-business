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
[`docker/`](../../docker/)).

## Build + install

1. In VMware Workstation/Fusion, create a new VM per the spec table above: 4 vCPU, 8192 MB RAM,
   80 GB disk (thin provisioned), Ubuntu Server 24.04 LTS ISO attached, single NIC on `LAN-LAB`.
2. Install interactively. In Subiquity's network step, set a static address `10.10.10.20/24`,
   gateway `10.10.10.1`, nameserver `10.10.10.10`. Create the `labadmin` user (matches
   `ansible_user` in `ansible/inventory/hosts.ini`). On the SSH step, install OpenSSH server and
   paste your public key.
3. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing.

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
