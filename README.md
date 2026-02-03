# PowerShell Robocopy Backup Tool

A robust backup solution using PowerShell and Robocopy, featuring single-instance locking (mutex), logging, and easy Windows Task Scheduler integration with Cron-style scheduling.

## Features

*   **Robust Copying:** Uses `robocopy` for efficient, resume-able file mirroring.
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

## Notes
*   **Task Scheduler:** `register_backup_task.ps1` must be run as **Administrator**.
*   **Logs:** By default, logs are saved to `C:\Users\<User>\Logs\`.
