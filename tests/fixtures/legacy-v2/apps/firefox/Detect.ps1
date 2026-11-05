# Standalone Intune detection; no PSADT, Evergreen, or module imports.
# Frozen example version observed 2026-11-03. Re-resolve this literal for each approved build.
$MinimumVersion = [version]'159.0.1'
$ErrorActionPreference = 'Stop'
try {
    if (-not [Environment]::Is64BitOperatingSystem) { exit 1 }
    $installDirectory = Join-Path $env:ProgramW6432 'Mozilla Firefox'
    $exePath = Join-Path $installDirectory 'firefox.exe'
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { exit 1 }
    # Check the installed release channel independently of the discovery channel label.
    # This reads the packaged preference file as text; it never evaluates JavaScript.
    $channelPath = Join-Path $installDirectory 'defaults\pref\channel-prefs.js'
    if (-not (Test-Path -LiteralPath $channelPath -PathType Leaf)) { exit 1 }
    $channelText = Get-Content -LiteralPath $channelPath -Raw
    $channelMatches = [regex]::Matches($channelText, '(?m)^\s*pref\("app\.update\.channel",\s*"([^"\r\n]+)"\);\s*$')
    if ($channelMatches.Count -ne 1 -or $channelMatches[0].Groups[1].Value -cne 'release') { exit 1 }

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
                if ($displayName -match '^Mozilla Firefox(?: \d+(?:\.\d+){1,3})? \(x64 en-US\)$' -and
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
        Write-Output 'Firefox x64 en-US meets the required version.'
        exit 0
    }
    exit 1
} catch { exit 1 }

