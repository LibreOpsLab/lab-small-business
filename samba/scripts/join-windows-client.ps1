<#
.SYNOPSIS
    Joins a Windows 11 client to the LAB.LOCAL domain into the correct OU.

.DESCRIPTION
    Run elevated on the Windows client after confirming DNS resolves lab.local to
    10.10.0.10 (Resolve-DnsName lab.local). Prompts for domain admin credentials
    interactively — never pass a plaintext password on the command line.

.EXAMPLE
    .\join-windows-client.ps1
#>
[CmdletBinding()]
param(
    [string]$DomainName = "lab.local",
    [string]$TargetOU   = "OU=Windows,OU=Workstations,OU=LAB,DC=lab,DC=local"
)

$ErrorActionPreference = "Stop"

Write-Host "[join-windows-client] Verifying DNS resolution for $DomainName..." -ForegroundColor Cyan
$dns = Resolve-DnsName -Name $DomainName -ErrorAction SilentlyContinue
if (-not $dns -or $dns[0].IPAddress -ne "10.10.0.10") {
    throw "DNS for $DomainName did not resolve to 10.10.0.10. Check the client's DHCP-assigned DNS server before joining. See docs/Troubleshooting.md#dns."
}

Write-Host "[join-windows-client] Enter domain admin credentials (e.g. LAB\administrator) when prompted." -ForegroundColor Cyan
$cred = Get-Credential -Message "Domain credentials with rights to join computers to $TargetOU"

Write-Host "[join-windows-client] Joining $DomainName, target OU: $TargetOU" -ForegroundColor Cyan
Add-Computer -DomainName $DomainName -OUPath $TargetOU -Credential $cred -Restart -Force

# Execution does not continue past -Restart; this line only prints if -Restart is removed
# for troubleshooting purposes.
Write-Host "[join-windows-client] Join submitted — machine will restart to complete." -ForegroundColor Green
