# Windows Server member server — `winsrv01`

A Windows Server joined to the Samba AD domain. It is the lab's commercial reference: file
server and shares, Group Policy management, and the place to run Windows-only server tools. It
joins `LAB.INTERNAL` like every other machine, Windows or Linux.

| Spec | Value                                                              |
| ---- | ------------------------------------------------------------------ |
| vCPU | 2                                                                  |
| RAM  | 4096 MB                                                            |
| Disk | 50 GB (thin)                                                       |
| NIC  | LAN Segment `LAN-LAB`                                              |
| ISO  | Windows Server 2022 or 2025 evaluation (Desktop Experience)        |
| IP   | `10.10.10.40`, static (outside the DHCP pool)                      |

**Where it runs.** In scenario 1 and 2 it is a **native VMware VM, never nested**: Windows under
nested KVM is slow. In scenario 3 it is a Proxmox VM. Sizing and the weeks it runs are in the
[scenario 2 table](../../scenarios/2-nested-proxmox/README.md#reference-lab-pc-and-sizing).

## Build + install

1. New VM wizard, **Windows Server 2022** (or 2025) as the guest OS, 2 vCPU, 4096 MB, 50 GB
   thin disk, the evaluation ISO, one NIC on `LAN-LAB`. Choose **Desktop Experience** at setup so
   the GUI management tools are available.
2. Install interactively. Evaluation editions run for a limited time (about 180 days); note the
   expiry date, since a rebuilt lab needs a fresh evaluation.
3. Set the static address `10.10.10.40/24`, gateway `10.10.10.1`, **DNS `10.10.10.10`** (the
   domain controller). Domain join fails without it.
4. Apply [`hypervisor/desktop/baseline.md`](../desktop/baseline.md) where it applies to Windows
   (updates, VMware Tools, time zone).

## Join the domain

1. Confirm DNS: `Resolve-DnsName lab.internal` returns `10.10.10.10`.
2. Run the same join script as the Windows client, with the server OU:

   ```powershell
   .\join-windows-client.ps1 -TargetOU "OU=Windows,OU=Servers,OU=LAB,DC=lab,DC=internal"
   ```

   ([`samba/scripts/join-windows-client.ps1`](../../samba/scripts/join-windows-client.ps1)). The
   `OU=Servers` structure is created by
   [`samba/scripts/create-ous.sh`](../../samba/scripts/create-ous.sh); re-run it if the OU is missing.
3. After the restart, sign in as a domain user and confirm CA trust arrived by Group Policy
   (`gpupdate /force`), as for the client. See [docs/PKI.md](../../docs/PKI.md#trust-deployment).

## What to do with it

- Install the Group Policy tools (`Install-WindowsFeature GPMC, RSAT-AD-Tools`) and manage the
  domain's GPOs from here. A Samba domain stores GPOs in SYSVOL and Windows manages them with
  the standard tools: see [SambaVsWindowsAD.md](../../docs/SambaVsWindowsAD.md).
- Host a file share with permissions based on domain groups (course week 7): see
  [File server exercise](#file-server-exercise) below.
- Provision users in bulk with PowerShell, not `csvde`:
  [`scripts/windows/New-LabUsers.ps1`](../../scripts/windows/New-LabUsers.ps1). It uses LDAP
  through .NET, not `New-ADUser`, because the Active Directory PowerShell module needs Active
  Directory Web Services, which Samba does not provide
  ([SambaVsWindowsAD.md](../../docs/SambaVsWindowsAD.md)).
- Install the monitoring and logging agents with
  [`scripts/windows/Install-MonitoringAgents.ps1`](../../scripts/windows/Install-MonitoringAgents.ps1):
  [Monitoring.md](../../docs/Monitoring.md#windows-hosts), [Logging.md](../../docs/Logging.md#windows-hosts).
- Harden it with Group Policy, using
  [`scripts/windows/Import-BaselineGpo.ps1`](../../scripts/windows/Import-BaselineGpo.ps1):
  [CISHardening.md](../../docs/CISHardening.md#windows-server-and-clients).

## File server exercise

A file share where access follows **domain groups**, and people only see what they may open.
This is the pattern behind every departmental share. None of these commands need the Active
Directory module, so they work against the Samba domain.

```powershell
# 1. Install the role and create the folder
Install-WindowsFeature FS-FileServer
New-Item -ItemType Directory -Path D:\Shares\Lecturers -Force

# 2. Share it. Access-based enumeration hides files a user cannot open.
New-SmbShare -Name Lecturers -Path D:\Shares\Lecturers `
  -FolderEnumerationMode AccessBased `
  -FullAccess "LAB\Domain Admins" -ChangeAccess "LAB\Lecturers"

# 3. NTFS permissions: the share permission and the NTFS permission BOTH apply, and the
#    stricter one wins. Remove inherited access, then grant by group.
$acl = Get-Acl D:\Shares\Lecturers
$acl.SetAccessRuleProtection($true, $false)
$rules = @(
  New-Object System.Security.AccessControl.FileSystemAccessRule("LAB\Domain Admins","FullControl","ContainerInherit,ObjectInherit","None","Allow"),
  New-Object System.Security.AccessControl.FileSystemAccessRule("LAB\Lecturers","Modify","ContainerInherit,ObjectInherit","None","Allow")
)
$rules | ForEach-Object { $acl.AddAccessRule($_) }
Set-Acl D:\Shares\Lecturers $acl
```

Then sign in as `lecturer01` and `student01` from `win-client01` and open the share at `\\winsrv01\Lecturers`.
Which can open it, which can see it, and why? Change a group membership and sign in again: when
does the change take effect (a new logon token is needed)?

Discuss: why use groups rather than users in permissions, what "stricter wins" means when the
share and NTFS permissions differ, and why `Domain Admins` is not the group to give day-to-day
access.
