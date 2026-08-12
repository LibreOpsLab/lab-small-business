<#
.SYNOPSIS
    Downloads the class CA root certificate from the registry and installs it into this
    Windows machine's local Trusted Root Certification Authorities store. See
    docs/ClassRegistry.md#trusting-the-class-ca.

.DESCRIPTION
    This is a per-machine local install (certutil -addstore), not a domain GPO push like
    pki/gpo/deploy-root-ca.ps1 — the class CA is a course-wide, cross-business trust anchor
    that doesn't belong to any one business's own AD domain, so there's no natural GPO to
    attach it to. Run elevated on each machine that needs to browse other businesses'
    edge-proxy HTTPS without warnings.

.EXAMPLE
    .\deploy-class-ca-trust.ps1 -Registry http://192.168.1.50:8080
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Registry
)

$ErrorActionPreference = "Stop"

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if (-not (Test-Admin)) { throw "Run this script from an elevated PowerShell prompt." }

$certPath = Join-Path $Env:TEMP "lab-class-ca.crt"
Write-Host "[deploy-class-ca-trust] Downloading class CA certificate from $Registry ..." -ForegroundColor Cyan
Invoke-WebRequest -Uri "$($Registry.TrimEnd('/'))/ca/root.crt" -OutFile $certPath -UseBasicParsing

Write-Host "[deploy-class-ca-trust] Installing into the local machine's Trusted Root store..." -ForegroundColor Cyan
certutil -addstore -f Root $certPath

Remove-Item -Path $certPath -ErrorAction SilentlyContinue

Write-Host "[deploy-class-ca-trust] Done. Verify with: certutil -verifystore Root | findstr /i 'LAB Class'" -ForegroundColor Green
