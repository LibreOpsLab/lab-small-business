# Host Firewalls

pfSense filters traffic **between networks**. A host firewall filters traffic **to that one
machine**, including from other machines on the same LAN, which pfSense never sees. Both are
needed: if one attacker machine on the LAN is compromised, only the host firewalls stand between
it and the other servers (lateral movement).

| Layer | Where | Stops |
| ----- | ----- | ----- |
| Perimeter | pfSense | Internet to LAN, LAN to Internet |
| Host | ufw / nftables / Windows Defender Firewall | LAN to this server, per port and per source |

## Linux: ufw

The [`common` role](../ansible/roles/common/tasks/main.yml) turns ufw on with default-deny
inbound and allows only SSH. Every service role then opens exactly what it needs and nothing
more. Example from [`node_exporter`](../ansible/roles/node_exporter/tasks/main.yml): port 9100
from the monitoring sources only.

```bash
sudo ufw status verbose          # what is allowed, and the default policy
sudo ufw allow from 10.10.10.20 to any port 9100 proto tcp comment 'Prometheus scrape'
sudo ufw delete allow from 10.10.10.20 to any port 9100 proto tcp
sudo ufw show added              # the rules as you would type them
```

Principles: default deny; allow the narrowest source that works (an address, not "anywhere");
comment every rule with why it exists; manage it from Ansible so it is repeatable.

### Gotcha: Docker bypasses ufw

Docker publishes container ports by editing iptables directly, ahead of ufw's rules. A
`ports: "8080:80"` is reachable from the LAN even if ufw says deny. In this lab only Traefik
and the mail stack publish ports, deliberately. To restrict a published port, bind it to an
address (`127.0.0.1:8080:80`) or put the rule in the `DOCKER-USER` chain.

## Linux: nftables (what is underneath)

ufw is a front end. On Ubuntu it drives the kernel's packet filter, and `nftables` is the
current native tool:

```bash
sudo nft list ruleset            # everything the kernel is enforcing
```

Read this output once so ufw is not magic: you will see the chains ufw created and your rules.
Writing nftables by hand is worth it for rules ufw cannot express (rate limits, sets of
addresses).

## Windows: Defender Firewall

On by default for every profile. Manage it with PowerShell so it is scriptable:

```powershell
Get-NetFirewallProfile | Select Name, Enabled, DefaultInboundAction
New-NetFirewallRule -DisplayName "Prometheus scrape (windows_exporter)" `
  -Direction Inbound -Protocol TCP -LocalPort 9182 -RemoteAddress 10.10.10.20 -Action Allow
Get-NetFirewallRule -DisplayName "Prometheus*" | Get-NetFirewallPortFilter
Remove-NetFirewallRule -DisplayName "Prometheus scrape (windows_exporter)"
```

In a domain, push rules with Group Policy (Computer Configuration, Windows Settings, Security
Settings, Windows Defender Firewall with Advanced Security) so every machine gets the same
baseline. See [SambaAdmin.md](SambaAdmin.md) for managing GPOs.

## Exercise

1. On `docker01`, `ufw status verbose`. Which ports are open and to whom?
2. From `linux-client01`, `curl http://10.10.10.20:9100/metrics` fails. Why? (Source not allowed.)
3. Temporarily allow your client's address, retry, then remove the rule.
4. Check Grafana: did anything go red while you changed rules? Why not?
5. Compare with pfSense: which of these rules could pfSense have enforced? Which could it not?
