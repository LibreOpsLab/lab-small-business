#!/usr/bin/env bash
# STUB — not implemented. See docs/LabInternet.md.
#
# Intended behaviour: run by the lecturer against a request file produced by a business's
# request-subordinate-ca.sh — signs the enclosed Issuing CA CSR with the LAB Internet Root CA
# (created by init-lecturer-root-ca.sh) and adds an NS delegation record for the business's
# subdomain to the lab.internet root zone. Produces a response bundle (signed cert chain) to
# send back to the business out-of-band, for install-subordinate-ca.sh to consume.
#
# Usage (intended): ./approve-business.sh --request <business-request-file>

set -euo pipefail
echo "[approve-business] STUB — not implemented." >&2
echo "" >&2
echo "This will sign a business's Issuing CA CSR with the LAB Internet Root CA and add its" >&2
echo "DNS delegation to the lab.internet root zone." >&2
echo "" >&2
echo "Blocked on: init-lecturer-root-ca.sh must be implemented first (this script consumes" >&2
echo "the Root CA and root DNS zone it creates), and item 2 in" >&2
echo "docs/LabInternet.md#implementation-status (the CSR cross-signing workflow)." >&2
echo "" >&2
echo "See docs/LabInternet.md for the full design." >&2
exit 1
