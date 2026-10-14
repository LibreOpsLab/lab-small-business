<#
.SYNOPSIS
    Creates a Group Policy Object that sets how Windows machines receive updates, and links it to
    an OU.

.DESCRIPTION
    Patching is a process (see docs/PatchManagement.md). This GPO sets the part Windows decides
    on its own: when it downloads, when it installs, and when it restarts. Pick ONE patching
    mechanism per machine, because two systems both installing updates will fight:

      Client   Windows installs updates itself overnight (3 AM), never restarts a machine that
               has someone signed in, and holds quality updates back for a few days so a bad
               update is noticed elsewhere first. This is the "Windows Update for Business"
               pattern, delivered by Group Policy.
      Server   Windows only DOWNLOADS-and-NOTIFIES. It never installs or restarts by itself.
               Ansible (ansible/playbooks/12-windows-patching.yml) installs updates in a
               planned window, in rings. A server that restarts on Windows' schedule is an outage
               you did not choose.

    -Source Wsus points machines at an internal WSUS server instead of Microsoft's.

    The domain is Samba AD. These settings are plain registry values written to SYSVOL, which
    Samba serves. Run this from a domain-joined Windows machine with the Group Policy Management
    tools, as a member of IT-Admins. If the new GPO's permissions look wrong afterwards, run on
    samba-dc01: samba-tool ntacl sysvolcheck / sysvolreset.

.PARAMETER Role
    Client or Server.

.PARAMETER LinkOU
    The OU to link to. Link to a test OU first.

.PARAMETER Source
    Microsoft (default) or Wsus.

.PARAMETER WsusUrl
    Required with -Source Wsus, for example http://wsus01.lab.internal:8530

.PARAMETER QualityDeferralDays
    Client only: hold security/quality updates back this many days (0 to 30).

.EXAMPLE
    .\New-PatchPolicyGpo.ps1 -Role Server -LinkOU "OU=Windows,OU=Servers,OU=LAB,DC=lab,DC=internal" -WhatIf

.NOTES
    Not yet run against the lab domain. Test on a snapshot first.
#>
#Requires -Version 5.1
#Requires -Modules GroupPolicy

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [ValidateSet('Client', 'Server')] [string]$Role,
    [Parameter(Mandatory)] [string]$LinkOU,
    [ValidateSet('Microsoft', 'Wsus')] [string]$Source = 'Microsoft',
    [string]$WsusUrl,
    [ValidateRange(0, 30)] [int]$QualityDeferralDays = 7
)

$ErrorActionPreference = 'Stop'
if ($Source -eq 'Wsus' -and -not $WsusUrl) { throw '-Source Wsus needs -WsusUrl.' }

$gpoName = "LAB - Windows Update ($Role)"
$wu = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au = "$wu\AU"

# name, key, type, value
$settings = New-Object System.Collections.Generic.List[object]
function Add-Setting($Key, $Name, $Type, $Value) { $settings.Add([pscustomobject]@{ Key = $Key; Name = $Name; Type = $Type; Value = $Value }) }

Add-Setting $au 'NoAutoUpdate' 'DWord' 0                      # automatic updating is on

if ($Role -eq 'Server') {
    Add-Setting $au 'AUOptions' 'DWord' 2                     # 2 = notify before download and install: Ansible installs
    Add-Setting $au 'NoAutoRebootWithLoggedOnUsers' 'DWord' 1
}
else {
    Add-Setting $au 'AUOptions' 'DWord' 4                     # 4 = download automatically and install on a schedule
    Add-Setting $au 'ScheduledInstallDay' 'DWord' 0           # 0 = every day
    Add-Setting $au 'ScheduledInstallTime' 'DWord' 3          # 3 AM
    Add-Setting $au 'NoAutoRebootWithLoggedOnUsers' 'DWord' 1 # never restart under someone
    Add-Setting $wu 'DeferQualityUpdates' 'DWord' 1
    Add-Setting $wu 'DeferQualityUpdatesPeriodInDays' 'DWord' $QualityDeferralDays
    Add-Setting $wu 'DeferFeatureUpdates' 'DWord' 1           # feature updates are a planned decision
    Add-Setting $wu 'DeferFeatureUpdatesPeriodInDays' 'DWord' 30
}

if ($Source -eq 'Wsus') {
    Add-Setting $wu 'WUServer' 'String' $WsusUrl
    Add-Setting $wu 'WUStatusServer' 'String' $WsusUrl
    Add-Setting $au 'UseWUServer' 'DWord' 1
}

Write-Host "[patch-gpo] GPO '$gpoName' -> $LinkOU" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess($gpoName, 'Create or update the GPO')) {
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if (-not $gpo) { $gpo = New-GPO -Name $gpoName -Comment "Managed by scripts/windows/New-PatchPolicyGpo.ps1. Role: $Role." }
    foreach ($s in $settings) {
        Set-GPRegistryValue -Name $gpoName -Key $s.Key -ValueName $s.Name -Type $s.Type -Value $s.Value | Out-Null
        Write-Host ("  {0}\{1} = {2}" -f ($s.Key -replace '^HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\', ''), $s.Name, $s.Value)
    }
}
else {
    $settings | ForEach-Object { Write-Host ("  would set {0}\{1} = {2}" -f $_.Key, $_.Name, $_.Value) }
}

if ($PSCmdlet.ShouldProcess($LinkOU, "Link '$gpoName'")) {
    $linked = (Get-GPInheritance -Target $LinkOU).GpoLinks | Where-Object DisplayName -eq $gpoName
    if (-not $linked) { New-GPLink -Name $gpoName -Target $LinkOU -LinkEnabled Yes | Out-Null; Write-Host "  linked" }
    else { Write-Host "  already linked" }
}

Write-Host ""
Write-Host "Done. On a target machine: gpupdate /force, then check Settings > Windows Update or:" -ForegroundColor Green
Write-Host "  Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'"
