# Mozilla documents this helper and /S; msiexec /x is unsupported for Firefox MSI.
Start-ADTProcess -FilePath "$env:ProgramW6432\Mozilla Firefox\uninstall\helper.exe" -ArgumentList '/S' -WaitForChildProcesses -ExitOnProcessFailure
# A missing uninstaller follows PSADT's native failure handling.
# Retain user profiles. Confirm absence with the independent detection script after removal.
