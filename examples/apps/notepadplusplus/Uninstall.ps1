Start-ADTProcess -FilePath "$env:ProgramW6432\Notepad++\uninstall.exe" -ArgumentList '/S' -WaitForChildProcesses -ExitOnProcessFailure
# A missing uninstaller follows PSADT's native failure handling.
# Retain user configuration; separately verify app detection is false after removal.
