# Desktop Apps & Experiences

The web apps in [`docker/`](../docker/) cover the server side. This doc covers the client
side: what runs on `linux-client01`/`win-client01` to give students an "Outlook/OneDrive/Teams
replacement" experience, what's automated, and what's a deliberate one-time manual step and
why. See [`desktop-apps/`](../desktop-apps/) for the installer/provisioning scripts this doc
walks through.

## At a glance

| Replaces | App | Automated? |
|---|---|---|
| OneDrive | NextCloud Desktop Sync | Install + server URL pre-filled automatically. Login is one click (SSO via Authentik). |
| Microsoft Office (viewing/editing) | OnlyOffice Desktop Editors | Install automated. Connects to the NextCloud portal for storage; login is the same SSO click. |
| Adobe Acrobat | Stirling PDF | No install — it's a web app at `pdf.lab.internal`. Installer scripts create a pinned "app" shortcut so it feels like a desktop app. Gated by Authentik forward-auth (see [docker/stirling-pdf/README.md](../docker/stirling-pdf/README.md)). |
| Outlook (mail+calendar+contacts) | **Betterbird** | Fully zero-click account setup via autoconfig — see below. |
| Teams + Outlook Web | NextCloud Talk + Calendar + Contacts + Mail apps | Installed/enabled automatically by [`docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh`](../docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh). Calendar/Contacts/Talk need zero extra client setup (browser-based, same NextCloud SSO session). Mail app needs one manual step per user — see below. |

## Why Betterbird

[Betterbird](https://betterbird.eu/) is a maintained fork of Thunderbird that keeps full
compatibility with Thunderbird's ecosystem (profiles, extensions, the Mozilla autoconfig
protocol) while shipping more frequent fixes and a few teaching-relevant UI defaults out of the
box. For this lab specifically:

- **Betterbird supports the Mozilla autoconfig protocol natively** (inherited from
  Thunderbird): type an email address, it queries
  `https://autoconfig.<domain>/mail/config-v1.1.xml` automatically and fills in IMAP/SMTP host,
  port, and encryption with zero manual entry. This repo serves that file
  (`docker/mail/autoconfig/config-v1.1.xml`, via the `autoconfig` service in
  [`docker/mail/docker-compose.yml`](../docker/mail/docker-compose.yml)) precisely so this
  works out of the box.
- **CalDAV/CardDAV autodiscovery** pairs directly with NextCloud's Calendar/Contacts apps
  (NextCloud serves the standard `/.well-known/caldav` and `/.well-known/carddav` redirects
  already) — add the NextCloud account once and calendar+contacts show up without separate
  configuration.
- No apt/winget package exists for it (see [Installation](#installation) below for how the
  scripts handle that), which is the one piece of friction versus upstream Thunderbird — worth
  it for the reasons above, but flagged here since it's the one part of setup that can drift if
  Betterbird changes its release URLs.

## Installation

Betterbird ships no apt (Linux) or winget (Windows) package, so both installer scripts fetch it
directly from betterbird.eu — a tarball on Linux (extracted to `/opt/betterbird`, same pattern
Mozilla uses for Firefox/Thunderbird), an NSIS installer on Windows (`/S` silent install, same
installer technology as upstream Thunderbird). **Betterbird's download URLs shift between
releases** — if either script reports a failed download, check
[betterbird.eu/downloads](https://betterbird.eu/downloads/) for the current linux64/win64 URL
and re-run with `--betterbird-url <url>` (Linux) / `-BetterbirdUrl <url>` (Windows).

## Betterbird: zero-click via autoconfig

1. Install: `desktop-apps/linux/install-desktop-apps.sh` (Linux) or
   `desktop-apps/windows/install-desktop-apps.ps1` (Windows).
2. Open Betterbird, "Set Up an Existing Email Account", enter name + `student01@lab.internal` +
   AD password.
3. Betterbird fetches `https://autoconfig.lab.internal/mail/config-v1.1.xml` automatically and
   proposes IMAP (993/SSL) + SMTP (587/STARTTLS) — accept and done. No hostnames typed.
4. Add the NextCloud CalDAV/CardDAV account (Betterbird's built-in "Address Book" → "New
   Address Book" → "On the network" / Calendar → "New Calendar" → "On the network", URL
   `https://cloud.lab.internal/remote.php/dav/`) for calendar/contacts sync — this one step
   isn't autoconfig-covered by the Mozilla protocol (it's NextCloud-specific), so it's a
   one-time manual URL entry, not zero-click.

## NextCloud Mail app: one manual step

[`docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh`](../docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh)
installs and enables the Mail app for everyone, but **cannot** auto-provision each user's
IMAP account the way some NextCloud+LDAP setups do. That shortcut only works when NextCloud
itself validates the login password directly against LDAP — this lab's NextCloud instead
authenticates via **OIDC** (see [oidc-flow.md](../diagrams/oidc-flow.md)), so NextCloud never
sees the user's AD password at all, and therefore has nothing to hand the Mail app. Each user
adds their `mail.lab.internal` account once from inside the NextCloud Mail app UI, using their
own AD password — a single manual step, not a missing feature. This is a good discussion point
for [StudentLabManual.md](StudentLabManual.md): OIDC's security property (the relying app never
holds your password) is exactly what makes this one step unavoidable.

## NextCloud Desktop Sync

`desktop-apps/*/install-desktop-apps.*` installs the client;
`desktop-apps/*/configure-nextcloud-client.*` pre-seeds the server URL
(`https://cloud.lab.internal`) into the client's config file
(`~/.config/Nextcloud/nextcloud.cfg` on Linux, `%APPDATA%\Nextcloud\nextcloud.cfg` on Windows)
so the student opens the app, sees the LAB-branded Authentik login screen immediately (server
field pre-filled), and clicks through SSO — no server hostname to type or look up.

## OnlyOffice Desktop Editors

Installed the same way. Connect it to the NextCloud portal once (Desktop Editors → "Connect to
cloud" → paste `https://cloud.lab.internal`) to edit documents stored in NextCloud directly
from the desktop app rather than only through the browser-embedded OnlyOffice editor.

## Stirling PDF: pinned web app, not a native install

Stirling PDF doesn't ship a desktop client — it's a web app. Both installer scripts create a
"pinned app" shortcut (`msedge --app=https://pdf.lab.internal` on Windows, a `.desktop` launcher
wrapping `chromium --app=` on Linux) so it opens in its own chromeless window from the Start
Menu/Applications launcher, indistinguishable in daily use from a native app, without
maintaining a separate desktop build. Access is gated by Authentik forward-auth — see
[docker/stirling-pdf/README.md](../docker/stirling-pdf/README.md).

## Running the provisioning scripts

```bash
# Linux client (run on linux-client01, after joining the domain)
sudo desktop-apps/linux/install-desktop-apps.sh
desktop-apps/linux/configure-nextcloud-client.sh
```

```powershell
# Windows client (elevated PowerShell, after joining the domain)
desktop-apps\windows\install-desktop-apps.ps1
desktop-apps\windows\configure-nextcloud-client.ps1
```

See [`desktop-apps/README.md`](../desktop-apps/README.md) for what each script does and
requires.
