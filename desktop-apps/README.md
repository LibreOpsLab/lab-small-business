# Desktop Apps

Client-side provisioning scripts for `linux-client01` and `win-client01` — see
[docs/DesktopApps.md](../docs/DesktopApps.md) for the full picture (what's automated, what's a
deliberate one-time manual step, and why).

| Script                                                                             | Platform       | Purpose                                                                                                         |
| ---------------------------------------------------------------------------------- | -------------- | --------------------------------------------------------------------------------------------------------------- |
| [`linux/install-desktop-apps.sh`](linux/install-desktop-apps.sh)                   | Ubuntu Desktop | Installs NextCloud Desktop, OnlyOffice Desktop Editors, Thunderbird, Evolution, and a Stirling PDF app shortcut |
| [`linux/configure-nextcloud-client.sh`](linux/configure-nextcloud-client.sh)       | Ubuntu Desktop | Pre-seeds the NextCloud desktop client's server URL                                                             |
| [`linux/configure-evolution.sh`](linux/configure-evolution.sh)                     | Ubuntu Desktop | Best-effort pre-provisioning of an Evolution IMAP/SMTP account                                                  |
| [`windows/install-desktop-apps.ps1`](windows/install-desktop-apps.ps1)             | Windows 11     | Installs the same set (minus Evolution, which is Linux/GNOME-only) via `winget`                                 |
| [`windows/configure-nextcloud-client.ps1`](windows/configure-nextcloud-client.ps1) | Windows 11     | Pre-seeds the NextCloud desktop client's server URL                                                             |

Run these after the client has joined the domain (`samba/scripts/join-linux-client.sh` /
`samba/scripts/join-windows-client.ps1`) and after `ansible/playbooks/05-pki-trust.yml` (or the
Windows GPO) has installed CA trust — several of these apps talk HTTPS to `*.lab.internal` and
need that trust in place first.
