#!/usr/bin/env bash
# Proxmox VE host prep for a LAB: switch off the paid-subscription defaults.
#
# Run this ON the Proxmox host, as root, once after installing Proxmox (scenarios 2 and 3).
# It does what the community-scripts "post-pve-install" helper does, in a form you can read
# before you run it:
#
#   1. Disables the Enterprise apt repos (pve-enterprise, ceph-enterprise). Without a paid
#      subscription they return 401 and `apt update` fails.
#   2. Adds the pve-no-subscription repo, which is what a lab should track.
#   3. Hides the "No valid subscription" popup at login, and re-applies that after upgrades.
#   4. Optionally runs a full upgrade (--upgrade).
#
# The no-subscription repo gets updates before they have had the Enterprise repo's extra
# testing. That is the right trade-off for a lab and the wrong one for production.
#
# This file is deliberately standalone (scp it to the host; the rest of the repo is not there),
# so it carries its own copies of the log/die helpers from scripts/lib/common.sh.
#
# Usage:
#   ./post-install.sh --dry-run     # show what would change, change nothing
#   ./post-install.sh               # apply
#   ./post-install.sh --upgrade     # apply, then apt dist-upgrade
#
# Supports Proxmox VE 8 (Debian bookworm, one-line .list repos) and 9 (Debian trixie, deb822
# .sources repos). Safe to run twice.

set -euo pipefail

log()  { printf '\033[1;34m[pve-prep]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[pve-prep][warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[pve-prep][error]\033[0m %s\n' "$*" >&2; exit 1; }

DRY_RUN=0
UPGRADE=0
for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN=1 ;;
    --upgrade) UPGRADE=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) die "Unknown option: ${arg} (try --help)" ;;
  esac
done

# do_write <path>  — reads the new content from stdin; honours --dry-run.
do_write() {
  local path="$1"
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "[dry-run] would write ${path}:"
    sed 's/^/    | /'
  else
    cat > "${path}"
    log "wrote ${path}"
  fi
}

[ "$(id -u)" -eq 0 ] || die "Run as root on the Proxmox host."
command -v pveversion >/dev/null 2>&1 || die "pveversion not found: this does not look like a Proxmox VE host."

PVE_MAJOR="$(pveversion | sed -n 's|^pve-manager/\([0-9]*\)\..*|\1|p')"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
log "Proxmox VE ${PVE_MAJOR} on Debian ${CODENAME}"

APT_DIR=/etc/apt/sources.list.d

# --- 1. Disable the Enterprise repos ---------------------------------------------------------------
# PVE 8 stores a repo as a one-line .list file: commenting the line out disables it.
# PVE 9 stores it as a deb822 .sources file: an "Enabled: false" field disables it.
disable_repo() {
  local base="$1"
  local list="${APT_DIR}/${base}.list" src="${APT_DIR}/${base}.sources"

  if [ -f "${list}" ] && grep -q '^deb ' "${list}"; then
    log "disabling ${list}"
    [ "${DRY_RUN}" -eq 1 ] || sed -i 's/^deb /# deb /' "${list}"
  fi
  if [ -f "${src}" ] && ! grep -qi '^Enabled: *false' "${src}"; then
    log "disabling ${src}"
    [ "${DRY_RUN}" -eq 1 ] || printf 'Enabled: false\n' >> "${src}"
  fi
}

disable_repo pve-enterprise
disable_repo ceph

# --- 2. Add the no-subscription repo ---------------------------------------------------------------
case "${PVE_MAJOR}" in
  8)
    do_write "${APT_DIR}/pve-no-subscription.list" <<EOF
# Added by hypervisor/proxmox/host/post-install.sh. Lab use only.
deb http://download.proxmox.com/debian/pve ${CODENAME} pve-no-subscription
EOF
    ;;
  9)
    do_write "${APT_DIR}/pve-no-subscription.sources" <<EOF
# Added by hypervisor/proxmox/host/post-install.sh. Lab use only.
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: ${CODENAME}
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    ;;
  *) die "Unsupported Proxmox VE major version '${PVE_MAJOR}'. Supported: 8, 9." ;;
esac

# --- 3. Hide the subscription nag ------------------------------------------------------------------
# The login popup is built by proxmoxlib.js. We neutralise the Ext.Msg.show call that opens it
# (a .bak copy is kept). A package upgrade overwrites the file, so an apt hook re-runs the patch.
WIDGET_JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
PATCH_BIN=/usr/local/sbin/pve-lab-hide-nag
HOOK=/etc/apt/apt.conf.d/99-pve-lab-hide-nag

do_write "${PATCH_BIN}" <<'EOF'
#!/bin/sh
# Installed by hypervisor/proxmox/host/post-install.sh. Idempotent.
JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
[ -f "$JS" ] || exit 0
grep -q "void({ //Ext.Msg.show" "$JS" && exit 0
sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" "$JS"
systemctl restart pveproxy.service
EOF

do_write "${HOOK}" <<EOF
DPkg::Post-Invoke { "[ -x ${PATCH_BIN} ] && ${PATCH_BIN} || true"; };
EOF

if [ "${DRY_RUN}" -eq 0 ]; then
  chmod 0755 "${PATCH_BIN}"
  "${PATCH_BIN}"
  grep -q "void({ //Ext.Msg.show" "${WIDGET_JS}" \
    && log "subscription popup disabled (hard-refresh the browser: Ctrl+Shift+R)" \
    || warn "nag patch did not match this proxmoxlib.js; the popup may still appear."
fi

# --- 4. Update -------------------------------------------------------------------------------------
if [ "${DRY_RUN}" -eq 1 ]; then
  log "[dry-run] would run: apt-get update$([ "${UPGRADE}" -eq 1 ] && echo ' && apt-get dist-upgrade -y')"
else
  apt-get update
  if [ "${UPGRADE}" -eq 1 ]; then
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
    log "Upgrade finished. Reboot if a new kernel was installed."
  fi
fi

log "Done."
