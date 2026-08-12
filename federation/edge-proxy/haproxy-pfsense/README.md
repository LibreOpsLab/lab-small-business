# Alternative: HAProxy on pfSense

The lower-friction alternative to [`../caddy/`](../caddy/) — no new container/VM, reuses the
pfSense box every business already has. pfSense's HAProxy package handles TLS termination +
Host-header-based routing for cross-business traffic the same way Caddy does, just configured
through the pfSense GUI/package system instead of a Caddyfile (consistent with how this repo
treats all pfSense config — see [`pfsense/README.md`](../../../pfsense/README.md)).

**dnsmasq is still needed either way** — see [`../dnsmasq/`](../dnsmasq/) — HAProxy replaces
only the Caddy piece, not the DNS-delegation-answer piece.

## Setup

1. **Install the package**: pfSense GUI → System → Package Manager → Available Packages →
   search "haproxy" → Install.
2. **Certificates**: System → Cert Manager → Certificates → Import, paste in the contents of
   `federation/class-registry-cert/<name>.cert.pem` (certificate) and
   `federation/class-registry-cert/<name>.key.pem` (private key) — from
   [`federation/scripts/request-class-cert.sh`](../../scripts/request-class-cert.sh)'s output.
   Repeat for the CA chain if HAProxy's config wants it separately (`<name>.ca-chain.pem`).
3. **Backend**: Services → HAProxy → Backends → Add:
   - Name: `internal-traefik`
   - Server: `10.10.0.20` (docker01), port `443`, SSL: yes, "Verify SSL Certificate": add your
     business's own PKI chain (`pki/intermediate-ca/certs/ca-chain.cert.pem`) as the backend's
     trusted CA — the same "validate, don't disable" principle as the Caddy setup's
     `tls_trust_pool` directive. Do not check "no SSL verification."
4. **Frontend**: Services → HAProxy → Frontends → Add:
   - Listen address: WAN address, port `443`
   - SSL Offloading: yes, select the certificate imported in step 2
   - Access Control List: match `Host` header per internal hostname (e.g.
     `cloud.<name>.lab.internet` → forward to `internal-traefik` backend with the request's
     `Host` header **rewritten** to `cloud.<name>.internal` under Actions → "Http Request Rules"
     → "Set Host header" — this is the same Host-rewrite trick the Caddyfile uses, so Traefik's
     existing internal routing needs no changes.
5. **Firewall**: Firewall → Rules → WAN → allow TCP/443 from any to this pfSense's WAN address
   (scoped further if your exercise calls for it — see
   [docs/Security.md](../../../docs/Security.md#firewall-recommendations-pfsense)).

## Why this exists as an alternative

Caddy needs a place to run (a container on `docker01`, or a small dedicated VM) and its own
port-forward. HAProxy-on-pfSense needs neither — it reuses hardware/infrastructure every
business already has, at the cost of GUI-driven setup instead of a version-controlled
Caddyfile. Pick whichever fits your course better; both terminate TLS with the same
class-CA-signed certificate and route on Host header the same way.
