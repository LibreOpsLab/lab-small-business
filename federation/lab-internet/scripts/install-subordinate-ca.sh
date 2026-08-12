#!/usr/bin/env bash
# STUB — not implemented. See docs/LabInternet.md.
#
# Intended behaviour: run by a business against the response bundle produced by the
# lecturer's approve-business.sh — installs the lecturer-signed Issuing CA in place of this
# business's self-signed one (pki/intermediate-ca/certs/intermediate.cert.pem gets replaced,
# not pki/root-ca — this business keeps no local Root CA at all once federated, since trust
# now flows from the lecturer's Root), and adds a conditional DNS forward zone for
# lab.internet pointed at the lecturer's root DNS (alongside, not instead of, the existing
# pfSense forwarder for everything else).
#
# Usage (intended): ./install-subordinate-ca.sh --response <lecturer-response-file>

set -euo pipefail
echo "[install-subordinate-ca] STUB — not implemented." >&2
echo "" >&2
echo "This will install the lecturer-signed Issuing CA in place of this business's" >&2
echo "self-signed one, and add a conditional DNS forward zone for lab.internet." >&2
echo "" >&2
echo "Blocked on: item 4 in docs/LabInternet.md#implementation-status (conditional forward" >&2
echo "zone support — today's dns_forwarder is a single blanket upstream, not a per-zone" >&2
echo "forward table), plus everything request-subordinate-ca.sh and approve-business.sh" >&2
echo "depend on." >&2
echo "" >&2
echo "See docs/LabInternet.md for the full design." >&2
exit 1
