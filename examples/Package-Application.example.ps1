#Requires -Version 5.1
<#
Illustrative local packaging only. Default is preview; -Execute runs the content preparation tool.
Precondition: a populated, validated official PSADT 4.1.8 working copy with approved payloads.
This does not establish installation success and never connects to Intune or assigns an app.
#>
[CmdletBinding(DefaultParameterSetName='Manifest')]
param(
    [Parameter(Mandatory,ParameterSetName='Manifest')][string]$BuildManifestPath,
    [Parameter(Mandatory,ParameterSetName='Legacy')][string]$SourceFolder,
    [Parameter(Mandatory)][string]$OutputFolder,
    [Parameter(Mandatory)][string]$IntuneWin32AppManifestPath,
    [Parameter(ParameterSetName='Manifest')][string]$IntuneWin32AppPackagePath,
    [Parameter(Mandatory)][string]$ContentPrepToolPath,
    [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedContentPrepSha256 = 'c1ba45b5cb939e84af064bb7ff4b38fb3dfe33c8dc1078fd9b157672eae671f6',
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/Application.Core.ps1')
. (Join-Path $PSScriptRoot '../scripts/Artifact.Core.ps1')
$build = $null
if ($PSCmdlet.ParameterSetName -eq 'Manifest') {
    Assert-AppJsonSchema $BuildManifestPath (Join-Path $PSScriptRoot '../schemas/application-build.v1.schema.json')
    $build = Read-AppJson $BuildManifestPath
    Assert-AppRecord $build 'ApplicationBuild'
    if ($build.status -ne 'Complete' -or -not $build.validation.static) { throw 'Packaging requires a complete statically validated build.' }
    if ($build.buildId -cne (Get-AppObjectHash $build.identity)) { throw 'Build identity differs from buildId.' }
    if ($ExpectedContentPrepSha256 -ine $build.identity.dependencyPins.contentPrepSha256) { throw 'Content preparation override differs from the frozen build pin.' }
    foreach ($implementation in $build.implementations) {
        $path = Resolve-AppSourcePath (Split-Path -Parent $PSScriptRoot) $implementation.path
        if ((Get-FileHash -LiteralPath $path).Hash -ine $implementation.sha256) { throw "Packaging implementation changed: $($implementation.path). Resolve and build a new attempt." }
    }
    $SourceFolder = $build.sourceFolder
    $null = Assert-BuildInventory $SourceFolder $build.sourceInventory
    if ((Get-FileHash -LiteralPath $build.detection.path).Hash -ine $build.detection.sha256) { throw 'Detection artifact changed after build.' }
    $profile = $build.profile
    if ($profile.setupFile -cne 'Invoke-AppDeployToolkit.exe') { throw 'Unsupported package entry point.' }
    $buildRecordHash = $build.recordHash
} else {
    # Explicit compatibility interface for earlier direct callers; current app workflow uses Manifest.
    $profile = [pscustomobject]@{setupFile='Invoke-AppDeployToolkit.exe';installCommand='Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Auto';uninstallCommand='Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Auto'}
}
$source = (Resolve-Path -LiteralPath $SourceFolder).Path.TrimEnd('\')
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder).TrimEnd('\')
if ($output -ieq $source -or $output.StartsWith(($source + '\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output must be outside the package source; IntuneWinAppUtil includes all source files.'
}
Assert-AppUnredirectedPath $source
Assert-AppUnredirectedPath $output
foreach ($file in @('Invoke-AppDeployToolkit.exe', 'Invoke-AppDeployToolkit.ps1', 'PSAppDeployToolkit\PSAppDeployToolkit.psd1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)) { throw "Missing package entry/framework file: $file" }
}
$toolkit = Import-PowerShellDataFile -LiteralPath (Join-Path $source 'PSAppDeployToolkit\PSAppDeployToolkit.psd1')
if ($toolkit.ModuleVersion -ne '4.1.8') { throw 'This packaging example is pinned to PSADT 4.1.8.' }
$tokens = $null; $parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'Invoke-AppDeployToolkit.ps1'), [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$module = Import-PowerShellDataFile -LiteralPath $IntuneWin32AppManifestPath
if ($module.ModuleVersion -ne '1.5.0') { throw 'This example was source-checked against IntuneWin32App 1.5.0.' }
if (-not (Test-Path -LiteralPath $ContentPrepToolPath -PathType Leaf)) { throw 'Supply a separately pinned and validated IntuneWinAppUtil.exe.' }
$toolHash = (Get-FileHash -LiteralPath $ContentPrepToolPath -Algorithm SHA256).Hash
if ($toolHash -ine $ExpectedContentPrepSha256) { throw 'Content preparation tool hash differs from the reviewed pin (default: v1.8.7).' }
$expectedModuleBase = Split-Path -Parent (Resolve-Path -LiteralPath $IntuneWin32AppManifestPath).Path
$moduleManifestHash = (Get-FileHash -LiteralPath $IntuneWin32AppManifestPath).Hash.ToLowerInvariant()
if ($null -ne $build) {
    if (-not $IntuneWin32AppPackagePath) { $IntuneWin32AppPackagePath = $expectedModuleBase + '.nupkg' }
    $modulePackageHash = '2cb7137ba5039981d35e43e3cfd7c75128cb37ce1ec1bbf5248376d42cfc738b'
    Assert-AppModuleArchive $expectedModuleBase $IntuneWin32AppPackagePath $modulePackageHash
}
foreach ($loaded in @(Get-Module -Name IntuneWin32App)) {
    if ($loaded.Version -ne [version]'1.5.0' -or $loaded.ModuleBase -ine $expectedModuleBase) {
        throw 'A different IntuneWin32App module is already loaded. Use a fresh PowerShell process.'
    }
}
$plan = [pscustomobject]@{
    operation = 'Create local intunewin package'
    sourceFolder = $source
    setupFile = $profile.setupFile
    expectedOutput = Join-Path $output 'Invoke-AppDeployToolkit.intunewin'
    installCommand = $profile.installCommand
    uninstallCommand = $profile.uninstallCommand
    contentPrepSha256 = $toolHash
    executesInstaller = $false
    changesTenant = $false
}
if (-not $Execute) { $plan; return }
$outputParent = [IO.Path]::GetDirectoryName($output)
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) { throw 'Create the output parent directory before packaging.' }
$lockPath = $output + '.package.lock'
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
if (Test-Path -LiteralPath $output) { throw 'Use a fresh output directory for this build; do not overwrite immutable artifacts.' }
New-Item -Path $output -ItemType Directory | Out-Null
Import-Module -Name $IntuneWin32AppManifestPath -Scope Local -ErrorAction Stop
$package = New-IntuneWin32AppPackage -SourceFolder $source `
    -SetupFile $profile.setupFile -OutputFolder $output -IntuneWinAppUtilPath $ContentPrepToolPath
if (-not (Test-Path -LiteralPath $plan.expectedOutput -PathType Leaf)) { throw 'The expected package was not produced.' }
if ($null -ne $build) {
    if ((Get-FileHash -LiteralPath $ContentPrepToolPath).Hash -ine $toolHash) { throw 'Content preparation tool changed during packaging.' }
    Assert-AppModuleArchive $expectedModuleBase $IntuneWin32AppPackagePath $modulePackageHash
    $current = Read-AppJson $BuildManifestPath
    Assert-AppRecord $current 'ApplicationBuild'
    if ($current.recordHash -cne $buildRecordHash) { throw 'Build manifest changed during packaging.' }
    $null = Assert-BuildInventory $source $build.sourceInventory
    if ((Get-FileHash -LiteralPath $build.detection.path).Hash -ine $build.detection.sha256) { throw 'Detection changed during packaging.' }
    $result = [pscustomobject]@{
        schemaVersion=1;recordType='ApplicationPackage';applicationId=$build.applicationId;buildId=$build.buildId;fixture=[bool]$build.fixture
        buildRecordHash=$buildRecordHash;buildManifestPath=(Resolve-Path -LiteralPath $BuildManifestPath).ProviderPath
        definition=$build.definition;release=$build.release;profile=$build.profile;publication=$build.publication;detection=$build.detection
        packagePath=$plan.expectedOutput;sha256=(Get-FileHash -LiteralPath $plan.expectedOutput).Hash.ToLowerInvariant()
        packagingTools=@{contentPrepPath=(Resolve-Path -LiteralPath $ContentPrepToolPath).ProviderPath;contentPrepSha256=$toolHash.ToLowerInvariant();moduleManifestPath=(Resolve-Path -LiteralPath $IntuneWin32AppManifestPath).ProviderPath;moduleManifestSha256=$moduleManifestHash;moduleVersion=[string]$module.ModuleVersion;moduleArchiveSha256=$modulePackageHash}
        packagingOnly=$true;installationTested=$false
    }
    $result | Add-Member -NotePropertyName recordHash -NotePropertyValue (Get-AppRecordHash $result)
    Write-AppJsonAtomic (Join-Path $output 'package-manifest.json') $result
    $result
    return
}
[pscustomobject]@{
    packagePath = $plan.expectedOutput
    sha256 = (Get-FileHash -LiteralPath $plan.expectedOutput -Algorithm SHA256).Hash
    setupEntryPoint = $plan.setupFile
    installCommand = $plan.installCommand
    uninstallCommand = $plan.uninstallCommand
    packagingOnly = $true
    installationTested = $false
}
} finally {
    $lock.Dispose()
    [IO.File]::Delete($lockPath)
}
