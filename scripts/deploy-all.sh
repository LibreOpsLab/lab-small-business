#!/usr/bin/env bash
# One-shot redeploy of the identity + application layers onto already-created VMs:
# issues/refreshes PKI leaf certs, runs the full Ansible playbook, then sweeps a
# post-flight health check. Does NOT create VMs or provision the Samba domain from scratch —
# see docs/DeploymentGuide.md for the full first-time bring-up sequence, of which this script
# covers steps 4-8 (re-runnable, idempotent).
#
# Usage: ./scripts/deploy-all.sh [--skip-pki] [--ask-vault-pass]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

SKIP_PKI=0
VAULT_ARG=""
for arg in "$@"; do
  case "${arg}" in
    --skip-pki) SKIP_PKI=1 ;;
    --ask-vault-pass) VAULT_ARG="--ask-vault-pass" ;;
    *) die "Unknown argument: ${arg}" ;;
  esac
done

require_cmd openssl
require_cmd ansible-playbook

if [[ "${SKIP_PKI}" -eq 0 ]]; then
  log "Ensuring the CA hierarchy exists and leaf certificates are issued"
  pushd "${REPO_ROOT}/pki/scripts" >/dev/null
  ./00-init-root-ca.sh
  ./01-init-intermediate-ca.sh
  ./02-issue-server-cert.sh --cn samba-dc01.lab.internal --san "DNS:samba-dc01.lab.internal,DNS:lab.internal"
  ./02-issue-server-cert.sh --cn cloud.lab.internal      --san DNS:cloud.lab.internal
  ./02-issue-server-cert.sh --cn docs.lab.internal       --san DNS:docs.lab.internal
  ./02-issue-server-cert.sh --cn mail.lab.internal       --san DNS:mail.lab.internal
  ./02-issue-server-cert.sh --cn auth.lab.internal       --san DNS:auth.lab.internal
  ./02-issue-server-cert.sh --cn www.lab.internal        --san DNS:www.lab.internal
  ./02-issue-server-cert.sh --cn pdf.lab.internal        --san DNS:pdf.lab.internal
  ./02-issue-server-cert.sh --cn autoconfig.lab.internal --san DNS:autoconfig.lab.internal
  popd >/dev/null
else
  log "Skipping PKI issuance (--skip-pki passed)"
fi

log "Running the full Ansible playbook against inventory/hosts.ini"
pushd "${REPO_ROOT}/ansible" >/dev/null
# shellcheck disable=SC2086
ansible-playbook playbooks/site.yml ${VAULT_ARG}
popd >/dev/null

log "Post-flight: Samba AD health check"
ssh -o StrictHostKeyChecking=accept-new samba-dc01.lab.internal \
  'sudo /opt/lab-small-business/samba/scripts/health-check.sh' || \
  warn "Could not run remote health-check.sh via SSH — run it manually on samba-dc01 if this host isn't SSH-reachable from the control node."

log "Wiring NextCloud groupware apps (Calendar/Contacts/Talk/Mail/OnlyOffice connector)"
"${REPO_ROOT}/docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh" || \
  warn "NextCloud groupware bootstrap failed or NextCloud isn't reachable from here — re-run docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh manually once it is."

log "Deploy complete. Optional next steps: docker/wordpress/scripts/configure-oidc-plugin.sh"
log "(WordPress SSO) and desktop-apps/ on each client (see docs/DesktopApps.md)."
log "Validate per docs/StudentLabManual.md#day-1-checklist."
