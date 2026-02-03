param(
    [Parameter(Mandatory=$true, HelpMessage="Name of the Scheduled Task")]
    [string]$TaskName,

    [Parameter(Mandatory=$true, HelpMessage="Source directory to backup")]
    [string]$SourcePath,

    [Parameter(Mandatory=$true, HelpMessage="Destination directory for backup")]
    [string]$DestPath,
    
    [Parameter(HelpMessage="Log file path")]
    [string]$LogPath,
    
    [Parameter(Mandatory=$true, HelpMessage="Cron notation (e.g. '* * * * *' for every minute, '*/5 * * * *' for every 5m, '0 2 * * *' for daily at 2:00)")]
    [string]$CronSchedule
)

$ErrorActionPreference = "Stop"

# Default log path using TaskName if not specified
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $env:USERPROFILE "Logs" "backup_log_$($TaskName).txt"
}

# Unique lock name per task
$LockName = "Global\PwshBackupper_$($TaskName)"

# Ensure absolute path for the script
$ScriptPath = Join-Path $PSScriptRoot "backup_script.ps1"
if (-not (Test-Path $ScriptPath)) {
    Write-Error "Could not find 'backup_script.ps1' in the current directory: $PSScriptRoot"
    exit 1
}

# Construct the arguments string
$Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -SourcePath `"$SourcePath`" -DestPath `"$DestPath`" -LogPath `"$LogPath`" -LockName `"$LockName`""

# Define Action
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $Arguments

# --- Cron Parsing Logic ---
Write-Host "Parsing Cron Schedule: $CronSchedule"
$parts = $CronSchedule -split '\s+'
if ($parts.Count -ne 5) { throw "Invalid Cron format. Expected 5 fields (Min Hour Dom Month Dow)." }

$min = $parts[0]
$hour = $parts[1]
$dom = $parts[2]
$month = $parts[3]
$dow = $parts[4]

$isAny = { param($v) $v -eq '*' }
$isInterval = { param($v) $v -match '^\*/(\d+)

