#requires -Version 5.1
# Build-side data utilities. Dot-sourcing defines functions only.
function Read-AppJson([string]$Path) {
    $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath, [Text.UTF8Encoding]::new($false, $true))
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        if (-not (Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { throw 'PowerShell 7.5+ is required to preserve JSON date strings. Windows PowerShell 5.1 is also supported.' }
        $value = ConvertFrom-Json -InputObject $text -DateKind String
    } else { $value = ConvertFrom-Json -InputObject $text }
    if ($null -eq $value -or $value -isnot [pscustomobject]) { throw "Expected a JSON object: $Path" }
    return $value
}

function Get-AppBytesHash([byte[]]$Bytes) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function ConvertTo-AppCanonicalJson($Value) {
    if ($null -eq $Value) { return 'null' }
    # Check primitive values first: provider-returned strings can carry a PSObject wrapper.
    if ($Value -is [string]) {
        $escaped = [Text.StringBuilder]::new()
        $null = $escaped.Append('"')
        foreach ($character in $Value.ToCharArray()) {
            if ($character -eq '"') { $null = $escaped.Append('\"') }
            elseif ($character -eq '\') { $null = $escaped.Append('\\') }
            elseif ([int]$character -lt 32) { $null = $escaped.Append(('\u{0:x4}' -f [int]$character)) }
            else { $null = $escaped.Append($character) }
        }
        $null = $escaped.Append('"'); return $escaped.ToString()
    }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    if ($Value -is [int] -or $Value -is [long]) { return $Value.ToString([cultureinfo]::InvariantCulture) }
    if ($Value -is [double]) {
        if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) { throw 'Non-finite JSON number.' }
        return $Value.ToString('G17', [cultureinfo]::InvariantCulture)
    }
    if ($Value -is [ValueType]) { throw "Unsupported canonical scalar type: $($Value.GetType().FullName)" }
    if ($Value -is [array]) { return '[' + ((@(foreach ($item in $Value) { ConvertTo-AppCanonicalJson $item })) -join ',') + ']' }
    if ($Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]) {
        [string[]]$keys = @(if ($Value -is [Collections.IDictionary]) { $Value.Keys } else { $Value.PSObject.Properties | ForEach-Object { $_.Name } })
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        $members = @(foreach ($key in $keys) { (ConvertTo-AppCanonicalJson $key) + ':' + (ConvertTo-AppCanonicalJson $Value.$key) })
        return '{' + ($members -join ',') + '}'
    }
    throw "Unsupported canonical data type: $($Value.GetType().FullName)"
}

function Get-AppObjectHash($Value) {
    return Get-AppBytesHash ([Text.UTF8Encoding]::new($false, $true).GetBytes((ConvertTo-AppCanonicalJson $Value)))
}

function Assert-AppUnredirectedPath([string]$Path) {
    $candidate = [IO.Path]::GetFullPath($Path)
    while ($candidate) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if ($item.PSObject.Properties['LinkType'] -and $item.LinkType) { throw "Redirected path is not permitted: $candidate" }
        }
        $parent = [IO.Path]::GetDirectoryName($candidate.TrimEnd('\', '/'))
        if ($parent -eq $candidate) { break }; $candidate = $parent
    }
}

function Resolve-AppSourcePath([string]$Root, [string]$RelativePath, [switch]$AllowMissing) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains(':') -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') { throw "Expected a contained relative path: $RelativePath" }
    if ($RelativePath -match '[\\/]{2,}' -or @($RelativePath -split '[\\/]' | Where-Object { $_ -match '[ .]$' -or $_ -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)' }).Count) { throw "Noncanonical or reserved Windows path: $RelativePath" }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $path = [IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    if (-not $path.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes its source root: $RelativePath" }
    Assert-AppUnredirectedPath $path
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required source file missing: $RelativePath" }
    return $path
}

function Assert-AppJsonSchema([string]$Path, [string]$SchemaPath) {
    if ($PSVersionTable.PSVersion -ge [version]'7.4') {
        if (-not (Test-Json -Json ([IO.File]::ReadAllText($Path)) -SchemaFile $SchemaPath -ErrorAction Stop)) { throw "Schema validation failed: $Path" }
    } else {
        $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if (-not $pwsh) { throw 'PowerShell 7.4+ is required for JSON Schema validation; Windows PowerShell orchestration cannot skip this check.' }
        $validator = Join-Path $PSScriptRoot 'Test-JsonContract.ps1'
        $messages = & $pwsh.Source -NoProfile -NonInteractive -File $validator -JsonPath $Path -SchemaPath $SchemaPath 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Schema validation failed for ${Path}: $messages" }
    }
}

function Write-AppJsonAtomic([string]$Path, $Value) {
    if (Test-Path -LiteralPath $Path) { throw "Refusing to overwrite a retained record: $Path" }
    Assert-AppUnredirectedPath $Path
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), [Text.UTF8Encoding]::new($false))
    # File.Move is exclusive: a competing writer cannot replace the final record.
    [IO.File]::Move($temporary, $Path)
}

function Get-AppRecordHash($Record) {
    $data = [ordered]@{}
    $keys = @(if ($Record -is [Collections.IDictionary]) { $Record.Keys } else { $Record.PSObject.Properties | ForEach-Object { $_.Name } })
    foreach ($key in $keys) {
        if ($key -ne 'recordHash') { $data[$key] = $Record.$key }
    }
    return Get-AppObjectHash $data
}

function Assert-AppRecord($Record, [string]$RecordType) {
    if ($Record.schemaVersion -ne 1 -or $Record.recordType -cne $RecordType -or $Record.recordHash -cne (Get-AppRecordHash $Record)) { throw "Invalid or changed $RecordType record." }
}

function Get-AppDiscoveryFingerprint($Definition) {
    return Get-AppObjectHash ([ordered]@{applicationId=$Definition.id; source=$Definition.source; variant=$Definition.variant})
}

function Read-AppDefinition([string]$Path) {
    $definition = Read-AppJson $Path
    if ($definition.schemaVersion -ne 3) { throw 'This workflow requires schemaVersion 3 app.json. Migrate the legacy recipe/metadata/actions explicitly; automatic merging is not supported.' }
    Assert-AppJsonSchema -Path $Path -SchemaPath (Join-Path $PSScriptRoot '../schemas/application-definition.v3.schema.json')
    foreach ($property in $definition.source.selectionMap.PSObject.Properties) {
        if ($definition.source.selectionConstants.PSObject.Properties[$property.Name]) { throw "Conflicting selection values: $($property.Name)" }
    }
    $codes = @{}
    foreach ($item in $definition.intune.returnCodes) {
        $key = [string]$item.code
        if ($codes.ContainsKey($key)) { throw "Duplicate Intune return code: $key" }; $codes[$key] = $item.type
    }
    # These mappings are unconditionally appended by the pinned IntuneWin32App release.
    foreach ($pair in @{ '0'='success';'1707'='success';'3010'='softReboot';'1641'='hardReboot';'1618'='retry' }.GetEnumerator()) {
        if ($codes[$pair.Key] -ne $pair.Value) { throw "IntuneWin32App 1.5.0 requires return code $($pair.Key)=$($pair.Value)." }
    }
    foreach ($code in $definition.toolkit.successExitCodes) {
        if ($code -in $definition.toolkit.rebootExitCodes -or $codes[[string]$code] -ne 'success') { throw "Contradictory success code: $code" }
    }
    foreach ($code in $definition.toolkit.rebootExitCodes) {
        if ($codes[[string]$code] -notin @('softReboot','hardReboot')) { throw "Contradictory reboot code: $code" }
    }
    $date = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($definition.toolkit.scriptDate, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)) { throw 'Invalid toolkit.scriptDate.' }
    return $definition
}

function Get-AppSelection($Definition) {
    $selection = [ordered]@{}
    foreach ($property in $Definition.source.selectionMap.PSObject.Properties) { $selection[$property.Name] = $Definition.variant.($property.Value) }
    foreach ($property in $Definition.source.selectionConstants.PSObject.Properties) { $selection[$property.Name] = $property.Value }
    return $selection
}

function Assert-AppDownloadUri([string]$Value, $AllowedHosts) {
    $uri = $null
    if (-not [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.DnsSafeHost -notin $AllowedHosts -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw 'Download identity requires an allowed HTTPS URL without credentials, query or fragment; do not persist signed URLs.' }
}
