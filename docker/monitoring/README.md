# Monitoring (Prometheus + Grafana)

Answers two questions: **is each machine healthy?** and **does each service work for a user?**
Dashboards at `https://grafana.lab.internal`. Full explanation, adding a service, and the
failure exercise: [docs/Monitoring.md](../../docs/Monitoring.md).

| Container           | Job                                                                         | Reachable from        |
| ------------------- | --------------------------------------------------------------------------- | --------------------- |
| `prometheus`        | Scrapes and stores metrics, evaluates alert rules                           | `monitoring` network only |
| `blackbox-exporter` | Probes HTTPS (with certificate validation) and TCP services from outside    | `monitoring` network only |
| `loki`              | Stores logs pushed by Alloy on each host ([Logging.md](../../docs/Logging.md)) | Traefik, push only, basic auth |
| `grafana`           | Dashboards; reads Prometheus and Loki                                       | Traefik, behind SSO   |

## Access control: forward-auth

Same pattern as [Stirling PDF](../stirling-pdf/README.md): Traefik's `authentik-forwardauth`
middleware authenticates every request, and Grafana's auth-proxy mode trusts the
`X-authentik-username` header Authentik returns. New users are created as Viewers on first
login. Grafana's local `admin` account (password in `.env`) is the break-glass and the way to
grant more rights. Configured by
[`authentik/blueprints/proxy-grafana.yaml`](../../authentik/blueprints/proxy-grafana.yaml); like
Stirling PDF, confirm "Grafana" appears on the embedded outpost after the first run.

Because Grafana trusts a header, **never add a `ports:` section** to it: the only route in must
be through Traefik.

## Files

- [`prometheus/prometheus.yml`](prometheus/prometheus.yml) — scrape targets (edit to add hosts).
- [`prometheus/alerts.yml`](prometheus/alerts.yml) — alert rules.
- [`blackbox/blackbox.yml`](blackbox/blackbox.yml) — probe modules; mounts the lab CA chain.
- [`grafana/`](grafana/) — provisioned data source and the "LAB core services" dashboard.

## Prerequisites

1. `ansible/roles/node_exporter` on each host (applied by `00-common-hardening.yml`).
2. `grafana.lab.internal` DNS CNAME and certificate (`make pki-issue-all`).
3. `loki.lab.internal` CNAME and certificate, and `ansible/playbooks/07-logging.yml` on each host.
4. `.env` rendered from the vault (`grafana_admin_password`), or copied from `.env.example`.
