#!/usr/bin/env bash
# Brings up the Authentik Compose stack, waits for it to become healthy, and applies the
# blueprints in authentik/blueprints/ via the API. Also (with --sync-secrets) reads back the
# generated OIDC client secrets and writes them into the consuming apps' .env files so
# NextCloud/OnlyOffice pick them up on next restart.
#
# Usage:
#   ./bootstrap-authentik.sh                # bring up + apply blueprints
#   ./bootstrap-authentik.sh --sync-secrets  # also sync OIDC secrets into docker/nextcloud/.env

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AUTHENTIK_DIR="${REPO_ROOT}/docker/authentik"
SECRETS_DIR="${SCRIPT_DIR}/.generated-secrets"

log()  { printf '\033[1;34m[bootstrap-authentik]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[bootstrap-authentik][error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "${AUTHENTIK_DIR}/.env" ]] || die "${AUTHENTIK_DIR}/.env not found — copy .env.example to .env and fill in secrets first (see docs/Security.md#secrets-management)."

mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

gen_secret() {
  local name="$1"
  local file="${SECRETS_DIR}/${name}"
  if [[ ! -f "${file}" ]]; then
    openssl rand -base64 36 > "${file}"
    chmod 600 "${file}"
    log "Generated new secret: ${name}"
  fi
  cat "${file}"
}

export NEXTCLOUD_OIDC_CLIENT_SECRET="$(gen_secret nextcloud-oidc-client-secret)"
export ONLYOFFICE_OIDC_CLIENT_SECRET="$(gen_secret onlyoffice-oidc-client-secret)"
export WORDPRESS_OIDC_CLIENT_SECRET="$(gen_secret wordpress-oidc-client-secret)"
export AUTHENTIK_LDAP_BIND_PASSWORD="${AUTHENTIK_LDAP_BIND_PASSWORD:-$(gen_secret ldap-bind-password)}"
# Stirling PDF is protected via an Authentik Proxy Provider + forward-auth (see
# authentik/blueprints/proxy-stirling-pdf.yaml), not an OIDC client secret embedded in the
# app itself, so it needs no gen_secret entry here.

log "Bringing up the Authentik Compose stack (docker/authentik)"
docker compose -f "${AUTHENTIK_DIR}/docker-compose.yml" --env-file "${AUTHENTIK_DIR}/.env" up -d

log "Waiting for Authentik API to become healthy..."
for i in $(seq 1 60); do
  if curl -ksf https://auth.lab.internal/-/health/live/ >/dev/null 2>&1 || \
     docker compose -f "${AUTHENTIK_DIR}/docker-compose.yml" exec -T server ak healthcheck >/dev/null 2>&1; then
    log "Authentik is healthy."
    break
  fi
  [[ "$i" -eq 60 ]] && die "Authentik did not become healthy in time — check: docker compose -f ${AUTHENTIK_DIR}/docker-compose.yml logs server"
  sleep 5
done

log "Blueprints are mounted read-only at /blueprints and auto-applied by the server on the
interval configured in AUTHENTIK_BLUEPRINTS_DIR polling (default: on startup + every 60s for
changed files). Forcing an immediate reconciliation pass:"
docker compose -f "${AUTHENTIK_DIR}/docker-compose.yml" exec -T worker \
  ak apply_blueprint /blueprints/ldap-source.yaml \
                       /blueprints/groups-roles.yaml \
                       /blueprints/oidc-nextcloud.yaml \
                       /blueprints/oidc-onlyoffice.yaml \
                       /blueprints/oidc-wordpress.yaml \
                       /blueprints/proxy-stirling-pdf.yaml \
                       /blueprints/mfa-policy.yaml

if [[ "${1:-}" == "--sync-secrets" ]]; then
  NEXTCLOUD_ENV="${REPO_ROOT}/docker/nextcloud/.env"
  ONLYOFFICE_ENV="${REPO_ROOT}/docker/onlyoffice/.env"
  [[ -f "${NEXTCLOUD_ENV}" ]] || die "${NEXTCLOUD_ENV} not found — copy .env.example first."

  log "Syncing NEXTCLOUD_OIDC_CLIENT_SECRET into ${NEXTCLOUD_ENV}"
  sed -i.bak "s|^NEXTCLOUD_OIDC_CLIENT_SECRET=.*|NEXTCLOUD_OIDC_CLIENT_SECRET=${NEXTCLOUD_OIDC_CLIENT_SECRET}|" "${NEXTCLOUD_ENV}"

  if [[ -f "${ONLYOFFICE_ENV}" ]]; then
    log "OnlyOffice secret is JWT-based (ONLYOFFICE_JWT_SECRET), not OIDC-consumed directly — no sync needed there."
  fi

  rm -f "${NEXTCLOUD_ENV}.bak"
  log "Secrets synced. Restart the NextCloud stack to pick them up: docker compose -f docker/nextcloud/docker-compose.yml up -d"
fi

log "Bootstrap complete. Admin login: https://auth.lab.internal (user: akadmin, password: from AUTHENTIK_BOOTSTRAP_PASSWORD in docker/authentik/.env)"
