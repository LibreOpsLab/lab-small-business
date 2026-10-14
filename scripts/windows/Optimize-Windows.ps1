<#
.SYNOPSIS
    Tunes a Windows machine for performance and security: removes telemetry, consumer bloat and
    unneeded services, apps and components, and tightens risky defaults. Checks its work, and
    can put things back.

.DESCRIPTION
    Windows ships with defaults tuned for a home PC and for Microsoft's data collection, not for
    a lab server or a managed workstation. This script applies the lab's profile
    (optimize-profile.psd1), which lists every change with the reason for it. It is the scripted,
    repeatable, reviewable equivalent of clicking through a tuning tool: the profile is the
    decision, this script is only the engine.

    Modes
      Audit    Read-only. Shows each setting as OK, DRIFT (differs from the profile) or n/a.
               Exit code 0 = nothing to change, 2 = drift found. Run it any time.
      Apply    Saves the original value of everything it changes (once), then changes it.
               Add -WhatIf to preview. Restart afterwards.
      Revert   Puts back what Apply changed, from the saved state. Removed apps are NOT restored:
               reinstall them from the Microsoft Store or winget if you need one.

    Safety
      - Services in the profile's ProtectedServices list (Windows Update, Defender, the firewall,
        the event log, DNS client, time, and others) are never touched, even if added to the
        profile by mistake.
      - Windows Update, Defender and the firewall are not part of the profile at all.
      - Credential Guard and VBS are left alone: they conflict with nested virtualisation and are
        controlled by Set-NestedVirtualisation.ps1.
      - Apps are removed by exact name from a list, never by wildcard.
      Test on a snapshot first. A setting that is right for a lab VM can be wrong for another
      machine (for example SysMain on a hard disk).

.PARAMETER Mode
    Audit (default), Apply or Revert.

.PARAMETER Category
    Limit to one or more profile categories, for example -Category Telemetry,Security.
    Default: all.

.PARAMETER ProfilePath
    The profile to use.

.PARAMETER StatePath
    Where original values are saved. Written once per setting by the first Apply.

.EXAMPLE
    .\Optimize-Windows.ps1
    Reports drift. Changes nothing.

.EXAMPLE
    .\Optimize-Windows.ps1 -Mode Apply -Category Telemetry,Security -WhatIf
    Shows what would change in two categories.

.EXAMPLE
    .\Optimize-Windows.ps1 -Mode Apply
    Applies the whole profile. Restart, then run Audit to verify.

.NOTES
    Run elevated for Apply and Revert (Audit works without, but cannot read features and apps).
    Works on Windows PowerShell 5.1 and PowerShell 7. Ansible runs this same script across the
    estate: see ansible/roles/windows_optimize and docs/WindowsTuning.md.
    Not yet run on a lab Windows Server. Apply on a snapshot first.
#>
#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Audit', 'Apply', 'Revert')]
    [string]$Mode = 'Audit',

    [string[]]$Category,

    [string]$ProfilePath = (Join-Path $PSScriptRoot 'optimize-profile.psd1'),

    [string]$StatePath = (Join-Path $env:ProgramData 'LabHostPrep\optimize-state.json')
)

$ErrorActionPreference = 'Stop'

# --- Setup ------------------------------------------------------------------------------------

if (-not (Test-Path $ProfilePath)) { throw "Profile not found: $ProfilePath" }
$profileData = Import-PowerShellDataFile -Path $ProfilePath

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Mode -ne 'Audit' -and -not $isAdmin -and -not $WhatIfPreference) { throw "Mode $Mode needs an elevated PowerShell (Run as administrator)." }

# ProductType: 1 = workstation, 2 = domain controller, 3 = server.
$productType = (Get-CimInstance -ClassName Win32_OperatingSystem).ProductType
$role = if ($productType -eq 1) { 'Client' } else { 'Server' }

# The saved original values, keyed by a string that identifies each setting.
$state = @{}
if (Test-Path $StatePath) {
    (Get-Content -Path $StatePath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value }
}

# --- Helpers: how to read, change and restore each kind of setting -------------------------------

function Get-ItemKey($Item) {
    switch ($Item.Type) {
        'Registry' { "Registry|$($Item.Path)|$($Item.Name)" }
        'Service'  { "Service|$($Item.Name)" }
        'Task'     { "Task|$($Item.Path)$($Item.Name)" }
        'Feature'  { "Feature|$($Item.Name)" }
        'Appx'     { "Appx|$($Item.Name)" }
        'AuditPol' { "AuditPol|$($Item.Name)" }
        'Hibernate'{ "Hibernate" }
    }
}

function Get-Title($Item) {
    switch ($Item.Type) {
        'Registry' { "$($Item.Path -replace '^HKLM:\\','HKLM\' )\$($Item.Name)" }
        'Task'     { "$($Item.Path)$($Item.Name)" }
        'Hibernate'{ 'Hibernation' }
        default    { "$($Item.Type) $($Item.Name)" }
    }
}

# Each reader returns @{ Status = 'OK'|'DRIFT'|'NA'; Actual = <text>; Note = <text> }.

function Read-Registry($Item) {
    $p = Get-ItemProperty -Path $Item.Path -Name $Item.Name -ErrorAction SilentlyContinue
    if ($null -eq $p) { return @{ Status = 'DRIFT'; Actual = '(not set)' } }
    $v = $p.($Item.Name)
    # Some values are bit fields (for example NtfsDisableLastAccessUpdate, where bit 0 means
    # "disabled" and bit 31 means "managed by the system"). BitMask compares that bit only.
    $ok = if ($Item.BitMask) { ([int64]$v -band [int64]$Item.Value) -eq [int64]$Item.Value } else { "$v" -eq "$($Item.Value)" }
    @{ Status = $(if ($ok) { 'OK' } else { 'DRIFT' }); Actual = "$v" }
}

function Read-Service($Item) {
    if ($profileData.ProtectedServices -contains $Item.Name) { return @{ Status = 'NA'; Actual = 'protected'; Note = 'in ProtectedServices' } }
    $s = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($Item.Name)'" -ErrorAction SilentlyContinue
    if ($null -eq $s) { return @{ Status = 'NA'; Actual = 'not present' } }
    @{ Status = $(if ($s.StartMode -eq $Item.StartupType) { 'OK' } else { 'DRIFT' }); Actual = $s.StartMode }
}

function Read-Task($Item) {
    $t = Get-ScheduledTask -TaskPath $Item.Path -TaskName $Item.Name -ErrorAction SilentlyContinue
    if ($null -eq $t) { return @{ Status = 'NA'; Actual = 'not present' } }
    @{ Status = $(if ($t.State -eq 'Disabled') { 'OK' } else { 'DRIFT' }); Actual = "$($t.State)" }
}

function Read-Feature($Item) {
    if (-not $isAdmin) { return @{ Status = 'NA'; Actual = 'needs elevation' } }
    $f = Get-WindowsOptionalFeature -Online -FeatureName $Item.Name -ErrorAction SilentlyContinue
    if ($null -eq $f) { return @{ Status = 'NA'; Actual = 'not present' } }
    @{ Status = $(if ($f.State -eq 'Disabled') { 'OK' } else { 'DRIFT' }); Actual = "$($f.State)" }
}

function Read-Appx($Item) {
    if (-not $isAdmin) { return @{ Status = 'NA'; Actual = 'needs elevation' } }
    $installed = @(Get-AppxPackage -AllUsers -Name $Item.Name -ErrorAction SilentlyContinue)
    $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $Item.Name)
    if ($installed.Count -eq 0 -and $prov.Count -eq 0) { return @{ Status = 'OK'; Actual = 'absent' } }
    @{ Status = 'DRIFT'; Actual = 'installed' }
}

function Read-AuditPol($Item) {
    if (-not $isAdmin) { return @{ Status = 'NA'; Actual = 'needs elevation' } }
    $csv = & auditpol.exe /get /subcategory:"$($Item.Name)" /r 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $csv) { return @{ Status = 'NA'; Actual = 'not readable'; Note = 'auditpol failed (non-English Windows uses localised names)' } }
    $row = $csv | ConvertFrom-Csv | Select-Object -First 1
    $actual = $row.'Inclusion Setting'
    # "No Auditing" never satisfies a wanted setting; otherwise every wanted word must be present.
    $ok = ($actual -ne 'No Auditing') -and (($Item.Setting -split ' and ') | ForEach-Object { $actual -match $_ } | Where-Object { -not $_ }).Count -eq 0
    @{ Status = $(if ($ok) { 'OK' } else { 'DRIFT' }); Actual = $actual }
}

function Get-HibernateOn {
    # The registry value is not present on every build, so fall back to the file itself:
    # hiberfil.sys exists exactly when hibernation is on.
    $v = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled
    if ($null -ne $v) { return ($v -ne 0) }
    [System.IO.File]::Exists((Join-Path $env:SystemDrive 'hiberfil.sys'))
}

function Read-Hibernate($Item) {
    $on = Get-HibernateOn
    @{ Status = $(if ($on) { 'DRIFT' } else { 'OK' }); Actual = $(if ($on) { 'on' } else { 'off' }) }
}

function Read-Item($Item) { & "Read-$($Item.Type)" $Item }

# Capture the original value of an item, so Revert can restore it.
function Get-Original($Item) {
    switch ($Item.Type) {
        'Registry' {
            $p = Get-ItemProperty -Path $Item.Path -Name $Item.Name -ErrorAction SilentlyContinue
            if ($null -eq $p) { @{ Existed = $false } } else { @{ Existed = $true; Value = $p.($Item.Name) } }
        }
        'Service'  { @{ StartMode = (Get-CimInstance Win32_Service -Filter "Name='$($Item.Name)'").StartMode } }
        'Task'     { @{ WasEnabled = ((Get-ScheduledTask -TaskPath $Item.Path -TaskName $Item.Name).State -ne 'Disabled') } }
        'Feature'  { @{ WasEnabled = ((Get-WindowsOptionalFeature -Online -FeatureName $Item.Name).State -eq 'Enabled') } }
        'AuditPol' { @{ Setting = (& auditpol.exe /get /subcategory:"$($Item.Name)" /r | ConvertFrom-Csv | Select-Object -First 1).'Inclusion Setting' } }
        'Hibernate'{ @{ WasOn = (Get-HibernateOn) } }
        'Appx'     { @{ Note = 'removed apps are not restored' } }
    }
}

function Set-AuditFlags([string]$Name, [string]$Setting) {
    $success = if ($Setting -match 'Success') { 'enable' } else { 'disable' }
    $failure = if ($Setting -match 'Failure') { 'enable' } else { 'disable' }
    & auditpol.exe /set /subcategory:"$Name" /success:$success /failure:$failure | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "auditpol could not set '$Name'." }
}

function Invoke-Apply($Item) {
    switch ($Item.Type) {
        'Registry' {
            if (-not (Test-Path $Item.Path)) { New-Item -Path $Item.Path -Force | Out-Null }
            Set-ItemProperty -Path $Item.Path -Name $Item.Name -Value $Item.Value -Type $Item.Kind
        }
        'Service' {
            $svc = Get-Service -Name $Item.Name -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') { Stop-Service -Name $Item.Name -Force -ErrorAction SilentlyContinue }
            Set-Service -Name $Item.Name -StartupType $Item.StartupType
        }
        'Task'      { Disable-ScheduledTask -TaskPath $Item.Path -TaskName $Item.Name | Out-Null }
        'Feature'   { Disable-WindowsOptionalFeature -Online -FeatureName $Item.Name -NoRestart | Out-Null }
        'Appx' {
            Get-AppxPackage -AllUsers -Name $Item.Name -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $Item.Name |
                Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
        }
        'AuditPol'  { Set-AuditFlags $Item.Name $Item.Setting }
        'Hibernate' { & powercfg.exe /hibernate off; if ($LASTEXITCODE -ne 0) { throw 'powercfg /hibernate off failed.' } }
    }
}

function Invoke-Revert($Item, $Orig) {
    switch ($Item.Type) {
        'Registry' {
            # A bit-field value is restored whole, exactly as it was.
            if ($Orig.Existed) { Set-ItemProperty -Path $Item.Path -Name $Item.Name -Value $Orig.Value -Type $Item.Kind }
            else { Remove-ItemProperty -Path $Item.Path -Name $Item.Name -ErrorAction SilentlyContinue }
        }
        'Service' {
            $map = @{ Auto = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled' }
            Set-Service -Name $Item.Name -StartupType $map[$Orig.StartMode]
        }
        'Task'      { if ($Orig.WasEnabled) { Enable-ScheduledTask -TaskPath $Item.Path -TaskName $Item.Name | Out-Null } }
        'Feature'   { if ($Orig.WasEnabled) { Enable-WindowsOptionalFeature -Online -FeatureName $Item.Name -All -NoRestart | Out-Null } }
        'AuditPol'  { Set-AuditFlags $Item.Name $Orig.Setting }
        'Hibernate' { if ($Orig.WasOn) { & powercfg.exe /hibernate on } }
        'Appx'      { }
    }
}

# --- Run ---------------------------------------------------------------------------------------

Write-Host "Windows tuning: $Mode  (this machine is a $role)" -ForegroundColor Cyan
if ($Mode -eq 'Revert' -and $state.Count -eq 0) { Write-Host "No saved state at $StatePath. Nothing to revert." -ForegroundColor Yellow; exit 1 }

$drift = 0; $changed = 0; $failed = @()
$rows = New-Object System.Collections.Generic.List[object]

foreach ($cat in $profileData.Categories) {
    if ($Category -and ($Category -notcontains $cat.Name)) { continue }
    Write-Host ""
    Write-Host "== $($cat.Name): $($cat.Description)" -ForegroundColor Cyan

    foreach ($item in $cat.Items) {
        if ($item.Roles -ne 'Both' -and $item.Roles -ne $role) { continue }
        if ($item.Type -eq 'Service' -and $profileData.ProtectedServices -contains $item.Name) {
            Write-Host ("  {0,-8} {1}" -f 'SKIP', "$(Get-Title $item) is protected and is never changed") -ForegroundColor DarkYellow
            continue
        }

        $key = Get-ItemKey $item
        $title = Get-Title $item
        $now = Read-Item $item

        if ($Mode -eq 'Audit') {
            $colour = switch ($now.Status) { 'OK' { 'Green' } 'DRIFT' { 'Yellow' } default { 'DarkGray' } }
            Write-Host ("  {0,-6} {1}  [{2}]" -f $now.Status, $title, $now.Actual) -ForegroundColor $colour
            if ($now.Status -eq 'DRIFT') { $drift++ }
            continue
        }

        if ($Mode -eq 'Apply') {
            if ($now.Status -ne 'DRIFT') { Write-Host ("  {0,-6} {1}" -f $now.Status, $title) -ForegroundColor DarkGray; continue }
            if ($PSCmdlet.ShouldProcess($title, "Apply: $($item.Why)")) {
                try {
                    if (-not $state.ContainsKey($key)) { $state[$key] = Get-Original $item }   # first change only
                    Invoke-Apply $item
                    $changed++
                    Write-Host ("  {0,-6} {1}" -f 'DONE', $title) -ForegroundColor Green
                }
                catch { $failed += "$title : $($_.Exception.Message)"; Write-Host ("  {0,-6} {1}" -f 'FAIL', $title) -ForegroundColor Red }
            }
            continue
        }

        # Revert
        if (-not $state.ContainsKey($key)) { continue }
        if ($PSCmdlet.ShouldProcess($title, 'Revert')) {
            try { Invoke-Revert $item $state[$key]; $changed++; Write-Host ("  {0,-6} {1}" -f 'BACK', $title) -ForegroundColor Green }
            catch { $failed += "$title : $($_.Exception.Message)"; Write-Host ("  {0,-6} {1}" -f 'FAIL', $title) -ForegroundColor Red }
        }
    }
}

# --- Finish ------------------------------------------------------------------------------------

Write-Host ""
if ($Mode -eq 'Audit') {
    if ($drift -eq 0) { Write-Host "Nothing to change: this machine matches the profile." -ForegroundColor Green; exit 0 }
    Write-Host "$drift setting(s) differ from the profile. Run with -Mode Apply (try -WhatIf first)." -ForegroundColor Yellow
    exit 2
}

if ($Mode -eq 'Apply' -and $changed -gt 0 -and -not $WhatIfPreference) {
    New-Item -ItemType Directory -Path (Split-Path $StatePath) -Force | Out-Null
    $state | ConvertTo-Json -Depth 5 | Set-Content -Path $StatePath -Encoding UTF8
    Write-Host "Original values saved to $StatePath" -ForegroundColor Green
}

if ($failed) {
    Write-Host "Problems:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
if ($WhatIfPreference) { Write-Host "-WhatIf: nothing was changed. Run without it to apply." -ForegroundColor Cyan; exit 0 }
if ($Mode -eq 'Apply') { Write-Host "Done: $changed change(s). RESTART, then run Audit to verify. Undo with -Mode Revert." -ForegroundColor Green }
if ($Mode -eq 'Revert') { Write-Host "Reverted $changed setting(s). RESTART to finish. Removed apps are not restored." -ForegroundColor Green }
exit 0
