<#
.SYNOPSIS
    Pre-seeds the NextCloud desktop client's server URL so the student opens the app and
    sees the login screen immediately, instead of typing a hostname. Login itself still goes
    through the real Authentik SSO browser flow — this only removes the "what's the server
    address" friction, not the login step (by design: real SSO).

.DESCRIPTION
    Run as the logged-in student (not elevated) — writes to their own %APPDATA%.

.EXAMPLE
    .\configure-nextcloud-client.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$configDir = Join-Path $Env:APPDATA "Nextcloud"
$configFile = Join-Path $configDir "nextcloud.cfg"
New-Item -ItemType Directory -Path $configDir -Force | Out-Null

if ((Test-Path $configFile) -and (Select-String -Path $configFile -Pattern "cloud.lab.internal" -Quiet -ErrorAction SilentlyContinue)) {
    Write-Host "[configure-nextcloud-client] Server URL already configured — nothing to do." -ForegroundColor Yellow
    return
}

Write-Host "[configure-nextcloud-client] Writing default server URL into $configFile" -ForegroundColor Cyan
Add-Content -Path $configFile -Value "`n[General]`noverrideServerUrl=https://cloud.lab.internal"

Write-Host "[configure-nextcloud-client] Done. Open NextCloud Desktop — the server field will" -ForegroundColor Green
Write-Host "be pre-filled; click through the Authentik SSO login to finish setup." -ForegroundColor Green
