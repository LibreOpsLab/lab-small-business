# pfSense

pfSense is the perimeter firewall, DHCP server, and DNS forwarder for the LAN. It is not
Ansible-managed (see [hypervisor/README.md](../hypervisor/README.md#why-not-terraform) for
the equivalent rationale — pfSense's config is XML-based and doesn't lend itself to idempotent
CLI automation the way Linux does).

**The files below are an optional shortcut, not the default first-run path.**
[`docs/DeploymentGuide.md`](../docs/DeploymentGuide.md#1-pfsense--fully-manual) and
[`hypervisor/vms/pfsense.md`](../hypervisor/vms/pfsense.md) walk through configuring pfSense
entirely by hand — start there. Come back to `config.xml.template` once you're comfortable with
the manual flow and want a reviewed, reusable baseline for future rebuilds.

## Files

- [`config/config.xml.template`](config/config.xml.template) — a reviewed baseline
  configuration (interfaces, DHCP scope, firewall rules, DNS Resolver settings) with
  placeholders for anything environment-specific. Import via \*\*Diagnostics > Backup & Restore
  > Restore config\*\* after a fresh install (see
  > [`hypervisor/vms/pfsense.md`](../hypervisor/vms/pfsense.md)).
- [`scripts/pfsense-post-install.sh`](scripts/pfsense-post-install.sh) — runs over SSH
  (`Diagnostics > Command Prompt` also works) to install the `pfSense-pkg-Cron` and
  `pfSense-pkg-Notes` packages and apply anything not expressible in `config.xml`.

## Before importing config.xml.template

Replace these placeholders (search for `__` prefixed tokens):

| Placeholder    | Meaning                                     | Example     |
| -------------- | ------------------------------------------- | ----------- |
| `__WAN_IF__`   | WAN interface name as pfSense enumerated it | `em0`       |
| `__LAN_IF__`   | LAN interface name as pfSense enumerated it | `em1`       |
| `__HOSTNAME__` | pfSense's own hostname                      | `pfsense01` |

Interface names are shown during the console "Assign Interfaces" step at install time — note
them down before importing.

## What the template configures

- WAN: DHCP client (from VMware NAT).
- LAN: static `10.10.10.1/24`.
- DHCP server on LAN: pool `10.10.10.100–10.10.10.199`, DNS option = `10.10.10.10` only, domain
  name `lab.internal`, gateway `10.10.10.1`.
- DNS Resolver (Unbound): enabled, LAN-only access, forwarding to Samba AD's DNS for
  `lab.internal` and to the WAN interface's upstream DNS for everything else — see
  [dns-architecture.md](../diagrams/dns-architecture.md).
- Firewall rules per [Security.md](../docs/Security.md#firewall-recommendations-pfsense).
- NTP server enabled on LAN (falls back to public pool servers on WAN; domain members
  should still prefer `samba-dc01` per [Security.md](../docs/Security.md#host-hardening-ansible-common-role)).

## Backup

pfSense's own **Diagnostics > Backup & Restore > Download configuration** produces a full
`config.xml` snapshot — take one after any manual GUI change and keep it alongside (but not
overwriting) `config.xml.template`, since the template is the reviewed/reproducible baseline,
not a live backup.
