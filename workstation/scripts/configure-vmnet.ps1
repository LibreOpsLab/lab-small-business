<#
.SYNOPSIS
    Creates the host-only "VMnet-LAB" virtual network (10.10.0.0/24) used as the lab LAN,
    with VMware's built-in DHCP service disabled (pfSense is the DHCP server for this subnet).

.DESCRIPTION
    Wraps VMware Workstation's network configuration CLI (vnetlib.exe or vnetlib64.exe).
    Must be run elevated. Idempotent — checks vnetlib's current mapping before making changes.

.NOTES
    VMnet8 (NAT/WAN) is left untouched; Workstation ships it by default and this lab uses
    it as-is for pfSense's WAN leg.
#>
[CmdletBinding()]
param(
    [string]$VmnetName = "VMnet-LAB",
    [string]$Subnet    = "10.10.0.0",
    [string]$Mask      = "255.255.255.0",
    [string]$VNetLibPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($VNetLibPath)) {
    $vnetlibCandidates = @(
        "$Env:ProgramFiles\VMware\VMware Workstation\vnetlib.exe",
        "$Env:ProgramFiles\VMware\VMware Workstation\vnetlib64.exe"
    )
    $VNetLibPath = $vnetlibCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $VNetLibPath -or -not (Test-Path $VNetLibPath)) {
    throw "VMware's vnetlib.exe or vnetlib64.exe was not found. Adjust -VNetLibPath or verify your VMware Workstation install location."
}

function Invoke-VNetLib {
    param([string[]]$Arguments)
    $executableName = Split-Path -Leaf $VNetLibPath
    Write-Verbose "$executableName $($Arguments -join ' ')"
    & $VNetLibPath @Arguments
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Verbose "$executableName did not accept the direct command form; retrying with the legacy '--' separator."
        & $VNetLibPath "--" @Arguments
        $exitCode = $LASTEXITCODE
    }

    if ($exitCode -ne 0) {
        throw "$executableName $($Arguments -join ' ') failed with exit code $exitCode"
    }
}

Write-Host "[configure-vmnet] Checking existing virtual network mappings..." -ForegroundColor Cyan
$existing = Invoke-VNetLib -Arguments @("enumerateNetworks") 2>$null
if ($existing -match [regex]::Escape($VmnetName)) {
    Write-Host "[configure-vmnet] $VmnetName already exists — skipping creation." -ForegroundColor Yellow
} else {
    Write-Host "[configure-vmnet] Adding host-only network $VmnetName ($Subnet/$Mask)..." -ForegroundColor Cyan
    Invoke-VNetLib -Arguments @("addAdapter", $VmnetName)
    Invoke-VNetLib -Arguments @("setNetType", $VmnetName, "hostonly")
    Invoke-VNetLib -Arguments @("setSubnetAddr", $VmnetName, $Subnet)
    Invoke-VNetLib -Arguments @("setSubnetMask", $VmnetName, $Mask)

    $created = Invoke-VNetLib -Arguments @("enumerateNetworks") 2>$null
    if ($created -notmatch [regex]::Escape($VmnetName)) {
        throw "$VmnetName was not reported by $([System.IO.Path]::GetFileName($VNetLibPath)) after creation. Check VMware Workstation's Virtual Network Editor or run this script with -Verbose."
    }
}

Write-Host "[configure-vmnet] Disabling VMware's built-in DHCP service on $VmnetName (pfSense will serve DHCP)..." -ForegroundColor Cyan
Invoke-VNetLib -Arguments @("setDhcp", $VmnetName, "disabled")

Write-Host "[configure-vmnet] Restarting VMware networking services to apply changes..." -ForegroundColor Cyan
Restart-Service -Name "VMware NAT Service" -ErrorAction SilentlyContinue
Restart-Service -Name "VMware DHCP Service" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " $VmnetName ready: $Subnet/$Mask, host DHCP disabled."
Write-Host " Assign it to each lab VM's LAN-side NIC via:"
Write-Host "   VM Settings > Network Adapter > Custom: Specific virtual network > $VmnetName"
Write-Host " pfSense's LAN NIC should be the ONLY interface that gets 10.10.0.1 statically;"
Write-Host " every other lab VM's LAN NIC receives its address via pfSense's DHCP (or is"
Write-Host " statically assigned per docs/Architecture.md's addressing table)."
Write-Host "====================================================================="
