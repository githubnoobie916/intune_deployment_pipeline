#requires -Version 5.1
<# Resolve reviewed local inputs only. No writes, network, installer execution or tenant access. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DefinitionPath,
    [Parameter(Mandatory)][string]$ReleasePath,
    [Parameter(Mandatory)][string]$InstallerPath,
    [Parameter(Mandatory)][string]$EvidencePath,
    [switch]$AllowFixture
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Application.Core.ps1')
. (Join-Path $PSScriptRoot 'Bind-ApplicationDetection.ps1')
$repository = Split-Path -Parent $PSScriptRoot
$definition = Read-AppDefinition $DefinitionPath
$definitionHash = (Get-FileHash -LiteralPath $DefinitionPath).Hash.ToLowerInvariant()
$sourceRoot = Split-Path -Parent (Resolve-Path -LiteralPath $DefinitionPath).ProviderPath
$release = Read-AppJson $ReleasePath
$evidence = Read-AppJson $EvidencePath
Assert-AppJsonSchema $ReleasePath (Join-Path $repository 'schemas/discovered-release.v1.schema.json')
Assert-AppJsonSchema $EvidencePath (Join-Path $repository 'schemas/installer-evidence.v1.schema.json')
$fingerprint = Get-AppDiscoveryFingerprint $definition
if ($release.applicationId -cne $definition.id -or $release.discoveryFingerprint -cne $fingerprint -or
    (Get-AppObjectHash $release.variant) -cne (Get-AppObjectHash $definition.variant) -or
    $release.evergreenModuleVersion -ne $definition.source.moduleVersion -or $release.definitionsRelease -ne $definition.source.definitionsRelease) { throw 'Release discovery identity/selection differs; explicitly rediscover or select its retained definition.' }
if ($definition.variant.versionPolicy -eq 'pinned' -and $definition.variant.targetVersion -cne $release.version) { throw 'Release does not match the explicitly pinned version.' }
Assert-AppDownloadUri $release.sourceUrl $definition.validation.allowedDownloadHosts
Assert-AppDownloadUri $evidence.finalUrl $definition.validation.allowedDownloadHosts
$installer = (Resolve-Path -LiteralPath $InstallerPath).ProviderPath
Assert-AppUnredirectedPath $installer
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Installer must be a regular file.' }
$installerHash = (Get-FileHash -LiteralPath $installer).Hash.ToLowerInvariant()
if ($evidence.applicationId -cne $definition.id -or $evidence.version -cne $release.version -or $evidence.sha256 -ine $installerHash) { throw 'Installer evidence does not match application, version or downloaded bytes.' }
if ($definition.validation.requireVendorSha256 -and $release.vendorSha256 -ine $installerHash) { throw 'Downloaded bytes differ from the recorded vendor SHA256.' }
if ($evidence.identity.productName -cne $definition.validation.expectedProductName -or $evidence.identity.architecture -ne $definition.variant.architecture -or $evidence.identity.version -cne $release.version -or
    ($definition.variant.language -ne 'Multi' -and $evidence.identity.language -cne $definition.variant.language)) { throw 'Reviewed installer identity does not match the application definition.' }
$fixture = [bool]$evidence.fixture
if ($fixture -and -not $AllowFixture) { throw 'Offline fixtures require -AllowFixture and can never be published.' }
$signature = [ordered]@{status='NotCheckedFixture';subject=$null}
if (-not $fixture) {
    $reviewDate = [datetimeoffset]::MinValue
    if ([string]::IsNullOrWhiteSpace($evidence.review.approvedBy) -or $evidence.review.approvedAtUtc -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$' -or
        -not [datetimeoffset]::TryParse($evidence.review.approvedAtUtc, [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$reviewDate)) { throw 'Installer identity requires named, dated engineer review with a valid UTC timestamp ending in Z.' }
    foreach ($property in $definition.validation.msiPropertiesToRecord) {
        if (-not $evidence.identity.msiProperties.PSObject.Properties[$property] -or [string]::IsNullOrWhiteSpace($evidence.identity.msiProperties.$property)) { throw "Required inspected MSI property was not completed: $property" }
    }
    if ($definition.validation.requireAuthenticode) {
        $auth = Get-AuthenticodeSignature -LiteralPath $installer
        if ($auth.Status -ne 'Valid' -or -not $auth.SignerCertificate -or $auth.SignerCertificate.Subject -notin $definition.validation.approvedSignerSubjects) { throw 'Installer Authenticode signature or approved signer does not satisfy policy.' }
        $signature = [ordered]@{status=[string]$auth.Status;subject=$auth.SignerCertificate.Subject}
    } else { $signature.status = 'NotRequired' }
}
$inputs = [Collections.Generic.List[object]]::new()
$actionSources = @{}
foreach ($operation in $definition.actions.PSObject.Properties) {
    foreach ($phase in $operation.Value.PSObject.Properties) {
        $path = Resolve-AppSourcePath $sourceRoot $phase.Value
        $relative = $phase.Value.Replace('\','/')
        if ($actionSources.ContainsKey($relative)) {
            if ($actionSources[$relative] -cne $relative) { throw "Case-aliased action path: $relative" }
            continue
        }
        $actionSources[$relative] = $relative
        $inputs.Add([pscustomobject]@{role='action';source=$path;relativePath=$relative;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();destination=$null})
    }
}
$detectionPath = Resolve-AppSourcePath $sourceRoot $definition.detection.source
$bound = Get-BoundApplicationDetection -SourcePath $detectionPath -Version $release.version
$inputs.Add([pscustomobject]@{role='detection';source=$detectionPath;relativePath=$definition.detection.source;sha256=$bound.SourceSha256;destination=$null})
$destinations = @{}
foreach ($support in $definition.payloads.support) {
    $path = Resolve-AppSourcePath $sourceRoot $support.source
    $destination = 'SupportFiles/' + $support.destination.Replace('\','/')
    $null = Resolve-AppSourcePath -Root $sourceRoot -RelativePath $destination -AllowMissing
    if ($destinations.ContainsKey($destination)) { throw "Duplicate payload destination: $destination" }; $destinations[$destination]=$true
    $inputs.Add([pscustomobject]@{role='support';source=$path;relativePath=$support.source;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();destination=$destination})
}
$inputs.Add([pscustomobject]@{role='installer';source=$installer;relativePath=$definition.payloads.installer.destination;sha256=$installerHash;destination=('Files/'+$definition.payloads.installer.destination)})
$metadata = [ordered]@{
    AppVendor=$definition.publisher;AppName=$definition.productName;AppVersion=$release.version
    AppArch=$definition.variant.architecture;AppLang=$definition.variant.language;AppRevision=$definition.toolkit.packageRevision
    AppSuccessExitCodes=@($definition.toolkit.successExitCodes);AppRebootExitCodes=@($definition.toolkit.rebootExitCodes)
    AppProcessesToClose=@(foreach ($process in $definition.deployment.processes) {
        $nativeProcess = [ordered]@{Name=$process.name}
        if ($process.PSObject.Properties['description']) { $nativeProcess.Description=$process.description }
        $nativeProcess
    })
    AppScriptVersion=$definition.toolkit.scriptVersion;AppScriptDate=$definition.toolkit.scriptDate;AppScriptAuthor=$definition.toolkit.scriptAuthor;RequireAdmin=$definition.toolkit.requireAdmin
}
$profile = [ordered]@{
    name=$definition.toolkit.profile;setupFile='Invoke-AppDeployToolkit.exe'
    installCommand=('Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode '+$definition.deployment.mode)
    uninstallCommand=('Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode '+$definition.deployment.mode)
    context=$definition.deployment.context;architecture=$definition.variant.architecture
    minimumOS=$definition.intune.requirements.minimumSupportedOperatingSystem
    maximumInstallationTimeInMinutes=$definition.intune.maximumInstallationTimeInMinutes
    returnCodes=@($definition.intune.returnCodes);runAs32Bit=$definition.detection.runAs32Bit;enforceSignatureCheck=$definition.detection.enforceSignatureCheck
}
$implementationFiles = @(Get-ChildItem -LiteralPath (Join-Path $repository 'scripts') -Filter '*.ps1' -File) +
    @(Get-ChildItem -LiteralPath (Join-Path $repository 'schemas') -Filter '*.json' -File) +
    @(Get-Item -LiteralPath (Join-Path $repository 'evidence/psadt-4.1.8-release.json')) +
    @(Get-Item -LiteralPath (Join-Path $repository 'evidence/intunewin32app-1.5.0-inspection.json')) +
    @(Get-Item -LiteralPath (Join-Path $repository 'examples/Package-Application.example.ps1'))
$implementations = @(foreach ($file in ($implementationFiles | Sort-Object FullName)) {
    [pscustomobject]@{path=$file.FullName.Substring($repository.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()}
})
$identityInputs = [Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($inputFile in $inputs) {
    $identityInputs[$inputFile.role+'|'+$inputFile.relativePath+'|'+$inputFile.destination] = $inputFile | Select-Object role,relativePath,sha256,destination
}
$identity = [ordered]@{
    applicationId=$definition.id;metadata=$metadata;actions=$definition.actions;profile=$definition.toolkit.profile;mode=$definition.deployment.mode
    inputs=@($identityInputs.Values)
    generatedDetectionSha256=$bound.GeneratedSha256;implementations=$implementations
    dependencyPins=@{evergreen=$definition.source.moduleVersion;definitions=$definition.source.definitionsRelease;psadt=$definition.toolkit.version;intuneWin32App='1.5.0';contentPrep='1.8.7';contentPrepSha256='c1ba45b5cb939e84af064bb7ff4b38fb3dfe33c8dc1078fd9b157672eae671f6'}
}
$resolved = [pscustomobject]@{
    schemaVersion=1;recordType='ResolvedBuild';applicationId=$definition.id;buildId=Get-AppObjectHash $identity;fixture=$fixture
    definitionSha256=$definitionHash;discoveryFingerprint=$fingerprint;release=$release;definition=$definition
    metadata=$metadata;actions=$definition.actions;sourceRoot=$sourceRoot;installerPath=$installer
    inputs=$inputs.ToArray();implementations=$implementations;detection=$bound;profile=$profile;identity=$identity
    publication=@{displayName=$definition.displayName;publisher=$definition.publisher;description=$definition.description;version=$release.version}
    provenance=@{releaseSha256=(Get-FileHash -LiteralPath $ReleasePath).Hash.ToLowerInvariant();installerEvidenceSha256=(Get-FileHash -LiteralPath $EvidencePath).Hash.ToLowerInvariant();authenticode=$signature;policyHash=Get-AppObjectHash $definition.validation}
}
$resolved | Add-Member -NotePropertyName recordHash -NotePropertyValue (Get-AppRecordHash $resolved)
$resolved
