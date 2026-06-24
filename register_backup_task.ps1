param(
    [Parameter(Mandatory=$true, HelpMessage="Name of the Scheduled Task")]
    [string]$TaskName,

    [Parameter(Mandatory=$true, HelpMessage="Source directory to backup")]
    [string]$SourcePath,

    [Parameter(Mandatory=$true, HelpMessage="Destination directory for backup")]
    [string]$DestPath,
    
    [Parameter(HelpMessage="Log file path")]
    [string]$LogPath,
    
    [Parameter(HelpMessage="Optional path to check before running (e.g. D:\)")]
    [string]$CheckPath,
    
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
if (-not [string]::IsNullOrWhiteSpace($CheckPath)) {
    $CheckPath = $CheckPath.TrimEnd('\')
    $Arguments += " -CheckPath `"$CheckPath`""
}

# Define Action
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $Arguments

# --- Cron Parsing Logic ---
Write-Host "Parsing Cron Schedule: $CronSchedule"
$parts = $CronSchedule.Trim() -split '\s+'
if ($parts.Count -ne 5) { throw "Invalid Cron format. Expected 5 fields: minute hour day-of-month month day-of-week." }

$min = $parts[0]
$hour = $parts[1]
$dom = $parts[2]
$month = $parts[3]
$dow = $parts[4]

$isAny = { param($v) $v -eq '*' }
$isIntegerInRange = {
    param(
        [string]$Value,
        [int]$MinValue,
        [int]$MaxValue,
        [string]$FieldName
    )

    if ($Value -notmatch '^\d+$') {
        throw "Invalid $FieldName field '$Value'. Expected a number from $MinValue to $MaxValue."
    }

    $number = [int]$Value
    if (($number -lt $MinValue) -or ($number -gt $MaxValue)) {
        throw "Invalid $FieldName field '$Value'. Expected a number from $MinValue to $MaxValue."
    }

    return $number
}

# 1. Minute Interval (e.g. "* * * * *" or "*/5 * * * *")
if ( (&$isAny $hour) -and (&$isAny $dom) -and (&$isAny $month) -and (&$isAny $dow) ) {
    $intervalMinutes = 1
    if ($min -match '^\*/(\d+)$') {
        $intervalMinutes = [int]$Matches[1]
        if (($intervalMinutes -lt 1) -or ($intervalMinutes -gt 1439)) {
            throw "Invalid minute interval '$min'. Expected an interval from */1 to */1439."
        }
    }
    elseif (-not (&$isAny $min)) {
        throw "Unsupported minute field '$min' with wildcard hour/day/month fields. Use '*' or '*/n'."
    }
    
    # Run Once immediately, repeat every X minutes, for 20 years (indefinite-ish)
    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $intervalMinutes) -RepetitionDuration (New-TimeSpan -Days (365*20))
    $ScheduleDesc = "Every $intervalMinutes minute(s)"
}
# 2. Daily (e.g. "30 2 * * *")
elseif ( (&$isAny $dom) -and (&$isAny $month) -and (&$isAny $dow) ) {
    if ((&$isAny $min) -or (&$isAny $hour)) { throw "Daily schedule requires specific minute and hour (e.g. '30 2 * * *')." }
    $minNumber = &$isIntegerInRange $min 0 59 "minute"
    $hourNumber = &$isIntegerInRange $hour 0 23 "hour"
    $timeOfDay = "{0:D2}:{1:D2}" -f $hourNumber, $minNumber
    $Trigger = New-ScheduledTaskTrigger -Daily -At $timeOfDay
    $ScheduleDesc = "Daily at $timeOfDay"
}
# 3. Weekly (e.g. "30 2 * * 1" -> Mon)
elseif ( (&$isAny $dom) -and (&$isAny $month) ) {
    if ((&$isAny $min) -or (&$isAny $hour)) { throw "Weekly schedule requires specific minute and hour." }
    $minNumber = &$isIntegerInRange $min 0 59 "minute"
    $hourNumber = &$isIntegerInRange $hour 0 23 "hour"
    $daysMap = @{ 0="Sunday"; 1="Monday"; 2="Tuesday"; 3="Wednesday"; 4="Thursday"; 5="Friday"; 6="Saturday"; 7="Sunday" }
    $dowNumber = &$isIntegerInRange $dow 0 7 "day-of-week"
    $dayName = $daysMap[$dowNumber]
    $timeOfDay = "{0:D2}:{1:D2}" -f $hourNumber, $minNumber
    $Trigger = New-ScheduledTaskTrigger -Weekly -At $timeOfDay -DaysOfWeek $dayName
    $ScheduleDesc = "Weekly on $dayName at $timeOfDay"
}
else {
    throw "Complex Cron format '$CronSchedule' not supported by this simplified parser."
}
# --------------------------

$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries:$false -DontStopIfGoingOnBatteries:$false

# Prefix the task name for Task Scheduler display/organization
$ScheduledTaskName = "PwshBackupper-$TaskName"

# Create Principal to run as the current user, but Hidden (S4U) and with Highest Privileges
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest

# Register the Task
try {
    # Unregister if exists to allow update
    Unregister-ScheduledTask -TaskName $ScheduledTaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    Register-ScheduledTask -TaskName $ScheduledTaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "Backup task. $ScheduleDesc. Source: $SourcePath, Dest: $DestPath" | Out-Null
    Write-Host "Success! Task '$ScheduledTaskName' registered."
    Write-Host "Schedule: $ScheduleDesc"
    Write-Host "Mode: Hidden (S4U)"
} catch {
    Write-Error "Failed to register task. Ensure you are running this script as Administrator."
    Write-Error $_
}
