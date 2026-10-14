# pfSense remote logging

Send the firewall's logs to Loki, so the evidence of what the perimeter blocked and allowed
lives somewhere an attacker on the LAN cannot erase it. A firewall that only keeps its own logs
loses them if it is rebooted, filled, or compromised.

Like the rest of pfSense in this repo, this is **instructions, not automation** (see
[README.md](README.md)). Menu names are for current pfSense; confirm them on your version.

## How it works

```text
pfSense --syslog (UDP/TCP 1514)--> alloy-syslog container on docker01 --> Loki --> Grafana
```

The `alloy-syslog` container in [`docker/monitoring/`](../docker/monitoring/docker-compose.yml)
listens on `10.10.10.20:1514` and forwards what it receives. It labels each line with the sending
host (`host`), severity (`level`) and program (`unit`), so the queries you use for the Linux
hosts work here too.

## Configure pfSense

1. Status > System Logs > **Settings**.
2. Tick **Enable Remote Logging**.
3. **Remote log servers:** `10.10.10.20:1514`.
4. **Remote Syslog Contents:** choose what to send. For the lab, tick **Firewall Events** and
   **System Events**. Everything is possible but noisy.
5. Save.

pfSense sends BSD-style (RFC 3164) syslog unless you change its format; the receiver expects
that. If you switch pfSense to RFC 5424, change `syslog_format` in
[`alloy-syslog/config.alloy`](../docker/monitoring/alloy-syslog/config.alloy) to match.

## Check it

In Grafana, Explore, Loki:

```logql
{job="pfsense-syslog"}                              # everything from pfSense
{job="pfsense-syslog", unit="filterlog"}            # firewall decisions (pass and block)
{job="pfsense-syslog", unit="filterlog"} |= ",block,"   # only blocks
```

Generate a block on purpose: from a client, try to reach a port that the firewall rules deny,
then find your own attempt in the log. Note the source address, destination and port.

## Gotchas

- **Syslog is not authenticated or encrypted.** Anything on the LAN can send lines to that port
  and they look like firewall logs. For a lab feed that is acceptable; for production you would
  use TLS syslog with client certificates. Say so in the threat model.
- **Docker publishes the port past the host firewall.** The only restriction is the bind address
  (`SYSLOG_BIND_ADDRESS` in `.env`), so keep it on the LAN address. See
  [HostFirewalls.md](../docs/HostFirewalls.md#gotcha-docker-bypasses-ufw).
- **Firewall logs are loud.** A busy firewall sends thousands of lines a minute. Send only what
  you will use, and watch the Loki volume.
- **UDP can lose lines.** Syslog over UDP has no delivery guarantee. The listener also accepts
  TCP on the same port if you want reliability.
- **The logs say what was decided, not why.** To understand a block, find the rule number in the
  line and match it to the rule in Firewall > Rules.
