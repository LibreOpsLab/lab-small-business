# Authentik

Declarative Authentik configuration for the lab's SSO layer. See
[docs/AuthentikAdmin.md](../docs/AuthentikAdmin.md) for the full admin guide and
[diagrams/oidc-flow.md](../diagrams/oidc-flow.md) for the authentication sequence.

## Contents

- [`blueprints/`](blueprints/) — declarative Authentik configuration, applied automatically
  on container start and idempotently re-appliable:
  - [`ldap-source.yaml`](blueprints/ldap-source.yaml) — federates Samba AD.
  - [`groups-roles.yaml`](blueprints/groups-roles.yaml) — Authentik-side groups mirroring AD.
  - [`oidc-nextcloud.yaml`](blueprints/oidc-nextcloud.yaml),
    [`oidc-onlyoffice.yaml`](blueprints/oidc-onlyoffice.yaml) — per-application OIDC providers.
  - [`mfa-policy.yaml`](blueprints/mfa-policy.yaml) — TOTP stage + enforcement policy.
- [`scripts/bootstrap-authentik.sh`](scripts/bootstrap-authentik.sh) — brings up the Compose
  stack ([`docker/authentik`](../docker/authentik)), waits for health, applies blueprints, and
  (with `--sync-secrets`) propagates generated OIDC client secrets into consuming apps' `.env`
  files.

## Usage

```bash
cd docker/authentik && cp .env.example .env   # fill in real secrets first
cd ../../authentik/scripts
./bootstrap-authentik.sh --sync-secrets
```

Re-running is safe — blueprints are declarative and generated secrets are cached under
`authentik/scripts/.generated-secrets/` (gitignored) so repeated runs don't rotate client
secrets out from under already-configured applications.
