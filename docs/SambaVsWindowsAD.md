# Samba AD or Windows AD?

The lab's domain, `LAB.INTERNAL`, runs on **Samba AD**: free, open source, and light enough to
run on a 2 GB VM. Most real businesses run **Windows Server Active Directory**. A Junior Server
Engineer should know what the open-source option gives, what it does not, and when each is the
right answer. This page is that comparison.

> **Verify before relying on it.** Samba changes quickly. The limitations below come from the
> Samba wiki FAQ and release discussions at the time of writing. Check the release notes for
> the version you installed (`samba --version`) and the
> [Samba FAQ](https://wiki.samba.org/index.php/FAQ) before quoting any of them in an assessment.

## What both do the same

An AD domain controller gives you a directory of users, groups and computers (LDAP), single
sign-on with Kerberos, a DNS zone for the domain, time service, and Group Policy distribution.
Windows clients, Linux clients (via SSSD), and applications (Authentik, Dovecot, Postfix) use
those the same way against either. That is why this whole lab works on Samba: the protocols are
the same.

## Where they differ

| Area | Windows Server AD | Samba AD (this lab) |
|---|---|---|
| Licence and cost | Server licence plus a client access licence per user or device | Free. Support is community or a paid vendor |
| Footprint | Heavy: a Windows Server VM, several GB of RAM | Light: runs in about 2 GB |
| Domain controller on | Windows Server only | Linux only |
| SYSVOL replication between DCs | Automatic (DFS-R) | **Not implemented.** Samba does not support DFS-R, so a second DC needs SYSVOL copied by hand or a script |
| Group Policy | Full: server evaluates and applies; OU, security and WMI filtering | Samba stores and serves GPOs through SYSVOL; the FAQ says it "does not support GPO restrictions". Windows clients apply them; the DC does not |
| Password policy | Default policy plus fine-grained policies per group | Domain-wide policy set with `samba-tool domain passwordsettings`; check the release notes for per-group policy support |
| Read-only DC (RODC) | Supported | Not covered by the FAQ's feature list: check the current release notes before relying on it |
| Mixed DCs | n/a | Windows Server 2008 to 2012 R2 are listed as supported to join; the FAQ lists 2016 as not supported, which later guides contradict: test before committing |
| Functional level | Current Windows levels | Behind Windows. Newer Samba releases (4.20 onwards) raised the level; older ones top out lower |
| PowerShell AD module (`New-ADUser`, `Get-ADUser`) | Works: the DC runs Active Directory Web Services (ADWS) | **Does not work.** Samba does not implement ADWS; the cmdlets fail with "Unable to find a default server with Active Directory Web Services running". Use LDAP-based scripts ([`New-LabUsers.ps1`](../scripts/windows/New-LabUsers.ps1)), `samba-tool`, or the RSAT GUI tools |
| Certificate Authority (AD CS) | Built in as a role | Not provided. This lab uses its own OpenSSL PKI ([PKI.md](PKI.md)) and distributes trust by Group Policy |
| Trusts with other domains | Full forest and external trusts | Marked experimental in the FAQ: SID filtering not applied |
| Hybrid cloud (Entra ID / Azure) | Supported, with Microsoft tooling | Not supported by Microsoft tooling |
| File server (`smbd` on the DC) | Full | The AD DC `smbd` does not support network browsing or the `guest account` setting |
| Vendor support | Microsoft | Samba Team and partners; no single vendor SLA |

## What this means in the lab

- **The AD PowerShell module will not work.** The course teaches PowerShell provisioning in place
  of `csvde`. Here that means LDAP through .NET ([`New-LabUsers.ps1`](../scripts/windows/New-LabUsers.ps1)).
  The `GroupPolicy` cmdlets are different: they use LDAP and the SYSVOL share, not ADWS, and work
  with Samba. This is the single most surprising difference for a Windows administrator, and a
  good reason to know both platforms. Samba's wiki tracks ADWS support
  ([ADWS / AD PowerShell compatibility](https://wiki.samba.org/index.php/ADWS_/_AD_Powershell_compatibility)).

- **Group Policy still works, with Windows doing the work.** Create and edit GPOs from the
  Windows Server (GPMC), and they land in Samba's SYSVOL; Windows clients apply them. The CA
  trust GPO in [`pki/gpo/`](../pki/gpo/) relies on this. Linux hosts do not read GPOs; their
  equivalent is Ansible and SSSD settings.
- **One DC only.** There is no second DC, so the missing SYSVOL replication never bites. Adding
  one is where the gap becomes real work.
- **Plan for the clock.** Kerberos fails if clocks differ by more than five minutes, on either
  platform. The dashboard watches for it ([Monitoring.md](Monitoring.md)).
- **Keep `Domain Admins` small.** The lab gives service accounts no group memberships and uses
  `IT-Admins` with delegated rights ([Security.md](Security.md)). That is the same on both.

## When to choose which

| Choose Samba AD when | Choose Windows AD when |
|---|---|
| Budget is tight and the estate is small to medium | You use Exchange, AD CS, ADFS or hybrid Entra ID |
| You are mostly Linux and want Windows clients to join | You need RODCs, DFS-R, or full Windows-native Group Policy filtering |
| You want a small, scriptable, lab-friendly DC | You need Microsoft support and a standard anyone can hire for |
| You can accept limits and test upgrades yourself | The directory is critical and downtime has a high cost |

## Exercise: Windows AD comparison

Other labs in the course build a Windows AD domain; here the point is to **compare it with the
domain you already have**. Build a throwaway Windows Server domain controller in a **separate
domain** (not `lab.internal`), run it while the other Windows VMs are off, and delete it
afterwards. Sizes and run rules are in the
[scenario 2 README](../scenarios/2-nested-proxmox/README.md#reference-lab-pc-and-sizing); it is a
native VMware VM, 4 GB of RAM, so stop `winsrv01` and the Windows client first.

| Task | Windows AD | Samba AD | Record |
|---|---|---|---|
| Create an OU, a user, a group | `Active Directory Users and Computers`, or `New-ADUser` | `samba-tool ou/user/group create`, or `New-LabUsers.ps1` (`New-ADUser` fails) | Same result? Which was faster? |
| Create a GPO and filter it by security group | GPMC | GPMC from `winsrv01` | Does filtering work? Where is it enforced? |
| Fine-grained password policy for one group | Password Settings Container | `samba-tool domain passwordsettings` | What can you scope? |
| Add a second DC, change a GPO on one, check the other | Replicates automatically | Check SYSVOL on the second DC | How long until it appears? |
| Add a Read-only DC | Wizard | Try it; read the release notes first | Supported on your version? |
| Install a CA | Add the AD CS role | Not available | What did the lab use instead? |
| Promote and check the functional level | `Get-ADForest` | `samba-tool domain level show` | What are the two levels? |

Write up three things Samba could not do, one it did as well as Windows, and the scenario in
which you would still choose it. That write-up is the assessment evidence.
