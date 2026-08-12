# WordPress

The lab's business website, at `https://www.lab.internal`. Brought up like every other
application stack via `ansible/roles/docker_engine` (see
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md#6-applications)).

## Automated setup

The `wp-init` one-shot container ([`scripts/wp-init.sh`](scripts/wp-init.sh)) runs on every
`docker compose up`, idempotently: installs WordPress core if not already installed, installs
and activates the [OpenID Connect Generic](https://wordpress.org/plugins/daggerhart-openid-connect-generic/)
plugin, and sets sane permalinks. No manual "five-minute install" wizard required.

## Optional SSO

WordPress SSO via Authentik is opt-in, not automatic on first boot (unlike NextCloud's OIDC,
which is baked into the image's own settings) because the plugin's configuration depends on
Authentik already having generated a client secret. Once
[`authentik/scripts/bootstrap-authentik.sh`](../../authentik/scripts/bootstrap-authentik.sh)
has run:

```bash
./docker/wordpress/scripts/configure-oidc-plugin.sh
```

This wires the plugin to Authentik's `wordpress` OIDC provider
([`authentik/blueprints/oidc-wordpress.yaml`](../../authentik/blueprints/oidc-wordpress.yaml)).
Map roles deliberately afterwards (`IT-Admins` → Administrator, everyone else → a low-privilege
role) via the plugin's settings — it defaults to creating Subscriber accounts for any
authenticated user, which is fine for a lab but worth calling out as a decision, not an
oversight, per [docs/Security.md](../../docs/Security.md#least-privilege--rbac).
