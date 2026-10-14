# Desktop VM Baseline

Applied once, right after the interactive OS install, to every general-purpose-OS VM in the lab
— `samba-dc01`, `docker01`, `authentik01`, `linux-client01`, `win-client01`. **Not** `pfsense01`:
it's a BSD appliance with its own package manager, no VM-tools concept, and no general-purpose
SSH shell — see [`../vms/pfsense.md`](../vms/pfsense.md) for its own (much shorter) post-install
steps instead.

## 1. Patch

```bash
sudo apt update && sudo apt full-upgrade -y
```

Reboot if the kernel was updated (`sudo reboot`) — Subiquity's installer usually leaves you on a
current kernel, but package updates released since the ISO was built are still worth applying
before doing anything else with the VM.

**Windows** (`win-client01` only): Settings → Windows Update → Check for updates, reboot if
prompted.

## 2. VM tools

```bash
sudo apt install -y open-vm-tools
```

On `linux-client01` only, also install `open-vm-tools-desktop` for clipboard sharing and better
display resolution handling — the three servers are headless and don't need it.

**Windows**: VM menu → **Install VMware Tools** (or **Reinstall VMware Tools**), then run the
installer from the mounted virtual CD.

## 3. Locale

Installer defaults don't always match where you actually are. Verify and correct:

```bash
localectl status                              # check current locale/keyboard
sudo localectl set-locale LANG=en_AU.UTF-8    # or whichever locale is correct for you
sudo timedatectl set-timezone Australia/Perth # or your actual timezone
```

**Windows**: Settings → Time & Language — check region, language, and time zone.

## 4. SSH keys

This is what lets the control host's (`linux-client01`) Ansible runs authenticate against
`samba-dc01`, `docker01`, and `authentik01` later — without it, every `ansible-playbook` run in
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md) from step 5 onward has nothing to log
in with.

**The three Ubuntu Server hosts and `linux-client01`**: use Subiquity's own "Import SSH
identity" / paste-a-public-key step during install, rather than doing this after the fact — it's
built into the installer's SSH configuration screen. If you already finished the install without
doing this, append your public key to `~/.ssh/authorized_keys` for the `labadmin` account
instead.

**`win-client01`**: enable the OpenSSH Server optional feature —

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
```

— then add your public key to `C:\ProgramData\ssh\administrators_authorized_keys` (**not**
`~\.ssh\authorized_keys`): Windows' OpenSSH server routes any account in the local
Administrators group through this file instead of the per-user one Linux uses. Its ACL must
restrict access to Administrators and SYSTEM only, or the OpenSSH service refuses to use it —
from an elevated PowerShell prompt:

```powershell
icacls.exe "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
```
