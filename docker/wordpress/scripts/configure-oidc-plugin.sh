#!/usr/bin/env bash
# Configures the OpenID Connect Generic plugin (installed by wp-init.sh) to use Authentik's
# WordPress OIDC provider. Run this AFTER authentik/scripts/bootstrap-authentik.sh has
# applied authentik/blueprints/oidc-wordpress.yaml (the client secret must exist first).
#
# Usage: ./docker/wordpress/scripts/configure-oidc-plugin.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SECRET_FILE="${REPO_ROOT}/authentik/scripts/.generated-secrets/wordpress-oidc-client-secret"

log() { printf '\033[1;34m[wp-oidc]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[wp-oidc][error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "${SECRET_FILE}" ]] || die "${SECRET_FILE} not found — run authentik/scripts/bootstrap-authentik.sh first (it generates this secret when applying oidc-wordpress.yaml)."
CLIENT_SECRET="$(cat "${SECRET_FILE}")"

log "Configuring the OpenID Connect Generic plugin via wp-cli"
docker compose -f "${REPO_ROOT}/docker/wordpress/docker-compose.yml" run --rm wp-init \
  wp option update openid_connect_generic_settings --format=json --allow-root <<EOF
{
  "login_type": "button",
  "client_id": "wordpress",
  "client_secret": "${CLIENT_SECRET}",
  "scope": "openid email profile groups",
  "endpoint_login": "https://auth.lab.internal/application/o/authorize/",
  "endpoint_userinfo": "https://auth.lab.internal/application/o/userinfo/",
  "endpoint_token": "https://auth.lab.internal/application/o/token/",
  "endpoint_end_session": "https://auth.lab.internal/application/o/wordpress/end-session/",
  "identity_key": "email",
  "nickname_key": "preferred_username",
  "email_format": "{email}",
  "displayname_format": "{name}",
  "identify_with_username": true,
  "enforce_privacy": false,
  "link_existing_users": true,
  "create_if_does_not_exist": true
}
EOF

log "Done. WordPress admin login now offers 'Login with OpenID Connect' — see docs/AuthentikAdmin.md."
log "Note: this grants WordPress accounts to anyone who can authenticate via Authentik. Map"
log "roles deliberately (IT-Admins -> Administrator, everyone else -> Subscriber/Author) via"
log "the plugin's role-mapping settings before treating this as production-ready."
