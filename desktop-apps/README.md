# Desktop Apps

Client-side provisioning scripts for `linux-client01` and `win-client01` — see
[docs/DesktopApps.md](../docs/DesktopApps.md) for the full picture (what's automated, what's a
deliberate one-time manual step, and why).

| Script | Platform | Purpose |
|---|---|---|
| [`linux/install-desktop-apps.sh`](linux/install-desktop-apps.sh) | Ubuntu Desktop | Installs NextCloud Desktop, OnlyOffice Desktop Editors, Betterbird, and a Stirling PDF app shortcut |
| [`linux/configure-nextcloud-client.sh`](linux/configure-nextcloud-client.sh) | Ubuntu Desktop | Pre-seeds the NextCloud desktop client's server URL |
| [`windows/install-desktop-apps.ps1`](windows/install-desktop-apps.ps1) | Windows 11 | Installs the same set via `winget` (NextCloud, OnlyOffice) + direct download (Betterbird) |
| [`windows/configure-nextcloud-client.ps1`](windows/configure-nextcloud-client.ps1) | Windows 11 | Pre-seeds the NextCloud desktop client's server URL |

Run these after the client has joined the domain (`samba/scripts/join-linux-client.sh` /
`samba/scripts/join-windows-client.ps1`) and after `ansible/playbooks/05-pki-trust.yml` (or the
Windows GPO) has installed CA trust — several of these apps talk HTTPS to `*.lab.internal` and
need that trust in place first.

Betterbird has no apt/winget package, so both install scripts fetch it directly from
betterbird.eu; if that download fails, see
[docs/DesktopApps.md#installation](../docs/DesktopApps.md#installation) for how to point the
script at a current URL.
