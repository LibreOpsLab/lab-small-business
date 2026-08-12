<#
.SYNOPSIS
    Installs the lab's standard desktop app set on Windows 11 via winget: NextCloud Desktop
    Sync, OnlyOffice Desktop Editors, Thunderbird, and a pinned web-app shortcut for
    Stirling PDF. See docs/DesktopApps.md.

.DESCRIPTION
    Evolution is GNOME/Linux-only and has no Windows build, so it's intentionally omitted
    here — Thunderbird is the cross-platform recommendation anyway (see
    docs/DesktopApps.md#why-thunderbird-over-evolution-as-the-primary-recommendation).

    Run elevated, after the machine has joined the domain and after the PKI Root/Issuing CA
    GPO (pki/gpo/deploy-root-ca.ps1) has applied — several of these apps talk HTTPS to
    *.lab.internal and need that trust in place first.

.EXAMPLE
    .\install-desktop-apps.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if (-not (Test-Admin)) { throw "Run this script from an elevated PowerShell prompt." }

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget not found — install 'App Installer' from the Microsoft Store first (present by default on Windows 11)."
}

$apps = @(
    @{ Id = "Nextcloud.NextcloudDesktop"; Name = "NextCloud Desktop Sync" }
    @{ Id = "ONLYOFFICE.DesktopEditors";  Name = "OnlyOffice Desktop Editors" }
    @{ Id = "Mozilla.Thunderbird";        Name = "Thunderbird" }
)

foreach ($app in $apps) {
    Write-Host "[install-desktop-apps] Installing $($app.Name)..." -ForegroundColor Cyan
    winget install --id $app.Id --exact --silent --accept-package-agreements --accept-source-agreements
}

Write-Host "[install-desktop-apps] Creating a pinned web-app shortcut for Stirling PDF (no native desktop client exists)..." -ForegroundColor Cyan
$edgePath = "$Env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edgePath)) { $edgePath = "$Env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }

if (Test-Path $edgePath) {
    $shortcutPath = "$Env:Public\Desktop\LAB PDF Tools.lnk"
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $edgePath
    $shortcut.Arguments = "--app=https://pdf.lab.internal"
    $shortcut.Description = "Stirling PDF (Adobe Acrobat replacement)"
    $shortcut.Save()
    Write-Host "[install-desktop-apps] Created $shortcutPath" -ForegroundColor Green
} else {
    Write-Host "[install-desktop-apps] Edge not found at the expected path — skipping the pinned shortcut; students can bookmark https://pdf.lab.internal instead." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " Done. Next: configure-nextcloud-client.ps1 to pre-fill the server URL."
Write-Host " See docs/DesktopApps.md for the full walkthrough (Thunderbird autoconfig,"
Write-Host " NextCloud groupware apps, OnlyOffice cloud connection)."
Write-Host "====================================================================="
