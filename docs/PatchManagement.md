# Patch Management

Most successful attacks use a vulnerability that already had a fix. Patching is how you stop
being the easy target. It is also how you cause your own outage, if a bad update reaches every
machine at once. So patching is a **process**, not a button: decide, test, roll out in stages,
verify, and be able to go back.

## The process

1. **Know what you have.** An inventory: which machines, which OS, what role.
2. **Know what is missing.** Report before installing:
   `ansible-playbook playbooks/12-windows-patching.yml -e patching_state=searched`
3. **Assess.** Security fixes are urgent; feature updates are a planned project.
4. **Test.** Install on **ring 0** (a test group) first.
5. **Roll out.** Only if ring 0 is healthy, install on **ring 1**.
6. **Verify.** Services up, monitoring green, no new errors.
7. **Roll back** if needed, and record what happened.
8. **Report.** What was patched, when, and what is still outstanding.

## Choose one mechanism per machine

Two systems both installing updates will fight over restarts. The lab's choices:

| Option | How it works | Use it for | Trade-off |
|---|---|---|---|
| **Windows Update direct** | Machine fetches from Microsoft on a schedule | Home PCs, tiny offices | No control over timing or testing |
| **Windows Update for Business**, delivered by Group Policy | Same source, but policy sets deferral, schedule and restart rules | **Windows 11 clients** (this lab) | Each machine downloads from the Internet |
| **WSUS** | An internal server holds approved updates; machines fetch from it | Larger estates that want approval and bandwidth control | A server to run, storage, and Microsoft has announced it is deprecated (check current guidance) |
| **Ansible** (`win_updates`) | A playbook installs in a planned window, in rings | **Windows servers** (this lab) | No console; you maintain the playbook |
| **An RMM** | An agent applies a policy with rings and windows | Many sites, a service desk | A server and agents to trust ([RMM.md](RMM.md)) |
| **`unattended-upgrades`** | Debian/Ubuntu fetch security fixes nightly | **Linux servers** (this lab, set by the `common` role) | Kernel updates still need a restart |

**In this lab:** clients patch themselves overnight under Group Policy with a few days' deferral;
servers only *notify*, and Ansible installs in a planned window; Linux uses unattended-upgrades.

## Setting it up

```powershell
# Group Policy: from a domain-joined Windows machine with the GP tools, as IT-Admins
.\New-PatchPolicyGpo.ps1 -Role Client -LinkOU "OU=Windows,OU=Workstations,OU=LAB,DC=lab,DC=internal" -WhatIf
.\New-PatchPolicyGpo.ps1 -Role Server -LinkOU "OU=Windows,OU=Servers,OU=LAB,DC=lab,DC=internal" -WhatIf
```

[`New-PatchPolicyGpo.ps1`](../scripts/windows/New-PatchPolicyGpo.ps1) creates the GPO. For the
**Server** role it sets Windows to *notify only* so it never installs or restarts by itself.

```bash
# Ansible: from the control host
kinit administrator@LAB.INTERNAL
ansible-playbook playbooks/12-windows-patching.yml -e patching_state=searched   # what is missing?
ansible-playbook playbooks/12-windows-patching.yml                              # install, ring by ring
```

Put one test machine in `[windows_ring0]` in [`hosts.ini`](../ansible/inventory/hosts.ini), the rest
in `[windows_ring1]`. Ring 0 runs one host at a time, and **ring 1 does not start if ring 0 had
any failed update**: the play stops. A skipped update known to break something goes in
`patching_reject_list`.

## Rollback

| Layer | How |
|---|---|
| **Snapshot** the VM first | Fastest and most complete. Revert in the hypervisor. A snapshot is not a backup |
| **Uninstall one update** | `wusa /uninstall /kb:5012345 /quiet /norestart` |
| **Stop it spreading** | Add the KB to `patching_reject_list` so ring 1 skips it |
| **Restore from backup** | Proxmox Backup Server ([Backup.md](Backup.md)) |

## Verifying

- **Installed?** `Get-HotFix | Sort-Object InstalledOn -Descending | Select -First 5`
- **Restart still pending?** The playbook reports `reboot_required`.
- **Healthy?** The Grafana dashboard ([Monitoring.md](Monitoring.md)): hosts up, probes passing.
- **What did Windows log?** In Loki ([Logging.md](Logging.md)): `{job="windows-eventlog", log="system"}`
  and look for Windows Update events (19 = installed, 20 = failed).

## Exercise

1. Run the report-only playbook. How many updates are missing on each ring?
2. Link the Server GPO to the Servers OU. On the server, confirm Windows now only notifies.
3. Install on ring 0. Read `C:\ProgramData\LabHostPrep\patching.log`. Did it need a restart?
4. Make ring 0 fail on purpose (stop and disable the Windows Update service on the ring 0 host
   before the run, and restore it afterwards) and show that ring 1 does not start. Why is that
   the right default?
5. Take a snapshot, install an update, uninstall it with `wusa`, and compare with reverting the
   snapshot. When would you choose each?
6. Draft a one-page change notice for a monthly patch window: scope, time, who is told, rollback.

## Gotchas

- **Restarts are the hidden cost.** A "patched" server that never restarted is not patched. Plan
  the window around the restart.
- **Don't patch everything at once.** That is the point of rings.
- **Feature updates are not patches.** They change behaviour. The GPO defers them; plan them.
- **Domain controllers** should be patched one at a time. This lab has one DC, so schedule an
  outage. It is a real argument for a second one.
- **Evaluation editions** of Windows Server stop working at the end of the evaluation period, no
  matter how patched.
- **Third-party software** (browsers, Java, PDF readers) is not delivered by Windows Update.
  An RMM, or a package manager like `winget`, covers it. That gap is a common finding in an audit.
