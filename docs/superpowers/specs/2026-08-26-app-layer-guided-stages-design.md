# App-Layer Guided Stages — Design

## Context

This is sub-project **C** of a five-part restructuring effort (D → A → C → B → E). D (subnet
picker) and A (desktop hypervisor manual baseline) are implemented; this sub-project covers the
app layer — Samba AD, PKI, Docker application server, Authentik, and the five Docker Compose
apps. Per the originating request: compose files, Ansible roles, and shell scripts are already
"complete" artifacts (per `CLAUDE.md`'s `docker/` convention) — nothing about *what* gets
deployed changes here. What changes is *how the learner encounters it*: today,
`docs/DeploymentGuide.md` step 5 collapses the entire app layer into one command,
`ansible-playbook playbooks/site.yml --ask-vault-pass`, which silently chains 7 playbooks with
no visibility into what each one does. The goal is to make each stage visible and
understood, the same way sub-project A made VM building visible — while leaving the actual
automation (compose files, Ansible roles/tasks, shell scripts) untouched wherever it isn't
itself redundant.

## Goal

1. Restructure `docs/DeploymentGuide.md` step 5 to walk through the app-layer playbooks as
   individually-run, individually-explained stages, instead of one `site.yml` invocation.
2. Deepen step 6's per-app verification into a short "what is this, why, how does it connect"
   paragraph per app, inline in the guide.
3. Remove `ansible/roles/samba_ad/` and `ansible/playbooks/01-samba-ad.yml` — a genuinely
   redundant automation layer that wraps the exact scripts `DeploymentGuide.md` step 3 already
   has the learner run directly, existing only to let the one-shot `site.yml` path also cover
   the DC.
4. Fix the gap that removal opens: nothing would otherwise apply `00-common-hardening.yml` or
   `05-pki-trust.yml` to `samba-dc01` (previously carried in by `01-samba-ad.yml`'s presence in
   `site.yml`'s chain, now missing since the per-VM `--limit` commands in `docker-server.md`/
   `authentik.md` only ever targeted `docker01`/`authentik01`).

## Non-goals

- **No changes to Docker Compose files, `.env.example` files, or any Ansible role's task logic**
  (`docker_engine`, `common`, `fail2ban`, `pki_trust`, `sssd_client`) — these are the "complete"
  artifacts the learner runs as-is, per the originating request.
- **`02-docker-server.yml` stays one atomic run** bringing up all 5 Compose stacks together —
  not split into per-app Ansible runs. The staging happens at the playbook level (which of the 6
  remaining playbooks to run, in what order, understanding each), not by re-engineering the
  Docker-apps role to run app-by-app.
- **`site.yml` and `scripts/deploy-all.sh` are not removed.** They remain the optional
  re-deployment fast-path once a learner has been through the guided sequence once — the same
  role `pfsense/config.xml.template` plays for pfSense's manual build. `site.yml` loses its
  `01-samba-ad.yml` import (see Goal 3) but is otherwise unchanged; `deploy-all.sh` needs no
  edits (its own header comment already says it doesn't provision Samba from scratch).
- **`hypervisor/vms/docker-server.md` and `authentik.md` are not modified.** Their existing
  Post-install sections already list the correct per-VM `ansible-playbook ... --limit <host>`
  commands `DeploymentGuide.md` step 5 will now walk through instead of bypassing.
- **`docs/StudentLabManual.md` is not modified.** The deepened per-app narrative goes inline
  into `DeploymentGuide.md` (per the approved design), not into a separate reflection document.

## Design

### Remove the redundant Samba AD Ansible role

Delete `ansible/roles/samba_ad/` (`tasks/main.yml` and `handlers/main.yml`) and
`ansible/playbooks/01-samba-ad.yml`. In `ansible/playbooks/site.yml`, drop the
`- import_playbook: 01-samba-ad.yml` line. `samba-dc01` becomes fully "provisioned outside
Ansible" — the same status pfSense and the desktop clients already have (see
`ansible/inventory/hosts.ini`'s existing comment about what's excluded and why) — provisioned
entirely by the direct scripts `hypervisor/vms/samba-dc.md`'s Post-install section (unchanged)
already documents.

### `docs/DeploymentGuide.md` step 5 — staged playbooks

Replace the current step 5 (which builds `docker01`/`authentik01` by hand, then runs
`ansible-playbook playbooks/site.yml --ask-vault-pass` as one command) with:

1. Build and install `docker01` and `authentik01` (unchanged from sub-project A's step 5
   content — VM build + baseline).
2. `ansible-playbook playbooks/00-common-hardening.yml --ask-vault-pass` (no `--limit`) — SSH
   hardening, `ufw`, `unattended-upgrades`, NTP against `samba-dc01` on all three servers
   (`samba-dc01`, `docker01`, `authentik01`), plus Fail2Ban on `docker01`/`authentik01`. Note
   inline that this is `samba-dc01`'s first Ansible contact — everything in step 3 ran directly
   on the DC over SSH, not through Ansible.
3. `ansible-playbook playbooks/04-linux-client-join.yml --ask-vault-pass` — SSSD-joins
   `docker01`/`authentik01` to `LAB.INTERNAL`, the same mechanism `linux-client01` used by hand
   in step 7's `join-linux-client.sh`, just automated here since there are two hosts instead of
   one interactive session.
4. `ansible-playbook playbooks/05-pki-trust.yml --ask-vault-pass` (no `--limit`) — distributes
   the CA chain built in step 4 to all three servers, including `samba-dc01` (its first CA-trust
   pass too, for the same reason as step 2 above).
5. `ansible-playbook playbooks/02-docker-server.yml --ask-vault-pass` — installs Docker Engine
   and brings up all 5 Compose stacks (`docker/{reverse-proxy,nextcloud,onlyoffice,mail,
   wordpress,stirling-pdf}`) on `docker01` in one run — the compose files themselves needed no
   changes to get here (Non-goal above).
6. `ansible-playbook playbooks/03-authentik.yml --ask-vault-pass` — brings up Authentik and
   applies its OIDC/LDAP blueprints via `bootstrap-authentik.sh` (the actual bootstrap logic;
   Ansible here is plumbing — copy repo, render `.env`, invoke the script).
7. `ansible-playbook playbooks/99-backups.yml --ask-vault-pass` — installs the daily backup
   timers for Samba AD (`samba-dc01`) and Docker volumes + PKI (`docker01`).

Each numbered item gets 1-2 sentences of "what this does and why it's ordered here" — matching
the inline-rationale depth `pfsense.md`/`samba-dc.md` already use, not a separate reflection
section.

### `docs/DeploymentGuide.md` step 6 — deepened per-app narrative

The existing bullet-point verification list (URL → expected result) gets a short paragraph added
per app, inline:

- **NextCloud**: what it is, and that its "Log in with Authentik" button is OIDC against the
  identity provider stood up in step 5 — the same trust relationship, not a separate login.
- **OnlyOffice**: the document-editing backend NextCloud calls out to — why it's a separate
  Compose stack/container rather than bundled into NextCloud itself.
- **Mail (Dovecot/Postfix)**: authenticates via direct LDAP bind against Samba AD — a different,
  older pattern than OIDC, worth contrasting directly against NextCloud's SSO.
- **WordPress**: SSO is opt-in (step 6a) — note why (a public-facing CMS defaulting to SSO isn't
  always what a real business wants).
- **Stirling PDF**: forward-auth via Traefik — a third distinct access-control pattern (Traefik
  asks Authentik "is this request allowed?" before proxying at all, vs. NextCloud's app-level
  OIDC button).

This sets up, rather than duplicates, the OIDC/LDAP-bind/forward-auth contrast that's already
the spine of `docs/StudentLabManual.md`'s "Understanding what you just did" section — that
document is unchanged (Non-goals).

## Testing

No test suite. Verification is:

- `bash -n` — not applicable (no shell scripts touched; `site.yml` is YAML).
- `ansible-playbook --syntax-check playbooks/site.yml` from `ansible/` (requires `ansible-core`
  on the machine doing the verification — if unavailable, a manual read of the YAML for valid
  `import_playbook` list syntax after the deletion is the fallback).
- Grep sweep for stale references to `01-samba-ad.yml` / `samba_ad` role across the repo after
  deletion — expect zero hits outside historical `docs/superpowers/` records.
- Manual read-through of `DeploymentGuide.md` end to end, confirming the staged step 5 sequence
  reads coherently and matches the dependency order already established by `site.yml`'s import
  list (hardening → domain-join → PKI trust → Docker apps → Authentik → backups).

## Open questions

None — this sub-project is fully scoped by the design above.
