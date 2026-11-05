#requires -Version 5.1
<# Parse the authored examples and JSON without executing deployment code. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$scripts = @(foreach ($folder in @('examples', 'scripts', 'tests')) {
    Get-ChildItem -LiteralPath (Join-Path $repository $folder) -Filter '*.ps1' -Recurse -File
})
$failures = @()
foreach ($file in $scripts) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($problem in $parseErrors) {
        $failures += ('{0}:{1}: {2}' -f $file.FullName, $problem.Extent.StartLineNumber, $problem.Message)
    }
}
$jsonFiles = @(foreach ($folder in @('examples', 'schemas', 'evidence')) {
    Get-ChildItem -LiteralPath (Join-Path $repository $folder) -Filter '*.json' -Recurse -File
})
foreach ($file in $jsonFiles) {
    try { Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
    catch { $failures += ('{0}: {1}' -f $file.FullName, $_.Exception.Message) }
}
$documentBlocks = 0
$fence = -join @([char]96, [char]96, [char]96)
$pattern = '(?ms)^' + $fence + 'powershell\s*\r?\n(.*?)^' + $fence
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repository 'docs') -Filter '*.md' -File) {
    foreach ($match in [regex]::Matches([IO.File]::ReadAllText($file.FullName), $pattern)) {
        $documentBlocks++
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($match.Groups[1].Value, [ref]$tokens, [ref]$parseErrors) | Out-Null
        foreach ($problem in $parseErrors) {
            $failures += ('{0}, PowerShell block: {1}' -f $file.FullName, $problem.Message)
        }
    }
}
if ($failures.Count) { throw ($failures -join [Environment]::NewLine) }
[pscustomobject]@{
    Passed = $true
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    ParsedPowerShellFiles = $scripts.Count
    ParsedJsonFiles = $jsonFiles.Count
    ParsedDocumentationBlocks = $documentBlocks
    Limitation = 'Syntax only; JSON Schema and runtime behavior are separate checks.'
}
