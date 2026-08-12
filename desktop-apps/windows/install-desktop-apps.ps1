<#
.SYNOPSIS
    Installs the lab's standard desktop app set on Windows 11: NextCloud Desktop Sync and
    OnlyOffice Desktop Editors via winget, Betterbird via direct download (no winget package
    exists for it), and a pinned web-app shortcut for Stirling PDF. See docs/DesktopApps.md.

.DESCRIPTION
    Run elevated, after the machine has joined the domain and after the PKI Root/Issuing CA
    GPO (pki/gpo/deploy-root-ca.ps1) has applied — several of these apps talk HTTPS to
    *.lab.internal and need that trust in place first.

.PARAMETER BetterbirdUrl
    Direct download URL for the Betterbird Windows installer. Betterbird has no winget
    package, so this is a direct download; the URL below can drift between releases — check
    https://betterbird.eu/downloads/ and pass a corrected URL here if the default 404s.

.EXAMPLE
    .\install-desktop-apps.ps1
#>
[CmdletBinding()]
param(
    [string]$BetterbirdUrl = "https://ftp.betterbird.eu/Betterbird/releases/latest/win64/en-US/Betterbird-latest.installer.exe"
)

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
)

foreach ($app in $apps) {
    Write-Host "[install-desktop-apps] Installing $($app.Name)..." -ForegroundColor Cyan
    winget install --id $app.Id --exact --silent --accept-package-agreements --accept-source-agreements
}

Write-Host "[install-desktop-apps] Installing Betterbird from $BetterbirdUrl ..." -ForegroundColor Cyan
$installerPath = Join-Path $Env:TEMP "betterbird-installer.exe"
try {
    Invoke-WebRequest -Uri $BetterbirdUrl -OutFile $installerPath -UseBasicParsing
    # Betterbird's installer is NSIS-based (same as upstream Thunderbird) - /S is silent install.
    Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
    Write-Host "[install-desktop-apps] Betterbird installed." -ForegroundColor Green
} catch {
    Write-Warning "Betterbird download/install failed ($($_.Exception.Message)). Betterbird's"
    Write-Warning "download URLs shift between releases - check https://betterbird.eu/downloads/"
    Write-Warning "and re-run with -BetterbirdUrl <correct-url>."
} finally {
    Remove-Item -Path $installerPath -ErrorAction SilentlyContinue
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
Write-Host " See docs/DesktopApps.md for the full walkthrough (Betterbird autoconfig,"
Write-Host " NextCloud groupware apps, OnlyOffice cloud connection)."
Write-Host "====================================================================="
