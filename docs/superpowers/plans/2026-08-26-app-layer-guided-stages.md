# App-Layer Guided Stages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the redundant `samba_ad` Ansible role (it duplicates what `DeploymentGuide.md` step 3 already has the learner run by hand), and restructure `DeploymentGuide.md` steps 5-6 so the app layer is walked through as individually-run, individually-explained playbook stages instead of one `site.yml` invocation.

**Architecture:** Delete `ansible/roles/samba_ad/` and `ansible/playbooks/01-samba-ad.yml`; drop that import from `site.yml`. Rewrite `DeploymentGuide.md`'s step 5 to run each of the 6 remaining playbooks individually with inline rationale, in the same dependency order `site.yml` already uses. Deepen step 6's per-app verification into short narrative paragraphs, and fix a stale `--tags apps` reference discovered while editing that exact line (no tags are actually defined anywhere in the role/playbook).

**Tech Stack:** YAML (Ansible) + Markdown documentation. No code logic changes to any role's tasks — this is a doc-and-playbook-inventory restructuring only.

**Spec:** [docs/superpowers/specs/2026-08-26-app-layer-guided-stages-design.md](../specs/2026-08-26-app-layer-guided-stages-design.md)

## Global Constraints

- No changes to any Docker Compose file, `.env.example`, or Ansible role's task logic (`docker_engine`, `common`, `fail2ban`, `pki_trust`, `sssd_client`) — these are "complete" artifacts per the spec's non-goals.
- `02-docker-server.yml` stays one atomic run — not split into per-app Ansible runs.
- `site.yml` and `scripts/deploy-all.sh` remain in the repo as the optional fast-path for re-deployment — not removed, just losing the `01-samba-ad.yml` import.
- `hypervisor/vms/docker-server.md` and `authentik.md` are not modified — their existing Post-install sections already show the correct per-VM `--limit` commands.
- `docs/StudentLabManual.md` is not modified.

---

### Task 1: Remove the redundant `samba_ad` Ansible role

**Files:**
- Delete: `ansible/roles/samba_ad/tasks/main.yml`
- Delete: `ansible/roles/samba_ad/handlers/main.yml`
- Delete: `ansible/playbooks/01-samba-ad.yml`
- Modify: `ansible/playbooks/site.yml`

**Interfaces:** None — pure deletion plus a one-line edit to `site.yml`'s import list. No other task depends on the `samba_ad` role existing.

- [ ] **Step 1: Delete the role and playbook**

```bash
rm -rf ansible/roles/samba_ad
rm -f ansible/playbooks/01-samba-ad.yml
```

- [ ] **Step 2: Rewrite `ansible/playbooks/site.yml`**

Find:
```yaml
---
# Master playbook — runs every component playbook in dependency order across the full
# inventory. See docs/DeploymentGuide.md for how this fits into the overall bring-up sequence
# (pfSense and the two desktop clients are provisioned outside Ansible — see their own docs).

- import_playbook: 00-common-hardening.yml
- import_playbook: 01-samba-ad.yml
- import_playbook: 04-linux-client-join.yml
- import_playbook: 05-pki-trust.yml
- import_playbook: 02-docker-server.yml
- import_playbook: 03-authentik.yml
- import_playbook: 99-backups.yml
```

Replace with:
```yaml
---
# Master playbook — runs every component playbook in dependency order across the full
# inventory. See docs/DeploymentGuide.md for how this fits into the overall bring-up sequence.
# pfSense and the two desktop clients are entirely outside this inventory (provisioned and
# managed by hand — see their own docs). samba-dc01 IS in inventory — hardening, PKI trust, and
# backups below all apply to it — but its AD domain provisioning happens outside Ansible,
# directly via samba/scripts/bootstrap-ad.sh (see hypervisor/vms/samba-dc.md).

- import_playbook: 00-common-hardening.yml
- import_playbook: 04-linux-client-join.yml
- import_playbook: 05-pki-trust.yml
- import_playbook: 02-docker-server.yml
- import_playbook: 03-authentik.yml
- import_playbook: 99-backups.yml
```

- [ ] **Step 3: Verify no other file references the removed role/playbook**

Run:
```bash
grep -rln "samba_ad\|01-samba-ad" --include="*.yml" --include="*.md" --include="*.sh" . 2>/dev/null | grep -v '^\./docs/superpowers/'
```
Expected: no output.

- [ ] **Step 4: YAML sanity check on `site.yml`**

Run: `python3 -c "import yaml; yaml.safe_load(open('ansible/playbooks/site.yml'))" && echo OK`
Expected: `OK` (confirms the file is still valid YAML after the edit — this repo has no
`ansible-core` verification step documented elsewhere, so a plain YAML parse is the available
sanity check).

- [ ] **Step 5: Commit**

```bash
git add -A ansible/roles/samba_ad ansible/playbooks/01-samba-ad.yml ansible/playbooks/site.yml
git status --short
git commit -m "$(cat <<'EOF'
Remove the redundant samba_ad Ansible role

It only wrapped the exact scripts (bootstrap-ad.sh, create-ous.sh, etc.)
that DeploymentGuide.md step 3 already has the learner run directly on
samba-dc01 over SSH — the role's own comment admitted the scripts were
"the source of truth." samba-dc01 is now fully provisioned outside Ansible,
same as pfSense and the desktop clients; it stays in Ansible's inventory for
hardening, PKI trust, and backups (site.yml's other playbooks still apply to
it, just not AD provisioning).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Restructure `DeploymentGuide.md` step 5 into staged playbooks

**Files:**
- Modify: `docs/DeploymentGuide.md`

**Interfaces:**
- Consumes: nothing new — references the same 6 playbooks Task 1 left in `site.yml`'s import list, in the same order.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Replace step 5's content**

Find:
```markdown
## 5. Docker application server + Authentik

1. Build and install `docker01` and `authentik01` by hand, then apply the baseline to each —
   see [`hypervisor/vms/docker-server.md`](../hypervisor/vms/docker-server.md) and
   [`hypervisor/vms/authentik.md`](../hypervisor/vms/authentik.md) for VM specs, static IPs, and
   `labadmin`/SSH-key setup.
2. From your control host, populate `ansible/inventory/hosts.ini` (already templated with these
   IPs) and run:

   ```bash
   cd ansible
   ansible-playbook playbooks/site.yml --ask-vault-pass
   ```

   `site.yml` runs, in order: `00-common-hardening.yml`, `04-linux-client-join.yml` (for
   `docker01`/`authentik01` as domain-joined Linux hosts), `05-pki-trust.yml`,
   `02-docker-server.yml` (installs Docker Engine + brings up the reverse proxy stack), and
   `03-authentik.yml` (brings up Authentik and applies blueprints via
   [`bootstrap-authentik.sh`](../authentik/scripts/bootstrap-authentik.sh)).

3. Verify: `https://auth.lab.internal` loads with a trusted cert and you can sign in as
   `akadmin` (bootstrap credentials in `ansible/inventory/host_vars/authentik01/vault.yml`).
```

Replace with:
```markdown
## 5. Docker application server + Authentik

1. Build and install `docker01` and `authentik01` by hand, then apply the baseline to each —
   see [`hypervisor/vms/docker-server.md`](../hypervisor/vms/docker-server.md) and
   [`hypervisor/vms/authentik.md`](../hypervisor/vms/authentik.md) for VM specs, static IPs, and
   `labadmin`/SSH-key setup.
2. From your control host, populate `ansible/inventory/hosts.ini` (already templated with these
   IPs), `cd ansible`, and run each of the following in order. Each is idempotent and
   individually re-runnable — this is the same sequence `ansible-playbook playbooks/site.yml`
   chains automatically for redeploys (see "One-shot re-runs" below), broken out here so each
   stage is visible on its own:

   ```bash
   ansible-playbook playbooks/00-common-hardening.yml --ask-vault-pass
   ```

   SSH hardening, `ufw`, `unattended-upgrades`, and NTP against `samba-dc01`, applied to all
   three servers (`samba-dc01`, `docker01`, `authentik01`) — plus Fail2Ban on `docker01`/
   `authentik01`. This is `samba-dc01`'s first contact with Ansible: everything in step 3 ran
   directly on the DC over SSH, not through a playbook.

   ```bash
   ansible-playbook playbooks/04-linux-client-join.yml --ask-vault-pass
   ```

   SSSD-joins `docker01` and `authentik01` to `LAB.INTERNAL` — the same underlying mechanism
   `linux-client01` used interactively in step 7's `join-linux-client.sh`, automated here
   because there are two hosts to join instead of one interactive session.

   ```bash
   ansible-playbook playbooks/05-pki-trust.yml --ask-vault-pass
   ```

   Distributes the CA chain built in step 4 to all three servers, `samba-dc01` included (its
   first CA-trust pass too).

   ```bash
   ansible-playbook playbooks/02-docker-server.yml --ask-vault-pass
   ```

   Installs Docker Engine and brings up all 5 Compose stacks (`docker/{reverse-proxy,nextcloud,
   onlyoffice,mail,wordpress,stirling-pdf}`) on `docker01` in one run.

   ```bash
   ansible-playbook playbooks/03-authentik.yml --ask-vault-pass
   ```

   Brings up Authentik and applies its OIDC/LDAP blueprints via
   [`bootstrap-authentik.sh`](../authentik/scripts/bootstrap-authentik.sh) — the actual
   bootstrap logic; Ansible's role here is just plumbing (copy the repo, render `.env`, invoke
   the script).

   ```bash
   ansible-playbook playbooks/99-backups.yml --ask-vault-pass
   ```

   Installs the daily backup timers for Samba AD (`samba-dc01`) and Docker volumes + PKI
   (`docker01`) — see [Backup.md](Backup.md).

3. Verify: `https://auth.lab.internal` loads with a trusted cert and you can sign in as
   `akadmin` (bootstrap credentials in `ansible/inventory/host_vars/authentik01/vault.yml`).
```

- [ ] **Step 2: Verify no stale references to `site.yml`-as-one-command remain in step 5**

Run: `grep -n "site.yml --ask-vault-pass" docs/DeploymentGuide.md`
Expected: no output within the step 5 section (a mention may still legitimately exist under
"One-shot re-runs" later in the file — Task 3 does not touch that section, so this check is
scoped to confirm step 5 itself no longer presents `site.yml` as the primary command).

---

### Task 3: Deepen step 6's per-app narrative and fix the stale `--tags apps` claim

**Files:**
- Modify: `docs/DeploymentGuide.md`

**Interfaces:** None — this task only edits prose in step 6, which Task 2 leaves untouched above it.

- [ ] **Step 1: Replace step 6's content**

Find:
```markdown
## 6. Applications

Still via `ansible-playbook playbooks/02-docker-server.yml --tags apps` (already included in
`site.yml`, listed separately here for iterative re-runs): brings up NextCloud, OnlyOffice,
Dovecot+Postfix, WordPress, and Stirling PDF Compose stacks under `docker/`, wired to Traefik
and to the OIDC/proxy providers created in step 5. Confirm:

- `https://cloud.lab.internal` → NextCloud, "Log in with Authentik" button present and working.
- `https://docs.lab.internal` → OnlyOffice Document Server status page.
- `mail.lab.internal:993` (IMAPS) / `:587` (submission) → see
  [docker/mail/README.md](../docker/mail/README.md) for a full send/receive test.
- `https://www.lab.internal` → WordPress, installed and ready (SSO is opt-in — see step 6a).
- `https://pdf.lab.internal` → Stirling PDF, prompts an Authentik login before showing the app
  (forward-auth, not native OIDC — see [docker/stirling-pdf/README.md](../docker/stirling-pdf/README.md)).
```

Replace with:
```markdown
## 6. Applications

NextCloud, OnlyOffice, Dovecot+Postfix, WordPress, and Stirling PDF all came up already, as part
of step 5's `02-docker-server.yml` run — this step is about understanding what you now have, not
deploying anything new. (To reapply this layer later, after editing a Compose file or `.env`,
re-run `ansible-playbook playbooks/02-docker-server.yml --ask-vault-pass` — it's idempotent, so
re-running the whole playbook to pick up one app's change is safe and cheap.)

- **NextCloud** (`https://cloud.lab.internal`) — file storage/groupware. Its "Log in with
  Authentik" button is OIDC against the identity provider you stood up in step 5: NextCloud
  never sees your AD password, only a token from Authentik. Confirm the button is present and
  working.
- **OnlyOffice** (`https://docs.lab.internal`) — the document-editing backend NextCloud calls
  out to for in-browser editing. It's a separate Compose stack/container, not bundled into
  NextCloud, so it can be updated or replaced independently. Confirm the Document Server status
  page loads.
- **Mail** (`mail.lab.internal:993` IMAPS / `:587` submission) — Dovecot and Postfix authenticate
  directly against Samba AD via LDAP bind, not OIDC — a different, older pattern worth
  contrasting with NextCloud's SSO button above. See
  [docker/mail/README.md](../docker/mail/README.md) for a full send/receive test.
- **WordPress** (`https://www.lab.internal`) — installed and ready; unlike the other apps, SSO
  here is opt-in rather than default (see step 6a) — a public-facing CMS doesn't always want
  every visitor routed through the internal identity provider.
- **Stirling PDF** (`https://pdf.lab.internal`) — a third distinct access-control pattern:
  forward-auth. Traefik asks Authentik "is this request allowed?" *before* proxying the request
  at all, rather than the app itself handling an OIDC login like NextCloud does. See
  [docker/stirling-pdf/README.md](../docker/stirling-pdf/README.md).
```

- [ ] **Step 2: Verify the stale `--tags apps` claim is gone**

Run: `grep -n "tags apps" docs/DeploymentGuide.md`
Expected: no output.

- [ ] **Step 3: Commit both step 5 and step 6 changes together**

```bash
git add docs/DeploymentGuide.md
git diff --cached --stat
git commit -m "$(cat <<'EOF'
Restructure DeploymentGuide.md steps 5-6 into staged, explained playbook runs

Step 5 now runs each of the 6 app-layer playbooks individually (matching
site.yml's own dependency order) instead of one site.yml invocation, with a
short "what this does and why" per stage. Step 6 turns the per-app
verification checklist into short narrative paragraphs contrasting
NextCloud's OIDC SSO, mail's direct LDAP bind, and Stirling PDF's
forward-auth — and drops a stale "--tags apps" reference that pointed at
tags no role or playbook actually defines.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Repo-wide verification sweep

**Files:** None modified — verification only.

**Interfaces:**
- Consumes: every file touched in Tasks 1-3.
- Produces: nothing — this is the plan's final confirmation step.

- [ ] **Step 1: Confirm no live file references the removed role/playbook**

Run:
```bash
grep -rln "samba_ad\|01-samba-ad\.yml" --include="*.yml" --include="*.md" --include="*.sh" . 2>/dev/null | grep -v '^\./docs/superpowers/'
```
Expected: no output.

- [ ] **Step 2: Confirm `site.yml`'s import list**

Run: `grep -A2 '^- import_playbook' ansible/playbooks/site.yml`
Expected: 6 `import_playbook` lines, in this order: `00-common-hardening.yml`,
`04-linux-client-join.yml`, `05-pki-trust.yml`, `02-docker-server.yml`, `03-authentik.yml`,
`99-backups.yml`. No `01-samba-ad.yml`.

- [ ] **Step 3: Confirm `ansible/roles/samba_ad/` no longer exists**

Run: `ls ansible/roles/samba_ad 2>&1`
Expected: "No such file or directory".

- [ ] **Step 4: Full-repo shell syntax sweep (confirms Task 1's deletions didn't break anything else)**

Run:
```bash
for f in $(find . -name "*.sh" -not -path "./.git/*"); do bash -n "$f" || echo "FAILED: $f"; done
```
Expected: no `FAILED:` lines.

- [ ] **Step 5: Read through `DeploymentGuide.md` steps 5-6 end to end**

Read the file and confirm: the staged commands in step 5 are in the same order as `site.yml`'s
import list (confirmed in Step 2 above), step 6 reads coherently as a continuation of step 5
rather than a new deployment action, and no leftover reference to the old one-command flow or
the stale `--tags apps` claim remains.
