<#
.SYNOPSIS
    Prepares a Windows machine to be managed by Ansible: a WinRM listener on HTTPS only, using a
    certificate from the lab's own CA, reachable from the control host only.

.DESCRIPTION
    Ansible manages Windows over WinRM (Windows Remote Management). The defaults are not safe
    enough: WinRM's HTTP listener sends traffic unencrypted and its HTTPS listener is not created
    until you do it. This script makes the safe configuration, and nothing else:

      1. Enables PowerShell remoting.
      2. Removes the HTTP listener (port 5985) and its firewall rule.
      3. Creates an HTTPS listener (port 5986) bound to a certificate whose name matches this
         machine, issued by the lab CA. Certificate validation stays ON everywhere: the control
         host checks the certificate, never skips it.
      4. Opens port 5986 in Windows Firewall to the control host only.
      5. Refuses Basic authentication and unencrypted traffic.

    Get the certificate first. On the machine that holds the lab PKI:
        pki/scripts/02-issue-server-cert.sh --cn winsrv01.lab.internal --san DNS:winsrv01.lab.internal
        openssl pkcs12 -export -inkey <key.pem> -in <fullchain.pem> -out winsrv01.pfx
    Copy the .pfx to the Windows machine, then run this script. You are prompted for its password.

    After this, Ansible connects as a domain account using Kerberos. See docs/WindowsManagement.md.

.PARAMETER PfxPath
    The certificate and key, as a .pfx file.

.PARAMETER ControlHost
    The IP address of the machine that runs Ansible (linux-client01). The only one allowed in.

.EXAMPLE
    .\Enable-AnsibleWinRM.ps1 -PfxPath C:\Temp\winsrv01.pfx -ControlHost 10.10.10.101 -WhatIf

.NOTES
    Not yet run on a lab Windows machine. Run with -WhatIf first, on a snapshot.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$PfxPath,
    [Parameter(Mandatory)] [string]$ControlHost,
    [string]$Domain = "lab.internal"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $PfxPath)) { throw "Certificate file not found: $PfxPath" }
$fqdn = "$($env:COMPUTERNAME.ToLower()).$Domain"

Write-Host "[winrm] Import the certificate for $fqdn" -ForegroundColor Cyan
$pfxPassword = Read-Host -AsSecureString "Password for $PfxPath"
$cert = $null
if ($PSCmdlet.ShouldProcess("LocalMachine\My", "Import $PfxPath")) {
    $cert = Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation Cert:\LocalMachine\My -Password $pfxPassword
}
else {
    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.DnsNameList.Unicode -contains $fqdn } | Select-Object -First 1
}

if ($cert) {
    if ($cert.DnsNameList.Unicode -notcontains $fqdn) {
        throw "The certificate is not valid for $fqdn (it covers: $($cert.DnsNameList.Unicode -join ', ')). Ansible will refuse it. Issue one for this exact name."
    }
    if ($cert.NotAfter -lt (Get-Date)) { throw "The certificate has expired ($($cert.NotAfter))." }
}

Write-Host "[winrm] Enable PowerShell remoting" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess("WinRM", "Enable-PSRemoting")) {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
}

Write-Host "[winrm] Remove the HTTP listener (port 5985)" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess("WinRM HTTP listener", "Remove")) {
    Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTP" } |
        ForEach-Object { Remove-Item -Path $_.PSPath -Recurse -Force }
    Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP*" -ErrorAction SilentlyContinue | Disable-NetFirewallRule
}

Write-Host "[winrm] Create the HTTPS listener (port 5986)" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess("WinRM HTTPS listener", "Create bound to $fqdn")) {
    $existing = Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTPS" }
    if ($existing) { $existing | ForEach-Object { Remove-Item -Path $_.PSPath -Recurse -Force } }
    New-WSManInstance -ResourceURI winrm/config/Listener `
        -SelectorSet @{ Address = "*"; Transport = "HTTPS" } `
        -ValueSet @{ Hostname = $fqdn; CertificateThumbprint = $cert.Thumbprint } | Out-Null
}

Write-Host "[winrm] Refuse Basic authentication and unencrypted traffic" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess("WinRM service", "Disable Basic and AllowUnencrypted")) {
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
}

Write-Host "[winrm] Allow port 5986 from $ControlHost only" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess("Windows Firewall", "Allow 5986 from $ControlHost")) {
    Remove-NetFirewallRule -DisplayName "Ansible WinRM HTTPS" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "Ansible WinRM HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 `
        -RemoteAddress $ControlHost -Action Allow | Out-Null
}

Write-Host ""
Write-Host "Done. From the Ansible control host, test with:" -ForegroundColor Green
Write-Host "  kinit administrator@LAB.INTERNAL"
Write-Host "  ansible $($env:COMPUTERNAME.ToLower()) -m ansible.windows.win_ping"
