#!/usr/bin/env bash
# STUB — not implemented. See docs/LabInternet.md.
#
# Intended behaviour: run by each business to generate an Issuing CA CSR (instead of
# pki/scripts/01-init-intermediate-ca.sh's local self-signing) plus a DNS delegation request
# (chosen subdomain label + this business's Samba DC IP), bundled into a request file to send
# the lecturer out-of-band — same exchange pattern as
# federation/scripts/register-business.sh, but carrying a CSR instead of connection params.
#
# Usage (intended): ./request-subordinate-ca.sh --subdomain acme --root-domain lab.internet

set -euo pipefail
echo "[request-subordinate-ca] STUB — not implemented." >&2
echo "" >&2
echo "This will generate an Issuing CA CSR for this business and a DNS delegation request," >&2
echo "for the lecturer to sign/approve via approve-business.sh." >&2
echo "" >&2
echo "Blocked on: item 1 in docs/LabInternet.md#implementation-status (this business must" >&2
echo "already have been provisioned with its final three-label LAB Internet domain, e.g." >&2
echo "acme.lab.internet, via a provision-business.sh that supports N-label domains — today" >&2
echo "it only supports two, e.g. acme.internal) and item 2 (the CSR export/cross-sign" >&2
echo "workflow itself, which does not exist yet in pki/scripts)." >&2
echo "" >&2
echo "See docs/LabInternet.md for the full design." >&2
exit 1
