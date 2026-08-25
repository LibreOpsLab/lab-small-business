#!/usr/bin/env bash
# Turns on SPF/DKIM/DMARC enforcement for the mail stack: enables the milters in the postfix
# container, then publishes the three DNS TXT records (SPF, DKIM selector, DMARC) needed for
# it to mean anything. Off by default — the mail stack works exactly as before without this.
# See docs/SPFDKIMDMARC.md.
#
# Usage: ./docker/mail/scripts/enable-spam-protection.sh [--dmarc-policy quarantine]
# Run from the Docker host (docker01), with samba-tool reachable (either locally if this host
# is domain-joined with the tools installed, or adjust the samba-tool invocations below to
# run over SSH against samba-dc01).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
MAIL_DIR="${REPO_ROOT}/docker/mail"
MAIL_DOMAIN="lab.internal"
DKIM_SELECTOR="mail"
DMARC_POLICY="quarantine"

[[ "${1:-}" == "--dmarc-policy" ]] && DMARC_POLICY="$2"

log()  { printf '\033[1;34m[enable-spam-protection]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[enable-spam-protection][error]\033[0m %s\n' "$*" >&2; exit 1; }

ENV_FILE="${MAIL_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  log "Creating ${ENV_FILE}"
  cat > "${ENV_FILE}" <<EOF
SPAM_PROTECTION_ENABLED=true
MAIL_DOMAIN=${MAIL_DOMAIN}
DKIM_SELECTOR=${DKIM_SELECTOR}
EOF
else
  if grep -q '^SPAM_PROTECTION_ENABLED=' "${ENV_FILE}"; then
    sed -i.bak 's/^SPAM_PROTECTION_ENABLED=.*/SPAM_PROTECTION_ENABLED=true/' "${ENV_FILE}"
  else
    echo "SPAM_PROTECTION_ENABLED=true" >> "${ENV_FILE}"
  fi
  rm -f "${ENV_FILE}.bak"
fi

log "Recreating the postfix container with SPAM_PROTECTION_ENABLED=true"
docker compose -f "${MAIL_DIR}/docker-compose.yml" up -d postfix

log "Waiting for the DKIM key to be generated..."
DKIM_TXT_PATH="/etc/opendkim/keys/${MAIL_DOMAIN}/${DKIM_SELECTOR}.txt"
for i in $(seq 1 30); do
  if docker compose -f "${MAIL_DIR}/docker-compose.yml" exec -T postfix test -f "${DKIM_TXT_PATH}"; then
    break
  fi
  [[ "$i" -eq 30 ]] && die "DKIM key never appeared — check: docker compose -f docker/mail/docker-compose.yml logs postfix"
  sleep 2
done

if ! command -v samba-tool >/dev/null 2>&1; then
  die "samba-tool not found on this host. Either 'sudo apt-get install -y samba-common-bin'" \
      "here, or copy the DNS TXT values this script prints below and add them from" \
      "samba-dc01 instead (samba-tool dns add samba-dc01 ${MAIL_DOMAIN} <name> TXT <value> -U administrator)."
fi

DKIM_RECORD_RAW="$(docker compose -f "${MAIL_DIR}/docker-compose.yml" exec -T postfix cat "${DKIM_TXT_PATH}")"
# opendkim-genkey emits a multi-line BIND-format record; the actual quoted value is what
# matters for the TXT record content - collapse it to a single quoted string for samba-tool.
DKIM_VALUE="$(echo "${DKIM_RECORD_RAW}" | grep -oP '"\K[^"]+(?=")' | tr -d '\n')"

log "Publishing DNS TXT records to Samba AD (${MAIL_DOMAIN} zone)"
samba-tool dns add samba-dc01 "${MAIL_DOMAIN}" "@" TXT \
  "\"v=spf1 mx a:mail.${MAIL_DOMAIN} -all\"" -U administrator || \
  log "SPF record add failed or already exists — check manually with: samba-tool dns query samba-dc01 ${MAIL_DOMAIN} @ TXT"

samba-tool dns add samba-dc01 "${MAIL_DOMAIN}" "${DKIM_SELECTOR}._domainkey" TXT \
  "\"${DKIM_VALUE}\"" -U administrator || \
  log "DKIM record add failed or already exists."

samba-tool dns add samba-dc01 "${MAIL_DOMAIN}" "_dmarc" TXT \
  "\"v=DMARC1; p=${DMARC_POLICY}; rua=mailto:postmaster@${MAIL_DOMAIN}\"" -U administrator || \
  log "DMARC record add failed or already exists."

log "Done. Verify with: dig TXT ${MAIL_DOMAIN} @10.10.10.10 ; dig TXT ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN} @10.10.10.10 ; dig TXT _dmarc.${MAIL_DOMAIN} @10.10.10.10"
log "See docs/SPFDKIMDMARC.md for what each record means and how to test enforcement."
