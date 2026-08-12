<#
.SYNOPSIS
    Creates the lab's VM shells (disk + .vmx) via vmrun/vmware-vdiskmanager, ready for OS
    installation. Does not install any OS — pfSense and Windows still require interactive
    install; Ubuntu hosts can be handed an autoinstall/cloud-init seed ISO (see each VM's
    spec sheet under workstation/vms/) for unattended installation.

.DESCRIPTION
    Reads the VM table below (mirrors docs/Architecture.md's component inventory) and, for
    each VM, creates a new virtual disk and a minimal .vmx with the right CPU/RAM/NIC
    settings, then registers it with vmrun so it shows up in the Workstation Library.

.PARAMETER VmDir
    Directory under which each VM's folder will be created (default: this repo's
    workstation/vms/<name>/).

.EXAMPLE
    .\create-vms.ps1 -IsoDir C:\ISOs
#>
[CmdletBinding()]
param(
    [string]$VmDir = (Resolve-Path (Join-Path $PSScriptRoot "..\vms")).Path,
    [string]$IsoDir = "C:\ISOs",
    [string]$VmwarePath = "$Env:ProgramFiles(x86)\VMware\VMware Workstation",
    [string]$LanNetwork = "VMnet-LAB",
    [string]$WanNetwork = "VMnet8"
)

$ErrorActionPreference = "Stop"
$vmrun = Join-Path $VmwarePath "vmrun.exe"
$vdiskman = Join-Path $VmwarePath "vmware-vdiskmanager.exe"

foreach ($exe in @($vmrun, $vdiskman)) {
    if (-not (Test-Path $exe)) { throw "Required tool not found: $exe. Adjust -VmwarePath." }
}

# name, vcpu, ramMB, diskGB, nics (array of network names), iso
$VMs = @(
    @{ Name = "pfsense01";      VCPU = 2; RamMB = 2048;  DiskGB = 20;  Nics = @($WanNetwork, $LanNetwork); Iso = "pfSense-CE.iso" }
    @{ Name = "samba-dc01";     VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork);               Iso = "ubuntu-server-24.04.iso" }
    @{ Name = "docker01";       VCPU = 4; RamMB = 8192;  DiskGB = 80;  Nics = @($LanNetwork);               Iso = "ubuntu-server-24.04.iso" }
    @{ Name = "authentik01";    VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork);               Iso = "ubuntu-server-24.04.iso" }
    @{ Name = "linux-client01"; VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork);               Iso = "ubuntu-desktop-24.04.iso" }
    @{ Name = "win-client01";   VCPU = 2; RamMB = 4096;  DiskGB = 60;  Nics = @($LanNetwork);               Iso = "Win11.iso" }
)

foreach ($vm in $VMs) {
    $vmFolder = Join-Path $VmDir $vm.Name
    $vmx = Join-Path $vmFolder "$($vm.Name).vmx"
    $vmdk = Join-Path $vmFolder "$($vm.Name).vmdk"

    if (Test-Path $vmx) {
        Write-Host "[create-vms] $($vm.Name) already exists at $vmx — skipping." -ForegroundColor Yellow
        continue
    }

    Write-Host "[create-vms] Creating $($vm.Name) ($($vm.VCPU) vCPU, $($vm.RamMB)MB RAM, $($vm.DiskGB)GB disk)..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $vmFolder -Force | Out-Null

    & $vdiskman -c -s "$($vm.DiskGB)GB" -a lsilogic -t 1 $vmdk

    $isoPath = Join-Path $IsoDir $vm.Iso
    $nicLines = ""
    for ($i = 0; $i -lt $vm.Nics.Count; $i++) {
        $nicLines += "ethernet$i.present = `"TRUE`"`nethernet$i.connectionType = `"custom`"`nethernet$i.vnet = `"$($vm.Nics[$i])`"`nethernet$i.virtualDev = `"e1000e`"`n"
    }

    @"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "$($vm.Name)"
numvcpus = "$($vm.VCPU)"
memsize = "$($vm.RamMB)"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$($vm.Name).vmdk"
ide1:0.present = "TRUE"
ide1:0.deviceType = "cdrom-image"
ide1:0.fileName = "$isoPath"
$nicLines
guestOS = "ubuntu-64"
"@ | Set-Content -Path $vmx -Encoding ASCII

    Write-Host "[create-vms] $($vm.Name) VM shell ready at $vmx" -ForegroundColor Green
    Write-Host "[create-vms] Boot with: `"$vmrun`" start `"$vmx`" gui" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "All VM shells created. See workstation/vms/*.md for per-VM install notes" -ForegroundColor Green
Write-Host "(autoinstall seeds for Ubuntu hosts, manual steps for pfSense/Windows)."
