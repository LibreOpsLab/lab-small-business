# Managing Windows with Ansible

Linux hosts are managed over SSH. Windows hosts can be managed by the **same tool** over WinRM
(Windows Remote Management), so one set of playbooks, one Git history and one habit covers both.

## Why Ansible for Windows

| Approach | How it works | Good for | Cost |
|---|---|---|---|
| **Ansible** (this lab) | Agentless: connects over WinRM, runs a task, disconnects | Repeatable change, in Git, one tool for Linux and Windows | You maintain the playbooks; no live dashboard |
| **Group Policy** | The domain pushes settings; machines pull them | Settings that must always hold (password rules, firewall, LAPS) | Poor at planned, ordered change: it cannot run a patch window in rings or report what happened |
| **An RMM** (agent plus server) | An agent on each machine phones home | Remote access, alerts, patching for many sites | A server and agents to run and trust. See [RMM.md](RMM.md) |

They are complements. Group Policy keeps settings true; Ansible makes planned changes; an RMM adds
a console. The lab uses the first two, and treats an RMM as an optional extra.

## What is automated here

| Task | How |
|---|---|
| Tune for performance and security | [`11-windows-optimize.yml`](../ansible/playbooks/11-windows-optimize.yml): [WindowsTuning.md](WindowsTuning.md) |
| Patch in rings | [`12-windows-patching.yml`](../ansible/playbooks/12-windows-patching.yml): [PatchManagement.md](PatchManagement.md) |
| Local administrator passwords | Group Policy: [LAPS.md](LAPS.md) |
| Monitoring and log agents | PowerShell: [`Install-MonitoringAgents.ps1`](../scripts/windows/Install-MonitoringAgents.ps1) |

## Setting it up

### 1. The Windows machine

Windows needs a WinRM listener on HTTPS with a certificate from the lab CA, reachable only from
the control host. [`Enable-AnsibleWinRM.ps1`](../scripts/windows/Enable-AnsibleWinRM.ps1) does
exactly that and removes the unencrypted HTTP listener.

```bash
# On the PKI machine: a certificate for the exact name Ansible will use
pki/scripts/02-issue-server-cert.sh --cn winsrv01.lab.internal --san DNS:winsrv01.lab.internal
openssl pkcs12 -export -inkey <key.pem> -in <fullchain.pem> -out winsrv01.pfx
```

Copy the `.pfx` across and run the script in an elevated PowerShell, with `-WhatIf` first.

### 2. The control host (`linux-client01`)

```bash
pip install "pywinrm[kerberos]"
sudo apt install krb5-user                       # already present on a domain-joined host
cd ansible && ansible-galaxy collection install -r requirements.yml
```

The inventory entries are commented out in [`hosts.ini`](../ansible/inventory/hosts.ini); uncomment
the Windows machines that exist. Connection settings are in
[`group_vars/windows.yml`](../ansible/group_vars/windows.yml).

### 3. Test

```bash
kinit administrator@LAB.INTERNAL          # a Kerberos ticket: no password is stored in Ansible
ansible windows -m ansible.windows.win_ping
```

`pong` means DNS, time, the certificate chain, Kerberos and WinRM are all working.

## Why Kerberos over HTTPS

- **Kerberos** proves who you are without sending a password, and proves the *machine* is the one
  you meant (mutual authentication). That is why the inventory uses names, not IP addresses.
- **HTTPS with a verified certificate** encrypts the session. The control host checks the
  certificate against the lab CA; it never skips the check.
- **No stored password.** You run `kinit`; the ticket expires on its own.

## Gotchas

- **Use the full name.** Kerberos needs `winsrv01.lab.internal`, not `10.10.10.40`. If `win_ping`
  fails with an authentication error, check you used the name the certificate and the Kerberos
  principal were issued for.
- **Clock skew.** More than five minutes apart and Kerberos fails. The monitoring dashboard
  watches this ([Monitoring.md](Monitoring.md)).
- **Updates drop the connection.** A patch can reset the network adapter. The patching role runs
  as SYSTEM for that reason.
- **The "double hop".** A Kerberos session cannot, by default, reach a second machine on your
  behalf (for example a network share) from inside a playbook. Copy files with Ansible instead.
- **`ansible.cfg` turns on sudo.** Windows has no sudo, so `group_vars/windows.yml` switches it
  off and the tasks that need elevation ask for `runas`.
- **Samba AD and ADWS.** The AD PowerShell module, and the Ansible modules built on it (most of
  the `microsoft.ad` collection), need Active Directory Web Services, which Samba does not provide
  ([SambaVsWindowsAD.md](SambaVsWindowsAD.md)). Manage accounts with `samba-tool` or the LDAP
  script instead. Machine management as described here is unaffected.
