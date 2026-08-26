# CLAUDE.md

Guidance for Claude Code (or any agent) working in this repository.

## What this is

A self-contained, IaC-driven homelab simulating a small organisation's IT estate on VMware
Workstation Pro (Windows/Linux) or Fusion Pro (macOS) — see
[hypervisor/README.md](hypervisor/README.md). Covers pfSense, Samba AD, an internal PKI,
Authentik SSO, a Docker application platform, and Windows/Linux endpoints.
It's a **teaching artifact** — code quality and doc clarity are
the product, not just a means to an end. Read [docs/Architecture.md](docs/Architecture.md)
before making structural changes; it explains the design principles and the trade-offs behind
them, and most of those trade-offs are deliberate, not oversights.

Domain: `lab.internal` / realm `LAB.INTERNAL` / NetBIOS `LAB` / subnet `10.10.10.0/24`. These
are placeholders re-derived by [`scripts/provision-business.sh`](scripts/provision-business.sh)
for spinning up additional "businesses" — see [docs/MultiBusiness.md](docs/MultiBusiness.md).

## Repository shape

- `docs/` — the authoritative documentation set. Every component has a doc; every doc is
  linked from `README.md`'s documentation index. If you add a component, add its doc and add
  the link — an undocumented component is an unfinished one here.
- `docker/` — one subdirectory per application stack (`docker-compose.yml`, `.env.example`,
  `README.md`). Base stacks (`reverse-proxy`, `authentik`, `nextcloud`, `onlyoffice`, `mail`,
  `wordpress`, `stirling-pdf`) are wired into `ansible/group_vars/docker_server.yml`'s
  `docker_compose_stacks` list and brought up automatically by `site.yml`.
- `federation/` — **optional, advanced, opt-in.** Multi-business bridging (IPSec/VPN), the
  class registry (shared CA + DNS), edge proxies, SPF/DKIM/DMARC. **Nothing under here is ever
  referenced by `ansible/playbooks/site.yml` or `docker_compose_stacks`.** If you add something
  to this layer, keep it that way — the base single-business lab must always deploy and run
  with `federation/` deleted entirely.
- `pki/`, `samba/`, `authentik/`, `ansible/`, `scripts/`, `desktop-apps/`, `hypervisor/`,
  `pfsense/` — see `docs/Architecture.md`'s repository layout section for what each owns.

## Conventions to follow

- **Secrets never committed.** Every stack takes a `.env.example` (committed) and reads `.env`
  (gitignored). Ansible secrets live in `ansible/inventory/host_vars/<host>/vault.yml`
  (gitignored; commit `vault.yml.example`). PKI private key material is always gitignored —
  see `.gitignore`'s dedicated sections before adding a new generated-material path.
- **Domain/subnet strings are literal, not templated, in most files.** `lab.internal`,
  `LAB.INTERNAL`, `DC=lab,DC=internal`, `10.10.10.` appear as plain text throughout scripts,
  compose files, and docs (Ansible-rendered `.j2` templates are the exception). This is
  intentional: `scripts/provision-business.sh` does a global sed sweep of exactly these
  patterns to re-base a whole copy of the repo onto a new identity. If you introduce a new
  hardcoded domain/subnet reference, use these same literal forms so the rename tool catches
  it — don't invent a new representation (no f-string-style interpolation, no alternate
  casing).
- **Least privilege by default.** New service accounts get their own AD user with no group
  memberships (see `samba/data/users.csv` for the pattern), never `Domain Admins`. New Docker
  services get `security_opt: [no-new-privileges:true]` and run as non-root where the image
  allows it.
- **Certificate validation is never disabled.** No `insecure_skip_verify`, no
  `verify=False`, anywhere, for any TLS connection this repo makes to itself. If two
  components need to trust each other, mount the relevant CA chain — see any existing
  `docker-compose.yml` for the pattern (`pki/intermediate-ca/certs/ca-chain.cert.pem` bind-
  mounted read-only).
- **pfSense is config-template-plus-instructions, not fully automated.** Don't try to script
  around this; it's a deliberate choice explained in `pfsense/README.md` and
  `docs/Architecture.md`'s trade-offs section.
- **Every shell script starts `set -euo pipefail`** (or `set -eu` for the few `#!/bin/sh`
  scripts, e.g. `federation/edge-proxy/dnsmasq/entrypoint.sh`) and sources
  `scripts/lib/common.sh` or `pki/scripts/lib/common.sh` where one already exists for that
  subtree, rather than re-declaring `log()`/`die()` helpers differently each time.
- **Avoid apostrophes inside `${VAR:?message}` parameter expansions.** This has already broken
  a script once in this repo (bash's lexer treats the quote as brace-matching-relevant even
  inside double quotes) — write around it rather than re-discovering it.

## Validating changes

There is no CI configured. Before considering a shell script done:

```bash
bash -n path/to/script.sh          # syntax check — do this for every script you touch or add
chmod +x path/to/script.sh          # scripts are tracked executable
```

For a broader sweep across the repo (useful after any multi-file change):

```bash
for f in $(find . -name "*.sh" -not -path "./.git/*"); do bash -n "$f" || echo "FAILED: $f"; done
```

There's no way to actually spin up the VMs/containers from this environment — changes to
compose files, Ansible roles, and Samba/pfSense scripts are reviewed for correctness by
reading, not by running. Be extra careful with anything touching `samba-tool`, `openssl ca`,
or `docker compose` invocations: get the syntax right the first time.

## Adding a new application stack

Follow the existing pattern (e.g. `docker/wordpress/` is a clean recent example):

1. `docker/<app>/docker-compose.yml` + `.env.example`, on the `lab-proxy` external network,
   Traefik labels for routing, `security_opt: [no-new-privileges:true]`.
2. `docker/<app>/README.md` explaining what it is and any non-obvious setup.
3. If it needs SSO: an OIDC blueprint under `authentik/blueprints/` (see
   `oidc-nextcloud.yaml`) or, if the app has no OIDC support, a forward-auth proxy provider
   (see `proxy-stirling-pdf.yaml` and the `authentik-forwardauth` Traefik middleware).
4. Add it to `ansible/group_vars/docker_server.yml`'s `docker_compose_stacks` and, if it needs
   rendered secrets, a template in `ansible/roles/docker_engine/templates/`.
5. Issue a cert (`pki/scripts/02-issue-server-cert.sh --cn <host>.lab.internal`) and add it to
   `Makefile`'s `pki-issue-all` and `scripts/deploy-all.sh`.
6. Update `diagrams/dns-architecture.md`'s zone table, `docs/Architecture.md`'s component
   inventory, and `docs/DeploymentGuide.md`'s applications step.

## What not to do

- Don't add anything to `federation/` that the base deploy path depends on.
- Don't silently change the default domain/subnet — that's a decision for the user, and there's
  already a supported path (`scripts/provision-business.sh`) for anyone who wants different
  values.
- Don't introduce a secrets-management dependency (Vault, etc.) — deliberately out of scope,
  see `docs/Security.md#secrets-management`.
- Don't commit generated PKI material, `.env` files, or anything else `.gitignore` already
  excludes, even "just for a demo."
