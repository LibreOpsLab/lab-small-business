<#
.SYNOPSIS
    Creates the lab's VM shells (disk + .vmx) via vmrun/vmware-vdiskmanager, ready for OS
    installation, for the four hosts with an unattended install seed
    (samba-dc01, docker01, authentik01, win-client01) — each one's
    hypervisor/vms/seeds/<name>/ folder gets built into a seed ISO via build-seed-iso.ps1 and
    attached, so it installs with zero prompts once booted. pfsense01 and linux-client01 are
    built entirely by hand in the Workstation GUI (see their respective vms/*.md) and are not
    in this script's table.

.DESCRIPTION
    Reads the VM table below (mirrors docs/Architecture.md's component inventory) and, for
    each VM, creates a new virtual disk and a minimal .vmx with the right CPU/RAM/NIC
    settings on the lab's LAN Segment, then registers it with vmrun so it shows up in the
    Workstation Library.

.PARAMETER VmDir
    Directory under which each VM's folder will be created (default: this repo's
    hypervisor/vms/<name>/).

.PARAMETER LanNetwork
    Name of the VMware LAN Segment every VM's NIC is attached to (default: "LAN-LAB", created
    the first time it's referenced from pfSense's NIC2 — see hypervisor/vms/pfsense.md). Every
    VM this script creates has exactly one NIC, on this network; pfSense is the only VM with a
    WAN-facing NIC, and it's built by hand, not by this script.

.EXAMPLE
    .\create-vms.ps1 -IsoDir C:\ISOs
#>
[CmdletBinding()]
param(
    [string]$VmDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\vms")).Path,
    [string]$IsoDir = "C:\ISOs",
    [string]$VmwarePath = "$Env:ProgramFiles(x86)\VMware\VMware Workstation",
    [string]$LanNetwork = "LAN-LAB"
)

$ErrorActionPreference = "Stop"
$vmrun = Join-Path $VmwarePath "vmrun.exe"
$vdiskman = Join-Path $VmwarePath "vmware-vdiskmanager.exe"

foreach ($exe in @($vmrun, $vdiskman)) {
    if (-not (Test-Path $exe)) { throw "Required tool not found: $exe. Adjust -VmwarePath." }
}

# name, vcpu, ramMB, diskGB, nics (array of network names), iso, firmware/vtpm, guest OS type
$VMs = @(
    @{ Name = "samba-dc01";     VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork); Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "docker01";       VCPU = 4; RamMB = 8192;  DiskGB = 80;  Nics = @($LanNetwork); Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "authentik01";    VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork); Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    # Windows 11 Setup hard-blocks installation without a detected TPM 2.0 and UEFI firmware —
    # this is the fix for that; every other VM above is untouched (still BIOS, no vTPM, exactly
    # as before this change).
    @{ Name = "win-client01";   VCPU = 2; RamMB = 4096;  DiskGB = 60;  Nics = @($LanNetwork); Iso = "Win11.iso";                Firmware = "efi";  Vtpm = $true;  GuestOS = "windows11-64" }
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

    # Unattended-install seed media: every VM left in this script's table has a
    # hypervisor/vms/seeds/<name>/ folder (Ubuntu Server autoinstall or Windows autounattend) —
    # pfsense01 and linux-client01 are built by hand and never reach this script at all.
    $seedFolder = Join-Path $VmDir "seeds\$($vm.Name)"
    $cdromLines = ""
    if (Test-Path $seedFolder) {
        Write-Host "[create-vms] $($vm.Name) has an unattended-install seed — building it..." -ForegroundColor Cyan
        & (Join-Path $PSScriptRoot "build-seed-iso.ps1") -Name $vm.Name
        $seedIso = Join-Path $vmFolder "$($vm.Name)-seed.iso"
        $cdromLines = "ide1:1.present = `"TRUE`"`nide1:1.deviceType = `"cdrom-image`"`nide1:1.fileName = `"$seedIso`"`n"
    }

    # win-client01 is the only entry with Firmware = "efi": Windows 11 Setup hard-requires
    # UEFI + Secure Boot + a TPM 2.0 and refuses to install without them. Every other VM here
    # gets none of these lines — same BIOS/no-vTPM behavior as before this change.
    $firmwareLines = ""
    if ($vm.Firmware -eq "efi") {
        $firmwareLines += "firmware = `"efi`"`n"
        $firmwareLines += "uefi.secureBoot.enabled = `"TRUE`"`n"
    }
    if ($vm.Vtpm) {
        $firmwareLines += "vtpm.present = `"TRUE`"`n"
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
$cdromLines$nicLines$firmwareLines
guestOS = "$($vm.GuestOS)"
"@ | Set-Content -Path $vmx -Encoding ASCII

    Write-Host "[create-vms] $($vm.Name) VM shell ready at $vmx" -ForegroundColor Green
    Write-Host "[create-vms] Boot with: `"$vmrun`" start `"$vmx`" gui" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "All VM shells created. See hypervisor/vms/*.md for per-VM install notes." -ForegroundColor Green
Write-Host "pfsense01 and linux-client01 are built by hand in the Workstation GUI - not by this script."
