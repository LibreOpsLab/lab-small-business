<#
.SYNOPSIS
    Builds a small ISO ("seed media") from the per-VM files under hypervisor/vms/seeds/<name>/,
    so create-vms.ps1 can attach it as a second CD-ROM and turn an interactive OS install into
    an unattended one.

.DESCRIPTION
    Two seed formats are supported, auto-detected by what's in the VM's seeds folder:

      - autounattend.xml       -> Windows Setup's own unattended-install answer file.
      - user-data + meta-data  -> cloud-init's "NoCloud" datasource, consumed by Ubuntu
                                   Server's autoinstall (Subiquity). The ISO's volume label
                                   MUST be exactly "cidata" (case-insensitive) - that literal
                                   string is how cloud-init recognises a NoCloud seed at all.

    Real secrets (a password hash, a plaintext local-account password) never live in the
    .example files committed to git - see hypervisor/vms/seeds/<name>/*.example. This script
    reads the filled-in *copies* you make of those files (same names, no .example suffix),
    which are gitignored, and refuses to build a seed ISO if it finds placeholder text still
    sitting in them un-replaced. That check exists because a seed ISO built from an untouched
    placeholder would boot the VM with a password hash that's sitting in this repo's public git
    history - not a mistake worth being possible to make by accident.

.PARAMETER Name
    VM name matching a subfolder of hypervisor/vms/seeds/ (e.g. "samba-dc01").

.PARAMETER SeedsDir
    Directory containing per-VM seed subfolders (default: hypervisor/vms/seeds, next to this
    script).

.PARAMETER OutFile
    Where to write the built ISO. Defaults to hypervisor/vms/<Name>/<Name>-seed.iso - the same
    folder create-vms.ps1 creates for the VM's .vmx/.vmdk, since that's where create-vms.ps1
    expects to find it.

.EXAMPLE
    .\build-seed-iso.ps1 -Name samba-dc01
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Name,
    [string]$SeedsDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\vms\seeds")).Path,
    [string]$OutFile
)

$ErrorActionPreference = "Stop"

$seedDir = Join-Path $SeedsDir $Name
if (-not (Test-Path $seedDir)) {
    throw "No seed folder for '$Name' at $seedDir — this VM has no unattended-install seed " +
          "(expected for pfsense01/linux-client01 — there's nothing for this script to do for them)."
}

if (-not $OutFile) {
    $vmDir = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..\vms")).Path $Name
    # create-vms.ps1 normally creates this folder before calling this script; create it here
    # too so this script also works standalone, e.g. re-building a seed after editing user-data
    # without recreating the whole VM.
    New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
    $OutFile = Join-Path $vmDir "$Name-seed.iso"
}

# This exact text can only survive in an un-edited .example file — if it's still present in the
# real (gitignored) file the student copied from it, they haven't filled it in yet.
$placeholderPattern = 'replace-with-a-mkpasswd-hash|REPLACE_ME'

function Assert-NoPlaceholder {
    param([string]$Path)
    if ((Get-Content -Path $Path -Raw) -match $placeholderPattern) {
        throw "$Path still has a placeholder value in it (search it for 'replace-with' or " +
              "'REPLACE_ME'). Fill in the real value, then re-run this script."
    }
}

# Auto-detect which seed format this VM uses.
$autounattend = Join-Path $seedDir "autounattend.xml"
$userData     = Join-Path $seedDir "user-data"
$metaData     = Join-Path $seedDir "meta-data"

if (Test-Path $autounattend) {
    Assert-NoPlaceholder $autounattend
    $files = @($autounattend)
    $volumeLabel = "AUTOUNATTEND"
} elseif ((Test-Path $userData) -and (Test-Path $metaData)) {
    Assert-NoPlaceholder $userData
    $files = @($userData, $metaData)
    $volumeLabel = "cidata"
} else {
    throw "$seedDir has neither autounattend.xml nor a user-data+meta-data pair. Copy the " +
          ".example file(s) in that folder, drop the .example suffix, and fill in the " +
          "placeholder value(s) before running this script."
}

$newestSource = ($files | Get-Item | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
if ((Test-Path $OutFile) -and ((Get-Item $OutFile).LastWriteTime -gt $newestSource)) {
    Write-Host "[build-seed-iso] $OutFile is already up to date — skipping." -ForegroundColor Yellow
    return
}

Write-Host "[build-seed-iso] Building $volumeLabel seed ISO for $Name -> $OutFile" -ForegroundColor Cyan

# IMAPI2 is Windows' built-in disc-image API - the same one Explorer's own "Burn disc image"
# feature uses. Using it here means this script needs nothing beyond a stock Windows install;
# the alternative (the Windows ADK's oscdimg.exe) would mean "install the ADK" becomes a new
# prerequisite just to build a handful of tiny text files onto a disc.
$fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$fsi.FileSystemsToCreate = 3  # ISO9660 (1) bitwise-or Joliet (2): readable by both Linux and Windows tooling
$fsi.VolumeName = $volumeLabel
foreach ($file in $files) {
    # AddTree takes either a file or a directory path; given a single file it just adds that
    # file to the current directory item, which is all that's needed here — each seed folder
    # only ever contains the exact files listed in $files, so there's nothing to recurse into.
    $fsi.Root.AddTree($file, $false) | Out-Null
}

$result = $fsi.CreateResultImage()
$adoStream = New-Object -ComObject ADODB.Stream
$adoStream.Type = 1  # adTypeBinary
$adoStream.Open()
$adoStream.LoadFromStream($result.ImageStream)
if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
$adoStream.SaveToFile($OutFile, 2)  # adSaveCreateOverWrite
$adoStream.Close()

Write-Host "[build-seed-iso] Done: $OutFile" -ForegroundColor Green
