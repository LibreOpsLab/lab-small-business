#!/bin/sh
# Entrypoint for the postfix image. Default behaviour is unchanged from a bare Postfix
# container (SPAM_PROTECTION_ENABLED unset/false: just starts postfix). When
# SPAM_PROTECTION_ENABLED=true (set by docker/mail/scripts/enable-spam-protection.sh), also
# generates/loads DKIM keys, starts the OpenDKIM and OpenDMARC milters, and wires Postfix to
# use them plus an SPF policy check - see docs/SPFDKIMDMARC.md.
set -e

MAIL_DOMAIN="${MAIL_DOMAIN:-lab.internal}"
DKIM_SELECTOR="${DKIM_SELECTOR:-mail}"

if [ "${SPAM_PROTECTION_ENABLED:-false}" = "true" ]; then
  KEY_DIR="/etc/opendkim/keys/${MAIL_DOMAIN}"
  mkdir -p "${KEY_DIR}" /etc/opendkim /var/run/opendkim /var/run/opendmarc

  if [ ! -f "${KEY_DIR}/${DKIM_SELECTOR}.private" ]; then
    echo "[entrypoint] Generating DKIM keypair for ${MAIL_DOMAIN} (selector: ${DKIM_SELECTOR})"
    opendkim-genkey -b 2048 -d "${MAIL_DOMAIN}" -s "${DKIM_SELECTOR}" -D "${KEY_DIR}"
  fi
  chown -R opendkim:opendkim /etc/opendkim /var/run/opendkim 2>/dev/null || true

  cat > /etc/opendkim/KeyTable <<EOF
${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN} ${MAIL_DOMAIN}:${DKIM_SELECTOR}:${KEY_DIR}/${DKIM_SELECTOR}.private
EOF
  cat > /etc/opendkim/SigningTable <<EOF
*@${MAIL_DOMAIN} ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}
EOF
  cat > /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
${MAIL_DOMAIN}
EOF

  echo "[entrypoint] Starting OpenDKIM + OpenDMARC milters"
  opendkim -x /etc/opendkim.conf
  opendmarc -c /etc/opendmarc.conf

  echo "[entrypoint] Wiring Postfix to the milters + SPF policy check (idempotent via postconf)"
  postconf -e "smtpd_milters=inet:127.0.0.1:8891,inet:127.0.0.1:8893"
  postconf -e "non_smtpd_milters=inet:127.0.0.1:8891"
  postconf -e "milter_default_action=accept"
  postconf -e "milter_protocol=6"

  CURRENT_RESTRICTIONS="$(postconf -h smtpd_recipient_restrictions)"
  case "${CURRENT_RESTRICTIONS}" in
    *policyd-spf*) ;;
    *) postconf -e "smtpd_recipient_restrictions=${CURRENT_RESTRICTIONS}, check_policy_service unix:private/policyd-spf" ;;
  esac

  echo "[entrypoint] SPAM_PROTECTION_ENABLED=true - DKIM/SPF/DMARC active."
  echo "[entrypoint] DKIM DNS TXT record to publish (also written to ${KEY_DIR}/${DKIM_SELECTOR}.txt):"
  cat "${KEY_DIR}/${DKIM_SELECTOR}.txt" 2>/dev/null || true
else
  echo "[entrypoint] SPAM_PROTECTION_ENABLED is not 'true' - starting plain Postfix (default)."
  echo "[entrypoint] See docker/mail/scripts/enable-spam-protection.sh to turn this on."
fi

exec postfix start-fg
