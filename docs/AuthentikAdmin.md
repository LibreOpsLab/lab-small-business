# Authentik — Administration Guide

## Role in the lab

Authentik is the single sign-on layer for web applications. It does **not** hold its own
password database for lab users — human identities live in Samba AD, and Authentik's **LDAP
Source** federates them in. This means password policy, account lockout, and account
disable/enable are all managed once, in AD, and simply take effect everywhere.

## Deployment

Runs as its own Docker Compose project on `authentik01` (`10.10.10.30`):
[`docker/authentik/docker-compose.yml`](../docker/authentik/docker-compose.yml) (server +
worker + PostgreSQL + Redis). Brought up by
[`authentik/scripts/bootstrap-authentik.sh`](../authentik/scripts/bootstrap-authentik.sh),
which also waits for the API to become healthy and applies the blueprints below via the
`ak` management CLI / blueprint import API.

## Blueprints

Authentik blueprints (`authentik/blueprints/*.yaml`) are applied automatically on container
start (mounted into `/blueprints/` per the Compose file) so the identity provider configures
itself declaratively rather than via manual admin-UI clicks:

| Blueprint                                                                    | Purpose                                                                                                                                                   |
| ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`ldap-source.yaml`](../authentik/blueprints/ldap-source.yaml)               | Federates Samba AD as an LDAP Source: bind DN `svc-authentik@lab.internal`, base DN `DC=lab,DC=internal`, group sync every 5 minutes.                     |
| [`groups-roles.yaml`](../authentik/blueprints/groups-roles.yaml)             | Maps synced AD groups (`IT-Admins`, `Docker-Admins`, `Lecturers`, `Students`) to Authentik groups used in policy bindings.                                |
| [`oidc-nextcloud.yaml`](../authentik/blueprints/oidc-nextcloud.yaml)         | OIDC provider + application for NextCloud, `groups` scope mapping included.                                                                               |
| [`oidc-onlyoffice.yaml`](../authentik/blueprints/oidc-onlyoffice.yaml)       | OIDC provider + application for OnlyOffice (used via NextCloud's ONLYOFFICE connector).                                                                   |
| [`oidc-wordpress.yaml`](../authentik/blueprints/oidc-wordpress.yaml)         | OIDC provider + application for WordPress. Opt-in on the app side — see [docker/wordpress/README.md](../docker/wordpress/README.md).                      |
| [`proxy-stirling-pdf.yaml`](../authentik/blueprints/proxy-stirling-pdf.yaml) | Proxy provider (forward-auth) for Stirling PDF, which has no native OIDC support — see [docker/stirling-pdf/README.md](../docker/stirling-pdf/README.md). |
| [`mfa-policy.yaml`](../authentik/blueprints/mfa-policy.yaml)                 | TOTP-based MFA stage + policy binding, enforced for `IT-Admins` and `Docker-Admins`, optional (prompted, skippable) for `Students`/`Lecturers`.           |

## LDAP source configuration

- **Server URI:** `ldaps://samba-dc01.lab.internal:636` (LDAPS only — the plain `ldap://389`
  listener is firewalled off from `authentik01` at the pfSense LAN rule level; see
  [Security.md](Security.md)).
- **Bind CN:** `CN=svc-authentik,OU=Service-Accounts,OU=LAB,DC=lab,DC=internal`
- **Base DN:** `DC=lab,DC=internal`
- **User object filter:** `(&(objectClass=person)(objectCategory=person))`
- **Group object filter:** `(objectClass=group)`
- **Sync interval:** 5 minutes (Authentik's built-in LDAP sync task)
- **TLS validation:** validates against the lab's Issuing CA chain, bind-mounted read-only into
  the Authentik server/worker containers from `pki/intermediate-ca/certs/ca-chain.cert.pem`.

## OIDC providers

Each application gets its own OIDC provider/client (never share client secrets across apps):

| Application                      | Client type  | Redirect URI                                                             | Scopes                        |
| -------------------------------- | ------------ | ------------------------------------------------------------------------ | ----------------------------- |
| NextCloud (`cloud.lab.internal`) | Confidential | `https://cloud.lab.internal/apps/user_oidc/code`                         | `openid profile email groups` |
| OnlyOffice (`docs.lab.internal`) | Confidential | delegated via NextCloud's ONLYOFFICE app (no direct browser-facing OIDC) | n/a                           |

Client secrets are generated at blueprint-apply time and written to
`authentik/scripts/.generated-secrets/` (gitignored) for the bootstrap script to hand to the
NextCloud Compose `.env` automatically — see
[`bootstrap-authentik.sh`](../authentik/scripts/bootstrap-authentik.sh).

## Role / group mappings

See the table in [oidc-flow.md](../diagrams/oidc-flow.md#claim--group-mapping). Group
membership flows: AD group → Authentik group (via LDAP sync) → `groups` claim in the OIDC
`id_token` → application-side role mapping (e.g. NextCloud's `user_oidc` app maps the
`IT-Admins` claim value to the NextCloud `admin` group via its provider group-mapping setting).

## MFA policy

[`mfa-policy.yaml`](../authentik/blueprints/mfa-policy.yaml) creates a TOTP authenticator
stage and binds it as **required** in the sign-in flow for the `IT-Admins` and `Docker-Admins`
groups, and as **available-but-optional** for everyone else — a deliberate teaching contrast
between enforced and opt-in MFA. Enrollment happens on first login for admins (flow redirects
to the TOTP enrollment stage before granting a session).

## Enrollment flows

Self-service enrollment is intentionally **disabled** — this lab represents a managed
organisation where accounts are provisioned by IT (via `samba/scripts/create-users.sh`), not a
public SaaS. The default `default-source-enrollment` flow is left in place but unbound from any
Source, so it's inert; this is documented so students can see the difference between "disabled"
and "removed" as a security posture choice.

## Recovery procedures

- **Lost admin access to Authentik itself:** Authentik's own `akadmin` bootstrap superuser
  (created from `AUTHENTIK_BOOTSTRAP_PASSWORD` / `AUTHENTIK_BOOTSTRAP_TOKEN` in
  [`docker/authentik/.env.example`](../docker/authentik/.env.example)) is **not** LDAP-backed
  and always works, even if AD is down — this is the designed break-glass path. Keep its
  password in the secrets manager described in [Security.md](Security.md).
- **User locked out / MFA device lost:** as `akadmin`, go to Directory → Users → select user →
  "Reset MFA devices". The underlying AD password itself is reset via
  `samba-tool user setpassword` (see [SambaAdmin.md](SambaAdmin.md)) since Authentik never
  stores it.
- **LDAP source broken (AD unreachable):** federated logins fail closed (Authentik will not
  cache AD credentials); only `akadmin` can sign in until Samba AD/network is restored. This is
  intentional — see the fail-closed rationale in [Security.md](Security.md).
- **Full Authentik restore:** see [Backup.md](Backup.md#authentik) — PostgreSQL dump +
  Compose volume restore, then blueprints re-apply automatically on next container start
  because they are declarative/idempotent.
