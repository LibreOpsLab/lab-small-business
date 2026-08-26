# Federation Lecturer-Guided Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the class-registry lecturer setup from 2 opaque commands into 4 explained, individually-runnable steps in `docs/ClassRegistry.md`, keep `init-registry.sh` as a documented fast-path, and simplify `federation/class-registry/README.md`'s duplicate quick-start to point at the now-canonical staged version.

**Architecture:** Pure documentation restructuring — no script or config logic changes. `docs/ClassRegistry.md`'s "End-to-end workflow" section gets the 4-step lecturer breakdown; `federation/class-registry/README.md`'s "Quick start (lecturer)" section is trimmed to a pointer; `init-registry.sh` gets one comment line added.

**Tech Stack:** Markdown + a single bash comment edit. No test framework applicable.

**Spec:** [docs/superpowers/specs/2026-08-26-federation-lecturer-guided-setup-design.md](../specs/2026-08-26-federation-lecturer-guided-setup-design.md)

## Global Constraints

- No changes to `init-class-ca.sh`, `bind/named.conf`, `app/app.py`, `docker-compose.yml`, or `.env.example` — all stay exactly as they are.
- No changes to any student-facing federation script or doc (`register-with-class.sh`, `request-class-cert.sh`, `deploy-class-ca-trust.sh`/`.ps1`, `federation/edge-proxy/`, `MultiBusiness.md`, `LabInternet.md`).
- `federation/lab-internet/` is untouched.
- `init-registry.sh` is not removed and its logic is not changed — only its header comment gains one line.

---

### Task 1: Stage the lecturer workflow in `docs/ClassRegistry.md` and simplify the class-registry README

**Files:**
- Modify: `docs/ClassRegistry.md`
- Modify: `federation/class-registry/README.md`

**Interfaces:** None — both are documentation-only edits with no other file depending on their exact wording.

- [ ] **Step 1: Replace `docs/ClassRegistry.md`'s "Lecturer, once" block**

Find:
```markdown
**Lecturer, once:**

```bash
cd federation/class-registry
./scripts/init-registry.sh --ns-ip <this-host's-reachable-IP>
docker compose up -d
```

Give students the registry URL and the printed `CLASS_REGISTRY_TOKEN`.
```

Replace with:
```markdown
**Lecturer, once.** Four things need to exist before the registry can run — each is small
enough to do by hand and worth understanding once, since this is the one piece of `federation/`
you're not just handing to students pre-built. `init-registry.sh` does all four in one shot as a
documented fast-path once you've been through them (see the end of this section).

1. **A shared secret between BIND9 and the registry container.** The registry rewrites the DNS
   zone and tells BIND9 to reload it via `rndc` — TSIG-authenticated, so the two containers need
   a shared key:

   ```bash
   cd federation/class-registry
   mkdir -p bind/keys
   SECRET="$(openssl rand -base64 32)"
   cat > bind/keys/rndc.key <<EOF
   key "rndc-key" {
       algorithm hmac-sha256;
       secret "${SECRET}";
   };
   EOF
   chmod 600 bind/keys/rndc.key
   ```

2. **Seed the `lab.internet` zone.** BIND9 needs a starting zone file with your registry host's
   own NS/A glue record before it can serve anything — the registry app rewrites this file on
   every student registration from here on
   ([`app/app.py`](../federation/class-registry/app/app.py)'s `regenerate_zone_file()`):

   ```bash
   sed "s/__ZONE_NS_IP__/<this-host's-reachable-IP>/" \
     bind/zones/db.lab.internet.seed > bind/zones/db.lab.internet
   ```

3. **Initialise the class CA.** This is the single-tier, online-key CA described in "PKI
   design" above — run it explicitly and read its output, since it explains the trade-off
   you're accepting:

   ```bash
   ./ca/init-class-ca.sh
   ```

4. **Configure the registry's `.env`.**

   ```bash
   cp .env.example .env
   # edit .env: set CLASS_REGISTRY_TOKEN to a random value students will need to register,
   # and ZONE_NS_IP to the same IP used in step 2
   ```

Then bring it up:

```bash
docker compose up -d
```

Give students the registry URL and the token from `.env`.

**Fast-path for later course offerings**: once you've done the above by hand and understand what
each piece does,
[`scripts/init-registry.sh --ns-ip <ip>`](../federation/class-registry/scripts/init-registry.sh)
does steps 1-4 in one command (idempotent — safe to re-run) — then just `docker compose up -d`.
```

- [ ] **Step 2: Replace `federation/class-registry/README.md`'s "Quick start (lecturer)" section**

Find:
```markdown
## Quick start (lecturer)

```bash
cd federation/class-registry
./scripts/init-registry.sh --ns-ip <this-host's-IP-students-can-reach>
docker compose up -d
```

Then give students: the registry URL (`http://<ns-ip>:8080`) and the generated
`CLASS_REGISTRY_TOKEN` (printed by `init-registry.sh`, also in `.env`).
```

Replace with:
```markdown
## Quick start (lecturer)

See [docs/ClassRegistry.md#end-to-end-workflow](../../docs/ClassRegistry.md#end-to-end-workflow)
for the staged, explained setup (shared BIND/registry secret, DNS zone seed, class CA init,
`.env`) — worth reading through once. [`scripts/init-registry.sh`](scripts/init-registry.sh) is
the fast-path once you've done it by hand.
```

- [ ] **Step 3: Verify both files read coherently and no orphaned references remain**

Run:
```bash
grep -n "Lecturer, once" docs/ClassRegistry.md
grep -n "init-registry.sh --ns-ip" federation/class-registry/README.md
```
Expected: the first finds the new "Lecturer, once." sentence (note: now ends in a period, not a
colon, since it's followed by prose, not immediately a command block); the second finds no
output (the duplicated command block is gone from the README).

- [ ] **Step 4: Commit**

```bash
git add docs/ClassRegistry.md federation/class-registry/README.md
git commit -m "$(cat <<'EOF'
Stage the class-registry lecturer setup into explained steps

docs/ClassRegistry.md's "Lecturer, once" block goes from 2 opaque commands
to 4 explained steps (shared rndc/TSIG key, DNS zone seed, class CA init,
.env config) plus docker compose up - matching the guided pattern from
sub-projects A and C. init-registry.sh stays as a documented fast-path.
federation/class-registry/README.md's duplicate quick-start now points to
the staged version instead of repeating it.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Point `init-registry.sh` at the staged documentation, verify

**Files:**
- Modify: `federation/class-registry/scripts/init-registry.sh`

**Interfaces:** None — comment-only change.

- [ ] **Step 1: Add a doc pointer to the header comment**

Find:
```bash
#!/usr/bin/env bash
# One-time setup, run by the lecturer before the first `docker compose up`: generates the
# rndc/TSIG key BIND9 and the registry container share, seeds the initial zone file, and
# initialises the class CA. Safe to re-run (skips anything already present).
#
# Usage: ./scripts/init-registry.sh --ns-ip <this-host's-IP-students-will-reach-it-on>
```

Replace with:
```bash
#!/usr/bin/env bash
# One-time setup, run by the lecturer before the first `docker compose up`: generates the
# rndc/TSIG key BIND9 and the registry container share, seeds the initial zone file, and
# initialises the class CA. Safe to re-run (skips anything already present).
#
# This is the fast-path version of 4 steps worth understanding individually the first time —
# see docs/ClassRegistry.md#end-to-end-workflow for what each one does and why.
#
# Usage: ./scripts/init-registry.sh --ns-ip <this-host's-IP-students-will-reach-it-on>
```

- [ ] **Step 2: Syntax check**

Run: `bash -n federation/class-registry/scripts/init-registry.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
git add federation/class-registry/scripts/init-registry.sh
git commit -m "$(cat <<'EOF'
Point init-registry.sh at the new staged documentation

One-line addition so a lecturer who opens the script directly knows where
the explained, step-by-step version of what it automates lives.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Repo-wide verification sweep**

Run:
```bash
for f in $(find . -name "*.sh" -not -path "./.git/*"); do bash -n "$f" || echo "FAILED: $f"; done
```
Expected: no `FAILED:` lines.

Run:
```bash
grep -rn "init-registry.sh --ns-ip.*docker compose up" docs/ federation/ 2>/dev/null
```
Expected: no output (confirms no other doc still shows the old 2-command block verbatim).
