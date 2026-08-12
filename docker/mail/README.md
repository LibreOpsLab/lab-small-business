# Mail (Dovecot + Postfix)

A closed, lab-internal-only mail system: users can send and receive `@lab.internal` mail from
any properly-authenticated client, but nothing is relayed to or accepted from the real
internet. Two services split the responsibilities the way real mail systems do:

| Service | Role | Auth |
|---|---|---|
| **Dovecot** | IMAPS (993) — mailbox storage/retrieval; also LMTP (24, internal-only) delivery target and SASL auth backend | LDAP bind against Samba AD (`dovecot-ldap.conf.ext`) |
| **Postfix** | Submission (587, STARTTLS) + SMTPS (465, implicit TLS) — accepts outgoing mail from authenticated clients only | SASL via Dovecot; recipient validity checked against Samba AD over LDAP (`ldap-virtual-mailbox.cf`) |

See [diagrams/dns-architecture.md](../../diagrams/dns-architecture.md) for `mail.lab.internal`'s
place in the zone, and [docs/SambaAdmin.md](../../docs/SambaAdmin.md) for the `svc-dovecot` /
`svc-postfix` service accounts both LDAP binds use.

## Why not just IMAP (the original scope)?

The base build shipped Dovecot (receive/store) only. That's enough to prove LDAP-backed IMAP
auth works, but a real "replace Outlook" experience needs to *send* mail too — Betterbird and
NextCloud Mail both expect a working SMTP submission endpoint. Postfix here is
deliberately minimal and hand-configured (not a black-box mail-in-a-box image) so
`docker/mail/postfix/main.cf`/`master.cf` stay readable as a teaching artifact: no internet
relay, submission-only, SASL-gated, LDAP-validated recipients, LMTP handoff to Dovecot rather
than Postfix owning mailboxes itself.

## Flow

```text
Client (Betterbird/NextCloud Mail)
  -> Postfix :587 (STARTTLS) or :465 (SMTPS), SASL auth via Dovecot
  -> Postfix checks recipient against Samba AD (LDAP `mail` attribute) — main.cf
  -> Postfix hands off via LMTP :24 (internal Docker network only) to Dovecot
  -> Dovecot stores in Maildir, serves back over IMAPS :993
```

## Client configuration

| Setting | Value |
|---|---|
| IMAP host/port | `mail.lab.internal` : `993` (SSL/TLS) |
| SMTP host/port | `mail.lab.internal` : `587` (STARTTLS) or `465` (SSL/TLS) |
| Username | `student01@lab.internal` (or any domain account's UPN) |
| Password | the account's AD password |

See [docs/DesktopApps.md](../../docs/DesktopApps.md) for how Betterbird gets these values
automatically via autoconfig.

## SPF / DKIM / DMARC (optional)

Off by default. See [docs/SPFDKIMDMARC.md](../../docs/SPFDKIMDMARC.md) and
`docker/mail/scripts/enable-spam-protection.sh` to turn on sender authentication — relevant
once mail might cross a trust boundary (e.g. a federated business, see
[docs/MultiBusiness.md](../../docs/MultiBusiness.md)), not needed for a single closed instance.

## Adding real users' mailboxes

Any AD user with a populated `mail` attribute (set via `samba-tool user create --mail-address=...`
or `samba-tool user edit`) can send/receive immediately — there's no separate mailbox
provisioning step. The seed accounts in [`samba/data/users.csv`](../../samba/data/users.csv)
don't set `mail` explicitly; add `--mail-address=student01@lab.internal` to
[`samba/scripts/create-users.sh`](../../samba/scripts/create-users.sh)'s `samba-tool user
create` call (or set it by hand) if you want the shipped seed accounts mail-enabled by default.
