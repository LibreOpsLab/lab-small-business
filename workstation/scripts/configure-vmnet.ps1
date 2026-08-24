<#
.SYNOPSIS
    Creates a numbered host-only VMnet (10.10.0.0/24) used as the lab LAN,
    with VMware's built-in DHCP service disabled (pfSense is the DHCP server for this subnet).

.DESCRIPTION
    Wraps VMware Workstation's Windows vnetlib.exe. Must be run elevated.
    VMware's CLI requires the '--' separator, uses spaced command names, and returns
    exit code 1 for success and 0 for failure.

.NOTES
    VMnet8 (NAT/WAN) is left untouched; Workstation ships it by default and this lab uses
    it as-is for pfSense's WAN leg.
#>
[CmdletBinding()]
param(
    [string]$VmnetName = "vmnet2",
    [string]$Subnet    = "10.10.0.0",
    [string]$Mask      = "255.255.255.0",
    [string]$VNetLibPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($VNetLibPath)) {
    $vnetlibCandidates = @(
        "$Env:ProgramFiles\VMware\VMware Workstation\vnetlib.exe",
        "$Env:ProgramFiles (x86)\VMware\VMware Workstation\vnetlib.exe",
        "$Env:ProgramFiles\VMware\VMware Workstation\vnetlib64.exe",
        "$Env:ProgramFiles (x86)\VMware\VMware Workstation\vnetlib64.exe"
    )
    $VNetLibPath = $vnetlibCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $VNetLibPath -or -not (Test-Path $VNetLibPath)) {
    throw "VMware's vnetlib.exe or vnetlib64.exe was not found. Adjust -VNetLibPath or verify your VMware Workstation install location."
}

if ($VmnetName -notmatch '^vmnet\d+$') {
    throw "-VmnetName must be a VMware network name such as 'vmnet2'; vnetlib.exe cannot create arbitrary names like 'VMnet-LAB'."
}

function Invoke-VNetLib {
    param([string[]]$Arguments)
    $executableName = Split-Path -Leaf $VNetLibPath
    $command = @('--') + $Arguments
    Write-Verbose "$executableName $($command -join ' ')"
    & $VNetLibPath @command
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 1) {
        throw "$executableName $($Arguments -join ' ') failed with exit code $exitCode"
    }
}

Write-Host "[configure-vmnet] Adding host-only network $VmnetName ($Subnet/$Mask)..." -ForegroundColor Cyan
Invoke-VNetLib -Arguments @("add", "adapter", $VmnetName)
Invoke-VNetLib -Arguments @("set", "vnet", $VmnetName, "addr", $Subnet)
Invoke-VNetLib -Arguments @("set", "vnet", $VmnetName, "mask", $Mask)

Write-Host "[configure-vmnet] Disabling VMware's built-in DHCP service on $VmnetName (pfSense will serve DHCP)..." -ForegroundColor Cyan
Invoke-VNetLib -Arguments @("remove", "dhcp", $VmnetName)
Invoke-VNetLib -Arguments @("update", "adapter", $VmnetName)

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
