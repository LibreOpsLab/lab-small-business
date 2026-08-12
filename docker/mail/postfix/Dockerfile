# Minimal, transparent Postfix build for the lab — a hand-authored config (not a black-box
# mail-in-a-box image) so students can actually read main.cf/master.cf and see how SMTP
# submission, LDAP recipient validation, and LMTP handoff to Dovecot fit together.
# See docs/SambaAdmin.md and docker/mail/README.md.
FROM debian:bookworm-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       postfix postfix-ldap ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/postfix/main.cf /etc/postfix/master.cf

COPY main.cf /etc/postfix/main.cf
COPY master.cf /etc/postfix/master.cf
COPY ldap-virtual-mailbox.cf /etc/postfix/ldap-virtual-mailbox.cf

EXPOSE 587 465

CMD ["postfix", "start-fg"]
