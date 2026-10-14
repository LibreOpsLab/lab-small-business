<#
.SYNOPSIS
    Creates domain users in bulk from a CSV, using PowerShell and LDAP. The Windows way to do what
    csvde did, against the lab's Samba AD domain.

.DESCRIPTION
    Reads samba/data/users.csv (same columns as samba/scripts/create-users.sh), creates each
    missing user in its OU, sets an initial password that must be changed at first logon, and adds
    the user to its groups. Skips users that already exist, so it is safe to run twice.

    WHY NOT New-ADUser? The ActiveDirectory PowerShell module (New-ADUser, Get-ADUser, ...) talks
    to Active Directory Web Services (ADWS), which a Windows domain controller runs and Samba does
    not. Against Samba those cmdlets fail with "Unable to find a default server with Active
    Directory Web Services running". This script uses the .NET System.DirectoryServices
    .AccountManagement classes instead, which speak LDAP and so work on both. Learn the cmdlets
    for Windows AD; use this pattern when the DC might not be Windows. See
    docs/SambaVsWindowsAD.md.

    Run it from a domain-joined Windows machine as a member of IT-Admins. It prompts for the
    initial password and never takes it on the command line.

.PARAMETER CsvPath
    Path to the users CSV. Lines starting with # are ignored.

.PARAMETER Domain
    The DNS name of the domain.

.PARAMETER DomainDN
    The distinguished name of the domain root.

.EXAMPLE
    .\New-LabUsers.ps1 -CsvPath ..\..\samba\data\users.csv -WhatIf

.NOTES
    Not yet run against the lab domain. Test with -WhatIf first, then on one user.
#>
#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$CsvPath,
    [string]$Domain = "lab.internal",
    [string]$DomainDN = "DC=lab,DC=internal"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.DirectoryServices.AccountManagement

# Short names for the three classes used below (a .NET namespace cannot be aliased directly).
$ns = "System.DirectoryServices.AccountManagement"
$ctxType = [System.DirectoryServices.AccountManagement.ContextType]::Domain
$byName = [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName

if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }

$secure = Read-Host -AsSecureString "Initial password for new accounts (they must change it at next logon)"
$password = [System.Net.NetworkCredential]::new("", $secure).Password

$rows = Get-Content $CsvPath |
    Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } |
    ConvertFrom-Csv -Header username, given_name, surname, ou, groups, description

# A context at the domain root finds existing users and groups anywhere.
$root = New-Object "$ns.PrincipalContext" -ArgumentList $ctxType, $Domain

foreach ($row in $rows) {
    $user = $row.username
    $ouDn = "$($row.ou),$DomainDN"

    if ([System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($root, $byName, $user)) {
        Write-Host "  exists:  $user"
    }
    elseif ($PSCmdlet.ShouldProcess("$user in $ouDn", "Create user")) {
        # A context scoped to the target OU makes the new user land there.
        $ouContext = New-Object "$ns.PrincipalContext" -ArgumentList $ctxType, $Domain, $ouDn
        $u = New-Object "$ns.UserPrincipal" -ArgumentList $ouContext
        $u.SamAccountName = $user
        $u.UserPrincipalName = "$user@$Domain"
        $u.GivenName = $row.given_name
        $u.Surname = $row.surname
        $u.DisplayName = "$($row.given_name) $($row.surname)"
        $u.EmailAddress = "$user@$Domain"
        $u.Description = $row.description
        $u.SetPassword($password)          # before Enabled, so the account meets password policy at creation
        $u.Enabled = $true
        $u.Save()
        $u.ExpirePasswordNow()             # must change at next logon
        Write-Host "  created: $user in $ouDn" -ForegroundColor Green
    }

    if ($row.groups) {
        foreach ($g in ($row.groups -split '\|' | Where-Object { $_ })) {
            $group = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($root, $byName, $g)
            if (-not $group) { Write-Warning "group not found: $g (run samba/scripts/create-groups.sh)"; continue }
            $member = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($root, $byName, $user)
            if ($member -and -not $group.Members.Contains($member) -and $PSCmdlet.ShouldProcess("$user", "Add to group $g")) {
                $group.Members.Add($member)
                $group.Save()
                Write-Host "    added $user to $g"
            }
        }
    }
}
$password = $null
