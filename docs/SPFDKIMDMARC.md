# SPF, DKIM, and DMARC (Optional)

Off by default — the base mail stack ([docker/mail/README.md](../docker/mail/README.md)) sends
and receives mail perfectly well without this. This is a teaching add-on for sender
authentication: SPF (who's allowed to send for a domain), DKIM (cryptographic proof a message
wasn't altered in transit and really came from where it claims), and DMARC (the policy tying
the two together — what to do when they disagree). Part of the optional advanced
federation/interop layer — see [docs/MultiBusiness.md](MultiBusiness.md) for the broader
context of why this matters more once businesses can reach each other's mail systems.

## Why this is off by default

A single closed, single-business mail system (the base build) has no real spoofing risk to
defend against — everyone's on the same Postfix instance. SPF/DKIM/DMARC earn their keep once
mail might cross a trust boundary: a business you've federated with over
[MultiBusiness.md](MultiBusiness.md)'s IPSec tunnel, or in a future exercise where two
businesses' Postfix instances relay to each other directly. Enabling it always, for every
single-business deployment, would just be extra moving parts with nothing to demonstrate.

## What gets enabled

`docker/mail/scripts/enable-spam-protection.sh`:

1. Sets `SPAM_PROTECTION_ENABLED=true` in `docker/mail/.env` and recreates the `postfix`
   container. The container's [`entrypoint.sh`](../docker/mail/postfix/entrypoint.sh) then
   (idempotently, every start):
   - Generates a DKIM keypair if one doesn't already exist (persisted in the `opendkim_keys`
     Docker volume, so it survives container recreation).
   - Starts OpenDKIM and OpenDMARC as milters on `127.0.0.1:8891` / `:8893`.
   - Wires Postfix to them (`smtpd_milters`) and to `postfix-policyd-spf-python` (an SPF
     policy check inserted into `smtpd_recipient_restrictions` — the service definition
     already exists in [`master.cf`](../docker/mail/postfix/master.cf), inert until
     referenced).
2. Publishes three DNS TXT records to Samba AD's `lab.internal` zone via `samba-tool dns add`:
   - `lab.internal. TXT "v=spf1 mx a:mail.lab.internal -all"` — only this mail server may send
     for the domain.
   - `mail._domainkey.lab.internal. TXT "<DKIM public key>"` — lets recipients verify DKIM
     signatures.
   - `_dmarc.lab.internal. TXT "v=DMARC1; p=quarantine; rua=mailto:postmaster@lab.internal"` —
     policy: quarantine mail that fails alignment (pass `--dmarc-policy reject` for the
     stricter option, or `none` for report-only/monitoring mode).

## Verifying it

```bash
# From any host that can reach samba-dc01's DNS:
dig TXT lab.internal @10.10.10.10
dig TXT mail._domainkey.lab.internal @10.10.10.10
dig TXT _dmarc.lab.internal @10.10.10.10

# Send a test message via Betterbird/webmail, then check headers on the receiving side for:
#   Authentication-Results: ...; dkim=pass ...; spf=pass ...; dmarc=pass
```

## Teaching angle

Break it on purpose: change `_dmarc.lab.internal`'s policy to `p=reject`, then send from a
spoofed `From:` address that doesn't match an authenticated sender, and watch it get rejected.
Or truncate the DKIM DNS TXT record by one character and watch signatures start failing
verification — a good, safe way to demonstrate exactly what these records protect against
without needing real internet-facing mail infrastructure.

## Disabling it again

```bash
sed -i 's/^SPAM_PROTECTION_ENABLED=.*/SPAM_PROTECTION_ENABLED=false/' docker/mail/.env
docker compose -f docker/mail/docker-compose.yml up -d postfix
```

The milters stop starting and Postfix reverts to its base configuration; the DNS TXT records
are left in place (harmless — remove with `samba-tool dns delete` if you want a clean slate).
