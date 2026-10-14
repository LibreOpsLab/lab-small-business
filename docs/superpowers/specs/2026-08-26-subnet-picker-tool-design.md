# Subnet Picker Tool — Design

## Context

This is sub-project **D** of a five-part restructuring effort (D → A → C → B → E) aimed at
de-automating the teaching path: reduce heavy automation on the VMware desktop path, extract
Proxmox/ESXi automation into a separate server-automation repo, turn the app-layer deployment
into guided manual stages, and rework `federation/` as lecturer-built content. D is scoped
narrowly and implemented first because the other four sub-projects will produce or reference
config/docs that embed the subnet literal, so getting the subnet-choice tooling right (and
correct) first avoids rework later.

The repo's default subnet is `10.10.10.0/24` (per `CLAUDE.md`), appearing as a literal string —
not templated — throughout scripts, compose files, and docs, by deliberate design: it lets a
sed-based rebase tool re-stamp the whole repo onto a new subnet. That tool already exists,
`scripts/provision-business.sh`, but it rebases a business's *entire identity* (domain, realm,
NetBIOS, subnet) into a fresh copy — there's no lightweight way to just pick a different subnet
without also renaming the domain/NetBIOS.

**Bug found during this design pass:** `scripts/provision-business.sh` line 118 sweeps for the
literal `10\.10\.0\.` when rewriting the subnet, but the repo migrated its default subnet from
`10.10.0.0/24` to `10.10.10.0/24` on 2026-08-24. The line 96 warning check was updated to
`10.10.10.` at the time, but the actual rewrite sweep on line 118 was missed — so today,
`provision-business.sh` silently fails to rewrite any subnet references at all. This is fixed as
part of this work, since the corrected sweep pattern is exactly the logic being extracted.

## Goal

1. A new standalone tool, `scripts/set-subnet.sh`, that lets a user pick a subnet at setup time
   (or later) without touching domain/NetBIOS identity — the last-octet-only concern.
2. Deduplicate the copy-and-rewrite logic shared between `set-subnet.sh` and
   `provision-business.sh` into `scripts/lib/business-rebase.sh`, fixing the stale-pattern bug in
   the process.
3. Document `10.10.10.0/24` as a suggested starter, with a pointer to `set-subnet.sh` for anyone
   who needs a different one, in the deployment flow.

## Non-goals

- No PKI regeneration: confirmed by grep that no certificate SANs, CNs, or config under `pki/`
  contain IP literals (SANs are hostnames, e.g. `docker01.lab.internal`), so a subnet change
  doesn't invalidate any issued certificate.
- No change to `provision-business.sh`'s CLI or externally-visible behavior beyond the bug fix —
  it still takes `--name --domain --netbios --subnet`.
- No interactive prompts. Both tools stay non-interactive, flag/positional-arg driven, consistent
  with every other script in this repo.

## Design

### `scripts/lib/business-rebase.sh` (new)

Sourced by both `provision-business.sh` and `set-subnet.sh`, alongside the existing
`scripts/lib/common.sh` (for `log()`/`warn()`/`die()`). Exposes:

- `copy_repo <src> <dst>` — the existing rsync-with-cp-fallback block from
  `provision-business.sh` (excludes `.git`, `pki/root-ca`, `pki/intermediate-ca`, `pki/issued`,
  `*.env`, `**/.generated-secrets`, vault.yml files), lifted verbatim, parameterized on
  src/dst instead of hardcoded to `REPO_ROOT`/`OUTPUT`.
- `validate_subnet <cidr>` — the existing RFC1918 `/24` validation (regex + octet-range checks
  for 10.x, 172.16-31.x, 192.168.x), extracted unchanged from `provision-business.sh`, returning
  the validated prefix (e.g. `10.20.30`) on stdout for the caller to use.
- `rewrite_subnet <dir> <old_prefix> <new_prefix>` — corrected grep+sed sweep: greps for
  `<old_prefix>\.` literally (not the stale `10\.10\.0\.`) and rewrites every matching file's
  occurrences of `<old_prefix>.` to `<new_prefix>.`.

`provision-business.sh` is refactored to source this lib and call `copy_repo`,
`validate_subnet`, and `rewrite_subnet` instead of its inlined versions; its own
domain/realm/NetBIOS rewrite logic stays local (nothing else needs it). No change to its
argument parsing, validation error messages, or output.

### `scripts/set-subnet.sh` (new)

```
scripts/set-subnet.sh <new-subnet-cidr> [--output <dir>] [--force]
```

- `<new-subnet-cidr>`: positional, required, e.g. `10.20.30.0/24`. Validated via
  `validate_subnet` from the shared lib.
- `--output <dir>`: optional. Defaults to `../<current-dirname>-<last-octet>` (e.g.
  `../lab-small-business-30` for `10.20.30.0/24`), mirroring `provision-business.sh`'s
  `../${NAME}-lab` default pattern.
- `--force`: overwrite a non-empty output directory, same semantics as
  `provision-business.sh --force`.

Behavior: validate the new subnet, refuse if it matches the repo's current subnet (nothing to
do), copy the repo via `copy_repo`, rewrite via `rewrite_subnet` (old prefix is always
`10.10.10` — the repo's checked-in default; this tool is specifically for rebasing *from* the
shipped default, not for chaining rebases of an already-rebased copy), write a short provenance
note into the copy's `README.md` (same pattern as `provision-business.sh`'s banner, scoped to
just noting the subnet change), and log next steps (`cd <output>`, continue the deployment
guide from there).

### Documentation integration

- `docs/DeploymentGuide.md`: new early step, before any VM work: "This lab defaults to
  `10.10.10.0/24`. If that collides with your home/office network or you just want a different
  range, run `scripts/set-subnet.sh <new-cidr>` now and do the rest of this guide from the
  resulting copy." Placed before the hypervisor-selection step so it's the very first decision.
- `hypervisor/README.md` and `docs/Architecture.md`'s domain/subnet section: one-line pointer to
  `set-subnet.sh` alongside the existing `provision-business.sh` mention.
- `scripts/provision-business.sh`'s header comment gets a one-line note that subnet-only changes
  can use the lighter-weight `set-subnet.sh` instead.

## Testing

- `bash -n` on all three touched/new scripts (per `CLAUDE.md`'s validation convention).
- Manual dry run: run `set-subnet.sh 10.20.30.0/24 --output /tmp/.../subnet-test`, grep the
  output for stray `10.10.10.` occurrences (should find none outside `.git`-excluded or
  intentionally-unrelated matches like unrelated third-party example IPs, if any exist — verify
  by inspection), and confirm `provision-business.sh`'s subnet rewrite now actually fires (grep
  the output of a `provision-business.sh` dry run for the new subnet prefix instead of the stale
  one).
- Confirm `chmod +x` on the new script per repo convention.

## Open questions

None — this sub-project is fully scoped by the design above.
