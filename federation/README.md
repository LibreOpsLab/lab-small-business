# Federation

Tooling for bridging independently-deployed "business" instances of this lab together. See
[docs/MultiBusiness.md](../docs/MultiBusiness.md) for the full design and workflow — this
directory is the automation that doc walks through.

## Contents

- [`scripts/register-business.sh`](scripts/register-business.sh) — writes this business's
  public connection manifest (domain, subnet, WAN endpoint) to `registry/<name>.yaml`, to send
  a partner business out-of-band.
- [`scripts/generate-ipsec-partner-config.sh`](scripts/generate-ipsec-partner-config.sh) — given
  your manifest and a partner's, generates matched pfSense IPSec Phase 1/2 field values plus a
  scoped (not subnet-wide) firewall rule for both sides.
- [`scripts/generate-wireguard-roadwarrior.sh`](scripts/generate-wireguard-roadwarrior.sh) —
  generates a WireGuard (or `--openvpn` field values) client config for one remote user, scoped
  to specific hosts.
- `registry/` — received/generated business manifests (gitignored — see
  [MultiBusiness.md](../docs/MultiBusiness.md#workflow-partnering-two-businesses-via-ipsec)).
- `wireguard-clients/` — generated client configs with private keys (gitignored).

## Why this isn't more automated

Two independently-deployed businesses have no shared control plane by design — that's the
point of the exercise (real B2B partnerships work the same way: you don't get API access to
your partner's firewall). Every step here either produces a manifest to exchange manually, or
prints pfSense GUI field values to enter by hand, mirroring how this would actually be done
between two organisations that don't trust each other with infrastructure-level access.
