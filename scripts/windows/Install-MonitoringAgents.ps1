<#
.SYNOPSIS
    Installs the lab's monitoring and logging agents on a Windows machine: windows_exporter
    (metrics for Prometheus) and Grafana Alloy (event logs for Loki).

.DESCRIPTION
    The Windows counterpart of ansible/roles/node_exporter and ansible/roles/alloy. Run it
    elevated on winsrv01 or win-client01 after the machine has joined the domain, so it already
    trusts the lab CA (the certificate for https://loki.lab.internal is checked, never skipped).

    You download the two installers yourself and give the script their SHA-256 hashes from the
    release pages. The script refuses to install a file whose hash does not match. That check is
    the point: an installer that runs as SYSTEM should never be trusted on the strength of a
    download alone.

    What it does
      1. Verifies each installer against the hash you supplied.
      2. Installs windows_exporter on port 9182, with a Windows Firewall exception that allows
         only the monitoring host (docker01) to connect.
      3. Writes an Alloy configuration that ships the Application, System and Security event logs
         to Loki, locks the file down (it holds the push password), and installs Alloy.

.PARAMETER ExporterMsi
    Path to the windows_exporter amd64 MSI (from the windows_exporter GitHub releases page).

.PARAMETER ExporterSha256
    SHA-256 of that MSI, as published on the release page.

.PARAMETER AlloyInstaller
    Path to alloy-installer-windows-amd64.exe (from the Grafana Alloy GitHub releases page).

.PARAMETER AlloySha256
    SHA-256 of that installer.

.PARAMETER LokiPushUser
    The Loki push user. Matches loki_push_user in ansible/group_vars/all.yml.

.EXAMPLE
    .\Install-MonitoringAgents.ps1 -ExporterMsi .\windows_exporter-amd64.msi -ExporterSha256 <hash> `
        -AlloyInstaller .\alloy-installer-windows-amd64.exe -AlloySha256 <hash>
    You are prompted for the Loki push password; it is never taken on the command line.

.NOTES
    Not yet run on a lab Windows machine. Check the Alloy service name afterwards
    (Get-Service *Alloy*); the Alloy documentation does not state it.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$ExporterMsi,
    [Parameter(Mandatory)] [string]$ExporterSha256,
    [Parameter(Mandatory)] [string]$AlloyInstaller,
    [Parameter(Mandatory)] [string]$AlloySha256,
    [string]$LokiPushUser = "lab-logs",
    [string]$LokiPushUrl = "https://loki.lab.internal/loki/api/v1/push",
    [string]$MonitoringHost = "10.10.10.20",
    [int]$ExporterPort = 9182,
    [string]$AlloyConfigDir = (Join-Path $env:ProgramData "GrafanaLabs")
)

$ErrorActionPreference = "Stop"

function Assert-Hash([string]$Path, [string]$Expected) {
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected.Trim().ToUpper()) {
        throw "SHA-256 mismatch for $Path.`n  expected: $($Expected.Trim().ToUpper())`n  actual:   $actual`nDo not install it. Download it again from the release page."
    }
    Write-Host "  hash OK: $Path" -ForegroundColor Green
}

Write-Host "[monitoring-agents] Verifying installers" -ForegroundColor Cyan
Assert-Hash $ExporterMsi $ExporterSha256
Assert-Hash $AlloyInstaller $AlloySha256

# --- windows_exporter ------------------------------------------------------------------------
Write-Host "[monitoring-agents] Installing windows_exporter on port $ExporterPort" -ForegroundColor Cyan
$msiArgs = @(
    "/i", "`"$((Resolve-Path $ExporterMsi).Path)`"", "/qn",
    "ENABLED_COLLECTORS=cpu,memory,logical_disk,net,os,service,time",
    "LISTEN_PORT=$ExporterPort",
    "ADDLOCAL=FirewallException",      # opens the port in Windows Firewall ...
    "REMOTE_ADDR=$MonitoringHost"      # ... for the monitoring host only
)
if ($PSCmdlet.ShouldProcess("windows_exporter", "Install")) {
    $p = Start-Process -FilePath msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) { throw "windows_exporter install failed (msiexec exit code $($p.ExitCode))." }
}

# --- Alloy ----------------------------------------------------------------------------------
Write-Host "[monitoring-agents] Enter the Loki push password for user '$LokiPushUser'" -ForegroundColor Cyan
$secure = Read-Host -AsSecureString "Loki push password"
$plain = [System.Net.NetworkCredential]::new("", $secure).Password

$hostName = $env:COMPUTERNAME.ToLower()
$config = @"
// Ships Windows event logs to Loki. Written by Install-MonitoringAgents.ps1. See docs/Logging.md.

loki.source.windowsevent "application" {
  eventlog_name = "Application"
  labels        = { job = "windows-eventlog", host = "$hostName", log = "application" }
  forward_to    = [loki.write.lab.receiver]
}

loki.source.windowsevent "system" {
  eventlog_name = "System"
  labels        = { job = "windows-eventlog", host = "$hostName", log = "system" }
  forward_to    = [loki.write.lab.receiver]
}

// The Security log holds logons and privilege use. The service runs as LocalSystem, which can read it.
loki.source.windowsevent "security" {
  eventlog_name = "Security"
  labels        = { job = "windows-eventlog", host = "$hostName", log = "security" }
  forward_to    = [loki.write.lab.receiver]
}

loki.write "lab" {
  endpoint {
    url = "$LokiPushUrl"

    basic_auth {
      username = "$LokiPushUser"
      password = "$plain"
    }
  }
}
"@

$configPath = Join-Path $AlloyConfigDir "config.alloy"
if ($PSCmdlet.ShouldProcess($configPath, "Write Alloy configuration and install Alloy")) {
    New-Item -ItemType Directory -Path $AlloyConfigDir -Force | Out-Null
    Set-Content -Path $configPath -Value $config -Encoding UTF8

    # The file holds the push password: only SYSTEM and Administrators may read it.
    & icacls.exe $configPath /inheritance:r /grant:r "SYSTEM:(R)" "Administrators:(F)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not restrict permissions on $configPath." }

    $p = Start-Process -FilePath (Resolve-Path $AlloyInstaller).Path `
        -ArgumentList "/S", "/CONFIG=`"$configPath`"", "/DISABLEREPORTING=yes" -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Alloy install failed (exit code $($p.ExitCode))." }
}
$plain = $null

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  1. Check both services: Get-Service *exporter*, *Alloy*"
Write-Host "  2. Add this machine to docker/monitoring/prometheus/targets/windows.yml:"
Write-Host "       - targets: [`"<this machine's IP>:$ExporterPort`"]  labels: { host: $hostName }"
Write-Host "  3. In Grafana > Explore > Loki, run: {job=`"windows-eventlog`", host=`"$hostName`"}"
