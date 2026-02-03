# PowerShell Robocopy Backup Tool

A robust backup solution using PowerShell and Robocopy, featuring single-instance locking (mutex), logging, and easy Windows Task Scheduler integration with Cron-style scheduling.

## Features

*   **Robust Copying:** Uses `robocopy` for efficient, resume-able file copying (Additive Backup). Files deleted from the source are **NOT** deleted from the destination.
*   **Single Instance Locking:** Prevents overlapping backup runs using a named Mutex.
*   **Logging:** automatically logs operations to a file.
*   **Cron-style Scheduling:** Helper script to register Windows Scheduled Tasks using familiar Cron syntax.
*   **Parameterized:** Fully customizable source, destination, and log paths.

## Scripts

### 1. `backup_script.ps1`
The core backup logic.
*   **Usage:**
    ```powershell
    .\backup_script.ps1 -SourcePath "C:\Data" -DestPath "D:\Backup"
    ```
*   **Parameters:**
    *   `-SourcePath`: Directory to copy from.
    *   `-DestPath`: Directory to copy to.
    *   `-LogPath`: (Optional) Path to log file. Defaults to `~/backup_log.txt`.
    *   `-LockName`: (Optional) Unique ID to prevent overlapping runs.

### 2. `register_backup_task.ps1`
Helper to register the backup script in Windows Task Scheduler.
*   **Usage:**
    ```powershell
    # Run as Administrator
    .\register_backup_task.ps1 -TaskName "MyBackup" -SourcePath "C:\Data" -DestPath "D:\Backups" -CronSchedule "* * * * *"
    ```
*   **Parameters:**
    *   `-TaskName`: Name of the scheduled task.
    *   `-SourcePath`: Source directory.
    *   `-DestPath`: Destination directory.
    *   `-CronSchedule`: Scheduling in Cron format (min hour dom month dow).
    *   `-LogPath`: (Optional) Custom log path. Defaults to `~/Logs/backup_log_<TaskName>.txt`.

## Scheduling Examples

The `register_backup_task.ps1` script supports common Cron patterns:

| Schedule | Cron Expression | Example Command |
| :--- | :--- | :--- |
| **Every Minute** | `* * * * *` | `-CronSchedule "* * * * *"` |
| **Every 5 Minutes** | `*/5 * * * *` | `-CronSchedule "*/5 * * * *"` |
| **Daily at 02:30** | `30 2 * * *` | `-CronSchedule "30 2 * * *"` |
| **Weekly (Mon) at 08:00** | `0 8 * * 1` | `-CronSchedule "0 8 * * 1"` |

## Using `gsudo` (Administrator Access)

If you are running in a non-elevated shell (or over SSH), you can use `gsudo` to run the registration script as Administrator.

**Installation:**
```powershell
winget install gsudo
```

**Usage:**
**Important:** When passing paths with spaces, wrap the command in `{ curly braces }`. This ensures arguments are passed correctly.
```powershell
gsudo { .\register_backup_task.ps1 -TaskName "LabData" -SourcePath "D:\Lab Data" -DestPath "E:\Backups\Lab Data" -CronSchedule "0 2 * * *" }
```

## Checking and Editing Schedules

### 1. Check Existing Tasks
You can view your registered backup tasks using PowerShell:
```powershell
Get-ScheduledTask | Where-Object { $_.TaskName -like "*Backup*" } | Select-Object TaskName, State
```
To see the specific trigger for a task:
```powershell
(Get-ScheduledTask -TaskName "MyBackup").Triggers
```

### 2. Edit the Schedule (Frequency)
**Method A: Re-run the Script (Recommended)**
The easiest way to change a schedule is to run the registration script again with the *same* TaskName and the *new* schedule. It will overwrite the old trigger.
```powershell
.\register_backup_task.ps1 -TaskName "MyBackup" -CronSchedule "*/15 * * * *" ...
```

**Method B: Task Scheduler GUI**
1.  Open **Task Scheduler** (search for it in the Start Menu).
2.  Navigate to **Task Scheduler Library**.
3.  Find your task in the list.
4.  Double-click it, go to the **Triggers** tab, and edit the trigger manually.

## Deleting a Task

Tasks are registered with the prefix `PwshBackupper-`. To remove a scheduled backup task, run PowerShell as Administrator (or use `gsudo`) and include this prefix:

```powershell
Unregister-ScheduledTask -TaskName "PwshBackupper-MyBackup" -Confirm:$false
```

## Notes
*   **Task Scheduler:** `register_backup_task.ps1` must be run as **Administrator**.
*   **Logs:** By default, logs are saved to `C:\Users\<User>\Logs\`.
