#requires -Version 5.1
# Resolves the same synthetic local inputs in two fresh processes. Never executes a deployment.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repository=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'ApplicationTest.Fixtures.ps1')
. (Join-Path $repository 'scripts/Application.Core.ps1')
$root=Join-Path $repository ('.validation/cross-runtime-'+[guid]::NewGuid().ToString('N'))
$fixture=New-ApplicationTestInputs $root
$driver=Join-Path $root 'resolve-child.ps1'
$source=@'
param($Repository,$InputRoot,$OutputPath,$PeerPath,[switch]$VerifyOnly)
$ErrorActionPreference='Stop'
. (Join-Path $Repository 'scripts/Application.Core.ps1')
if ($PeerPath) { Assert-AppRecord (Read-AppJson $PeerPath) 'ResolvedBuild' }
if ($VerifyOnly) { return }
$record=& (Join-Path $Repository 'scripts/Resolve-Application.ps1') -DefinitionPath (Join-Path $InputRoot 'application/app.json') -ReleasePath (Join-Path $InputRoot 'release.json') -InstallerPath (Join-Path $InputRoot 'Firefox.msi') -EvidencePath (Join-Path $InputRoot 'installer-evidence.json') -AllowFixture
Write-AppJsonAtomic $OutputPath $record
'@
[IO.File]::WriteAllText($driver,$source,[Text.UTF8Encoding]::new($true))
$ps7=Join-Path $root 'ps7.json';$ps5=Join-Path $root 'ps5.json'
& pwsh.exe -NoProfile -NonInteractive -File $driver -Repository $repository -InputRoot $root -OutputPath $ps7
if ($LASTEXITCODE) { throw 'PowerShell 7 resolution failed.' }
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $driver -Repository $repository -InputRoot $root -OutputPath $ps5 -PeerPath $ps7
if ($LASTEXITCODE) { throw 'PowerShell 5 resolution or PS7 record verification failed.' }
& pwsh.exe -NoProfile -NonInteractive -File $driver -Repository $repository -InputRoot $root -PeerPath $ps5 -VerifyOnly
if ($LASTEXITCODE) { throw 'PowerShell 7 could not verify the PS5 record.' }
$a=Read-AppJson $ps7;$b=Read-AppJson $ps5
if ($a.buildId -cne $b.buildId -or $a.recordHash -cne $b.recordHash) { throw 'Identical inputs produced different build or record identity across runtimes.' }
$summary=[pscustomobject]@{Passed=$true;Checks=3;Runtime=$PSVersionTable.PSVersion.ToString();Root=$root;BuildId=$a.buildId;RecordHash=$a.recordHash;Limitation='Same fake inputs resolved in PS5 and PS7 and each engine verified the other record; no build or endpoint execution.'}
Write-AppJsonAtomic (Join-Path $root 'results.json') $summary
$summary
