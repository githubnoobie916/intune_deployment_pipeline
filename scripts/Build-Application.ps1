#requires -Version 5.1
<# Offline staging only. Preview reads local inputs; Execute creates a fresh retained build. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResolvedPath,
    [Parameter(Mandatory)][string]$TemplatePath,
    [Parameter(Mandatory)][string]$DestinationPath,
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Application.Core.ps1')
. (Join-Path $PSScriptRoot 'Artifact.Core.ps1')
$repository = Split-Path -Parent $PSScriptRoot
Assert-AppJsonSchema $ResolvedPath (Join-Path $repository 'schemas\resolved-build.v1.schema.json')
$resolved = Read-AppJson $ResolvedPath
Assert-AppRecord $resolved 'ResolvedBuild'
if ($resolved.buildId -cne (Get-AppObjectHash $resolved.identity)) { throw 'Resolved build identity hash differs from buildId.' }
foreach ($field in @('applicationId','metadata','actions','implementations')) {
    if ((Get-AppObjectHash $resolved.$field) -cne (Get-AppObjectHash $resolved.identity.$field)) { throw "Resolved $field differs from its build identity." }
}
if ($resolved.profile.name -cne $resolved.identity.profile -or $resolved.definition.deployment.mode -cne $resolved.identity.mode -or
    $resolved.detection.GeneratedSha256 -cne $resolved.identity.generatedDetectionSha256 -or
    $resolved.metadata.AppVersion -cne $resolved.release.version -or $resolved.detection.Version -cne $resolved.release.version -or $resolved.publication.version -cne $resolved.release.version -or
    $resolved.applicationId -cne $resolved.definition.id -or $resolved.release.applicationId -cne $resolved.applicationId) { throw 'Resolved release, deployment, detection or profile identity differs.' }
$identityInputs = [Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($entry in $resolved.inputs) { $identityInputs[$entry.role+'|'+$entry.relativePath+'|'+$entry.destination] = $entry | Select-Object role,relativePath,sha256,destination }
if ((Get-AppObjectHash @($identityInputs.Values)) -cne (Get-AppObjectHash $resolved.identity.inputs)) { throw 'Resolved inputs differ from the build identity.' }
if ((Get-AppObjectHash $resolved.actions) -cne (Get-AppObjectHash $resolved.definition.actions) -or
    (Get-AppObjectHash $resolved.profile.returnCodes) -cne (Get-AppObjectHash $resolved.definition.intune.returnCodes) -or
    $resolved.profile.enforceSignatureCheck -ne $resolved.definition.detection.enforceSignatureCheck -or
    $resolved.publication.displayName -cne $resolved.definition.displayName -or $resolved.publication.publisher -cne $resolved.definition.publisher -or $resolved.publication.description -cne $resolved.definition.description) { throw 'Resolved settings differ from the frozen application definition.' }
$definition = $resolved.definition
$expectedMetadata = [ordered]@{
    AppVendor=$definition.publisher;AppName=$definition.productName;AppVersion=$resolved.release.version;AppArch=$definition.variant.architecture;AppLang=$definition.variant.language
    AppRevision=$definition.toolkit.packageRevision;AppScriptVersion=$definition.toolkit.scriptVersion;AppScriptDate=$definition.toolkit.scriptDate;AppScriptAuthor=$definition.toolkit.scriptAuthor
    AppSuccessExitCodes=@($definition.toolkit.successExitCodes);AppRebootExitCodes=@($definition.toolkit.rebootExitCodes);RequireAdmin=$definition.toolkit.requireAdmin
    AppProcessesToClose=@(foreach ($process in $definition.deployment.processes) {
        $native = [ordered]@{Name=$process.name}; if ($process.PSObject.Properties['description']) { $native.Description=$process.description }; $native
    })
}
if ((Get-AppObjectHash $resolved.metadata) -cne (Get-AppObjectHash $expectedMetadata)) { throw 'Resolved PSADT metadata differs from the frozen application definition.' }
$resolvedFileHash = (Get-FileHash -LiteralPath $ResolvedPath -Algorithm SHA256).Hash
$template = (Resolve-Path -LiteralPath $TemplatePath).ProviderPath.TrimEnd('\','/')
$destination = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)).TrimEnd('\','/')
if (Test-Path -LiteralPath $destination) { throw 'Destination exists; choose a new build directory. Existing attempts are never overwritten.' }
$parent = [IO.Path]::GetDirectoryName($destination)
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Create the destination parent directory before building.' }
Assert-AppUnredirectedPath $destination
Assert-AppUnredirectedPath $template
if ($destination -ieq $template -or $destination.StartsWith($template + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Build destination must be outside the pristine template.' }
$lockPath = $destination + '.build.lock'
if (Test-Path -LiteralPath $lockPath) { throw 'A build lock exists; reconcile the prior attempt and use a fresh destination.' }

function Assert-BuildInputs {
    if ((Get-FileHash -LiteralPath $ResolvedPath -Algorithm SHA256).Hash -ine $resolvedFileHash) { throw 'Resolved record changed during the build.' }
    foreach ($inputFile in $resolved.inputs) {
        if ($inputFile.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or -not [IO.Path]::IsPathRooted($inputFile.source)) { throw 'Invalid resolved source identity.' }
        Assert-AppUnredirectedPath $inputFile.source
        if ((Get-FileHash -LiteralPath $inputFile.source -Algorithm SHA256).Hash -ine $inputFile.sha256) { throw "Resolved input changed: $($inputFile.relativePath)" }
    }
    foreach ($implementation in $resolved.implementations) {
        $path = Resolve-AppSourcePath $repository $implementation.path
        if ($implementation.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $implementation.sha256) { throw "Build implementation changed: $($implementation.path)" }
    }
}
foreach ($required in @('scripts/Build-Application.ps1','scripts/Application.Core.ps1','scripts/Artifact.Core.ps1','scripts/Populate-PSADTTemplate.ps1','scripts/Bind-ApplicationDetection.ps1','schemas/resolved-build.v1.schema.json','schemas/application-build.v1.schema.json','evidence/psadt-4.1.8-release.json')) {
    if (@($resolved.implementations | Where-Object { $_.path.Replace('\','/') -ieq $required }).Count -ne 1) { throw "Missing unique implementation pin: $required" }
}
Assert-BuildInputs
$pristine = Read-AppJson (Join-Path $repository 'evidence\psadt-4.1.8-release.json')
if ($pristine.version -ne '4.1.8' -or $pristine.archiveSha256 -ne '50cb8d32973fc7648060a48cad63912ecb5caca5a70754f37e83aa06bd380283' -or $pristine.files.Count -ne 222) { throw 'Unexpected trusted PSADT release manifest.' }
$null = Assert-BuildInventory $template $pristine.files
$inputLookup = @{}; $payloadLookup = @{}
foreach ($inputFile in $resolved.inputs) {
    if ($inputFile.role -notin @('action','detection','support','installer')) { throw "Unsupported resolved input role: $($inputFile.role)" }
    $relative = $inputFile.relativePath.Replace('\','/')
    $null = Resolve-AppSourcePath (Join-Path $destination 'Inputs\application') $relative -AllowMissing
    if ($inputLookup.ContainsKey($relative) -or $relative -in @('metadata.generated.json','actions.generated.json')) { throw "Duplicate or reserved source path: $relative" }
    $inputLookup[$relative] = $inputFile
    if ($inputFile.role -in @('installer','support')) {
        $expectedPrefix = if ($inputFile.role -eq 'installer') { 'Files/' } else { 'SupportFiles/' }
        $payload = [string]$inputFile.destination
        if (-not $payload.StartsWith($expectedPrefix, [StringComparison]::Ordinal)) { throw 'Payload destination does not match its input role.' }
        $null = Resolve-AppSourcePath (Join-Path $destination 'Source') $payload -AllowMissing
        if ($payloadLookup.ContainsKey($payload) -or @($pristine.files | Where-Object { $_.path -ieq $payload }).Count) { throw "Payload collides with another payload or upstream file: $payload" }
        $payloadLookup[$payload] = $inputFile
    } elseif ($null -ne $inputFile.destination) { throw 'Actions and detection cannot be staged as payloads.' }
}
if (@($resolved.inputs | Where-Object role -eq 'installer').Count -ne 1 -or @($resolved.inputs | Where-Object role -eq 'detection').Count -ne 1) { throw 'This build profile requires exactly one installer and detection source.' }
foreach ($operation in $resolved.actions.PSObject.Properties) {
    foreach ($phase in $operation.Value.PSObject.Properties) {
        $reference = ([string]$phase.Value).Replace('\','/')
        if (-not $inputLookup.ContainsKey($reference) -or $inputLookup[$reference].role -ne 'action') { throw "Action source is absent from the frozen inventory: $reference" }
    }
}
. (Join-Path $PSScriptRoot 'Bind-ApplicationDetection.ps1')
$detectionInput = @($resolved.inputs | Where-Object role -eq 'detection')[0]
$bound = Get-BoundApplicationDetection -SourcePath $detectionInput.source -Version $resolved.detection.Version
if ($bound.SourceSha256 -ine $resolved.detection.SourceSha256 -or $bound.GeneratedSha256 -ine $resolved.detection.GeneratedSha256 -or $bound.Text -cne $resolved.detection.Text) { throw 'Frozen detection binding differs from the reviewed source.' }
if (-not $Execute) {
    [pscustomobject]@{operation='BuildApplication';executed=$false;buildId=$resolved.buildId;applicationId=$resolved.applicationId;fixture=[bool]$resolved.fixture;destination=$destination;sourceFileCount=($pristine.files.Count + $payloadLookup.Count);changesTenant=$false;executesDeployment=$false}
    return
}
$lock = $null
try {
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $lockBytes = [Text.UTF8Encoding]::new($false).GetBytes("BuildId=$($resolved.buildId)`nDestination=$destination`nProcessId=$PID")
    $lock.Write($lockBytes, 0, $lockBytes.Length); $lock.Flush()
    if (Test-Path -LiteralPath $destination) { throw 'Another operation created the destination; use a fresh directory.' }
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    Write-AppJsonAtomic (Join-Path $destination 'build-attempt.json') ([pscustomobject]@{recordType='ApplicationBuildAttempt';buildId=$resolved.buildId;startedAtUtc=[datetime]::UtcNow.ToString('o');completionRecord='build-manifest.json';note='Incomplete unless a valid completion record exists. Retain failed attempts for review.'})
    $inputRoot = Join-Path $destination 'Inputs'
    $applicationRoot = Join-Path $inputRoot 'application'
    [IO.Directory]::CreateDirectory($applicationRoot) | Out-Null
    $snapshots = [Collections.Generic.List[object]]::new()
    foreach ($inputFile in $resolved.inputs) {
        $copyPath = Resolve-AppSourcePath $applicationRoot $inputFile.relativePath -AllowMissing
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($copyPath)) | Out-Null
        [IO.File]::Copy($inputFile.source, $copyPath, $false)
        if ((Get-FileHash -LiteralPath $copyPath -Algorithm SHA256).Hash -ine $inputFile.sha256) { throw "Snapshot copy differs: $($inputFile.relativePath)" }
        $snapshots.Add([pscustomobject]@{role=$inputFile.role;path=$copyPath;relativePath=$inputFile.relativePath;sha256=$inputFile.sha256;originalSource=$inputFile.source})
    }
    $metadataPath = Join-Path $applicationRoot 'metadata.generated.json'
    $actionsPath = Join-Path $applicationRoot 'actions.generated.json'
    Write-AppJsonAtomic $metadataPath $resolved.metadata
    Write-AppJsonAtomic $actionsPath $resolved.actions
    Write-AppJsonAtomic (Join-Path $inputRoot 'resolved.json') $resolved
    $sourceFolder = Join-Path $destination 'Source'
    $adapterResult = & (Join-Path $PSScriptRoot 'Populate-PSADTTemplate.ps1') -TemplatePath $template -DestinationPath $sourceFolder -MetadataPath $metadataPath -ActionsPath $actionsPath -OmitCompletionPrompt -ValidateNativeApplicationCommands
    if (-not $adapterResult.Passed) { throw 'Template adapter did not confirm structural validation.' }
    Write-AppJsonAtomic (Join-Path $destination 'template-validation.json') $adapterResult
    $expected = [Collections.Generic.List[object]]::new()
    foreach ($entry in $pristine.files) {
        $hash = if ($entry.path -eq 'Invoke-AppDeployToolkit.ps1') { $adapterResult.GeneratedScriptSha256 } else { $entry.sha256 }
        $expected.Add([pscustomobject]@{path=$entry.path;sha256=$hash})
    }
    foreach ($payloadPath in $payloadLookup.Keys) {
        $inputFile = $payloadLookup[$payloadPath]
        $copyPath = Resolve-AppSourcePath $sourceFolder $payloadPath -AllowMissing
        if (Test-Path -LiteralPath $copyPath) { throw "Payload would overwrite generated or upstream content: $payloadPath" }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($copyPath)) | Out-Null
        $snapshotPath = Resolve-AppSourcePath $applicationRoot $inputFile.relativePath
        [IO.File]::Copy($snapshotPath, $copyPath, $false)
        $expected.Add([pscustomobject]@{path=$payloadPath;sha256=$inputFile.sha256})
    }
    $detectionPath = Join-Path $destination 'Detect.ps1'
    [IO.File]::WriteAllText($detectionPath, $bound.Text, [Text.UTF8Encoding]::new($true, $true))
    if ((Get-FileHash -LiteralPath $detectionPath -Algorithm SHA256).Hash -ine $bound.GeneratedSha256) { throw 'Written detection differs from the frozen binding.' }
    foreach ($snapshot in $snapshots) {
        Assert-AppUnredirectedPath $snapshot.path
        if ((Get-FileHash -LiteralPath $snapshot.path -Algorithm SHA256).Hash -ine $snapshot.sha256) { throw "Input snapshot changed during staging: $($snapshot.relativePath)" }
    }
    $sourceInventory = @(Assert-BuildInventory $sourceFolder $expected.ToArray())
    $null = Assert-BuildInventory $template $pristine.files
    Assert-BuildInputs
    $manifest = [pscustomobject]@{
        schemaVersion=1;recordType='ApplicationBuild';status='Complete';buildId=$resolved.buildId;applicationId=$resolved.applicationId;fixture=[bool]$resolved.fixture
        definitionSha256=$resolved.definitionSha256;discoveryFingerprint=$resolved.discoveryFingerprint
        definition=$resolved.definition;release=$resolved.release;profile=$resolved.profile;publication=$resolved.publication;identity=$resolved.identity
        inputs=$resolved.inputs;inputSnapshots=$snapshots.ToArray();implementations=$resolved.implementations;provenance=$resolved.provenance
        sourceFolder=$sourceFolder;sourceInventory=$sourceInventory
        detection=[pscustomobject]@{path=$detectionPath;sha256=$bound.GeneratedSha256;sourceSha256=$bound.SourceSha256;version=$bound.Version}
        templateValidationPath=(Join-Path $destination 'template-validation.json');createdAtUtc=[datetime]::UtcNow.ToString('o')
        validation=[pscustomobject]@{static=$true;endpoint=$false;business=$false;packaging=$false;tenant=$false}
    }
    $manifest | Add-Member -NotePropertyName recordHash -NotePropertyValue (Get-AppRecordHash $manifest)
    $candidateManifestPath = Join-Path $destination 'build-manifest.candidate.json'
    Write-AppJsonAtomic $candidateManifestPath $manifest
    Assert-AppJsonSchema $candidateManifestPath (Join-Path $repository 'schemas\application-build.v1.schema.json')
    Assert-AppRecord (Read-AppJson $candidateManifestPath) 'ApplicationBuild'
    [IO.File]::Move($candidateManifestPath, (Join-Path $destination 'build-manifest.json'))
    return $manifest
} finally {
    if ($null -ne $lock) {
        $lock.Dispose()
        Assert-AppUnredirectedPath $lockPath
        Remove-Item -LiteralPath $lockPath -ErrorAction Stop
    }
}
