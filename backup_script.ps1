<#
.SYNOPSIS
    Robocopy Backup Script with Single-Instance Locking
.DESCRIPTION
    This script mirrors files from Source to Destination using Robocopy.
    It ensures only one instance runs at a time using a Mutex.
    It does NOT delete files from the destination (no /PURGE or /MIR).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Path to the source folder")]
    [string]$SourcePath,

    [Parameter(Mandatory=$true, HelpMessage="Path to the destination folder")]
    [string]$DestPath,

    [Parameter(HelpMessage="Path to the log file")]
    [string]$LogPath = "$env:USERPROFILE\backup_log.txt",

    [Parameter(HelpMessage="Unique name for the mutex to prevent overlapping runs")]
    [string]$LockName = "Global\MyUniqueBackupScriptLock",

    [Parameter(HelpMessage="Optional path to check before starting (e.g. to verify a drive is mounted)")]
    [string]$CheckPath
)

# Robocopy Options
# /E   : Copy Subdirectories, including Empty ones.
# /XO  : eXclude Older files (only copy new/changed).
# /FFT : Assume FAT File Times (2-second granularity), good for network shares.
# /R:3 : Retry 3 times on failed copies.
# /W:10: Wait 10 seconds between retries.
# /NP  : No Progress - don't show percentage copied (keeps logs clean).
$RoboOptions = @("/E", "/XO", "/FFT", "/R:3", "/W:10", "/NP")
# ---------------------

# Acquire Mutex for Single Instance Locking
$Mutex = New-Object System.Threading.Mutex($false, $LockName)
$HasHandle = $false

try {
    # Try to acquire the mutex (wait 0ms)
    $HasHandle = $Mutex.WaitOne(0, $false)
    
    if (-not $HasHandle) {
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Msg = "[$Timestamp] SKIP: Another instance is already running."
        Add-Content -Path $LogPath -Value $Msg
        Write-Warning $Msg
        exit
    }

    # --- Start Backup Process ---
    $LogDir = Split-Path -Parent $LogPath
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    }
    
    # Pre-flight check: Verify CheckPath existence if provided
    if (-not [string]::IsNullOrWhiteSpace($CheckPath)) {
        if (-not (Test-Path $CheckPath)) {
            $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $Msg = "[$Timestamp] SKIP: CheckPath not found: '$CheckPath'. Is the drive mounted?"
            Add-Content -Path $LogPath -Value $Msg
            Write-Warning $Msg
            exit
        }
    }

    Start-Transcript -Path $LogPath -Append -Force

    Write-Output "Starting backup: $(Get-Date)"
    Write-Output "Source: $SourcePath"
    Write-Output "Dest:   $DestPath"

    # Create destination if it doesn't exist
    if (!(Test-Path $DestPath)) {
        New-Item -ItemType Directory -Force -Path $DestPath | Out-Null
    }

    # Execute Robocopy
    # Robocopy returns specific exit codes, we capture them to avoid script errors on partial success
    # NOTE: We construct a single string for ArgumentList to ensure quotes are preserved for paths with spaces in PowerShell 5.1
    $RoboArgsString = "`"$SourcePath`" `"$DestPath`" " + ($RoboOptions -join " ")
    
    $Process = Start-Process -FilePath "robocopy.exe" -ArgumentList $RoboArgsString -NoNewWindow -PassThru -Wait
    
    # Robocopy Exit Codes:
    # 0 = No files were copied (No change).
    # 1 = Files were copied successfully.
    # 2 = Extra files or directories were detected (only with /MIR).
    # 4 = Mismatched files or directories were detected.
    # 8 = Some copies failed.
    # 16 = Serious error.
    
    $ExitCode = $Process.ExitCode
    if ($ExitCode -ge 8) {
        Write-Error "Robocopy finished with ERRORS. Exit Code: $ExitCode"
    } elseif ($ExitCode -ge 4) {
        Write-Warning "Robocopy finished with mismatches. Exit Code: $ExitCode"
    } else {
        Write-Output "Robocopy finished successfully. Exit Code: $ExitCode"
    }

    Write-Output "Backup finished: $(Get-Date)"

} catch {
    Write-Error "An unexpected error occurred: $_"
} finally {
    # Clean up
    if ($HasHandle) {
        $Mutex.ReleaseMutex()
    }
    if ($Mutex) {
        $Mutex.Dispose()
    }
    Stop-Transcript
}
