# Samba Active Directory — Administration Guide

## Domain facts

| Item | Value |
|---|---|
| Domain (DNS) | `lab.local` |
| Realm | `LAB.LOCAL` |
| NetBIOS | `LAB` |
| DC hostname | `samba-dc01.lab.local` (`10.10.0.10`) |
| Functional level | 2016 (`samba-tool domain provision --function-level=2016`) |

## Provisioning

[`samba/scripts/bootstrap-ad.sh`](../samba/scripts/bootstrap-ad.sh) provisions a fresh Ubuntu
24.04 host into a new AD DC in one run:

```bash
sudo ./samba/scripts/bootstrap-ad.sh
```

It: installs `samba`, `krb5-*`, `winbind` packages; removes conflicting `systemd-resolved`
stub resolver binding on :53; runs `samba-tool domain provision` with the realm/domain/NetBIOS
above and `--dns-backend=SAMBA_INTERNAL`; disables and masks the distro `smbd`/`nmbd`/`winbind`
services in favour of the unified `samba-ad-dc` service; installs the generated
`/var/lib/samba/private/krb5.conf` as the system `krb5.conf`; and opens firewall ports via ufw
(88, 135, 137-138/udp, 139, 389, 445, 464, 636, 3268-3269, 53).

## OU structure

Created by [`samba/scripts/create-ous.sh`](../samba/scripts/create-ous.sh):

```text
lab.local
└── OU=LAB
    ├── OU=IT-Admins
    ├── OU=Staff
    │   └── OU=Lecturers
    ├── OU=Students
    ├── OU=Service-Accounts
    └── OU=Workstations
        ├── OU=Linux
        └── OU=Windows
```

Rationale: separating `Workstations/Linux` and `Workstations/Windows` lets GPOs and SSSD/GPO
policy scope cleanly by OS, and `Service-Accounts` keeps non-interactive principals (like
`svc-authentik`) out of the way of user-management GPOs (password expiry, screen-lock, etc).

## Users and groups

Seed data lives in [`samba/data/users.csv`](../samba/data/users.csv) and
[`samba/data/groups.csv`](../samba/data/groups.csv);
[`create-users.sh`](../samba/scripts/create-users.sh) and
[`create-groups.sh`](../samba/scripts/create-groups.sh) are idempotent wrappers around
`samba-tool user create` / `samba-tool group add` + `group addmembers` that read those CSVs.

| Account | OU | Groups | Notes |
|---|---|---|---|
| `administrator` | built-in | `Domain Admins` | Break-glass; day-to-day admin work should use a named `it-*` account added to `IT-Admins` |
| `lecturer01` | Staff/Lecturers | `Lecturers` | Sample teaching-staff account |
| `student01`, `student02` | Students | `Students` | Sample student accounts |
| `svc-authentik` | Service-Accounts | `IT-Admins` (read-only via ACL, see below) | LDAP bind account for Authentik's LDAP source |

Groups: `Students`, `Lecturers`, `IT-Admins`, `Docker-Admins` (mapped to Portainer/Traefik
dashboard access via Authentik's OIDC group claim, see
[oidc-flow.md](../diagrams/oidc-flow.md)).

Default password policy (set by `bootstrap-ad.sh` via `samba-tool domain passwordsettings`):
minimum length 12, complexity required, 24 password history, max age 90 days for `Students`/
`Lecturers` OUs via fine-grained password policy, no expiry for service accounts.

`svc-authentik` is granted **read-only** LDAP bind rights only — it is a regular AD user with
no group memberships beyond the default `Domain Users`; LDAP itself is read-only for bind
accounts unless explicitly delegated, so no additional ACL lockdown is required beyond not
adding it to any privileged group.

## Group Policy recommendations

Not automated (GPMC has no first-class CLI in Samba AD short of `samba-tool gpo`), but
recommended baseline GPOs to create via RSAT from a Windows admin workstation:

1. **Default Domain Policy** — password policy already enforced via `samba-tool`; leave as-is.
2. **Root CA Trust** — deployed by [`pki/gpo/deploy-root-ca.ps1`](../pki/gpo/deploy-root-ca.ps1).
3. **Workstation Lock Screen** — 15-minute idle lock, applied to `OU=Windows`.
4. **Students — Restricted** — remove local admin rights, disable Control Panel access,
   applied to `OU=Students`. Useful teaching example of GPO security filtering.

`samba-tool gpo list`, `samba-tool gpo backup`, and `samba-tool gpo restore` are used for
exporting/importing these once created — see the backup section below.

## Linux client integration (SSSD)

[`samba/scripts/join-linux-client.sh`](../samba/scripts/join-linux-client.sh) installs
`sssd`, `sssd-tools`, `realmd`, `adcli`, `krb5-user`, `packagekit`; runs
`realm join --client-software=sssd lab.local -U administrator`; then overlays
[`samba/templates/sssd.conf.j2`](../samba/templates/sssd.conf.j2)-derived config to enable
`enumerate = true` (so students can browse group membership locally, deliberately
teaching-friendly — disable for production) and `use_fully_qualified_names = false` so `whoami`
shows `student01` rather than `student01@lab.local`. Home directories are auto-created via
`pam_mkhomedir` (enabled through `pam-auth-update`).

## Windows client integration

[`samba/scripts/join-windows-client.ps1`](../samba/scripts/join-windows-client.ps1) wraps
`Add-Computer -DomainName lab.local -OUPath "OU=Windows,OU=Workstations,OU=LAB,DC=lab,DC=local"
-Restart`, run from an elevated PowerShell prompt on the Windows client after confirming DNS
resolves `lab.local` to `10.10.0.10` (`Resolve-DnsName lab.local`).

## DNS

Samba's internal DNS (`SAMBA_INTERNAL` backend) is authoritative for `lab.local`. Forward zone
`.` is delegated to pfSense's Unbound resolver (`10.10.0.1`) so domain members still resolve
public names — configured via `dns forwarder = 10.10.0.1` in
[`samba/templates/smb.conf.j2`](../samba/templates/smb.conf.j2). See
[dns-architecture.md](../diagrams/dns-architecture.md) for the full record set. Manage records
with `samba-tool dns add/delete samba-dc01 lab.local <name> <type> <data> -U administrator`.

## Backup & restore

[`samba/scripts/backup-ad.sh`](../samba/scripts/backup-ad.sh) runs
`samba-tool domain backup online --server=localhost --targetdir=/var/backups/samba-ad/<date>`
(full DC backup: SYSVOL, DB, secrets) on a daily timer, retaining the last 14 days, and also
exports `samba-tool gpo backup` for every GPO found. See [Backup.md](Backup.md) for restore
procedure via `samba-tool domain backup restore`.

## Health checks

[`samba/scripts/health-check.sh`](../samba/scripts/health-check.sh) runs (and reports
pass/fail for each): `samba-tool dbcheck`, `samba-tool drs showrepl`, `samba_dnsupdate
--verbose --all-names` (dry-run), `kinit administrator` ticket test, and `smbclient -L
localhost -U% -N` to confirm the share list responds. Intended to run from cron/Ansible as a
smoke test after provisioning or restore.
