#requires -Version 5.1
<# Reads frozen local package/evidence inputs. Returns a request; never writes files, imports a module, authenticates or contacts Intune. Explicit SignedDetectionPath additionally checks Authenticode. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageManifestPath,
    [string]$AcceptancePath,
    [string]$SignedDetectionPath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Application.Core.ps1')
function Assert-PublicationFile([string]$Path,[string]$Hash) {
    Assert-AppUnredirectedPath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or $Hash -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Hash) { throw "Publication artifact/evidence hash mismatch: $Path" }
}
function Assert-PublicationReviewer($Review,[string]$Label) {
    $date=[datetimeoffset]::MinValue
    if ([string]::IsNullOrWhiteSpace([string]$Review.approvedBy) -or [string]::IsNullOrWhiteSpace([string]$Review.approvedAtUtc) -or -not [datetimeoffset]::TryParse([string]$Review.approvedAtUtc,[cultureinfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)) { throw "Named and dated approval is required: $Label" }
}
$manifestPath=(Resolve-Path -LiteralPath $PackageManifestPath).ProviderPath
Assert-AppUnredirectedPath $manifestPath
$manifestHash=(Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant()
$package=Read-AppJson $manifestPath
Assert-AppRecord $package 'ApplicationPackage'
if ($package.applicationId -cne $package.definition.id -or $package.applicationId -cne $package.release.applicationId -or $package.buildId -notmatch '^[a-f0-9]{64}$' -or $package.publication.version -cne $package.release.version) { throw 'Package application/release identity is inconsistent.' }
$profile=$package.profile
if ($profile.name -cne 'official-4.1.8-native-v2' -or $profile.setupFile -cne 'Invoke-AppDeployToolkit.exe' -or $profile.installCommand -cne 'Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Auto' -or $profile.uninstallCommand -cne 'Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Auto' -or $profile.context -cne 'system' -or $profile.architecture -cne 'x64' -or $profile.minimumOS -cne 'W11_22H2' -or $profile.maximumInstallationTimeInMinutes -ne 120 -or $profile.runAs32Bit) { throw 'Unsupported frozen publication profile.' }
if ($package.publication.displayName -cne $package.definition.displayName -or $package.publication.publisher -cne $package.definition.publisher -or $package.publication.description -cne $package.definition.description) { throw 'Frozen display metadata disagrees with the packaged definition.' }
if ((Get-AppObjectHash $profile.returnCodes) -cne (Get-AppObjectHash $package.definition.intune.returnCodes) -or $profile.enforceSignatureCheck -ne $package.definition.detection.enforceSignatureCheck) { throw 'Frozen publication profile disagrees with the packaged definition.' }
$codes=@{}
foreach ($code in $profile.returnCodes) {
    if ($codes.ContainsKey([string]$code.code) -or $code.code -lt 0 -or $code.code -gt [int]::MaxValue -or $code.type -notin @('success','softReboot','hardReboot','retry','failed')) { throw 'Invalid frozen return-code policy.' }
    $codes[[string]$code.code]=$code.type
}
foreach ($pair in @{'0'='success';'1707'='success';'3010'='softReboot';'1641'='hardReboot';'1618'='retry'}.GetEnumerator()) {
    if ($codes[$pair.Key] -cne $pair.Value) { throw 'Frozen return-code policy conflicts with IntuneWin32App 1.5.0 defaults.' }
}
Assert-PublicationFile $package.packagePath $package.sha256
Assert-PublicationFile $package.detection.path $package.detection.sha256
$detectionPath=$package.detection.path
$detectionHash=$package.detection.sha256
$signedPath=$null
if ($SignedDetectionPath) {
    $signedPath=(Resolve-Path -LiteralPath $SignedDetectionPath).ProviderPath
    Assert-AppUnredirectedPath $signedPath
    $signedHash=(Get-FileHash -LiteralPath $signedPath).Hash.ToLowerInvariant()
    $unsigned=[IO.File]::ReadAllText($package.detection.path,[Text.UTF8Encoding]::new($false,$true))
    $signed=[IO.File]::ReadAllText($signedPath,[Text.UTF8Encoding]::new($false,$true))
    $block=[regex]::Match($signed,'(?ms)^# SIG # Begin signature block\r?\n(?<data>(?:# [A-Za-z0-9+/=]+\r?\n)+)# SIG # End signature block(?:\r?\n)*\z')
    if (-not $block.Success -or [regex]::Matches($signed,'(?m)^# SIG # Begin signature block').Count -ne 1 -or $unsigned.Contains('# SIG # Begin signature block') -or $signed.Substring(0,$block.Index).TrimEnd([char[]]"`r`n") -cne $unsigned.TrimEnd([char[]]"`r`n")) { throw 'Signed detection must preserve the unsigned body and append exactly one recognized signature block.' }
    $signatureData=($block.Groups['data'].Value -replace '(?m)^# ','') -replace '\s',''
    try { $null=[Convert]::FromBase64String($signatureData) } catch { throw 'Unrecognized detection signature encoding.' }
    if ((Get-AuthenticodeSignature -LiteralPath $signedPath).Status -ne 'Valid') { throw 'Signed detection requires a valid Authenticode signature.' }
    if ((Get-FileHash -LiteralPath $signedPath).Hash.ToLowerInvariant() -cne $signedHash) { throw 'Signed detection changed during signature verification.' }
    $detectionPath=$signedPath
    $detectionHash=$signedHash
}
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($detectionPath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Frozen detection script does not parse.' }
$requirements=@(
    foreach ($requirement in $package.definition.deployment.prerequisites) {
        $value=[ordered]@{kind='application';requirement=$requirement}
        [pscustomobject]@{hash=(Get-AppObjectHash $value);kind='application';requirement=$requirement}
    }
    foreach ($requirement in $package.definition.deployment.externalPolicyPrerequisites) {
        $value=[ordered]@{kind='externalPolicy';requirement=$requirement}
        [pscustomobject]@{hash=(Get-AppObjectHash $value);kind='externalPolicy';requirement=$requirement}
    }
)
if (@($requirements | Group-Object hash | Where-Object Count -gt 1).Count) { throw 'Duplicate prerequisite definitions require review.' }
$missing=[Collections.Generic.List[string]]::new()
if ($package.fixture) { $missing.Add('Offline fixture packages cannot be published.') }
if ($profile.enforceSignatureCheck -and -not $signedPath) { $missing.Add('A separate valid signed detection artifact is required.') }
$acceptanceReference=$null
if (-not $AcceptancePath) { $missing.Add('Endpoint, business and prerequisite acceptance evidence is required.') }
else {
    $acceptanceFile=(Resolve-Path -LiteralPath $AcceptancePath).ProviderPath
    Assert-AppUnredirectedPath $acceptanceFile
    $acceptanceHash=(Get-FileHash -LiteralPath $acceptanceFile).Hash.ToLowerInvariant()
    Assert-AppJsonSchema $acceptanceFile (Join-Path $PSScriptRoot '../schemas/release-acceptance.v1.schema.json')
    $acceptance=Read-AppJson $acceptanceFile
    if ($acceptance.applicationId -cne $package.applicationId -or $acceptance.buildId -cne $package.buildId -or $acceptance.packageSha256 -ine $package.sha256 -or $acceptance.detectionSha256 -ine $detectionHash) { throw 'Acceptance evidence does not match this exact application, build, package and detection artifact.' }
    $evidenceFiles=[Collections.Generic.List[object]]::new()
    function Add-AcceptanceEvidence($Evidence,[string]$Label) {
        if ($null -eq $Evidence) { throw "Acceptance evidence file is required: $Label" }
        $path=if ([IO.Path]::IsPathRooted($Evidence.path)) {$Evidence.path} else {Resolve-AppSourcePath (Split-Path -Parent $acceptanceFile) $Evidence.path}
        Assert-PublicationFile $path $Evidence.sha256
        $evidenceFiles.Add([pscustomobject]@{label=$Label;path=[IO.Path]::GetFullPath($path);sha256=$Evidence.sha256.ToLowerInvariant()})
    }
    foreach ($name in @('endpoint','business')) {
        $review=$acceptance.$name
        if (-not $review.passed) { throw "Acceptance has not passed: $name" }
        Assert-PublicationReviewer $review $name
        Add-AcceptanceEvidence $review.evidence $name
    }
    $confirmed=@{}
    foreach ($confirmation in $acceptance.prerequisites) {
        if ($confirmed.ContainsKey($confirmation.requirementHash) -or $confirmation.requirementHash -notin @($requirements.hash)) { throw 'Unknown or duplicate prerequisite confirmation.' }
        Assert-PublicationReviewer $confirmation 'prerequisite'
        Add-AcceptanceEvidence $confirmation.evidence $confirmation.requirementHash
        $confirmed[$confirmation.requirementHash]=$true
    }
    foreach ($requirement in $requirements) { if (-not $confirmed.ContainsKey($requirement.hash)) { throw 'A declared prerequisite has no matching approval evidence.' } }
    Assert-PublicationFile $acceptanceFile $acceptanceHash
    $acceptanceReference=[pscustomobject]@{path=$acceptanceFile;sha256=$acceptanceHash;evidenceFiles=$evidenceFiles.ToArray()}
}
Assert-PublicationFile $manifestPath $manifestHash
Assert-PublicationFile $package.packagePath $package.sha256
Assert-PublicationFile $package.detection.path $package.detection.sha256
Assert-PublicationFile $detectionPath $detectionHash
$request=[pscustomobject]@{
    schemaVersion=1;recordType='PublicationRequest';applicationId=$package.applicationId;releaseId=$package.buildId;buildId=$package.buildId
    fixture=[bool]$package.fixture;ready=($missing.Count -eq 0);missingEvidence=$missing.ToArray();requiredPrerequisites=$requirements
    packageManifestPath=$manifestPath;packageManifestSha256=$manifestHash;packageRecordHash=$package.recordHash
    packagePath=$package.packagePath;packageSha256=$package.sha256;detection=[pscustomobject]@{path=$detectionPath;sha256=$detectionHash}
    signedDetectionPath=$signedPath;profile=$profile;publication=$package.publication;acceptance=$acceptanceReference
}
$request | Add-Member -NotePropertyName recordHash -NotePropertyValue (Get-AppRecordHash $request)
$request
