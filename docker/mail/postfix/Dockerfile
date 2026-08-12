# Minimal, transparent Postfix build for the lab — a hand-authored config (not a black-box
# mail-in-a-box image) so students can actually read main.cf/master.cf and see how SMTP
# submission, LDAP recipient validation, and LMTP handoff to Dovecot fit together.
# See docs/SambaAdmin.md, docker/mail/README.md, and docs/SPFDKIMDMARC.md for the optional
# opendkim/opendmarc/policyd-spf packages below (installed always, only ACTIVATED when
# SPAM_PROTECTION_ENABLED=true - see entrypoint.sh - so the default image behaves exactly
# like plain Postfix).
FROM debian:bookworm-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       postfix postfix-ldap ca-certificates \
       opendkim opendkim-tools opendmarc postfix-policyd-spf-python \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/postfix/main.cf /etc/postfix/master.cf

COPY main.cf /etc/postfix/main.cf
COPY master.cf /etc/postfix/master.cf
COPY ldap-virtual-mailbox.cf /etc/postfix/ldap-virtual-mailbox.cf
COPY opendkim.conf /etc/opendkim.conf
COPY opendmarc.conf /etc/opendmarc.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 587 465

ENTRYPOINT ["/entrypoint.sh"]
