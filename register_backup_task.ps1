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

# Sanitize paths to avoid "trailing backslash escaping quote" issues in command line arguments
$SourcePath = $SourcePath.TrimEnd('\')
$DestPath = $DestPath.TrimEnd('\')

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
$isInterval = { param($v) $v -match '^\*/(\d+)$' }

# 1. Minute Interval (e.g. "* * * * *" or "*/5 * * * *")
if ( (&$isAny $hour) -and (&$isAny $dom) -and (&$isAny $month) -and (&$isAny $dow) ) {
    $intervalMinutes = 1
    if (&$isInterval $min) { $intervalMinutes = [int]$Matches[1] }
    elseif (-not (&$isAny $min)) { throw "Specific minute with wildcards (Hourly) not supported yet. Use '*/n' or '*'. " }
    
    # Run Once immediately, repeat every X minutes, for 20 years (indefinite-ish)
    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $intervalMinutes) -RepetitionDuration (New-TimeSpan -Days (365*20))
    $ScheduleDesc = "Every $intervalMinutes minute(s)"
}
# 2. Daily (e.g. "30 2 * * *")
elseif ( (&$isAny $dom) -and (&$isAny $month) -and (&$isAny $dow) ) {
    if ((&$isAny $min) -or (&$isAny $hour)) { throw "Daily schedule requires specific minute and hour (e.g. '30 2 * * *')." }
    $Trigger = New-ScheduledTaskTrigger -Daily -At "$hour`:$min"
    $ScheduleDesc = "Daily at $hour`:$min"
}
# 3. Weekly (e.g. "30 2 * * 1" -> Mon)
elseif ( (&$isAny $dom) -and (&$isAny $month) ) {
    if ((&$isAny $min) -or (&$isAny $hour)) { throw "Weekly schedule requires specific minute and hour." }
    $daysMap = @{ 0="Sunday"; 1="Monday"; 2="Tuesday"; 3="Wednesday"; 4="Thursday"; 5="Friday"; 6="Saturday"; 7="Sunday" }
    if (-not $daysMap.ContainsKey([int]$dow)) { throw "Invalid Day of Week: $dow (Use 0-7)" }
    $dayName = $daysMap[[int]$dow]
    $Trigger = New-ScheduledTaskTrigger -Weekly -At "$hour`:$min" -DaysOfWeek $dayName
    $ScheduleDesc = "Weekly on $dayName at $hour`:$min"
}
else {
    throw "Complex Cron format '$CronSchedule' not supported by this simplified parser."
}
# --------------------------

$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries:$false -DontStopIfGoingOnBatteries:$false

# Register the Task
try {
    # Unregister if exists to allow update
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Backup task. $ScheduleDesc. Source: $SourcePath, Dest: $DestPath" | Out-Null
    Write-Host "Success! Task '$TaskName' registered."
    Write-Host "Schedule: $ScheduleDesc"
} catch {
    Write-Error "Failed to register task. Ensure you are running this script as Administrator."
    Write-Error $_
}