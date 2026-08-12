# Security Requirements & Posture

This is a teaching lab, not a production system exposed to the internet — but it is built to
demonstrate real controls rather than skip them for convenience.

## Least privilege / RBAC

- `administrator` (Domain Admin) is a break-glass account only. Day-to-day AD administration
  uses named accounts added to the `IT-Admins` group, which is granted delegated rights over
  the `OU=LAB` subtree (not full Domain Admin) via `samba-tool` ACL delegation — see
  [`samba/scripts/create-ous.sh`](../samba/scripts/create-ous.sh) for the `dsacls` delegation
  commands.
- Service accounts (`svc-authentik`, `svc-nextcloud`) are plain `Domain Users` with no group
  memberships, scoped to exactly the operation they perform (LDAP bind, SMTP relay).
  `svc-authentik` cannot write to AD — the LDAP source is bind-only, read access.
- `Docker-Admins` maps to the Traefik dashboard and Portainer (if enabled) via Authentik's OIDC
  group claim — see [oidc-flow.md](../diagrams/oidc-flow.md).
- Container-level: every service in `docker/*/docker-compose.yml` runs as a non-root user where
  the upstream image supports it, and `no-new-privileges:true` is set on all services.

## Certificate validation

- All internal HTTPS/LDAPS endpoints use certificates from the lab's own Issuing CA — no
  self-signed, no `insecure_skip_verify`. Root/Issuing CA chain is distributed to every trust
  store (GPO, `update-ca-certificates`, Docker bind-mounts) — see [PKI.md](PKI.md).
- Authentik's LDAP source and Dovecot's LDAP auth both validate the DC's certificate against
  the mounted CA chain rather than disabling TLS verification.
- Traefik ([`docker/reverse-proxy/traefik/traefik.yml`](../docker/reverse-proxy/traefik/traefik.yml))
  terminates TLS with the issued `*.lab.local` service certs, redirects all HTTP → HTTPS, and
  sets `minVersion: VersionTLS12`.

## MFA

Enforced for `IT-Admins` and `Docker-Admins` via Authentik's TOTP stage; optional for
`Students`/`Lecturers`. See [AuthentikAdmin.md](AuthentikAdmin.md#mfa-policy).

## Secure cookie settings

Authentik's Compose env sets `AUTHENTIK_COOKIE_DOMAIN=lab.local`,
`AUTHENTIK_SESSION_STORAGE=cache` with Redis-backed sessions, and Traefik injects
`Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, and `X-Frame-Options: SAMEORIGIN`
headers via the `security-headers` middleware in
[`docker/reverse-proxy/traefik/dynamic.yml`](../docker/reverse-proxy/traefik/dynamic.yml).
NextCloud's `overwriteprotocol=https` and `trusted_proxies` are set so it correctly marks its
own session cookies `Secure`.

## Firewall recommendations (pfSense)

Baseline rules (see [`pfsense/config/config.xml.template`](../pfsense/config/config.xml.template)
and [`pfsense/README.md`](../pfsense/README.md)):

| Rule                      | Source                   | Destination      | Ports                                                    | Action                                            |
| ------------------------- | ------------------------ | ---------------- | -------------------------------------------------------- | ------------------------------------------------- |
| LAN → DC                  | LAN net                  | `10.10.0.10`     | 53, 88, 123, 135, 137-139, 389, 445, 464, 636, 3268-3269 | allow                                             |
| LAN → Docker apps         | LAN net                  | `10.10.0.20`     | 80, 443                                                  | allow                                             |
| LAN → Authentik           | LAN net                  | `10.10.0.30`     | 443                                                      | allow                                             |
| Client LDAP (plain) block | `10.10.0.30` (Authentik) | `10.10.0.10:389` | 389                                                      | **block** (forces LDAPS)                          |
| LAN → WAN                 | LAN net                  | any              | 443, 80, 53                                              | allow (outbound only, for updates/DNS forwarding) |
| default deny              | any                      | any              | any                                                      | deny + log                                        |

Anti-lockout rule for the pfSense GUI itself is left in place per pfSense defaults. All rules
are logged for the [Troubleshooting.md](Troubleshooting.md) log-review workflow.

## Host hardening (Ansible `common` role)

[`ansible/roles/common`](../ansible/roles/common) applies to every Linux host:

- SSH: `PermitRootLogin no`, `PasswordAuthentication no` (key-based only), non-standard `Port`
  optional (left at 22 by default for lab simplicity, documented as a hardening exercise for
  students in [StudentLabManual.md](StudentLabManual.md)).
- `unattended-upgrades` enabled for security patches.
- `ufw` enabled with default-deny inbound, explicit allows per role (see each role's
  `tasks/main.yml`).
- Kernel: `net.ipv4.conf.all.rp_filter=1`, `net.ipv4.tcp_syncookies=1` via
  `ansible/roles/common/templates/99-lab-hardening.conf.j2` sysctl drop-in.
- NTP: all hosts sync against `samba-dc01` (which itself is authoritative — Samba AD requires
  tight clock sync for Kerberos), rather than public NTP, to keep the domain self-contained.

## Fail2Ban

[`ansible/roles/fail2ban`](../ansible/roles/fail2ban) installs and configures Fail2Ban on
`docker01` (protecting Traefik's auth-adjacent endpoints and SSH) and `authentik01` (protecting
SSH and, via a custom filter in
[`ansible/roles/fail2ban/templates/authentik.conf.j2`](../ansible/roles/fail2ban/templates/authentik.conf.j2),
repeated failed-login patterns in Authentik's structured JSON log). Samba AD is intentionally
**not** given Fail2Ban — AD's own account-lockout policy
(`samba-tool domain passwordsettings set --account-lockout-threshold=5`) is the correct control
there; layering Fail2Ban on Kerberos/LDAP traffic risks false-positive lockouts of legitimate
domain traffic from NAT'd sources, which is worth discussing as a design decision with students.

## Secrets management

This lab does not run a dedicated secrets manager (Vault, etc.) — that's a reasonable extension
exercise, not baseline scope. Instead:

- Ansible secrets (join passwords, service-account passwords, Authentik bootstrap token) are
  stored in `ansible/inventory/host_vars/*/vault.yml`, encrypted with **Ansible Vault**
  (`ansible-vault encrypt`). Only `vault.yml.example` (placeholder values) is committed; real
  `vault.yml` files are gitignored.
- Docker Compose secrets use `.env` files, never committed (`*.env.example` templates are
  committed instead) — see each stack under `docker/`.
- The PKI Root CA private key is the one piece of material meant to leave the repo's runtime
  footprint entirely (moved to offline storage) — see [PKI.md](PKI.md).
- No plaintext credentials appear in this repository; every script that needs one prompts
  interactively, reads from an Ansible Vault variable, or reads from a gitignored `.env`.
