# LAPS: Unique Local Administrator Passwords

Every Windows machine has a local Administrator account. If they all share one password, one
stolen password opens every machine: the attacker moves sideways (**lateral movement**), which is
how a single compromised PC becomes a whole-estate incident. **LAPS** (Local Administrator
Password Solution) gives each machine its own random password, rotates it on a schedule, and
keeps it in that machine's own directory object, readable only by chosen groups.

The lab uses **Windows LAPS**, built into Windows 11 and Windows Server 2022/2025 once updated
since April 2023. It replaces the older "legacy" Microsoft LAPS, which is a separate download.

## How it works

```text
machine: sets its own random local Admin password every 30 days (policy from a GPO)
       --> writes it to its own computer object in AD (msLAPS-Password)
       --> only IT-Admins can read it:  Get-LapsADPassword -Identity winsrv01 -AsPlainText
```

Group Policy sets the length, age, and which account. Active Directory permissions say who may
read and reset it.

## On Samba AD: what is different

This is where Samba and Windows AD part ways, and it is a good lesson in reading the small print.

| | Windows AD | Samba AD (this lab) |
|---|---|---|
| Schema ready for LAPS | `Update-LapsADSchema` | **Manual**: an LDIF extension applied on the DC with `ldbadd` (below) |
| Password stored | Encrypted, if the functional level allows | **Clear text** in `msLAPS-Password`, protected only by AD permissions |
| Password encryption | Supported at a 2016 functional level | **Not supported**: enabling it stops LAPS from working |
| Reading in the GUI | Active Directory Users and Computers has a LAPS tab | A 2023 Samba mailing-list report says that tab hung against Samba; use `Get-LapsADPassword` and check whether it still happens on your version |
| Domain controllers' own DSRM password | Can be managed | Not available |

The practical effect: on Samba, anyone who can read the password attribute can read the clear-text
password, so **keep the reading group very small** and treat it as privileged. A schema extension
**cannot be undone**, which is why the script backs the domain up first and wants `--yes`.

## Setting it up

### 1. Extend the schema (once, on the DC)

Get the two LDIF files from Samba-AD's guide
([Configuring LAPS for Samba-AD](https://samba.tranquil.it/doc/en/samba_advanced_methods-samba_configure_laps.html)),
read them, and change the example domain to `DC=lab,DC=internal`. They are not in this repo because
they are Microsoft's schema definitions and a wrong copy would spread to every lab. Then:

```bash
# take a VM snapshot first
sudo samba/scripts/extend-schema-laps.sh --ldif1 laps-1.ldif --ldif2 laps-2.ldif --dry-run
sudo samba/scripts/extend-schema-laps.sh --ldif1 laps-1.ldif --ldif2 laps-2.ldif --yes
```

[`extend-schema-laps.sh`](../samba/scripts/extend-schema-laps.sh) checks it is running on the
Schema Master, skips work already done, backs up with [`backup-ad.sh`](../samba/scripts/backup-ad.sh),
applies the two files in order, and restarts Samba.

### 2. Permissions and policy (from Windows, as Domain Admin)

```powershell
.\Enable-WindowsLaps.ps1 -WhatIf -ReadersGroup "LAB\IT-Admins" -ComputerOU `
  "OU=Windows,OU=Servers,OU=LAB,DC=lab,DC=internal",
  "OU=Windows,OU=Workstations,OU=LAB,DC=lab,DC=internal"
```

[`Enable-WindowsLaps.ps1`](../scripts/windows/Enable-WindowsLaps.ps1) lets machines write their own
password, lets the named group read and reset it, creates the "LAB - Windows LAPS" GPO (password
back-up to Active Directory, 20 characters, 30 days, encryption off), and links it.

### 3. Check

On a managed machine: `gpupdate /force; Invoke-LapsPolicyProcessing`. The **LAPS** event log
(Applications and Services Logs > Microsoft > Windows > LAPS > Operational) should show event
**10018**: password updated in Active Directory. Then, as an IT-Admin:

```powershell
Get-LapsADPassword -Identity winsrv01 -AsPlainText
```

## Using it

- **Normal work:** use your own named domain account. LAPS is for the break-glass local account,
  used when the domain is unreachable or the machine has dropped out of it.
- **After using a password:** it resets itself after the grace period (24 hours by default,
  `PostAuthenticationActions` also signs the session out). Or force it: `Reset-LapsPassword`.
- **After a leaver or a breach:** rotate with `Set-LapsADPasswordExpirationTime`.

## Exercise

1. Without LAPS, set the same local Administrator password on two machines. From one, use it to
   reach the other. This is lateral movement.
2. Apply LAPS. Read each machine's password. Confirm they differ.
3. Sign in to one machine locally with its LAPS password. Wait for (or force) the reset. Does the
   old password still work?
4. As an ordinary user (not in the readers group), try `Get-LapsADPassword`. What happens, and why?
5. Find the clear-text value in AD with an LDAP tool. What does that tell you about the readers
   group, and what would a Windows AD at a 2016 level do differently?
6. Look at the LAPS event log and Loki. What would you alert on?

## Gotchas

- **Order.** Schema first, then permissions and policy. A policy with no schema produces errors
  in the LAPS log and no password.
- **The managed account must exist.** LAPS does not create a custom account; with the default it
  manages the built-in Administrator, found by its RID, not its name.
- **Complexity must fit local policy.** A length or complexity the machine's own password policy
  rejects fails with event 10027.
- **Domain controllers have no local accounts**, so LAPS does not apply to them.
- **LAPS is one control, not a strategy.** Pair it with least privilege, tiered admin accounts and
  the [hardening](CISHardening.md) and [tuning](WindowsTuning.md) work.
