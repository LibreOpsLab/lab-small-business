#!/usr/bin/env bash
# STUB — not implemented. See docs/LabInternet.md.
#
# Intended behaviour: run once, by the lecturer, to create the "LAB Internet Root CA"
# (analogous to pki/scripts/00-init-root-ca.sh but one level above every business's own
# Root/Issuing CA) and an empty authoritative DNS zone for lab.internet that businesses
# get NS-delegated into as they onboard (see approve-business.sh).
#
# Usage (intended): ./init-lecturer-root-ca.sh --root-domain lab.internet

set -euo pipefail
echo "[init-lecturer-root-ca] STUB — not implemented." >&2
echo "" >&2
echo "This will create a Root CA analogous to pki/scripts/00-init-root-ca.sh, and a" >&2
echo "non-AD-integrated authoritative DNS zone for lab.internet." >&2
echo "" >&2
echo "Blocked on: item 3 in docs/LabInternet.md#implementation-status (a delegating root" >&2
echo "DNS server — Samba's internal DNS is designed to serve one AD domain, not act as a" >&2
echo "generic delegating root, so this needs new infrastructure, e.g. a standalone BIND9" >&2
echo "or Unbound-in-authoritative-mode role)." >&2
echo "" >&2
echo "See docs/LabInternet.md for the full design." >&2
exit 1
