# NSIS /D must be the final argument, with no quotation marks even when its path has spaces.
# /noUpdater also deselects Plugins Admin in the inspected vendor installer source.
$installerArguments = "/S /noUpdater /D=$env:ProgramW6432\Notepad++"
Start-ADTProcess -FilePath 'NotepadPlusPlus.exe' -ArgumentList $installerArguments -WaitForChildProcesses -ExitOnProcessFailure
