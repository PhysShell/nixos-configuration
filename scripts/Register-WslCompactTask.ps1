<#
.SYNOPSIS
    Register the scheduled task that compacts a WSL distro's ext4.vhdx.

.DESCRIPTION
    Run this ONCE from an elevated PowerShell.  Afterwards the task can be
    started without any elevation prompt:

        schtasks /run /tn CompactWslDisk

    which is what makes wsl-disk-guard able to reclaim host space unattended.
    Compacting needs the distro stopped and Administrator rights, so it cannot
    happen from inside WSL - but triggering an already-registered task can.

    The task shuts WSL down before compacting. Anything running in the distro
    at that moment is terminated.
#>
# This script talks to a person running it by hand: the whole point of the
# output is to tell them the task name and how to trigger it afterwards, so
# Write-Host (host-only, not the pipeline) is the correct channel here.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Progress and instructions for an interactive operator, not data.')]
[CmdletBinding()]
param(
    [string]$TaskName = 'CompactWslDisk',
    [string]$Distro = 'NixOS',
    [string]$VhdxPath = '',
    [switch]$RunNow
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Registering a task that runs with highest privileges needs an elevated shell.'
}

# Find the distro's disk from the registry rather than hardcoding a GUID path.
if (-not $VhdxPath) {
    $entry = Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty $_.PSPath } |
        Where-Object { $_.DistributionName -eq $Distro } |
        Select-Object -First 1
    if (-not $entry) { throw "No WSL distro named '$Distro' in the registry." }
    # BasePath comes back as \\?\D:\... - strip that prefix with a
    # plain string operation: escaping backslashes inside a -replace regex
    # is a reliable way to end up with an invalid pattern.
    $base = $entry.BasePath
    if ($base.StartsWith('\\?\')) { $base = $base.Substring(4) }
    $VhdxPath = Join-Path $base 'ext4.vhdx'
}
if (-not (Test-Path -LiteralPath $VhdxPath)) { throw "Not found: $VhdxPath" }
Write-Host "Distro '$Distro' disk: $VhdxPath"

# Mount read-only + Optimize-VHD -Mode Full is the supported way to shrink a
# dynamic VHDX.  wsl --manage --set-sparse would be the other one, but Microsoft
# disabled it over data-corruption reports, so it is deliberately not used here.
$action = @"
`$ErrorActionPreference = 'Continue'
wsl.exe --shutdown
Start-Sleep -Seconds 8
`$before = (Get-Item -LiteralPath '$VhdxPath').Length
`$mounted = `$false
try {
    Mount-VHD -Path '$VhdxPath' -ReadOnly -NoDriveLetter -ErrorAction Stop
    `$mounted = `$true
    Optimize-VHD -Path '$VhdxPath' -Mode Full -ErrorAction Stop
} finally {
    if (`$mounted) { Dismount-VHD -Path '$VhdxPath' -ErrorAction SilentlyContinue }
}
`$after = (Get-Item -LiteralPath '$VhdxPath').Length
Write-Output ('compacted {0}: {1} -> {2} bytes' -f '$VhdxPath', `$before, `$after)
"@

$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($action))

$taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $encoded"
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Principal $principal `
    -Settings $settings -Description "Shut down WSL and compact $Distro's ext4.vhdx" -Force | Out-Null

Write-Host "Registered task '$TaskName'. Trigger it from anywhere, no elevation needed:"
Write-Host "  schtasks /run /tn $TaskName"

if ($RunNow) {
    Write-Host 'Running it now...'
    Start-ScheduledTask -TaskName $TaskName
}
