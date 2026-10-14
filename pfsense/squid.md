# Squid web proxy on pfSense

A filtering forward proxy: LAN clients send web requests to it, and it applies rules, caches,
and logs them. It lives **on pfSense** (or whichever firewall sits outside the hypervisor), not
in a Proxmox guest. Reason: it should sit on the path that all LAN traffic must cross, and a
proxy that runs on the same hypervisor it protects can be bypassed or taken down with it.

Like the rest of pfSense in this repo, this is **instructions, not automation** (see
[README.md](README.md)). Menu names below are for the pfSense Squid package; confirm them on
your pfSense version, and note any differences.

## Forward proxy or reverse proxy?

| | Forward proxy (this page) | Reverse proxy (Traefik, `docker/reverse-proxy`) |
| - | - | - |
| Acts for | Clients going out | Servers being reached |
| Typical jobs | Filtering, caching, logging, authentication of users | TLS termination, routing by hostname, SSO gate |

## Install

1. System > Package Manager > Available Packages: install **squid**. (Optionally
   **squidGuard** for category blocklists.)
2. Services > Squid Proxy Server > **Local Cache**: keep the defaults for the lab. Save.
3. Services > Squid Proxy Server > **General**:
   - Proxy Interface(s): **LAN** (and loopback).
   - Proxy Port: `3128`.
   - Allow Users on Interface: ticked.
   - Transparent proxy: **off** to begin with (see below).
   - Enable Squid, Save.

## Access control

Services > Squid Proxy Server > **ACLs**:

- Allowed Subnets: `10.10.10.0/24`.
- Blacklist: a few domains to test, one per line, for example `example.org`.
- Whitelist: `lab.internal` so internal sites never go through the filter.

Without an allow list, an open proxy is an abuse risk. Check that the WAN has no rule letting
port 3128 in.

## Point clients at it

- Linux: `export https_proxy=http://10.10.10.1:3128` (or set it in the system proxy settings).
- Windows: Settings > Network > Proxy > manual, `10.10.10.1`, port `3128`; better, set it by GPO.
- Test: `curl -I -x http://10.10.10.1:3128 https://www.debian.org` returns headers; the
  blacklisted domain returns an access-denied page.
- Watch the traffic: Services > Squid Proxy Server > Real Time, or `/var/squid/logs/access.log`.

## HTTPS: what the proxy can and cannot see

For `https://` sites the client sends `CONNECT host:443` and the proxy tunnels encrypted bytes.
It can allow or block by **hostname** but cannot see paths or content. Inspecting content
means "SSL bump": the proxy impersonates sites using a certificate from its own CA, which every
client must trust.

- Do this only with a CA you control. The lab's PKI ([PKI.md](../docs/PKI.md)) can issue a
  dedicated intermediate for it.
- It breaks apps that pin certificates, and it makes the proxy a high-value target.
- The repo rule still applies: the proxy must **validate the real site's certificate**.
  Never configure it to ignore upstream certificate errors.
- Treat it as an advanced stretch exercise; hostname filtering needs no bumping.

## Transparent mode

Transparent mode redirects port 80 traffic through Squid with a firewall rule, so clients need
no settings. Convenient, but HTTPS cannot be transparently filtered by hostname without bumping
or SNI inspection, and failures are harder to diagnose. Start explicit, then try transparent as
a comparison.

## Make it harder to bypass

A proxy only filters clients that use it. As an exercise, add LAN firewall rules so only the
proxy (and pfSense itself) may reach the Internet on 80 and 443, and see what breaks.
Then compare the Squid log with what the Grafana dashboard shows.

## Monitoring

Add `10.10.10.1:3128` to the `probe-tcp` job in
[`docker/monitoring/prometheus/prometheus.yml`](../docker/monitoring/prometheus/prometheus.yml)
(see [Monitoring.md](../docs/Monitoring.md#adding-a-service)). Keep a config backup after the
change: Diagnostics > Backup & Restore.
