# Backup & Recovery

## Samba AD

**Backup:** [`samba/scripts/backup-ad.sh`](../samba/scripts/backup-ad.sh), scheduled daily via
`ansible/playbooks/99-backups.yml` (systemd timer `lab-samba-backup.timer`). Uses
`samba-tool domain backup online` (full: SYSVOL, sam.ldb, secrets, DNS) into
`/var/backups/samba-ad/<UTC-timestamp>/`, retains 14 days, and additionally runs
`samba-tool gpo backup --all` for every linked GPO.

**Restore:** on a freshly reinstalled DC (or a DR standby):

```bash
samba-tool domain backup restore \
  --backup-file=/var/backups/samba-ad/<timestamp>/samba-backup-<timestamp>.tar.bz2 \
  --targetdir=/var/lib/samba \
  --newservername=samba-dc01
systemctl unmask samba-ad-dc && systemctl enable --now samba-ad-dc
samba/scripts/health-check.sh
```

Then re-import GPOs with `samba-tool gpo restore <GUID> <backup-dir>`. See
[SambaAdmin.md](SambaAdmin.md#backup--restore).

## Authentik

**Backup:** `docker/authentik/docker-compose.yml`'s `postgresql` service is dumped nightly by
the `pg-backup` sidecar container (runs `pg_dump` on a cron schedule into a bind-mounted
`./backups/` directory, see the compose file's `pg-backup` service). Redis is cache-only and
intentionally not backed up — losing it only costs active sessions, not data.

**Restore:**

```bash
docker compose -f docker/authentik/docker-compose.yml stop server worker
docker compose -f docker/authentik/docker-compose.yml exec -T postgresql \
  psql -U authentik -d authentik < backups/authentik-<date>.sql
docker compose -f docker/authentik/docker-compose.yml start server worker
```

Blueprints re-apply automatically on `server` start and are idempotent, so provider/source
config self-heals even from an empty database — only user-specific state (sessions, enrolled
MFA devices, LDAP sync cache) actually needs the SQL restore.

## Docker volumes (NextCloud / OnlyOffice / mail)

Named volumes (`nextcloud_data`, `nextcloud_db`, `onlyoffice_data`, `mail_data`) are backed up
by [`scripts/lib/common.sh`](../scripts/lib/common.sh)'s `backup_volume()` helper, invoked from
`ansible/playbooks/99-backups.yml`, which runs a throwaway container that tars each volume to
`/opt/lab-backups/<volume>-<date>.tar.gz`:

```bash
docker run --rm -v nextcloud_data:/data -v /opt/lab-backups:/backup \
  alpine tar czf /backup/nextcloud_data-$(date +%F).tar.gz -C /data .
```

NextCloud is also put into maintenance mode (`occ maintenance:mode --on`) for the duration of
its DB dump to guarantee a consistent snapshot; see the `nextcloud-backup` task in
`99-backups.yml`.

**Restore:** stop the stack, extract the tarball back into a fresh named volume, start the
stack, run `occ maintenance:mode --off` and `occ files:scan --all` for NextCloud.

## PKI

The entire `pki/root-ca/`, `pki/intermediate-ca/`, and `pki/issued/` trees (excluding the
offline Root CA private key, which by design lives outside this backup entirely) are backed up
as part of the `docker01` host backup — they're plain files, no special tooling needed:

```bash
tar czf /opt/lab-backups/pki-$(date +%F).tar.gz pki/intermediate-ca pki/issued
```

The Root CA private key backup is a manual, deliberate step: copy
`pki/root-ca/private/ca.key.pem` to two separate pieces of offline media (documented, not
automated — automating offline-key handling would defeat the point). Losing the Issuing CA key
is recoverable (re-issue from Root); losing the Root CA key means re-establishing trust
lab-wide, which is why it gets the extra manual care.

## Configuration files

Everything under version control (this repository) is definitionally backed up by `git` — push
to a remote regularly. The only things that must exist _outside_ git are the generated secrets
covered above (Vault-encrypted vars, `.env` files, PKI key material) — see
[Security.md](Security.md#secrets-management) for what's excluded and why.

## Restore drill recommendation

For teaching purposes, run a full DR drill at least once per course: snapshot all VMs, then
deliberately destroy `samba-dc01` and restore it from backup using the procedure above, timing
how long the domain is degraded. This is the single most valuable exercise in
[StudentLabManual.md](StudentLabManual.md) for building real operational confidence.
