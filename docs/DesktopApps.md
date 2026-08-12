# Desktop Apps & Experiences

The web apps in [`docker/`](../docker/) cover the server side. This doc covers the client
side: what runs on `linux-client01`/`win-client01` to give students an "Outlook/OneDrive/Teams
replacement" experience, what's automated, and what's a deliberate one-time manual step and
why. See [`desktop-apps/`](../desktop-apps/) for the installer/provisioning scripts this doc
walks through.

## At a glance

| Replaces                            | App                                              | Automated?                                                                                                                                                                                                                                                                                                  |
| ----------------------------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OneDrive                            | NextCloud Desktop Sync                           | Install + server URL pre-filled automatically. Login is one click (SSO via Authentik).                                                                                                                                                                                                                      |
| Microsoft Office (viewing/editing)  | OnlyOffice Desktop Editors                       | Install automated. Connects to the NextCloud portal for storage; login is the same SSO click.                                                                                                                                                                                                               |
| Adobe Acrobat                       | Stirling PDF                                     | No install — it's a web app at `pdf.lab.internal`. Installer scripts create a pinned "app" shortcut so it feels like a desktop app. Gated by Authentik forward-auth (see [docker/stirling-pdf/README.md](../docker/stirling-pdf/README.md)).                                                                |
| Outlook (mail+calendar+contacts)    | **Thunderbird** (recommended)                    | Fully zero-click account setup via autoconfig — see below.                                                                                                                                                                                                                                                  |
| Outlook (alternative, GNOME-native) | Evolution                                        | Best-effort scripted account provisioning; less reliable than Thunderbird's autoconfig — see [Evolution](#evolution-alternative-best-effort).                                                                                                                                                               |
| Teams + Outlook Web                 | NextCloud Talk + Calendar + Contacts + Mail apps | Installed/enabled automatically by [`docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh`](../docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh). Calendar/Contacts/Talk need zero extra client setup (browser-based, same NextCloud SSO session). Mail app needs one manual step per user — see below. |

## Why Thunderbird over Evolution as the primary recommendation

You asked for Evolution specifically ("unless there's something better?") — there is, for this
lab's purposes specifically:

- **Thunderbird supports the Mozilla autoconfig protocol natively**: type an email address,
  Thunderbird queries `https://autoconfig.<domain>/mail/config-v1.1.xml` automatically and
  fills in IMAP/SMTP host, port, and encryption with zero manual entry. This repo now serves
  that file (`docker/mail/autoconfig/config-v1.1.xml`, via the `autoconfig` service in
  [`docker/mail/docker-compose.yml`](../docker/mail/docker-compose.yml)) precisely so this
  works out of the box.
- **Thunderbird's CalDAV/CardDAV autodiscovery** pairs directly with NextCloud's Calendar/
  Contacts apps (NextCloud serves the standard `/.well-known/caldav` and `/.well-known/carddav`
  redirects already) — add the NextCloud account once and calendar+contacts show up without
  separate configuration.
- **Evolution is GNOME-native and closer to Outlook's integrated single-app feel**, and remains
  a fully reasonable choice if that matters more to your course than zero-click setup — it's
  documented below as a supported alternative, just not the default.
- Both are free/open-source and available on Ubuntu; neither is a downgrade in capability, this
  is purely about automation reliability for a teaching lab.

If your course specifically wants to teach the GNOME desktop stack end-to-end, switch the
default in [`desktop-apps/linux/install-desktop-apps.sh`](../desktop-apps/linux/install-desktop-apps.sh)
by flipping which app the script marks primary — both install scripts are already there.

## Thunderbird: zero-click via autoconfig

1. Install: `desktop-apps/linux/install-desktop-apps.sh` (Linux) or
   `desktop-apps/windows/install-desktop-apps.ps1` (Windows) installs Thunderbird via
   `apt`/`winget`.
2. Open Thunderbird, "Set Up an Existing Email Account", enter name + `student01@lab.internal`
   - AD password.
3. Thunderbird fetches `https://autoconfig.lab.internal/mail/config-v1.1.xml` automatically and
   proposes IMAP (993/SSL) + SMTP (587/STARTTLS) — accept and done. No hostnames typed.
4. Add the NextCloud CalDAV/CardDAV account (Thunderbird's built-in "Address Book" → "New
   Address Book" → "On the network" / Calendar → "New Calendar" → "On the network", URL
   `https://cloud.lab.internal/remote.php/dav/`) for calendar/contacts sync — this one step
   isn't autoconfig-covered by the Mozilla protocol (it's NextCloud-specific), so it's a
   one-time manual URL entry, not zero-click.

## Evolution (alternative, best-effort)

[`desktop-apps/linux/configure-evolution.sh`](../desktop-apps/linux/configure-evolution.sh)
attempts to pre-seed an IMAP/SMTP account via `gsettings`/`dconf` against Evolution's mail
account schema. This is marked best-effort in the script itself: Evolution's account storage
schema has shifted across GNOME releases, so treat this as "saves most students the typing,"
not "guaranteed zero-click" — verify it actually applied after running it on your specific
Ubuntu Desktop image, and fall back to Evolution's own "Add Mail Account" wizard (a few clicks:
email + password, same IMAP/SMTP values as the [mail client configuration table](../docker/mail/README.md#client-configuration))
if it didn't.

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
desktop-apps/linux/configure-evolution.sh   # optional, best-effort — see caveat above
```

```powershell
# Windows client (elevated PowerShell, after joining the domain)
desktop-apps\windows\install-desktop-apps.ps1
desktop-apps\windows\configure-nextcloud-client.ps1
```

See [`desktop-apps/README.md`](../desktop-apps/README.md) for what each script does and
requires.
