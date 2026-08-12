#!/usr/bin/env bash
# Smoke-tests a Samba AD DC. Intended for use after provisioning, restore, or as a periodic
# cron/Ansible check. Exits non-zero if any check fails; prints a pass/fail summary.
#
# Run on samba-dc01 (or any domain member with samba-tool + krb5-user installed and network
# access to the DC).

set -uo pipefail

PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  printf '%-55s' "${desc}"
  if "$@" >/tmp/health-check.out 2>&1; then
    printf '\033[1;32mPASS\033[0m\n'
    PASS=$((PASS+1))
  else
    printf '\033[1;31mFAIL\033[0m\n'
    sed 's/^/    /' /tmp/health-check.out | tail -n 5
    FAIL=$((FAIL+1))
  fi
  rm -f /tmp/health-check.out
}

echo "=== Samba AD health check: $(date -u +%FT%TZ) ==="

check "samba-tool dbcheck (no repair)" samba-tool dbcheck --cross-ncs
check "samba-tool drs showrepl" samba-tool drs showrepl
check "DNS zone update dry-run (samba_dnsupdate)" samba_dnsupdate --verbose --all-names --use-file=/dev/null
check "Kerberos ticket acquisition (machine keytab)" bash -c 'kinit -k -t /etc/krb5.keytab "$(hostname -s | tr a-z A-Z)\$@LAB.INTERNAL" && klist -s'
check "SMB share listing (anonymous)" smbclient -L localhost -U "%" -N
check "systemd: samba-ad-dc active" systemctl is-active --quiet samba-ad-dc
check "systemd: chrony active" systemctl is-active --quiet chrony
check "NTP sync status" bash -c 'chronyc tracking | grep -q "Leap status.*Normal"'

echo "=== Summary: ${PASS} passed, ${FAIL} failed ==="
[[ "${FAIL}" -eq 0 ]]
