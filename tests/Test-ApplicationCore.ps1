#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/Application.Core.ps1')
$checks = 0
function Assert-Core($Condition, $Message) {
    if (-not $Condition) { throw $Message }; $script:checks++
}
$a = [pscustomobject]@{ z = @('one', 'two'); a = [pscustomobject]@{ second = 2; first = $true } }
$b = [pscustomobject]@{ a = [pscustomobject]@{ first = $true; second = 2 }; z = @('one', 'two') }
Assert-Core ((Get-AppObjectHash $a) -eq (Get-AppObjectHash $b)) 'Property ordering changes identity.'
Assert-Core ((Get-AppObjectHash @{a=@('one')}) -ne (Get-AppObjectHash @{a='one'})) 'Array identity collapsed to scalar.'
Assert-Core ((Get-AppObjectHash @{a=@()}) -ne (Get-AppObjectHash @{a=$null})) 'Empty array identity collapsed to null.'
Assert-Core ((Get-AppObjectHash @{}) -ne (Get-AppObjectHash @())) 'Empty object collapsed to array.'
Assert-Core ((ConvertTo-AppCanonicalJson @{name="O'Connor"}) -ceq '{"name":"O''Connor"}') 'Canonical JSON apostrophe escaped differently.'
Assert-Core ((Get-AppObjectHash @{name="O'Connor"}) -ceq '20d64937d11417a273e637646d521d370295e11ace2788af1c8844d273253ec2') 'Canonical shared fixture hash differs.'
Assert-Core ((ConvertTo-AppCanonicalJson ([double]::Parse('0.84551240822557006', [cultureinfo]::InvariantCulture))) -ceq '0.84551240822557006') 'Canonical floating point representation differs.'
$file = Resolve-AppSourcePath -Root $root -RelativePath 'examples/apps/firefox/Install.ps1'
Assert-Core ((Test-Path -LiteralPath $file -PathType Leaf)) 'Contained source missing.'
foreach ($bad in @('../outside.ps1', 'C:\outside.ps1', 'examples/apps/firefox/Install.ps1:stream', 'folder//alias', 'folder./alias', 'folder /alias', 'NUL.txt')) {
    $rejected = $false
    try { Resolve-AppSourcePath -Root $root -RelativePath $bad -AllowMissing | Out-Null } catch { $rejected = $true }
    Assert-Core $rejected "Unsafe path accepted: $bad"
}
$roundTripPath = Join-Path $root ('.validation/core-' + [guid]::NewGuid().ToString('N') + '.json')
$record = [pscustomobject]@{schemaVersion=1;recordType='Test';at='2026-11-05T00:00:00Z';empty=@();nested=@{a='value'}}
$record | Add-Member generatedPath (Join-Path $root 'Detect.ps1')
$record | Add-Member recordHash (Get-AppRecordHash $record)
Write-AppJsonAtomic $roundTripPath $record
Assert-AppRecord (Read-AppJson $roundTripPath) 'Test'
$checks++
[pscustomobject]@{ Passed=$true; Checks=$checks; Runtime=$PSVersionTable.PSVersion.ToString() }
