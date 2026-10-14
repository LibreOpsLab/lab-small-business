# Domain Join

Every Windows and Linux machine in the lab joins `LAB.INTERNAL`. One directory, one set of
accounts, one place to disable a leaver and one place to apply policy. A machine outside the
domain is a machine nobody is managing.

## What joins, and how

| Machine | OS | Method | Computer OU |
|---|---|---|---|
| `samba-dc01` | Linux | **Is** the domain: [`bootstrap-ad.sh`](../samba/scripts/bootstrap-ad.sh) | `Domain Controllers` |
| `docker01`, `authentik01` | Ubuntu | Ansible: [`04-linux-client-join.yml`](../ansible/playbooks/04-linux-client-join.yml) | `OU=Linux,OU=Servers` |
| `pbs01` (Proxmox guest) | Debian LXC | Same Ansible playbook, once uncommented in the inventory | `OU=Linux,OU=Servers` |
| `scanner01` | Ubuntu | Same Ansible playbook, once uncommented in the inventory | `OU=Linux,OU=Servers` |
| `linux-client01` | Ubuntu Desktop | Interactive: [`join-linux-client.sh`](../samba/scripts/join-linux-client.sh) | `OU=Linux,OU=Workstations` |
| `win-client01` | Windows 11 | PowerShell: [`join-windows-client.ps1`](../samba/scripts/join-windows-client.ps1) | `OU=Windows,OU=Workstations` |
| `winsrv01` | Windows Server | Same script with `-TargetOU` for servers: [`windows-server.md`](../hypervisor/vms/windows-server.md) | `OU=Windows,OU=Servers` |
| Proxmox web interface | Proxmox | Login realm (below). The host is not "joined" | n/a |

**Why two methods?** Ansible joins the machines that are already under Ansible's control, because
there are several of them and it can repeat the join. Machines with a person at the keyboard are
joined by hand, where seeing the steps is the point. Windows is joined with PowerShell rather
than Ansible over WinRM: it needs no extra remote-management setup, and a Windows join is one
command.

## Automating the Linux joins

[`sssd_client`](../ansible/roles/sssd_client/tasks/main.yml) installs SSSD, realmd and the
Kerberos client, runs `realm join` with the OU for that host group, writes the lab's
`sssd.conf`, and turns on home-directory creation. It works on Ubuntu and Debian, and inside an
unprivileged LXC container.

To add a Proxmox guest or the scanner:

1. Build it (Terraform for `pbs01`; by hand for `scanner01`).
2. Uncomment it, and its group under `[linux_clients:children]`, in
   [`inventory/hosts.ini`](../ansible/inventory/hosts.ini). They are commented out so the base lab
   never waits on a machine a VMware-only build does not have.
3. Copy `host_vars/<host>/vault.yml.example` to `vault.yml`, fill it in, and encrypt it.
4. Run the playbooks in order, limited to the new host:

   ```bash
   ansible-playbook playbooks/00-common-hardening.yml -l pbs01 --ask-vault-pass
   ansible-playbook playbooks/04-linux-client-join.yml -l pbs01 --ask-vault-pass
   ansible-playbook playbooks/05-pki-trust.yml -l pbs01 --ask-vault-pass
   ansible-playbook playbooks/07-logging.yml -l pbs01 --ask-vault-pass
   ```

Re-running is safe: a host that is already joined is left alone.

> **LXC and the firewall.** The `common` role enables `ufw`. Whether `ufw` works inside an
> unprivileged LXC container has not been tested in this lab. If that task fails, use Proxmox's
> own firewall for the container instead and skip the `ufw` tasks for that host.

## Proving it worked

Three independent checks, because a join can fail in three different ways:

| Check | Where | Proves |
|---|---|---|
| `ansible-playbook playbooks/10-verify-ad-join.yml` | Control host | Each Linux host is enrolled, can look up a domain user, and shows its clock offset |
| `sudo samba/scripts/check-joins.sh` | `samba-dc01` | The DC has a computer account for **every** machine, Windows and Linux, joined by any method |
| Sign in as a domain user | Each machine | The real test: a person can log in with a domain account |

`check-joins.sh --require PBS01` makes an optional machine required.

## Proxmox web interface logins

Add the domain as a login realm so staff sign in to Proxmox with their domain accounts, and
access is removed when the account is. Datacenter > Permissions > Realms > Add > Active
Directory:

- Domain `lab.internal`, server `samba-dc01.lab.internal`.
- Use LDAPS with certificate verification on, and the lab CA chain as the trusted CA. Do not
  disable verification. The DC needs a certificate from the lab PKI first
  ([`docs/PKI.md`](PKI.md)).
- Add a bind user with no group memberships, as the other service accounts are.

Then grant a **domain group** a role at Datacenter > Permissions, so access follows group
membership rather than individual names. Field names move between Proxmox versions; follow the
current Proxmox documentation for the realm dialog.

## Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| `realm join` cannot find the domain | DNS not pointing at the DC | `host -t SRV _kerberos._udp.lab.internal` |
| "Clock skew too great" | Time differs by more than five minutes | `chronyc tracking`; see the clock panel in [Monitoring.md](Monitoring.md) |
| Join works, `getent passwd` finds nobody | SSSD cannot reach LDAP, or the cache is stale | `journalctl -u sssd`, `sss_cache -E` |
| Windows: "domain could not be contacted" | The client's DNS is not the DC | `Resolve-DnsName lab.internal` |
| Account already exists | A rebuilt machine reuses the name | Delete the old computer account: `samba-tool computer delete <NAME>` |

More in [Troubleshooting.md](Troubleshooting.md).

## Gotchas

- **A rebuilt machine needs its old account removed**, or the join reports the account already
  exists. Treat "delete the stale computer object" as part of any rebuild.
- **Join credentials are powerful.** The join account is in each host's vault. In a production
  domain you would delegate "join computers" to a service account with no other rights.
- **Joined does not mean hardened.** Domain membership gives you central accounts. Apply
  [CIS hardening](CISHardening.md) and [monitoring](Monitoring.md) as well.
