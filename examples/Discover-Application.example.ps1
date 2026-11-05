#Requires -Version 5.1
<#
Explicit discovery contacts vendor services and optionally writes one immutable local record.
It does not download installers, update definitions, import IntuneWin32App, or call Graph.
Requires a version 3 app.json, trusted Evergreen 2610.2859.0 and definitions v26.11.03.146.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][Alias('RecipePath')][string]$DefinitionPath,
    [Parameter(Mandatory)][string]$EvergreenManifestPath,
    [Parameter(Mandatory)][string]$DefinitionsPath,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/Application.Core.ps1')
$definitionHash = (Get-FileHash -LiteralPath $DefinitionPath -Algorithm SHA256).Hash.ToLowerInvariant()
$definition = Read-AppDefinition $DefinitionPath
if ((Get-FileHash -LiteralPath $DefinitionPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $definitionHash) { throw 'Application definition changed during validation; retry from a stable reviewed input.' }
$selection = Get-AppSelection $definition
$fingerprint = Get-AppDiscoveryFingerprint $definition
$moduleData = Import-PowerShellDataFile -LiteralPath $EvergreenManifestPath
if ($moduleData.ModuleVersion -ne $definition.source.moduleVersion) { throw 'Evergreen version mismatch.' }
if ($definition.source.definitionsRelease -cne 'v26.11.03.146') { throw 'Review discovery for a new definitions release.' }
$definitionCache = (Resolve-Path -LiteralPath $DefinitionsPath).ProviderPath
if (-not (Test-Path -LiteralPath $definitionCache -PathType Container)) { throw 'DefinitionsPath must be the reviewed definition directory.' }
if (Test-Path -LiteralPath (Join-Path $definitionCache 'Filters')) { throw 'Unexpected local filters can change discovery output; use the isolated pristine definition snapshot.' }
$resolvedOutput = $null
if ($OutputPath) {
    $resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    if (Test-Path -LiteralPath $resolvedOutput) { throw 'Output exists; preserve the prior discovery record.' }
    Assert-AppUnredirectedPath $resolvedOutput
}
$priorCachePath = [Environment]::GetEnvironmentVariable('EVERGREEN_APPS_PATH', 'Process')
try {
    $env:EVERGREEN_APPS_PATH = $definitionCache
    Import-Module -Name $EvergreenManifestPath -Scope Local -ErrorAction Stop
    $query = @{Name=$definition.source.application}
    if ($definition.source.parameterMap.PSObject.Properties['Language']) {
        $query.AppParams = @{Language=[string[]]@($definition.variant.($definition.source.parameterMap.Language))}
    }
    # Do not request verbose provider output: the inspected release can print request headers.
    $candidates = @(Get-EvergreenApp @query)
    $selected = @($candidates | Where-Object {
        $candidate = $_
        $matches = $true
        foreach ($filter in $selection.GetEnumerator()) {
            $propertyName = if ($filter.Key -ceq 'UriSuffix') { 'URI' } else { $filter.Key }
            $property = $candidate.PSObject.Properties[$propertyName]
            if ($null -eq $property -or $property.Value -isnot [string]) { $matches = $false; continue }
            if ($filter.Key -ceq 'UriSuffix') {
                if (-not $property.Value.EndsWith([string]$filter.Value, [StringComparison]::OrdinalIgnoreCase)) { $matches = $false }
            } elseif ($property.Value -ine [string]$filter.Value) { $matches = $false }
        }
        $matches
    })
    if ($selected.Count -ne 1) { throw "Expected exactly one installer; found $($selected.Count)." }
    $item = $selected[0]
    $versionProperty = $item.PSObject.Properties['Version']
    $version = if ($versionProperty) { [string]$versionProperty.Value } else { '' }
    $parsedVersion = $null
    if ($version -notmatch '^[0-9]+(?:\.[0-9]+){1,3}$' -or -not [version]::TryParse($version, [ref]$parsedVersion)) { throw 'Discovery returned no supported numeric release version.' }
    if ($definition.variant.versionPolicy -ceq 'pinned' -and $version -cne $definition.variant.targetVersion) {
        throw 'The pinned version is not the current discovery result. Use its retained approved release record/artifact; discovery does not locate historical installers.'
    }
    $uriProperty = $item.PSObject.Properties['URI']
    if (-not $uriProperty -or $uriProperty.Value -isnot [string]) { throw 'The selected installer has no usable download URL.' }
    Assert-AppDownloadUri -Value $uriProperty.Value -AllowedHosts $definition.validation.allowedDownloadHosts
    $shaProperty = $item.PSObject.Properties['Sha256']
    $vendorSha = if ($shaProperty -and -not [string]::IsNullOrWhiteSpace([string]$shaProperty.Value)) { [string]$shaProperty.Value } else { $null }
    if (($null -ne $vendorSha -and $vendorSha -notmatch '^[0-9a-fA-F]{64}$') -or ($definition.validation.requireVendorSha256 -and $null -eq $vendorSha)) { throw 'The application definition requires a valid independently recorded vendor SHA256.' }
    $rawMetadata = [ordered]@{}
    foreach ($field in @('Version','Architecture','Type','Channel','Language','InstallerType','Sha256')) {
        $property = $item.PSObject.Properties[$field]
        if ($property) {
            if ($null -ne $property.Value -and $property.Value -isnot [string]) { throw "Provider metadata must be a string or null: $field" }
            $rawMetadata[$field] = $property.Value
        }
    }
    if ((Get-FileHash -LiteralPath $DefinitionPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $definitionHash) { throw 'Application definition changed during discovery; discard the result and retry from a stable reviewed input.' }
    $release = [pscustomobject]@{
        schemaVersion=1;recordType='DiscoveredRelease';applicationId=$definition.id
        definitionSha256=$definitionHash;discoveryFingerprint=$fingerprint
        version=$version;sourceUrl=$uriProperty.Value;vendorSha256=$vendorSha
        variant=$definition.variant;evergreenModuleVersion=[string]$moduleData.ModuleVersion
        definitionsRelease=$definition.source.definitionsRelease;discoveredAtUtc=[DateTime]::UtcNow.ToString('o')
        rawMetadata=[pscustomobject]$rawMetadata
    }
    if ($resolvedOutput) { Write-AppJsonAtomic -Path $resolvedOutput -Value $release }
    $release
} finally {
    [Environment]::SetEnvironmentVariable('EVERGREEN_APPS_PATH', $priorCachePath, 'Process')
}
