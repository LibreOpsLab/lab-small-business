# Student Lab Manual

Welcome to the LAB.INTERNAL environment — a simulated small-business IT estate you'll use to
practice real sysadmin and DevOps skills: Active Directory, PKI, single sign-on, and containerised
application hosting.

## Your accounts

| Account                   | Use for                                                                               |
| ------------------------- | ------------------------------------------------------------------------------------- |
| `student01` / `student02` | Day-to-day logon on `linux-client01` and `win-client01`, NextCloud file storage, mail |
| `lecturer01`              | Instructor demonstrations — has broader NextCloud group-folder rights                 |

Default lab password for seeded accounts is distributed by your instructor out-of-band (never
committed to this repository — see [Security.md](Security.md#secrets-management)). You will be
required to change it on first logon.

## Day 1 checklist

Work through these in order; each exercises a different layer of the stack.

1. **Domain logon.** Log into `win-client01` as `LAB\student01`. Confirm your desktop loads and
   `whoami /groups` shows you as a member of `LAB\Students`.
2. **Linux logon.** Log into `linux-client01` as `student01` (no `LAB\` prefix needed — SSSD is
   configured for short names). Run `id` and confirm group membership matches.
3. **Certificate trust.** Open a browser on `win-client01` and visit `https://auth.lab.internal`.
   You should see a padlock with **no warnings** — this confirms the GPO-deployed CA trust is
   working. Repeat on `linux-client01`.
4. **Single sign-on.** Visit `https://cloud.lab.internal`, click "Log in with Authentik", and sign
   in with your domain credentials. You should land in NextCloud without entering your password
   a second time.
5. **Mail.** Run `desktop-apps/linux/install-desktop-apps.sh` if you haven't already, then set
   up Betterbird with `student01@lab.internal` — it should autoconfigure IMAP/SMTP with no
   hostnames typed (see [DesktopApps.md](DesktopApps.md#betterbird-zero-click-via-autoconfig)).
   Send yourself a test email and confirm it arrives — this exercises both Dovecot (receive)
   and Postfix (send).
6. **A different access pattern.** Visit `https://pdf.lab.internal` (Stirling PDF). You'll hit
   an Authentik login before you ever see the app — unlike NextCloud's "click a button" SSO,
   this is Traefik asking Authentik "is this request allowed?" before proxying it at all. See
   [DesktopApps.md](DesktopApps.md) and [docker/stirling-pdf/README.md](../docker/stirling-pdf/README.md)
   for why this app needed a different integration than NextCloud/WordPress.

If any step fails, check [Troubleshooting.md](Troubleshooting.md) before asking your instructor
— the fix is almost always documented there.

## Understanding what you just did

- Steps 1-2 exercised **Kerberos authentication** — see
  [auth-flow.md](../diagrams/auth-flow.md). Your password never left your machine; a ticket did.
- Step 3 exercised the **PKI trust chain** — see [cert-trust-chain.md](../diagrams/cert-trust-chain.md).
- Step 4 exercised **OIDC federation** — see [oidc-flow.md](../diagrams/oidc-flow.md). NextCloud
  never saw your AD password at all; it trusted an identity token from Authentik.
- Step 5 exercised **direct LDAP bind authentication** (Dovecot/Postfix), a different (older,
  simpler) pattern than OIDC — worth comparing the two.
- Step 6 exercised **forward-auth**, a third pattern — used when an app (Stirling PDF) has no
  SSO support of its own, so the reverse proxy enforces auth in front of it instead. See
  [Security.md](Security.md#two-access-control-patterns-oidc-vs-forward-auth).

## Exercises

1. **Break and fix DNS.** On `linux-client01`, temporarily point `/etc/resolv.conf` at a public
   resolver instead of `10.10.0.10`, then try to `kinit`. Explain why it fails (see
   [dns-architecture.md](../diagrams/dns-architecture.md)) and revert.
2. **Group-driven access.** Ask your instructor to add you to `Docker-Admins` in AD
   (`samba-tool group addmembers Docker-Admins student01`). Log out and back into
   `cloud.lab.internal` and observe your new access (Traefik dashboard becomes visible). Note the
   propagation delay — why isn't it instant? (LDAP sync interval — see
   [AuthentikAdmin.md](AuthentikAdmin.md#ldap-source-configuration).)
3. **Certificate lifecycle.** Using `pki/scripts/03-renew-cert.sh`, renew the `cloud.lab.internal`
   certificate before it expires, and observe that Traefik picks it up without a restart (it
   watches the mounted cert path). Then deliberately revoke it with `04-revoke-cert.sh` and
   explain what a client checking the CRL would see.
4. **Backup and restore drill.** Working in pairs, one student breaks `samba-dc01` (stop the
   `samba-ad-dc` service and corrupt `/var/lib/samba/private/sam.ldb`), the other restores it
   from the previous night's backup per [Backup.md](Backup.md#samba-ad) and times the recovery.
5. **Least privilege audit.** Using `samba-tool group listmembers`, produce a report of who is
   in `IT-Admins` vs `Domain Admins` and explain why the distinction matters (see
   [Security.md](Security.md#least-privilege--rbac)).
6. **WordPress SSO, deliberately.** Run `docker/wordpress/scripts/configure-oidc-plugin.sh`,
   then log into `https://www.lab.internal/wp-admin` via Authentik. Check which WordPress role
   you were given by default — is it appropriate? Fix the role mapping if not (see
   [docker/wordpress/README.md](../docker/wordpress/README.md)).
7. **Partner with another business.** If a classmate has their own deployment running, work
   through [MultiBusiness.md](MultiBusiness.md) together to bridge them via IPSec, scoped to
   one specific service only. Afterwards, try to visit a page on their NextCloud that you did
   *not* explicitly allow through the firewall — confirm it's blocked, and explain why that's
   the correct behaviour, not a bug.

## Getting help

1. Check [Troubleshooting.md](Troubleshooting.md).
2. Check the relevant admin guide: [SambaAdmin.md](SambaAdmin.md),
   [AuthentikAdmin.md](AuthentikAdmin.md), [PKI.md](PKI.md), or [DesktopApps.md](DesktopApps.md).
3. Ask your instructor — but bring what you've already tried.
