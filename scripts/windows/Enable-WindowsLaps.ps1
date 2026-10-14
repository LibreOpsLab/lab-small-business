<#
.SYNOPSIS
    Turns on Windows LAPS (Local Administrator Password Solution) for the machines in an OU:
    sets the Active Directory permissions, creates the policy, and links it.

.DESCRIPTION
    Every Windows machine has a local Administrator account. If they all share one password,
    stealing it from one machine unlocks every machine (lateral movement). LAPS gives each machine
    its own random password, rotates it on a schedule, and stores it in the machine's own object
    in Active Directory, readable only by the groups you choose.

    ORDER MATTERS. On a Samba AD domain the schema must be extended FIRST, once, on the DC:
        sudo samba/scripts/extend-schema-laps.sh --ldif1 laps-1.ldif --ldif2 laps-2.ldif --yes
    (see docs/LAPS.md). Without it, machines have nowhere to store the password and the policy
    below only produces errors in the "LAPS" event log.

    SAMBA LIMITATION: Windows LAPS can encrypt the stored password, but only when the domain
    functional level supports it and the directory implements the encryption. Samba does not, and
    enabling it breaks LAPS. So this script turns encryption OFF (ADPasswordEncryptionEnabled=0)
    and the password is stored in clear text in msLAPS-Password, protected only by Active
    Directory permissions. That is why the read permission is limited to one named group.

    The GPO writes registry values under HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS,
    which is where Windows LAPS reads Group Policy settings. The LAPS ADMX template is only needed
    to EDIT the policy in the Group Policy editor; clients do not need it.

    Run from a domain-joined Windows Server or Windows 11 machine updated since April 2023 (so the
    LAPS PowerShell module is present), as a Domain Admin.

.PARAMETER ComputerOU
    One or more OUs (distinguished names) holding the machines to manage.

.PARAMETER ReadersGroup
    The group allowed to read the passwords, for example "LAB\IT-Admins". Keep it small.

.PARAMETER ResetGroup
    The group allowed to force a password rotation. Defaults to ReadersGroup.

.PARAMETER AdministratorAccountName
    Manage a custom local account instead of the built-in Administrator. The account must exist:
    LAPS does not create it.

.EXAMPLE
    .\Enable-WindowsLaps.ps1 -ComputerOU "OU=Windows,OU=Servers,OU=LAB,DC=lab,DC=internal","OU=Windows,OU=Workstations,OU=LAB,DC=lab,DC=internal" `
        -ReadersGroup "LAB\IT-Admins" -WhatIf

.NOTES
    Not yet run against the lab domain. Needs the Samba schema extension first. Snapshot first.
#>
#Requires -Version 5.1
#Requires -Modules GroupPolicy

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string[]]$ComputerOU,
    [Parameter(Mandatory)] [string]$ReadersGroup,
    [string]$ResetGroup = $ReadersGroup,
    [string]$AdministratorAccountName,
    [ValidateRange(8, 64)] [int]$PasswordLength = 20,
    [ValidateRange(1, 365)] [int]$PasswordAgeDays = 30,
    [string]$GpoName = 'LAB - Windows LAPS'
)

$ErrorActionPreference = 'Stop'

foreach ($cmd in 'Set-LapsADComputerSelfPermission', 'Set-LapsADReadPasswordPermission', 'Set-LapsADResetPasswordPermission') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd not found. This machine needs the Windows LAPS PowerShell module (Windows updated since April 2023, or Windows Server 2022/2025)."
    }
}

# 1. Permissions in Active Directory, on each OU.
foreach ($ou in $ComputerOU) {
    Write-Host "[laps] Permissions on $ou" -ForegroundColor Cyan
    if ($PSCmdlet.ShouldProcess($ou, 'Let machines write their own password')) {
        Set-LapsADComputerSelfPermission -Identity $ou | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($ou, "Let $ReadersGroup read passwords")) {
        Set-LapsADReadPasswordPermission -Identity $ou -AllowedPrincipals $ReadersGroup | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($ou, "Let $ResetGroup force a rotation")) {
        Set-LapsADResetPasswordPermission -Identity $ou -AllowedPrincipals $ResetGroup | Out-Null
    }
}

# 2. The policy.
$key = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
$settings = @(
    @{ Name = 'BackupDirectory';                    Type = 'DWord'; Value = 2 }       # 2 = Active Directory
    @{ Name = 'PasswordAgeDays';                    Type = 'DWord'; Value = $PasswordAgeDays }
    @{ Name = 'PasswordLength';                     Type = 'DWord'; Value = $PasswordLength }
    @{ Name = 'PasswordComplexity';                 Type = 'DWord'; Value = 4 }       # upper, lower, digits, symbols
    @{ Name = 'PasswordExpirationProtectionEnabled'; Type = 'DWord'; Value = 1 }
    @{ Name = 'ADPasswordEncryptionEnabled';        Type = 'DWord'; Value = 0 }       # Samba cannot do this (see above)
    @{ Name = 'PostAuthenticationResetDelay';       Type = 'DWord'; Value = 24 }      # hours after the password is used
    @{ Name = 'PostAuthenticationActions';          Type = 'DWord'; Value = 3 }       # 3 = reset password and sign out
)
if ($AdministratorAccountName) {
    $settings += @{ Name = 'AdministratorAccountName'; Type = 'String'; Value = $AdministratorAccountName }
}

Write-Host "[laps] GPO '$GpoName'" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess($GpoName, 'Create or update the LAPS policy')) {
    if (-not (Get-GPO -Name $GpoName -ErrorAction SilentlyContinue)) {
        New-GPO -Name $GpoName -Comment 'Managed by scripts/windows/Enable-WindowsLaps.ps1. Encryption is off: Samba does not support it.' | Out-Null
    }
    foreach ($s in $settings) {
        Set-GPRegistryValue -Name $GpoName -Key $key -ValueName $s.Name -Type $s.Type -Value $s.Value | Out-Null
        Write-Host ("  {0} = {1}" -f $s.Name, $s.Value)
    }
}

# 3. Link it.
foreach ($ou in $ComputerOU) {
    if ($PSCmdlet.ShouldProcess($ou, "Link '$GpoName'")) {
        $linked = (Get-GPInheritance -Target $ou).GpoLinks | Where-Object DisplayName -eq $GpoName
        if (-not $linked) { New-GPLink -Name $GpoName -Target $ou -LinkEnabled Yes | Out-Null; Write-Host "  linked to $ou" }
        else { Write-Host "  already linked to $ou" }
    }
}

Write-Host ""
Write-Host "Done. To check it worked, on a managed machine:" -ForegroundColor Green
Write-Host "  gpupdate /force ; Invoke-LapsPolicyProcessing"
Write-Host "  (the 'LAPS' event log should show event 10018: password updated in Active Directory)"
Write-Host "To read a password (Domain Admins and $ReadersGroup only):"
Write-Host "  Get-LapsADPassword -Identity <computer> -AsPlainText"
Write-Host "Expect 'Source: CleartextPassword': that is the Samba limitation. Treat the readers group as privileged."
