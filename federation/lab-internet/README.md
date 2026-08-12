# LAB Internet — Skeleton

**Superseded for most uses by [`federation/class-registry/`](../class-registry/) — see
[docs/ClassRegistry.md](../../docs/ClassRegistry.md), which is implemented and working.** This
directory remains a stub for the deeper variant (cross-signing every business's own Issuing
CA, not just their edge-proxy cert) — see [docs/LabInternet.md](../../docs/LabInternet.md) for
what that would still need (short version: three-label domain support, a CSR cross-signing
workflow for the Issuing CA specifically, and a non-AD-integrated delegating root DNS server —
the last of which `class-registry/` already builds, reusable if you extend this further).

The four scripts in [`scripts/`](scripts/) are stubs: each prints what it will do, what it
needs as input, and which prerequisite from [docs/LabInternet.md#implementation-status](../../docs/LabInternet.md#implementation-status)
blocks it, then exits non-zero. They exist so a future implementation pass has a reviewed
starting shape (argument parsing, expected inputs/outputs, sequencing) rather than a blank
page — run them to see the intended interface, not to get working output.

| Script | Run by | Purpose (once implemented) |
|---|---|---|
| `init-lecturer-root-ca.sh` | Lecturer | Create the LAB Internet Root CA + empty root DNS zone |
| `request-subordinate-ca.sh` | Each business | Generate an Issuing CA CSR + DNS delegation request for the lecturer |
| `approve-business.sh` | Lecturer | Sign a business's CSR, add its DNS delegation |
| `install-subordinate-ca.sh` | Each business | Install the lecturer-signed Issuing CA + point DNS forwarding at the root |
