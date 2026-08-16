<#
.SYNOPSIS
    Creates the lab's VM shells (disk + .vmx) via vmrun/vmware-vdiskmanager, ready for OS
    installation. For any VM with a workstation/vms/seeds/<name>/ folder (every host except
    pfsense01 and linux-client01), also builds and attaches an unattended-install seed ISO via
    build-seed-iso.ps1 — those VMs install with zero prompts once booted. pfSense has no
    unattended installer to target; the Linux desktop client's install is intentionally manual
    (see linux-client.md).

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

# name, vcpu, ramMB, diskGB, nics (array of network names), iso, firmware/vtpm, guest OS type
$VMs = @(
    @{ Name = "pfsense01";      VCPU = 2; RamMB = 2048;  DiskGB = 20;  Nics = @($WanNetwork, $LanNetwork); Iso = "pfSense-CE.iso";           Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "samba-dc01";     VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork);               Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "docker01";       VCPU = 4; RamMB = 8192;  DiskGB = 80;  Nics = @($LanNetwork);               Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "authentik01";    VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork);               Iso = "ubuntu-server-24.04.iso";  Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    @{ Name = "linux-client01"; VCPU = 2; RamMB = 4096;  DiskGB = 40;  Nics = @($LanNetwork);               Iso = "ubuntu-desktop-24.04.iso"; Firmware = "bios"; Vtpm = $false; GuestOS = "ubuntu-64" }
    # Windows 11 Setup hard-blocks installation without a detected TPM 2.0 and UEFI firmware —
    # this is the fix for that; every other VM above is untouched (still BIOS, no vTPM, exactly
    # as before this change).
    @{ Name = "win-client01";   VCPU = 2; RamMB = 4096;  DiskGB = 60;  Nics = @($LanNetwork);               Iso = "Win11.iso";                Firmware = "efi";  Vtpm = $true;  GuestOS = "windows11-64" }
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

    # Unattended-install seed media: workstation/vms/seeds/<name>/ only exists for hosts that
    # support an unattended install (Ubuntu Server autoinstall, Windows autounattend). pfSense
    # and the Linux desktop client have no seed folder, so this is a no-op for them — they boot
    # straight into the normal interactive installer, exactly as before this change.
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
Write-Host "All VM shells created. See workstation/vms/*.md for per-VM install notes" -ForegroundColor Green
Write-Host "(autoinstall seeds for Ubuntu hosts, manual steps for pfSense/Windows)."
