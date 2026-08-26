# Authentik IAM — `authentik01`

| Spec    | Value                     |
| ------- | ------------------------- |
| vCPU    | 2                         |
| RAM     | 4096 MB                   |
| Disk    | 40 GB (thin)              |
| NIC     | LAN Segment `LAN-LAB`     |
| ISO     | Ubuntu Server 24.04 LTS   |
| IP      | `10.10.10.30/24` (static) |
| Gateway | `10.10.10.1`              |
| DNS     | `10.10.10.10`             |

Kept on its own VM (rather than co-located on `docker01`) so the identity plane's failure
domain is isolated from the application plane — see
[docs/Architecture.md#trade-offs-and-scope](../../docs/Architecture.md#trade-offs-and-scope).

## Build + install

1. In VMware Workstation/Fusion, create a new VM per the spec table above: 2 vCPU, 4096 MB RAM,
   40 GB disk (thin provisioned), Ubuntu Server 24.04 LTS ISO attached, single NIC on `LAN-LAB`.
2. Install interactively. In Subiquity's network step, set a static address `10.10.10.30/24`,
   gateway `10.10.10.1`, nameserver `10.10.10.10`. Create the `labadmin` user (matches
   `ansible_user` in `ansible/inventory/hosts.ini`). On the SSH step, install OpenSSH server and
   paste your public key.
3. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) before continuing.

## Post-install

```bash
ansible-playbook ansible/playbooks/00-common-hardening.yml --limit authentik01
ansible-playbook ansible/playbooks/04-linux-client-join.yml --limit authentik01
ansible-playbook ansible/playbooks/05-pki-trust.yml --limit authentik01
ansible-playbook ansible/playbooks/03-authentik.yml --limit authentik01
```

See [docs/AuthentikAdmin.md](../../docs/AuthentikAdmin.md).
