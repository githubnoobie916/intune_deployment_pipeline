# Firefox MSI is an EXE wrapper. Do not use MSI product-code detection/uninstall/repair.
$msiArguments = "INSTALL_DIRECTORY_PATH=`"$env:ProgramW6432\Mozilla Firefox`" DESKTOP_SHORTCUT=false INSTALL_MAINTENANCE_SERVICE=false REMOVE_DISTRIBUTION_DIR=false"
Start-ADTMsiProcess -Action Install -FilePath 'Firefox.msi' -AdditionalArgumentList $msiArguments -ExitOnProcessFailure
