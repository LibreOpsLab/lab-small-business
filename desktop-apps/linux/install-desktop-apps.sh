#!/usr/bin/env bash
# Installs the lab's standard desktop app set on Ubuntu Desktop: NextCloud Desktop Sync,
# OnlyOffice Desktop Editors, Betterbird (mail/calendar/contacts client — see
# docs/DesktopApps.md#why-betterbird), and a pinned web-app shortcut for Stirling PDF.
#
# Run as root (or via sudo) on linux-client01, after joining the domain and after
# ansible/playbooks/05-pki-trust.yml has installed CA trust.
#
# Usage: sudo ./desktop-apps/linux/install-desktop-apps.sh [--betterbird-url <tarball-url>]

set -euo pipefail

log()  { printf '\033[1;34m[install-desktop-apps]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install-desktop-apps][warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install-desktop-apps][error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root (sudo $0)."
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"
[[ -n "${REAL_USER}" ]] || die "Could not determine the invoking (non-root) user — run via sudo, not as root directly."
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"

# Betterbird ships no apt/winget package — it's distributed as a tarball, the same way
# Mozilla distributes upstream Thunderbird. Betterbird's download URLs occasionally change
# with new releases; override with --betterbird-url if this default 404s. Check
# https://betterbird.eu/downloads/ for the current linux64 tarball link if so.
BETTERBIRD_URL="https://ftp.betterbird.eu/Betterbird/releases/latest/linux-x86_64/en-US/betterbird-latest.tar.bz2"
[[ "${1:-}" == "--betterbird-url" ]] && BETTERBIRD_URL="$2"

log "Updating package lists"
apt-get update -qq

log "Installing NextCloud Desktop Sync"
apt-get install -y -qq nextcloud-desktop

log "Installing OnlyOffice Desktop Editors"
if ! apt-cache show onlyoffice-desktopeditors >/dev/null 2>&1; then
  log "Adding the ONLYOFFICE apt repository (not in Ubuntu's default repos)"
  apt-get install -y -qq gnupg
  curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --dearmor -o /usr/share/keyrings/onlyoffice.gpg
  echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" \
    > /etc/apt/sources.list.d/onlyoffice.list
  apt-get update -qq
fi
apt-get install -y -qq onlyoffice-desktopeditors

log "Installing Betterbird (mail/calendar/contacts client) from ${BETTERBIRD_URL}"
apt-get install -y -qq bzip2 libgtk-3-0 libx11-xcb1 libdbus-glib-1-2
TMP_TARBALL="$(mktemp --suffix=.tar.bz2)"
if curl -fsSL "${BETTERBIRD_URL}" -o "${TMP_TARBALL}"; then
  rm -rf /opt/betterbird
  mkdir -p /opt/betterbird
  tar -xjf "${TMP_TARBALL}" -C /opt/betterbird --strip-components=1
  ln -sf /opt/betterbird/betterbird /usr/local/bin/betterbird
  cat > /usr/share/applications/betterbird.desktop <<'EOF'
[Desktop Entry]
Name=Betterbird
Comment=Mail, calendar, and contacts (LAB default client)
Exec=/usr/local/bin/betterbird %u
Icon=/opt/betterbird/chrome/icons/default/default128.png
Terminal=false
Type=Application
Categories=Network;Email;
MimeType=x-scheme-handler/mailto;
EOF
  log "Betterbird installed to /opt/betterbird"
else
  warn "Download failed (${BETTERBIRD_URL} unreachable or moved). Betterbird's download URLs"
  warn "shift between releases — check https://betterbird.eu/downloads/ and re-run with"
  warn "--betterbird-url <correct-tarball-url>."
fi
rm -f "${TMP_TARBALL}"

log "Creating a pinned web-app shortcut for Stirling PDF (no native desktop client exists)"
DESKTOP_FILE="/usr/share/applications/lab-stirling-pdf.desktop"
BROWSER_BIN="$(command -v chromium-browser || command -v chromium || command -v google-chrome || echo "")"
if [[ -n "${BROWSER_BIN}" ]]; then
  cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Name=LAB PDF Tools
Comment=Stirling PDF (Adobe Acrobat replacement) — https://pdf.lab.internal
Exec=${BROWSER_BIN} --app=https://pdf.lab.internal
Icon=x-office-document
Terminal=false
Type=Application
Categories=Office;
EOF
  chmod 644 "${DESKTOP_FILE}"
  log "Created ${DESKTOP_FILE}"
else
  log "No Chromium/Chrome found for --app= mode — Firefox has no equivalent 'app mode' flag;"
  log "students can still just bookmark https://pdf.lab.internal in Firefox."
fi

log "Done. Next: configure-nextcloud-client.sh. See docs/DesktopApps.md for Betterbird autoconfig."
log "Home directory for config seeding: ${REAL_HOME} (user: ${REAL_USER})"
