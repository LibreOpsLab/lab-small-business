<#
.SYNOPSIS
    Imports a security-baseline Group Policy Object from a backup folder and links it to an OU.

.DESCRIPTION
    Windows hardening in a domain is delivered by Group Policy, so one GPO reaches every machine
    in the OU. This script wraps the standard GroupPolicy cmdlets (Import-GPO, New-GPLink) so the
    import is repeatable and previewable with -WhatIf.

    Where the baseline comes from: download the Microsoft Security Compliance Toolkit baseline
    for your Windows Server or Windows 11 version (free from Microsoft), or the CIS GPO build kit
    if you have CIS membership, and unzip it. The GPO backups are in its "GPOs" folder. The
    script does not download anything.

    Run it from a domain-joined Windows Server with the Group Policy Management tools
    (Install-WindowsFeature GPMC, RSAT-AD-Tools), signed in as a member of IT-Admins.

    The domain is a Samba AD domain. GPMC and these cmdlets work against it, but Samba does not
    enforce GPO restrictions itself and stores policy in SYSVOL (see docs/SambaVsWindowsAD.md).
    If a new GPO's permissions look wrong, run on samba-dc01:
        samba-tool ntacl sysvolcheck
        samba-tool ntacl sysvolreset

.PARAMETER BackupPath
    Folder that contains the GPO backup(s), for example the toolkit's "GPOs" folder.

.PARAMETER BackupGpoName
    Name of the GPO inside the backup, as shown in the backup's manifest.

.PARAMETER TargetName
    Name for the GPO in the domain. A baseline should be named so people can see what it is.

.PARAMETER LinkOU
    DN of the OU to link it to. Link to a TEST OU first.

.EXAMPLE
    .\Import-BaselineGpo.ps1 -BackupPath C:\Baselines\GPOs -BackupGpoName "MSFT Windows Server 2022 - Member Server" `
        -TargetName "LAB Baseline - Member Server" -LinkOU "OU=Windows,OU=Servers,OU=LAB,DC=lab,DC=internal" -WhatIf

.NOTES
    Not yet run against the lab domain. Test on a snapshot of winsrv01 before linking to a wider OU.
#>
#Requires -Version 5.1
#Requires -Modules GroupPolicy

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$BackupPath,
    [Parameter(Mandatory)] [string]$BackupGpoName,
    [Parameter(Mandatory)] [string]$TargetName,
    [Parameter(Mandatory)] [string]$LinkOU
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $BackupPath)) { throw "Backup folder not found: $BackupPath" }

Write-Host "[baseline-gpo] Importing '$BackupGpoName' as '$TargetName'" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess($TargetName, "Import GPO from backup")) {
    Import-GPO -BackupGpoName $BackupGpoName -Path $BackupPath -TargetName $TargetName -CreateIfNeeded | Out-Null
}

Write-Host "[baseline-gpo] Linking '$TargetName' to $LinkOU" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess($LinkOU, "Link GPO '$TargetName'")) {
    $existing = Get-GPInheritance -Target $LinkOU | Select-Object -ExpandProperty GpoLinks | Where-Object DisplayName -eq $TargetName
    if ($existing) {
        Write-Host "  already linked" -ForegroundColor Yellow
    }
    else {
        New-GPLink -Name $TargetName -Target $LinkOU -LinkEnabled Yes | Out-Null
    }
}

Write-Host ""
Write-Host "Done. Next:" -ForegroundColor Green
Write-Host "  1. On a target machine: gpupdate /force, then gpresult /r to confirm the GPO applied."
Write-Host "  2. Test every lab service still works (Grafana dashboard, domain logons, file shares)."
Write-Host "  3. Record any setting you override or disable in the exceptions register (docs/CISHardening.md)."
