#!/usr/bin/env bash
# Installs and configures the "Teams & Outlook replacement" groupware apps inside NextCloud:
# Calendar, Contacts, Talk, Mail, and the ONLYOFFICE connector. Idempotent — `occ app:install`
# no-ops if already installed. Run after docker/nextcloud is up (and, for the ONLYOFFICE
# wiring, after docker/onlyoffice is up too). See docs/DesktopApps.md.
#
# Usage: ./docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
COMPOSE="docker compose -f ${REPO_ROOT}/docker/nextcloud/docker-compose.yml"

log()  { printf '\033[1;34m[nextcloud-apps]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[nextcloud-apps][error]\033[0m %s\n' "$*" >&2; exit 1; }

occ() { ${COMPOSE} exec -T -u www-data app php occ "$@"; }

log "Waiting for NextCloud to be installed..."
for i in $(seq 1 30); do
  occ status --output=json 2>/dev/null | grep -q '"installed":true' && break
  [[ "$i" -eq 30 ]] && die "NextCloud did not report installed=true in time."
  sleep 5
done

log "Installing/enabling Calendar, Contacts, Talk, and Mail apps"
for app in calendar contacts spreed mail; do
  occ app:install "${app}" 2>/dev/null || occ app:enable "${app}"
done

log "Configuring the ONLYOFFICE connector (docker/onlyoffice) — internal + public URLs"
ONLYOFFICE_ENV="${REPO_ROOT}/docker/onlyoffice/.env"
[[ -f "${ONLYOFFICE_ENV}" ]] || die "${ONLYOFFICE_ENV} not found — copy .env.example first."
# shellcheck disable=SC1090
JWT_SECRET="$(grep '^ONLYOFFICE_JWT_SECRET=' "${ONLYOFFICE_ENV}" | cut -d= -f2-)"
occ app:install onlyoffice 2>/dev/null || occ app:enable onlyoffice
occ config:app:set onlyoffice DocumentServerUrl --value="https://docs.lab.internal/"
occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://onlyoffice-documentserver/"
occ config:app:set onlyoffice StorageUrl --value="http://nextcloud-app/"
occ config:app:set onlyoffice jwt_secret --value="${JWT_SECRET}"
occ config:app:set onlyoffice jwt_header --value="AuthorizationJwt"

log "Talk (spreed) uses direct WebRTC on the lab LAN by default — fine for same-subnet calls."
log "No TURN server is configured; cross-subnet calls (e.g. over the MultiBusiness VPN/IPSec"
log "tunnels in docs/MultiBusiness.md) will need one added via: occ talk:turn:add ..."

log "Done. Calendar/Contacts/Talk are immediately usable (native NextCloud auth, no extra"
log "credentials). Mail requires each user to add their mail.lab.internal account once from"
log "inside the app — see docs/DesktopApps.md#nextcloud-mail-app-one-manual-step for why"
log "this one step can't be automated away (NextCloud never sees the AD password when SSO"
log "goes through OIDC, so it can't silently reuse it for IMAP)."
