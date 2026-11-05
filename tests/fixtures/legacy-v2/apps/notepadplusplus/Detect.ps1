# Standalone Intune detection; no PSADT, Evergreen, or module imports.
# Frozen example version observed 2026-11-03. Re-resolve this literal for each approved build.
$MinimumVersion = [version]'8.9.8.1'
$ErrorActionPreference = 'Stop'
try {
    if (-not [Environment]::Is64BitOperatingSystem) { exit 1 }
    $installDirectory = Join-Path $env:ProgramW6432 'Notepad++'
    $exePath = Join-Path $installDirectory 'notepad++.exe'
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { exit 1 }

    # PE Machine 0x8664 is x64; a folder name alone does not establish architecture.
    $stream = [IO.File]::Open($exePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { exit 1 }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) { exit 1 }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550 -or $reader.ReadUInt16() -ne 0x8664) { exit 1 }
    } finally { $reader.Dispose(); $stream.Dispose() }

    # Use the 64-bit machine registration explicitly, independent of host registry redirection.
    $machine = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    $uninstall = $null
    $identityMatched = $false
    try {
        $uninstall = $machine.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
        if ($null -eq $uninstall) { exit 1 }
        foreach ($name in $uninstall.GetSubKeyNames()) {
            $entry = $uninstall.OpenSubKey($name)
            try {
                $displayName = [string]$entry.GetValue('DisplayName', '')
                $location = [string]$entry.GetValue('InstallLocation', '')
                if ($displayName -match '^Notepad\+\+(?: .*)?$' -and
                    $location.TrimEnd('\') -ieq $installDirectory.TrimEnd('\')) {
                    $identityMatched = $true
                    break
                }
            } finally { if ($null -ne $entry) { $entry.Dispose() } }
        }
    } finally {
        if ($null -ne $uninstall) { $uninstall.Dispose() }
        $machine.Dispose()
    }
    if (-not $identityMatched) { exit 1 }
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
    $installedVersion = [version]('{0}.{1}.{2}.{3}' -f
        $info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart)
    if ($installedVersion -ge $MinimumVersion) {
        Write-Output 'Notepad++ x64 meets the required version.'
        exit 0
    }
    exit 1
} catch { exit 1 }

