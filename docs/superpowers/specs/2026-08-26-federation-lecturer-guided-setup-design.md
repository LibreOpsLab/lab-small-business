# Federation Lecturer-Guided Setup — Design

## Context

This is sub-project **E** of a five-part restructuring effort (D → A → C → B → E) — the last.
D, A, C, and B are implemented. Per the originating request: `federation/` stays in the repo,
but is redesigned "for the Lecturer to build themselves," a mix of manual and automated.

Investigation found that most of `federation/` already fits this description. The student-facing
side — `register-with-class.sh`, `request-class-cert.sh`, `deploy-class-ca-trust.sh`,
`federation/edge-proxy/` (dnsmasq + Caddy/HAProxy), and every `MultiBusiness.md` peer-to-peer
script — is already multi-step, hands-on, and explicitly documented as deliberately non-automated
(`federation/README.md`'s own "Why the MultiBusiness scripts aren't more automated" section).
The one piece that's a pure black-box turnkey deployment is the **lecturer's** side: standing up
`federation/class-registry/` (Flask + BIND9 + a single-tier CA) is currently two opaque commands
— `init-registry.sh --ns-ip <ip>` followed by `docker compose up -d` — with no visibility into
what gets set up or why.

## Goal

Restructure the lecturer-facing class-registry setup documentation
(`docs/ClassRegistry.md`, `federation/class-registry/README.md`) so the four distinct things
`init-registry.sh` currently does silently — generate a shared rndc/TSIG key, seed the DNS zone,
initialise the class CA, configure `.env` — become explained, individually-run steps, the same
pattern established for VM building (sub-project A) and the app layer (sub-project C).
`init-registry.sh` stays in the repo as a documented fast-path for a lecturer who's already done
this once or is redeploying for a new course offering.

## Non-goals

- **No changes to any script's or config's actual logic.** `init-class-ca.sh`,
  `bind/named.conf`, `app/app.py`, `docker-compose.yml`, `.env.example` — all stay exactly as
  they are; they're already complete, well-commented artifacts.
- **No changes to student-facing federation content.** `register-with-class.sh`,
  `request-class-cert.sh`, `deploy-class-ca-trust.sh`/`.ps1`, `federation/edge-proxy/` (all
  three sub-directories), and every `MultiBusiness.md`/`LabInternet.md`-related script — already
  appropriately staged and hands-on, per this design's investigation.
- **`init-registry.sh` is not removed** — kept as an explicit, documented fast-path, matching
  `site.yml`'s treatment in sub-project C, not `create-vms.ps1`'s removal in sub-project A. The
  distinguishing factor: `init-registry.sh` orchestrates otherwise-independent setup steps (like
  `site.yml`), it doesn't replace an interactive process with a black-box unattended install
  (like `create-vms.ps1` did).
- **`federation/lab-internet/`** (already explicitly "stubs for a deeper, not-built variant" per
  `federation/README.md`) is untouched — same treatment ESXi got in sub-project B: out of scope,
  not a status quo this sub-project needs to change.

## Design

### `docs/ClassRegistry.md`'s "End-to-end workflow" section

The current "Lecturer, once" block:
```bash
cd federation/class-registry
./scripts/init-registry.sh --ns-ip <this-host's-reachable-IP>
docker compose up -d
```
is replaced with 4 explained, individually-runnable steps, framed by one sentence explaining why
they're worth doing by hand once: this is the one piece of `federation/` the lecturer isn't just
handing to students pre-built.

1. **Shared rndc/TSIG key** between BIND9 and the registry container — the registry rewrites the
   DNS zone and tells BIND9 to reload it via `rndc`, TSIG-authenticated, so the two containers
   need a shared secret:
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
2. **Seed the `lab.internet` zone** — BIND9 needs a starting zone file with the registry host's
   own NS/A glue record; the registry app rewrites this file on every student registration from
   here on (`app/app.py`'s `regenerate_zone_file()`):
   ```bash
   sed "s/__ZONE_NS_IP__/<this-host's-reachable-IP>/" \
     bind/zones/db.lab.internet.seed > bind/zones/db.lab.internet
   ```
3. **Initialise the class CA** — calling `./ca/init-class-ca.sh` explicitly as its own step; the
   script already prints a full explanation of the single-tier, online-key trade-off (see "PKI
   design" above), so this document doesn't re-explain it, just calls it out as a distinct,
   worth-reading step rather than a buried sub-call.
4. **Configure `.env`** — copy `.env.example`, set `CLASS_REGISTRY_TOKEN` and `ZONE_NS_IP`
   (same IP as step 2).

Then `docker compose up -d`, followed by the existing "give students the URL and token" line
(unchanged). Closes with a "Fast-path for later course offerings" paragraph: once the lecturer
understands the four steps, `init-registry.sh --ns-ip <ip>` does all four idempotently.

### `federation/class-registry/README.md`'s "Quick start (lecturer)" section

Drops the duplicated 3-line block. Points to
`docs/ClassRegistry.md#end-to-end-workflow` for the staged, explained version, and names
`scripts/init-registry.sh` as the fast-path — matching the existing pattern elsewhere in this
repo where a directory-level README points to its canonical guide instead of duplicating steps
(e.g. `pfsense/README.md` → `docs/DeploymentGuide.md`).

### `federation/class-registry/scripts/init-registry.sh`

One-line addition to the header comment pointing at
`docs/ClassRegistry.md#end-to-end-workflow`, so a lecturer who opens this script directly (rather
than reading the docs first) knows where the explained, step-by-step version lives.

## Testing

No test suite. Verification is:

- `bash -n federation/class-registry/scripts/init-registry.sh` (only script touched, and only by
  a comment addition — no logic change).
- Manual read-through of `docs/ClassRegistry.md`'s new staged section, confirming the four
  commands, run in order, reproduce exactly what `init-registry.sh` currently does (cross-checked
  against its source).
- Grep sweep confirming no other doc references the old 3-line "Lecturer, once" block or is left
  inconsistent with the new staged version.

## Open questions

None — this sub-project is fully scoped by the design above.
