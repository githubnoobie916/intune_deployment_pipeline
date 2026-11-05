#requires -Version 5.1
# Deliberately fake installer bytes. Only called by offline tests; never publish these artifacts.
function New-ApplicationTestInputs([string]$Root, [string]$Application = 'firefox', [switch]$IncludeSupport) {
    $repository = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repository 'scripts/Application.Core.ps1')
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    $originalRoot = Join-Path $repository ('examples/apps/'+$Application)
    $definition = Read-AppDefinition (Join-Path $originalRoot 'app.json')
    $applicationRoot = Join-Path $Root 'application'
    [IO.Directory]::CreateDirectory($applicationRoot) | Out-Null
    $sourcePaths = @($definition.detection.source) + @($definition.payloads.support | ForEach-Object source) + @(
        foreach ($operation in $definition.actions.PSObject.Properties) { foreach ($phase in $operation.Value.PSObject.Properties) { $phase.Value } }
    )
    foreach ($relative in @($sourcePaths | Select-Object -Unique)) {
        $source = Resolve-AppSourcePath $originalRoot $relative
        $target = Resolve-AppSourcePath $applicationRoot $relative -AllowMissing
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.File]::Copy($source, $target, $false)
    }
    if ($IncludeSupport) {
        $supportPath = Join-Path $applicationRoot 'fixture-support.txt'
        [IO.File]::WriteAllText($supportPath, 'OFFLINE FIXTURE SUPPORT DATA')
        $definition.payloads.support = @($definition.payloads.support) + @([pscustomobject]@{source='fixture-support.txt';destination='fixture-support.txt'})
    }
    $definitionPath = Join-Path $applicationRoot 'app.json'
    Write-AppJsonAtomic $definitionPath $definition
    $version = if ($Application -eq 'firefox') { '159.0.1' } else { '8.9.8.1' }
    $payload = Join-Path $Root $definition.payloads.installer.destination
    [IO.File]::WriteAllText($payload, 'OFFLINE FIXTURE ONLY - NOT AN INSTALLER')
    $sha = (Get-FileHash -LiteralPath $payload).Hash.ToLowerInvariant()
    $release = [pscustomobject]@{
        schemaVersion=1;recordType='DiscoveredRelease';applicationId=$definition.id;definitionSha256=(Get-FileHash -LiteralPath $definitionPath).Hash.ToLowerInvariant()
        discoveryFingerprint=Get-AppDiscoveryFingerprint $definition;version=$version;sourceUrl=('https://'+$definition.validation.allowedDownloadHosts[0]+'/offline-fixture');vendorSha256=$sha
        variant=$definition.variant;evergreenModuleVersion=$definition.source.moduleVersion;definitionsRelease=$definition.source.definitionsRelease
        discoveredAtUtc='2026-11-05T00:00:00Z';rawMetadata=@{}
    }
    $evidence = [pscustomobject]@{
        schemaVersion=1;recordType='InstallerEvidence';fixture=$true;applicationId=$definition.id;version=$version;sha256=$sha
        finalUrl=$release.sourceUrl;identity=@{productName=$definition.validation.expectedProductName;architecture='x64';version=$version;language=$definition.variant.language;msiProperties=@{}}
        review=@{approvedBy='Offline fixture';approvedAtUtc='2026-11-05T00:00:00Z'}
    }
    $releasePath=Join-Path $Root 'release.json';$evidencePath=Join-Path $Root 'installer-evidence.json'
    Write-AppJsonAtomic $releasePath $release;Write-AppJsonAtomic $evidencePath $evidence
    $resolved = & (Join-Path $repository 'scripts/Resolve-Application.ps1') -DefinitionPath $definitionPath -ReleasePath $releasePath -InstallerPath $payload -EvidencePath $evidencePath -AllowFixture
    $resolvedPath=Join-Path $Root 'resolved.json';Write-AppJsonAtomic $resolvedPath $resolved
    [pscustomobject]@{Resolved=$resolved;ResolvedPath=$resolvedPath;Root=$Root;ApplicationRoot=$applicationRoot;DefinitionPath=$definitionPath;InstallerPath=$payload;ReleasePath=$releasePath;EvidencePath=$evidencePath}
}
function New-ApplicationTestBuild([string]$Root, [string]$Application = 'firefox') {
    $repository = Split-Path -Parent $PSScriptRoot
    $fixture = New-ApplicationTestInputs -Root $Root -Application $Application
    $build = & (Join-Path $repository 'scripts/Build-Application.ps1') -ResolvedPath $fixture.ResolvedPath -TemplatePath (Join-Path $repository '.research/psadt/pristine') -DestinationPath (Join-Path $Root 'build') -Execute
    [pscustomobject]@{Build=$build;BuildManifestPath=(Join-Path $Root 'build/build-manifest.json');ResolvedPath=$fixture.ResolvedPath;Root=$Root}
}
