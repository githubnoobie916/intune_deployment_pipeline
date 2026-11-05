#requires -Version 5.1
# Dot-source after Application.Core.ps1. Defines read-only artifact inventory functions.
function Assert-AppModuleArchive([string]$ModuleRoot, [string]$ArchivePath, [string]$ExpectedSha256) {
    Assert-AppUnredirectedPath $ArchivePath
    if ((Get-FileHash -LiteralPath $ArchivePath).Hash -ine $ExpectedSha256) { throw 'Module archive differs from the reviewed package pin.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $expected = [Collections.Generic.List[object]]::new()
        foreach ($entry in $archive.Entries) {
            if (-not $entry.Name) { continue }
            $stream = $entry.Open(); $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
            finally { $stream.Dispose(); $sha.Dispose() }
            $expected.Add([pscustomobject]@{path=$entry.FullName.Replace('\','/');sha256=$hash})
        }
        try { $null = Assert-BuildInventory $ModuleRoot $expected.ToArray() }
        catch { throw "Module content differs from the verified archive: $($_.Exception.Message)" }
    } finally { $archive.Dispose() }
}
function Get-BuildInventory([string]$Root) {
    Assert-AppUnredirectedPath $Root
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Artifact directory does not exist: $Root" }
    $pending = [Collections.Generic.Queue[string]]::new(); $pending.Enqueue($Root)
    $inventory = [Collections.Generic.List[object]]::new()
    while ($pending.Count) {
        foreach ($item in @(Get-ChildItem -LiteralPath $pending.Dequeue() -Force -ErrorAction Stop)) {
            if ($item.PSObject.Properties['LinkType'] -and $item.LinkType) { throw "Redirected build content is not permitted: $($item.FullName)" }
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName); continue }
            $inventory.Add([pscustomobject]@{path=$item.FullName.Substring($Root.TrimEnd('\','/').Length + 1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()})
        }
    }
    return @($inventory.ToArray() | Sort-Object path)
}
function Assert-BuildInventory([string]$Root, $Expected) {
    $actual = @(Get-BuildInventory $Root)
    if ($actual.Count -ne @($Expected).Count) { throw "Unexpected file inventory under $Root" }
    $lookup = @{}
    foreach ($entry in $Expected) {
        $key = $entry.path.Replace('\','/')
        if ($lookup.ContainsKey($key)) { throw "Duplicate inventory path: $key" }; $lookup[$key] = $entry.sha256
    }
    foreach ($entry in $actual) {
        if (-not $lookup.ContainsKey($entry.path) -or $lookup[$entry.path] -ine $entry.sha256) { throw "Build content changed: $($entry.path)" }
    }
    return $actual
}
