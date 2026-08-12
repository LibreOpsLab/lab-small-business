# lab-small-business

A self-contained, Infrastructure-as-Code homelab that simulates a small organisation's IT
estate on a single VMware Workstation host: perimeter firewall, Active Directory, an internal
PKI, an IAM/SSO platform, containerised applications, and both Windows and Linux endpoints.
Built for repeatable deployment and hands-on sysadmin/DevOps teaching.

## What's in the box

| Layer | Technology |
|---|---|
| Perimeter firewall / DHCP / DNS forwarder | pfSense |
| Directory / Kerberos / LDAP / DNS / NTP | Samba Active Directory |
| Identity federation / SSO | Authentik (LDAP source + OIDC) |
| Application host | Docker Engine + Traefik reverse proxy |
| Applications | NextCloud, OnlyOffice, Dovecot (IMAP) |
| Internal PKI | Two-tier OpenSSL CA (offline Root + online Issuing CA) |
| Endpoints | Ubuntu Desktop (SSSD) + Windows 11 (native AD) |
| Automation | Bash, Ansible, Docker Compose, PowerShell |

Domain: `lab.local` / realm `LAB.LOCAL` / NetBIOS `LAB`, on `10.10.0.0/24`. Full addressing
and component inventory: [docs/Architecture.md](docs/Architecture.md).

## Start here

1. [docs/Architecture.md](docs/Architecture.md) — component inventory, network diagram, design
   principles, and the trade-offs behind them.
2. [docs/DeploymentGuide.md](docs/DeploymentGuide.md) — the full, ordered bring-up sequence
   from bare VMware Workstation host to a working lab.
3. [docs/StudentLabManual.md](docs/StudentLabManual.md) — what to do once it's up, if you're
   learning from this lab rather than building it.

## Repository layout

```text
repo-root/
├── docs/           Architecture, deployment, admin, and student documentation
├── diagrams/        Mermaid source for network/auth/PKI/OIDC/DNS diagrams
├── workstation/     VMware Workstation VM inventory, network config, provisioning notes
├── pfsense/         pfSense config.xml template + post-install hardening script
├── samba/           samba-tool automation: AD provisioning, users, groups, OUs, backup
├── pki/             Two-tier internal CA: root/intermediate init, issuance, renewal, revocation
├── docker/          Docker Compose stacks: reverse proxy, Authentik, NextCloud, OnlyOffice, mail
├── authentik/       Authentik blueprints (LDAP source, OIDC providers, groups, MFA) + bootstrap
├── ansible/         Playbooks and roles that tie every component together
├── scripts/         Top-level orchestration entry points (deploy-all.sh, issue-cert.sh, ...)
└── templates/       Shared Jinja2 templates (motd, hosts)
```

## Documentation index

| Doc | Covers |
|---|---|
| [Architecture.md](docs/Architecture.md) | Component inventory, design principles, trade-offs |
| [DeploymentGuide.md](docs/DeploymentGuide.md) | Ordered, repeatable bring-up procedure |
| [PKI.md](docs/PKI.md) | Two-tier CA design, issuance, renewal, revocation, trust distribution |
| [SambaAdmin.md](docs/SambaAdmin.md) | AD provisioning, OUs, users/groups, DNS, backup, health checks |
| [AuthentikAdmin.md](docs/AuthentikAdmin.md) | LDAP source, OIDC providers, MFA, recovery |
| [Security.md](docs/Security.md) | RBAC, cert validation, firewall rules, hardening, Fail2Ban, secrets |
| [Backup.md](docs/Backup.md) | Backup/restore for AD, Authentik, Docker volumes, PKI, config |
| [Troubleshooting.md](docs/Troubleshooting.md) | DNS, Kerberos, LDAP, certs, OIDC, Docker/proxy issues |
| [StudentLabManual.md](docs/StudentLabManual.md) | Day-1 checklist and hands-on exercises |

## Diagrams

[Network Topology](diagrams/network-topology.md) ·
[Authentication Flow](diagrams/auth-flow.md) ·
[Certificate Trust Chain](diagrams/cert-trust-chain.md) ·
[OIDC Authentication Flow](diagrams/oidc-flow.md) ·
[DNS Architecture](diagrams/dns-architecture.md)

## Quick start

```bash
# 1. Networking + VMs (Windows host, elevated PowerShell)
workstation\scripts\configure-vmnet.ps1
workstation\scripts\create-vms.ps1

# 2. pfSense, Samba AD, endpoints — see docs/DeploymentGuide.md for the full sequence
#    (pfSense install and OS installs are interactive; everything after is scripted)

# 3. PKI + identity + application layers, once VMs exist and are reachable over SSH
make pki-init
make pki-issue-all
make deploy   # wraps scripts/deploy-all.sh: runs ansible/playbooks/site.yml end to end
```

See [docs/DeploymentGuide.md](docs/DeploymentGuide.md) for the complete step-by-step, including
the manual steps that have no scriptable equivalent (pfSense install, Windows install).

## Security posture

This is a teaching lab, not a hardened production system — but it implements real controls
rather than skipping them: least-privilege delegation (not `Domain Admins` for day-to-day
work), MFA for privileged groups, an internal PKI with no disabled certificate validation
anywhere, a default-deny firewall posture, and Vault-encrypted secrets. See
[docs/Security.md](docs/Security.md) for the full posture and the reasoning behind each choice.

## License

MIT — see [LICENSE](LICENSE).
