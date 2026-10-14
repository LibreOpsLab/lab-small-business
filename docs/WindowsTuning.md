# Windows Tuning: Performance and Security

A fresh Windows install is tuned for a home PC and for Microsoft's data collection. On a lab
server or a managed workstation that means: telemetry running, advertising apps installed,
dozens of services nobody uses, old protocols still switched on, and too little logging to
investigate anything. This page is the lab's answer, and it is **required**, not optional.

## The approach

One data file decides, one script obeys:

| File | Role |
|---|---|
| [`optimize-profile.psd1`](../scripts/windows/optimize-profile.psd1) | The **decisions**: every change, with a one-line reason |
| [`Optimize-Windows.ps1`](../scripts/windows/Optimize-Windows.ps1) | The **engine**: audits, applies, reverts |
| [`windows_optimize`](../ansible/roles/windows_optimize/tasks/main.yml) | Ansible runs the same script across many machines |

This is the scripted, repeatable, reviewable equivalent of a GUI tuning tool such as Winhance:
you can read it, diff it, review it, keep it in Git, and run it identically on fifty machines.
A GUI is fine for learning what exists; a profile is what you would hand to a team. If you prefer
a GUI tool, use its output to decide what belongs in the profile.

## What it covers

| Category | Purpose | Examples |
|---|---|---|
| **Telemetry** | Stop sending usage data to Microsoft | Diagnostic data level, the `DiagTrack` service, CEIP and compatibility-appraiser tasks, advertising ID, activity history |
| **Consumer features** | Remove home-PC clutter and cloud features | Suggested apps, web search in Start, Widgets, Copilot, Recall, OneDrive, Edge startup boost, background apps |
| **Apps** | Remove built-in apps by exact name | News, Weather, Solitaire, Xbox, Clipchamp, Phone Link, Quick Assist |
| **Services** | Switch off what is not used | Print Spooler on servers, UPnP/SSDP, geolocation, Bluetooth, Xbox services |
| **Features** | Remove old components | SMB1, PowerShell 2.0, Internet Explorer mode |
| **Performance** | Cut idle work and disk use | Hibernation off (frees a file as big as RAM), Fast Startup off, no last-access writes, Superfetch off, Server Manager not at logon |
| **Security** | Tighten risky defaults | SMB signing, LLMNR and mDNS off, NTLMv2 only, no WDigest clear text, AutoRun off, RDP needs NLA |
| **Logging** | Record what a defender needs | PowerShell script-block logging, command lines in process events, bigger event logs, audit policy for logons, accounts, groups, processes |

Every item states its reason in the `Why` field. Read the file; it is the lesson.

## Running it

```powershell
# 1. Look. Changes nothing. Exit code 2 means differences were found.
.\Optimize-Windows.ps1

# 2. Preview one category.
.\Optimize-Windows.ps1 -Mode Apply -Category Security -WhatIf

# 3. Apply everything (elevated). Originals are saved first.
.\Optimize-Windows.ps1 -Mode Apply

# 4. Restart, then confirm.
.\Optimize-Windows.ps1

# 5. Change your mind.
.\Optimize-Windows.ps1 -Mode Revert
```

Across the estate, from the Ansible control host (snapshot first):

```bash
ansible-playbook playbooks/11-windows-optimize.yml -l winsrv01 --check   # what would change
ansible-playbook playbooks/11-windows-optimize.yml -l winsrv01           # do it
```

## Safety built in

- **Audit first, by default.** Nothing changes unless you ask.
- **Originals are saved**, once per setting, to `C:\ProgramData\LabHostPrep\optimize-state.json`,
  so Revert restores exactly what was there. Removed apps are the one exception: reinstall them
  from the Store or `winget`.
- **Protected services.** Windows Update, Defender, the firewall, the event log, the DNS client,
  time, and others are on a list the script will never change, even if you add them to the
  profile by mistake.
- **Not in the profile at all:** Windows Update, Defender, the firewall, and Credential Guard/VBS.
  The last conflicts with nested virtualisation and is controlled by
  [`Set-NestedVirtualisation.ps1`](../scripts/Set-NestedVirtualisation.ps1).
- **Exact names.** Apps are removed from an explicit list, never by wildcard.
- **Role aware.** Client-only and server-only items are skipped on the wrong kind of machine.

## Trade-offs to know

- **Telemetry level 0** is honoured on Enterprise, Education and Server only. On Pro it is treated
  as the minimum. The profile still sets it; the audit shows what Windows actually accepts.
- **Turning off error reporting** means Microsoft does not see your crashes. You read the local
  Event Log, and ship it to Loki.
- **NTLMv2 only** breaks very old devices. Samba accepts NTLMv2, so the lab is fine.
- **Superfetch off** helps SSDs and VMs and hurts machines with a hard disk. This profile is
  sized for the lab.
- **Windows can put things back.** A feature update may reinstall apps or reset policies.
  Re-run the audit after every feature update; Ansible makes that one command.
- **Domain Group Policy wins.** If a GPO sets the same value, it overrides this script at the next
  refresh. That is correct: GPO is the source of truth where both exist.
- **Not every machine is a lab VM.** Read the profile before running it on anything else.

## Exercise: measure it

1. On a fresh VM, record: idle RAM in Task Manager, number of running services
   (`(Get-Service | ? Status -eq Running).Count`), free disk space, and boot time.
2. Run `Optimize-Windows.ps1` (audit) and count the differences.
3. Apply, restart, and record the same four numbers.
4. Open the Event Viewer. Which logs now record more? Find a failed sign-in (event 4625) and a
   process start (event 4688) that includes a command line.
5. Pick three profile items and argue for or against each in a business with 20 PCs and no IT
   staff. Record any you remove in the exceptions register
   ([CISHardening.md](CISHardening.md#exceptions-register)).
6. Run `-Mode Revert` and show the machine returned to how it started.

## Gotchas

- **Snapshot before Apply.** Services and features are easiest to undo from a snapshot.
- **A setting can be "on" and not honoured.** Check with the audit, not with the registry alone.
- **Don't tune the tuner.** Edit the profile, not the script, so the decisions stay readable.
- **Auditing needs elevation** to read features, apps and audit policy; unelevated, those lines
  show `NA`.
