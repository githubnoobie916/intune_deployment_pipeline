#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repository=Split-Path -Parent $PSScriptRoot
$files=@(Get-Item -LiteralPath (Join-Path $repository 'README.md'),(Join-Path $repository 'AGENTS.md')) + @(Get-ChildItem -LiteralPath (Join-Path $repository 'docs') -Filter '*.md' -File)
$failures=[Collections.Generic.List[string]]::new();$links=0;$blocks=0
$fence=-join @([char]96,[char]96,[char]96)
foreach ($file in $files) {
    $content=[IO.File]::ReadAllText($file.FullName)
    $prose=[regex]::Replace($content,('(?ms)^'+$fence+'[^\r\n]*\r?\n.*?^'+$fence+'\s*$'),'')
    foreach ($match in [regex]::Matches($prose,'(?<!!)\[[^\]]+\]\(([^)]+)\)')) {
        $target=$match.Groups[1].Value.Trim('<','>')
        if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $target.StartsWith('#')) { continue }
        $path=($target -split '#',2)[0]
        if (-not $path) { continue }
        $links++
        if (-not (Test-Path -LiteralPath (Join-Path $file.DirectoryName ([uri]::UnescapeDataString($path))))) { $failures.Add("Missing local link in $($file.Name): $target") }
    }
    foreach ($match in [regex]::Matches($content,('(?ms)^'+$fence+'powershell\s*\r?\n(.*?)^'+$fence))) {
        $blocks++;$tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseInput($match.Groups[1].Value,[ref]$tokens,[ref]$errors)
        foreach ($error in $errors) { $failures.Add("$($file.Name): $($error.Message)") }
    }
}
if ($failures.Count) { throw ($failures -join [Environment]::NewLine) }
[pscustomobject]@{Passed=$true;Runtime=$PSVersionTable.PSVersion.ToString();Documents=$files.Count;LocalLinks=$links;PowerShellBlocks=$blocks;Limitation='Local target existence and PowerShell parsing only; external links, Markdown anchors and endpoint commands are not executed.'}
