# Troubleshooting

## DNS

**Symptom:** domain-joined client can't find the DC / `realm join` fails with "Cannot find KDC
for realm".

- Confirm the client's DNS server is `10.10.0.10`, not pfSense or a public resolver:
  `resolvectl status` (Linux) / `ipconfig /all` (Windows). If wrong, check pfSense's DHCP scope
  (`pfsense/config/config.xml.template`, `<dnsserver>` under the LAN DHCP block) — option 6
  must point at `10.10.0.10` only.
- `dig @10.10.0.10 _kerberos._udp.lab.local SRV` should return `samba-dc01.lab.local:88`. If
  empty, run `samba_dnsupdate --verbose --all-names` on the DC to repair auto-generated SRV
  records.
- Confirm forwarding works: `dig @10.10.0.10 example.com` should resolve via pfSense's Unbound
  forwarder. If it times out, check `dns forwarder` in `smb.conf` matches pfSense's LAN IP and
  that the pfSense LAN rule allows `10.10.0.10 → 10.10.0.1:53`.

## Kerberos / domain join

**Symptom:** `kinit administrator` returns `KDC_ERR_PREAUTH_FAILED` or clock-skew errors.

- Kerberos tolerates ~5 minutes of clock skew by default. Verify NTP: `timedatectl` (Linux)
  should show `synchronized: yes` against `samba-dc01`; `w32tm /query /status` (Windows). All
  hosts must sync against the DC, not independent sources — see
  [Security.md](Security.md#host-hardening-ansible-common-role).
- Confirm the account isn't locked (`samba-tool user show <user>` — check
  `userAccountControl`) or password-expired (`samba-tool user password-expires`).

**Symptom:** `realm join` succeeds but login hangs / "Access denied" at the login screen.

- Check SSSD is actually running and has a cached connection:
  `systemctl status sssd; sudo sss_cache -E; journalctl -u sssd -n 50`.
- Confirm `use_fully_qualified_names = false` and `access_provider = simple` (or `ad`) in
  `/etc/sssd/sssd.conf` matches [`samba/templates/sssd.conf.j2`](../samba/templates/sssd.conf.j2)
  — a mismatched `access_provider` is the most common cause of "authenticates but access
  denied" on SSSD.

## LDAP / LDAPS

**Symptom:** Authentik's LDAP source shows "connection failed" or a TLS validation error.

- Test manually from `authentik01`:
  `openssl s_client -connect samba-dc01.lab.local:636 -CAfile /path/to/ca-chain.cert.pem`.
  A validation failure almost always means the CA chain bind-mount in
  [`docker/authentik/docker-compose.yml`](../docker/authentik/docker-compose.yml) is stale —
  re-run `ansible-playbook playbooks/05-pki-trust.yml --limit authentik01` and restart the
  Authentik containers.
- Confirm the DC's LDAPS cert CN/SAN actually includes `samba-dc01.lab.local` (re-issue with
  `pki/scripts/02-issue-server-cert.sh` if it was issued before the SAN was corrected).
- Bind test: `ldapwhoami -x -D "svc-authentik@lab.local" -W -H ldaps://samba-dc01.lab.local`.

## Certificates

**Symptom:** browser shows "Not Secure" / cert warning for `*.lab.local` sites even after
GPO/`update-ca-certificates` deployment.

- On Linux: `ls /etc/ssl/certs/ | grep -i lab` should show the Root and Issuing CA; if missing,
  re-run `sudo update-ca-certificates` after confirming the certs exist under
  `/usr/local/share/ca-certificates/`.
- On Windows: `certutil -verifystore -enterprise Root` should list "LAB Root CA"; if absent,
  the GPO hasn't applied — `gpupdate /force` then re-check, and confirm the computer object is
  actually inside an OU the GPO is linked to (`OU=Windows,OU=Workstations,OU=LAB`).
- Confirm you're hitting the CN/SAN the cert was actually issued for — `cloud.lab.local`, not
  `docker01.lab.local` — mismatched name is a separate warning from untrusted issuer.
- Check expiry: `pki/scripts/03-renew-cert.sh --check` lists days-to-expiry for every issued
  cert.

## Authentik / OIDC

**Symptom:** NextCloud's "Log in with Authentik" redirects back with an error instead of
logging in.

- Check the redirect URI registered on the Authentik OIDC provider
  ([`authentik/blueprints/oidc-nextcloud.yaml`](../authentik/blueprints/oidc-nextcloud.yaml))
  exactly matches `https://cloud.lab.local/apps/user_oidc/code` (trailing slash mismatches are
  the most common cause).
- Confirm the client secret in `docker/nextcloud/.env` matches what Authentik generated — if
  `bootstrap-authentik.sh` was re-run and regenerated secrets, NextCloud's `.env` is now stale;
  re-run `authentik/scripts/bootstrap-authentik.sh --sync-secrets`.
- Check Authentik's own logs: `docker compose -f docker/authentik/docker-compose.yml logs
server | grep -i error`.
- If the user can authenticate to Authentik itself but the `groups` claim is empty in
  NextCloud, the LDAP group sync interval (5 min) may not have run yet, or the user's AD group
  membership was changed after the last sync — check "Last successful sync" on the LDAP Source
  page in the Authentik admin UI.

## Docker / reverse proxy

**Symptom:** `502 Bad Gateway` from Traefik.

- `docker compose -f docker/reverse-proxy/docker-compose.yml logs traefik` — look for
  "unable to obtain certificate" or backend connection refused.
- Confirm the target container is on the `lab-proxy` external Docker network (`docker network
inspect lab-proxy`) — a container not attached to that network is invisible to Traefik
  regardless of correct labels.
- Confirm Traefik labels on the target service match `docker/reverse-proxy/traefik/dynamic.yml`
  routing conventions (`traefik.http.routers.<name>.rule=Host(...)`).

## General log locations

| Component | Log                                                                                                       |
| --------- | --------------------------------------------------------------------------------------------------------- |
| Samba AD  | `journalctl -u samba-ad-dc`, `/var/log/samba/log.samba`                                                   |
| SSSD      | `journalctl -u sssd`, `/var/log/sssd/*.log`                                                               |
| pfSense   | GUI: Status > System Logs; SSH: `/var/log/system.log`                                                     |
| Authentik | `docker compose -f docker/authentik/docker-compose.yml logs -f`                                           |
| Traefik   | `docker compose -f docker/reverse-proxy/docker-compose.yml logs -f traefik`                               |
| NextCloud | `docker compose -f docker/nextcloud/docker-compose.yml exec app tail -f /var/www/html/data/nextcloud.log` |

When in doubt, run `samba/scripts/health-check.sh` and
`ansible-playbook playbooks/site.yml --check --diff` first — the latter surfaces any
configuration drift between the repo's intended state and what's actually deployed.
