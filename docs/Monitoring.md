# Monitoring

A secure system you do not watch is a system that has failed without telling you. The lab's
rule: **a service is not finished until it is monitored.**

Stack: Prometheus (collect and alert), Grafana (look), node_exporter (per-host metrics),
blackbox exporter (does the service work). All of it runs in
[`docker/monitoring/`](../docker/monitoring/README.md) on `docker01`, except node_exporter,
which runs on every host.

## Two kinds of check

| Kind | Tool | Question | Example failure it catches |
| ---- | ---- | -------- | -------------------------- |
| Inside-out | node_exporter | Is the machine healthy? | Disk 95% full, clock drifting, host down |
| Outside-in | blackbox exporter | Does the service work for a user? | Certificate expired, port closed, app returns 502 |

A host can be perfectly healthy while its service is broken, and the reverse. You need both.

## How it works

1. Each host runs `prometheus-node-exporter` on `<its LAN IP>:9100`. The host firewall (ufw)
   allows only the monitoring sources to reach that port (see [HostFirewalls.md](HostFirewalls.md)).
2. Prometheus **pulls** from each target every 30 seconds. Pull means a dead host is visible as
   a failed scrape (`up == 0`), which a push system cannot show.
3. The blackbox exporter makes real HTTPS and TCP connections and reports `probe_success`,
   TLS expiry, and timings. Certificates are verified against the lab CA chain; verification is
   never turned off.
4. Alert rules ([`alerts.yml`](../docker/monitoring/prometheus/alerts.yml)) turn conditions
   into alerts. They are visible in Grafana and on Prometheus's Alerts page. Nothing is
   delivered anywhere yet, on purpose.

## First dashboard

"LAB core services" answers the first question every operator asks: **are the core services
up?** Hosts up, probe pass rate, firing alerts, a probe table, CPU, clock offset (Kerberos
fails when clocks differ by more than 5 minutes) and free disk.

## Exercise: watch something fail

1. Open Grafana, find "LAB core services". Everything is green.
2. On `docker01`, stop one service: `docker stop stirling-pdf`.
3. Wait about 2.5 minutes. `https://pdf.lab.internal` turns red, and `ServiceProbeFailed`
   fires. Why the delay? Scrape every 30 s, plus the rule's `for: 2m`. Discuss the trade-off
   between fast detection and false alarms.
4. `docker start stirling-pdf`. Time how long recovery takes to show.
5. Second failure: on a client, stop the clock service on a host (`sudo systemctl stop chrony`)
   and watch `node_timex_offset_seconds` over the following hours. Why does a DC care?

## Adding a service

Every new service finishes with these three steps (the definition of done):

1. **A check.** Add its URL to `probe-https` or `host:port` to `probe-tcp` in
   [`prometheus.yml`](../docker/monitoring/prometheus/prometheus.yml), then
   `docker compose restart prometheus` (or send `SIGHUP`).
2. **An alert rule** if the generic `ServiceProbeFailed` is not specific enough.
3. **One deliberate failure** to see it fire, as in the exercise.

## Windows hosts

Install `windows_exporter` (a Prometheus project), restricted to the monitoring host:

```powershell
# Run elevated. Download the MSI from the windows_exporter GitHub releases page first.
msiexec /i windows_exporter.msi ENABLED_COLLECTORS="cpu,memory,logical_disk,net,os,service,time" LISTEN_PORT=9182 /qn
New-NetFirewallRule -DisplayName "Prometheus scrape (windows_exporter)" `
  -Direction Inbound -Protocol TCP -LocalPort 9182 -RemoteAddress 10.10.10.20 -Action Allow
```

Then add `10.10.10.x:9182` under a new `windows` job in `prometheus.yml`. The `time` collector
exposes clock offset like the Linux one.

## Things that surprise people

- **Docker bypasses ufw.** Published container ports are opened by Docker's own iptables rules,
  before ufw sees the traffic. Monitoring's containers publish no ports for this reason.
- **No data is not good data.** A panel showing "No data" for a down host is not green. Alert
  on `up == 0`, which is what `HostDown` does.
- **Clock drift looks like login failures.** Kerberos, TLS and log correlation all depend on
  time. This is why NTP is on the dashboard.

## Next steps (not built yet)

- Alertmanager for email delivery, using the lab's own mail server.
- Security events on top of the logs in [Logging.md](Logging.md) (Wazuh).
- Proxmox host metrics via a read-only API token (Pulse, or the Proxmox exporter).
