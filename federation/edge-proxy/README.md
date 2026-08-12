# Edge Proxy

Each business's "front door" for cross-business ("class internet") traffic — the piece that
takes the class-CA-signed certificate from
[`federation/scripts/request-class-cert.sh`](../scripts/request-class-cert.sh) and actually
terminates HTTPS with it, routing into the business's existing internal Traefik stack without
changing anything about how Traefik itself is configured. See
[docs/ClassRegistry.md#edge-proxy-setup](../../docs/ClassRegistry.md#edge-proxy-setup) for how
this fits into the full registration → cert → DNS → proxy workflow.

## Two options

| | [`caddy/`](caddy/) | [`haproxy-pfsense/`](haproxy-pfsense/) |
|---|---|---|
| Runs where | New container on `docker01` | Existing pfSense box (package) |
| Config | Version-controlled `Caddyfile` | pfSense GUI |
| New infrastructure needed | One more container + one port-forward | None — reuses pfSense |
| Best for | Teaching config-as-code reverse proxying | Lower setup friction, teaching pfSense's fuller feature set |

Both terminate TLS with the same class-CA cert and rewrite the `Host` header to reuse
Traefik's existing internal routing unchanged — pick one, not both.

## Also required either way: [`dnsmasq/`](dnsmasq/)

The edge proxy handles HTTPS; a business still needs *something* answering DNS for
`*.<name>.lab.internet` at the same edge IP (the NS delegation the class registry set up
points there). [`dnsmasq/`](dnsmasq/) is a tiny, purpose-built answer for exactly that — it is
not a choice alongside Caddy/HAProxy, it's a required companion to either.

## Setup order

1. Register with the class registry
   ([`federation/scripts/register-with-class.sh`](../scripts/register-with-class.sh)).
2. Get your edge cert signed
   ([`federation/scripts/request-class-cert.sh`](../scripts/request-class-cert.sh)).
3. Stand up `dnsmasq/` (DNS answer for your delegated zone).
4. Stand up `caddy/` or `haproxy-pfsense/` (HTTPS termination + routing).
5. Port-forward on your pfSense: WAN:53 → your edge IP:53, WAN:443 → your edge IP's HTTPS
   listener (`:8443` for the Caddy option, `:443` for the HAProxy-on-pfSense option since it
   *is* pfSense).
6. Ask a classmate on another business to try `https://cloud.<your-name>.lab.internet` — and
   trust the class CA first (
   [`federation/scripts/deploy-class-ca-trust.sh`](../scripts/deploy-class-ca-trust.sh) /
   `.ps1`) or they'll see a cert warning even though everything else worked.
