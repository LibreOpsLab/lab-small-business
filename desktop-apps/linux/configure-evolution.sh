#!/usr/bin/env bash
# BEST EFFORT — pre-seeds an Evolution IMAP/SMTP mail account via gsettings/dconf. Evolution's
# account storage schema has shifted across GNOME releases, so this is not guaranteed to work
# on every Ubuntu Desktop image; verify the account actually appears after running this, and
# fall back to Evolution's own "Add Mail Account" wizard (Edit > Accounts > Add) if it didn't.
# See docs/DesktopApps.md#evolution-alternative-best-effort for why Thunderbird's autoconfig
# (configure via the app itself, no script needed) is the more reliable default.
#
# Run as the student's own user (not root).
#
# Usage: ./desktop-apps/linux/configure-evolution.sh --email student01@lab.internal --name "Sam Ahmed"

set -euo pipefail

log()  { printf '\033[1;34m[configure-evolution]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[configure-evolution][warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[configure-evolution][error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -ne 0 ]] || die "Run as the student's own user, not root."
command -v evolution >/dev/null 2>&1 || die "Evolution is not installed — run install-desktop-apps.sh first."

EMAIL=""
DISPLAY_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --email) EMAIL="$2"; shift 2 ;;
    --name) DISPLAY_NAME="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done
[[ -n "${EMAIL}" && -n "${DISPLAY_NAME}" ]] || die "Usage: $0 --email <user>@lab.internal --name \"Display Name\""

USERNAME="${EMAIL%@*}"
UID_STR="lab-$(echo -n "${EMAIL}" | md5sum | cut -c1-8)"

log "Attempting to create an Evolution mail account for ${EMAIL} via the 'source registry'"
log "(Evolution's actual account store — this is the same mechanism GNOME Online Accounts"
log "uses, exposed as .source key files rather than gsettings in modern Evolution versions)."

SOURCE_DIR="${HOME}/.config/evolution/sources"
mkdir -p "${SOURCE_DIR}"

# Evolution account = 3 linked .source files: the account identity, the IMAP collection, and
# the SMTP transport. This mirrors what Evolution itself writes when you complete the GUI
# wizard manually — best-effort because the exact key set has changed across versions.
cat > "${SOURCE_DIR}/${UID_STR}.source" <<EOF
[Data Source]
DisplayName=${DISPLAY_NAME} (LAB)
Enabled=true
Parent=

[Mail Account]
Identity=${UID_STR}-identity
BackendName=imapx
Enabled=true

[Identity]
Address=${EMAIL}
Name=${DISPLAY_NAME}

[Collection]
Identity=${UID_STR}-identity
BackendName=imapx
Enabled=true
CalendarEnabled=false
ContactsEnabled=false
MailEnabled=true

[Authentication]
Host=mail.lab.internal
Port=993
User=${EMAIL}
Method=plain

[Security]
Method=tls
EOF

cat > "${SOURCE_DIR}/${UID_STR}-identity.source" <<EOF
[Data Source]
DisplayName=${DISPLAY_NAME}
Enabled=true
Parent=

[Mail Identity]
Address=${EMAIL}
Name=${DISPLAY_NAME}

[Mail Composition]
DraftsFolder=
SentFolder=
EOF

cat > "${SOURCE_DIR}/${UID_STR}-transport.source" <<EOF
[Data Source]
DisplayName=${DISPLAY_NAME} (SMTP)
Enabled=true
Parent=${UID_STR}-identity

[Mail Transport]
BackendName=smtp

[Authentication]
Host=mail.lab.internal
Port=587
User=${EMAIL}
Method=plain

[Security]
Method=starttls
EOF

log "Wrote source files to ${SOURCE_DIR}. Restart Evolution (or 'evolution --force-shutdown'"
log "then reopen) for it to pick up the new account. It will still prompt for the account"
log "password on first sync — that part is never automatable (nor should it be)."
warn "If the account does not appear after restart, this Ubuntu image's Evolution version"
warn "has a different source-file schema than expected — use Evolution's own Edit > Accounts"
warn "> Add wizard instead, with the values in docker/mail/README.md#client-configuration."
