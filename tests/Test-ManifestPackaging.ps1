#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('firefox','notepadplusplus')][string]$Application='firefox')
$ErrorActionPreference='Stop'
$repository=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'ApplicationTest.Fixtures.ps1')
. (Join-Path $repository 'scripts/Application.Core.ps1')
$root=Join-Path $repository ('.validation/packaging-'+[guid]::NewGuid().ToString('N'))
$fixture=New-ApplicationTestBuild $root $Application
$packagingTestState=@{Calls=0;AllowExecution=$false}
function Import-Module { $packagingTestState.Calls++; if (-not $packagingTestState.AllowExecution) { throw 'Preview imported a module.' } }
function New-IntuneWin32AppPackage {
    param($SourceFolder,$SetupFile,$OutputFolder,$IntuneWinAppUtilPath)
    $packagingTestState.Calls++
    if (-not $packagingTestState.AllowExecution) { throw 'Preview executed packaging.' }
    [IO.File]::WriteAllText((Join-Path $OutputFolder 'Invoke-AppDeployToolkit.intunewin'), 'MOCK PACKAGE - NOT INTUNE CONTENT')
}
$arguments=@{BuildManifestPath=$fixture.BuildManifestPath;OutputFolder=(Join-Path $root 'package');IntuneWin32AppManifestPath=(Join-Path $repository '.research/intune/IntuneWin32App.1.5.0/IntuneWin32App.psd1');ContentPrepToolPath=(Join-Path $repository '.research/intune/IntuneWinAppUtil-1.8.7.exe')}
$packager=Join-Path $repository 'examples/Package-Application.example.ps1'
$preview=& $packager @arguments
if ($packagingTestState.Calls -ne 0 -or (Test-Path -LiteralPath $arguments.OutputFolder) -or $preview.installCommand -cne $fixture.Build.profile.installCommand) { throw 'Packaging preview crossed its boundary or ignored effective settings.' }
$moduleCopy=Join-Path $root 'module-copy'
Copy-Item -LiteralPath (Split-Path -Parent $arguments.IntuneWin32AppManifestPath) -Destination $moduleCopy -Recurse
[IO.File]::AppendAllText((Join-Path $moduleCopy 'Public/New-IntuneWin32AppPackage.ps1'), "`r`n# unexpected local change")
$savedModule=$arguments.IntuneWin32AppManifestPath
$arguments.IntuneWin32AppManifestPath=Join-Path $moduleCopy 'IntuneWin32App.psd1'
$rejected=$false
try { & $packager @arguments -IntuneWin32AppPackagePath (Join-Path $repository '.research/intune/IntuneWin32App.1.5.0.nupkg') | Out-Null } catch { if ($_.Exception.Message -notmatch 'Module content differs') { throw }; $rejected=$true }
if (-not $rejected -or $packagingTestState.Calls -ne 0) { throw 'Modified published module was accepted.' }
$arguments.IntuneWin32AppManifestPath=$savedModule
$packagingTestState.AllowExecution=$true
$package=& $packager @arguments -Execute
if (-not $package.fixture -or $package.buildId -ne $fixture.Build.buildId -or -not (Test-Path -LiteralPath (Join-Path $arguments.OutputFolder 'package-manifest.json'))) { throw 'Packaging result lost frozen build or fixture state.' }
Assert-AppRecord (Read-AppJson (Join-Path $arguments.OutputFolder 'package-manifest.json')) 'ApplicationPackage'
$packagingTestState.AllowExecution=$false
$request=& (Join-Path $repository 'scripts/Prepare-ApplicationPublication.ps1') -PackageManifestPath (Join-Path $arguments.OutputFolder 'package-manifest.json')
if ($request.ready -or -not $request.fixture -or $request.buildId -cne $package.buildId) { throw 'Fixture package lost its readiness boundary.' }
$requestPath=Join-Path $root 'publication-request.json'
Write-AppJsonAtomic $requestPath $request
$calls=$packagingTestState.Calls
$publishPreview=& (Join-Path $repository 'examples/Publish-Unassigned.example.ps1') -RequestPath $requestPath
if ($publishPreview.Ready -or $publishPreview.InstallCommandLine -cne $package.profile.installCommand -or $packagingTestState.Calls -ne $calls) { throw 'Frozen publication preview drifted or imported a module.' }
$rejected=$false
try { & (Join-Path $repository 'examples/Publish-Unassigned.example.ps1') -RequestPath $requestPath -Execute | Out-Null } catch { if ($_.Exception.Message -notmatch 'non-fixture request') { throw }; $rejected=$true }
if (-not $rejected -or $packagingTestState.Calls -ne $calls) { throw 'Fixture reached publication execution.' }
$arguments.OutputFolder=Join-Path $root 'locked-output'
$lockPath=$arguments.OutputFolder+'.package.lock'
[IO.File]::WriteAllText($lockPath,'TEST LOCK')
try {
    $rejected=$false
    try { & $packager @arguments -Execute | Out-Null } catch { if ($_.Exception.Message -notmatch 'already exists') { throw }; $rejected=$true }
    if (-not $rejected -or $packagingTestState.Calls -ne $calls -or (Test-Path $arguments.OutputFolder)) { throw 'A competing package lock was ignored.' }
} finally { [IO.File]::Delete($lockPath) }
$arguments.OutputFolder=Join-Path $root 'changed-detector'
$detectorBytes=[IO.File]::ReadAllBytes($fixture.Build.detection.path)
try {
    [IO.File]::AppendAllText($fixture.Build.detection.path,'# edited')
    $rejected=$false
    try { & $packager @arguments -Execute | Out-Null } catch { if ($_.Exception.Message -notmatch 'Detection artifact changed') { throw }; $rejected=$true }
    if (-not $rejected -or $packagingTestState.Calls -ne $calls) { throw 'Changed detector reached the tool.' }
} finally { [IO.File]::WriteAllBytes($fixture.Build.detection.path,$detectorBytes) }
$arguments.OutputFolder=Join-Path $root 'tampered-output'
[IO.File]::WriteAllText((Join-Path $fixture.Build.sourceFolder 'unexpected.txt'),'tampered')
$calls=$packagingTestState.Calls;$rejected=$false
try { & $packager @arguments -Execute | Out-Null } catch { $rejected=$true }
if (-not $rejected -or $calls -ne $packagingTestState.Calls -or (Test-Path -LiteralPath $arguments.OutputFolder)) { throw 'Source inventory drift reached packaging execution.' }
$summary=[pscustomobject]@{Passed=$true;Checks=11;Application=$Application;Runtime=$PSVersionTable.PSVersion.ToString();Root=$root;Limitation='Actual template/build with fake installer and mocked package tool; no real packaging or tenant calls.'}
Write-AppJsonAtomic (Join-Path $root 'results.json') $summary
$summary
