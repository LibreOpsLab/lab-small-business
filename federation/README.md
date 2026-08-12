# Federation

**Everything in this directory is optional.** The base lab ([docs/DeploymentGuide.md](../docs/DeploymentGuide.md))
is one complete, self-contained business deployment and needs none of this. `federation/` is a
separate, opt-in layer for courses running *multiple* businesses that want to interconnect —
nothing here is referenced by `ansible/playbooks/site.yml` or any base `docker_compose_stacks`
entry.

## Two ways to connect businesses

| | [docs/MultiBusiness.md](../docs/MultiBusiness.md) | [docs/ClassRegistry.md](../docs/ClassRegistry.md) |
|---|---|---|
| Connects | Exactly two businesses, peer-to-peer | Any number, via one shared lecturer-run registry |
| Gives you | Network reachability (IPSec) or remote access (WireGuard/OpenVPN) | Trusted HTTPS + real DNS delegation across every registered business |
| Shared infrastructure | None — fully decentralized, manifests exchanged out-of-band | A registry the lecturer runs (CA + DNS) |
| Setup effort | Lower, per-pair | One-time lecturer setup, then self-service per business |

Use one, both, or neither — they're independent and don't conflict.

## Contents

- [`scripts/`](scripts/) — IPSec/WireGuard generators
  ([MultiBusiness.md](../docs/MultiBusiness.md)) and class-registry client scripts
  ([ClassRegistry.md](../docs/ClassRegistry.md)): `register-business.sh`,
  `generate-ipsec-partner-config.sh`, `generate-wireguard-roadwarrior.sh`,
  `register-with-class.sh`, `request-class-cert.sh`, `deploy-class-ca-trust.sh`/`.ps1`.
- [`registry/`](registry/), [`wireguard-clients/`](wireguard-clients/) — generated
  MultiBusiness manifests/configs (gitignored).
- [`class-registry/`](class-registry/) — the lecturer-run registry app itself (Flask + BIND9 +
  a single-tier CA) — see [`class-registry/README.md`](class-registry/README.md).
- [`edge-proxy/`](edge-proxy/) — per-business Caddy/HAProxy + dnsmasq setup that consumes a
  class-registry-issued certificate.
- [`lab-internet/`](lab-internet/) — stubs for a deeper (not-built) variant of ClassRegistry.md
  that cross-signs every business's own Issuing CA, not just their edge-proxy cert. See
  [docs/LabInternet.md](../docs/LabInternet.md).

## Why the MultiBusiness scripts aren't more automated

Two independently-deployed businesses connecting peer-to-peer have no shared control plane by
design — that's the point of the exercise (real B2B partnerships work the same way: you don't
get API access to your partner's firewall). Every IPSec/WireGuard step either produces a
manifest to exchange manually, or prints pfSense GUI field values to enter by hand. The Class
Registry (above) is the alternative for when you *do* want shared infrastructure — a lecturer
running one thing everyone opts into, rather than N² manual pairings.
