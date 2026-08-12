# LAB Internet — Skeleton

**Not implemented yet.** See [docs/LabInternet.md](../../docs/LabInternet.md) for the full
design, the workflow these scripts are meant to drive, and exactly what's blocking a working
implementation (short version: three-label domain support, a CSR cross-signing workflow, and a
non-AD-integrated delegating root DNS server).

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
