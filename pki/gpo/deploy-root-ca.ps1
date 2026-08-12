<#
.SYNOPSIS
    Publishes the LAB Root CA and LAB Issuing CA certificates to a domain GPO so every
    domain-joined Windows machine trusts the lab's internal PKI automatically.

.DESCRIPTION
    Run once (elevated PowerShell, RSAT GroupPolicy + ActiveDirectory modules) from
    samba-dc01 or an RSAT-equipped admin workstation, after pki/scripts/01-init-intermediate-ca.sh
    has produced pki/root-ca/certs/ca.cert.pem and pki/intermediate-ca/certs/intermediate.cert.pem.

    Creates (if missing) a GPO named "LAB - PKI Trust", imports:
      - Root CA cert  -> Trusted Root Certification Authorities
      - Issuing CA cert -> Intermediate Certification Authorities
    and links the GPO to the domain root (DC=lab,DC=internal) so it applies to every OU,
    including OU=Windows,OU=Workstations,OU=LAB.

.PARAMETER RepoRoot
    Path to the root of this repository (defaults to two levels up from this script).

.EXAMPLE
    .\deploy-root-ca.ps1 -RepoRoot C:\lab-small-business
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$GpoName  = "LAB - PKI Trust",
    [string]$DomainDn = "DC=lab,DC=internal"
)

$ErrorActionPreference = "Stop"

Import-Module GroupPolicy
Import-Module ActiveDirectory

$rootCaCert = Join-Path $RepoRoot "pki\root-ca\certs\ca.cert.pem"
$intCaCert  = Join-Path $RepoRoot "pki\intermediate-ca\certs\intermediate.cert.pem"

foreach ($p in @($rootCaCert, $intCaCert)) {
    if (-not (Test-Path $p)) {
        throw "Certificate not found: $p — run pki/scripts/00-init-root-ca.sh and 01-init-intermediate-ca.sh first."
    }
}

Write-Host "[gpo] Locating or creating GPO '$GpoName'..." -ForegroundColor Cyan
$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $GpoName -Comment "Distributes LAB Root/Issuing CA trust to domain members. Managed by pki/gpo/deploy-root-ca.ps1 in the lab-small-business repo."
    Write-Host "[gpo] Created new GPO '$GpoName'" -ForegroundColor Green
} else {
    Write-Host "[gpo] Found existing GPO '$GpoName' — updating in place" -ForegroundColor Yellow
}

# certutil operates against the GPO's on-disk policy store; -Domain targets the GPO by GUID.
$gpoGuid = $gpo.Id.ToString("B")

Write-Host "[gpo] Importing Root CA into Trusted Root Certification Authorities..." -ForegroundColor Cyan
certutil.exe -f -dspublish $rootCaCert RootCA | Out-Null
certutil.exe -f -addstore -policyserver $gpoGuid Root $rootCaCert

Write-Host "[gpo] Importing Issuing CA into Intermediate Certification Authorities..." -ForegroundColor Cyan
certutil.exe -f -dspublish $intCaCert SubCA | Out-Null
certutil.exe -f -addstore -policyserver $gpoGuid CA $intCaCert

Write-Host "[gpo] Linking GPO to domain root ($DomainDn)..." -ForegroundColor Cyan
$existingLink = (Get-GPInheritance -Target $DomainDn).GpoLinks | Where-Object { $_.GpoId -eq $gpo.Id }
if (-not $existingLink) {
    New-GPLink -Guid $gpo.Id -Target $DomainDn -LinkEnabled Yes | Out-Null
    Write-Host "[gpo] Linked." -ForegroundColor Green
} else {
    Write-Host "[gpo] Already linked to $DomainDn." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " GPO '$GpoName' now distributes LAB Root/Issuing CA trust domain-wide."
Write-Host " Run 'gpupdate /force' on client machines (or wait for the next"
Write-Host " background refresh) then verify with:"
Write-Host "   certutil -verifystore -enterprise Root"
Write-Host "====================================================================="
