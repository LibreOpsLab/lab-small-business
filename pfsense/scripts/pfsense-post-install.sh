#!/bin/sh
# Run on pfSense itself (Diagnostics > Command Prompt, or over SSH as the admin user) after
# importing pfsense/config/config.xml.template. Installs packages and applies tweaks that
# aren't expressible in config.xml.
#
# pfSense's shell is a restricted-ish sh (FreeBSD base + pfSsh.php for config-aware actions),
# so this deliberately sticks to pkg + pfSsh.php rather than assuming bash/GNU tools.

set -e

echo "[pfsense-post-install] Installing pfSense-pkg-Cron (visibility into scheduled tasks)..."
pkg-static install -y pfSense-pkg-Cron || echo "  already installed or unavailable — continuing"

echo "[pfsense-post-install] Installing pfSense-pkg-Notes (in-GUI runbook notes for students)..."
pkg-static install -y pfSense-pkg-Notes || echo "  already installed or unavailable — continuing"

echo "[pfsense-post-install] Forcing a config save + Unbound reload so DNS forwarder changes take effect..."
pfSsh.php playback svc restart unbound

echo "[pfsense-post-install] Reloading filter to ensure imported firewall rules are active..."
pfSsh.php playback svc restart filter

echo "[pfsense-post-install] Done. Verify from the GUI:"
echo "  Status > DHCP Leases        (confirm scope 10.10.0.100-199 is live)"
echo "  Status > System Logs > Firewall  (confirm rules are hit, not falling through to default deny)"
echo "  Diagnostics > DNS Lookup    (confirm lab.local resolves via 10.10.0.10)"
