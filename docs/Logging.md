# Central Logging (Loki)

Metrics tell you **that** something is wrong; logs tell you **why**. A CPU graph says a server
is busy. The log says someone is guessing passwords against SSH. Without central logging, the
evidence sits on the machine an attacker has just logged into, where they can delete it.

Stack: **Loki** (store and query), **Grafana Alloy** (collect and ship) on every Linux host, and
**Grafana** (look). It lives in [`docker/monitoring/`](../docker/monitoring/README.md) beside
Prometheus.

## How it works

```text
each host: systemd journal -> Alloy --HTTPS + basic auth--> Traefik --> Loki --> Grafana (Explore, dashboards)
```

1. Linux services write to the systemd journal. That includes `sshd` and `sudo`, so logins and
   privilege use are already there.
2. Alloy (installed by the [`alloy` role](../ansible/roles/alloy/tasks/main.yml)) reads the
   journal, adds a few labels (`host`, `unit`, `level`), and pushes to
   `https://loki.lab.internal`.
3. Traefik terminates TLS and checks the push credential before Loki sees a byte. Loki publishes
   no port of its own, so nothing can reach it around the host firewall.
4. Grafana queries Loki. The "LAB logs" dashboard is provisioned.

**Why Alloy and not Promtail?** Promtail was the original Loki agent and has been retired by
Grafana. Alloy is its replacement. Older tutorials still show Promtail; skip them.

## Loki is not Splunk or Elasticsearch

Loki indexes only the **labels**, not the log text. That keeps it small enough to run in a
lab, and fast when you narrow by label first. The trade-off is that searching the text is a
scan: always start with labels (`host`, `unit`), then filter the text.

| | Loki | Splunk / Elasticsearch |
|---|---|---|
| Indexes | Labels only | Full text |
| Footprint | Small | Large |
| Best at | "Show me sshd on docker01 in the last hour" | Arbitrary search across everything |
| Cost model | Cheap to store, scan to search | Costly to store, fast to search |

Splunk is taught in other classes and is not built here. A SIEM adds correlation, alert
workflows and compliance reporting on top of log collection; this lab stops at collection and
search.

## LogQL: first queries

Open Grafana, Explore, choose Loki. A query has a **selector** (labels) then optional
**filters** (text).

```logql
{host="docker01"}                                   # everything from docker01
{host="docker01", unit="ssh.service"}               # only sshd
{unit="ssh.service"} |= "Failed password"           # lines containing this text
{unit="ssh.service"} |~ "Failed|Invalid user"       # regular expression
{level="err"}                                       # errors from every host
sum by (host) (count_over_time({unit="ssh.service"} |= "Failed password" [5m]))   # a metric from logs
```

## Exercise: see an attack

1. On `linux-client01`, try to SSH to `docker01` as a user that does not exist, five times.
2. In Grafana, open "LAB logs". Find the failed logins panel.
3. In Explore, run `{host="docker01", unit="ssh.service"} |= "Invalid user"`. What do you learn:
   the time, the user name tried, the source address?
4. Fail2Ban bans the address after five failures. Find the Fail2Ban line in the same log. Which
   came first, the failures or the ban?
5. Stop Alloy on a host (`sudo systemctl stop alloy`), generate more failures, and start it
   again. Do the lines arrive late or get lost? (Alloy remembers its position.) What would an
   attacker with root on that host do to the evidence, and how does central logging help?

## Retention and size

Loki keeps seven days (`retention_period` in
[`loki-config.yml`](../docker/monitoring/loki/loki-config.yml)). Raise it if the disk allows. Check
the volume with `docker system df -v` on `docker01`. Logs from a quiet lab are small; a noisy
service in debug mode is not.

## Windows hosts

Windows logs go to the Event Log, not the journal.
[`scripts/windows/Install-MonitoringAgents.ps1`](../scripts/windows/Install-MonitoringAgents.ps1)
installs Alloy on a Windows machine with a configuration that ships the **Application**,
**System** and **Security** logs to Loki, with the same credential as the Linux hosts. You download
the installer and give the script its SHA-256 from the release page; it refuses a file that does
not match. Query them with:

```logql
{job="windows-eventlog", host="winsrv01"}
{job="windows-eventlog", log="security"} |= "4625"      # 4625 = failed logon
```

Event IDs worth knowing: **4624** successful logon, **4625** failed logon, **4720** account
created, **4728/4732** added to a privileged group. Windows events arrive as structured text;
add `| json` to a query to split the fields.

## Firewall logs (pfSense)

pfSense sends its syslog to an `alloy-syslog` receiver on `docker01`, which forwards it to Loki
with `job="pfsense-syslog"`. Setup and the queries: [pfsense/remote-logging.md](../pfsense/remote-logging.md).

## Gotchas

- **Labels are not free.** A label with many distinct values (a user name, a request id) makes
  Loki slow and large. Keep labels few; put the detail in the log text.
- **Clock drift ruins timelines.** Logs from hosts with different times cannot be lined up
  during an incident. That is why clock offset is on the metrics dashboard.
- **The push password is a secret.** It is in each host's vault and in the Alloy config
  (mode 0640). Anyone holding it can write fake log lines.
- **No logs for the first window of a new host** is normal: install Alloy, wait a minute.

## Next steps (not built yet)

- Alert on log patterns (many failed logins in five minutes), using Grafana alerting or Loki's ruler.
- Wazuh or another security-event layer on top, if the course needs host-based detection.
- Ship the Windows agent by Group Policy startup script instead of by hand.
