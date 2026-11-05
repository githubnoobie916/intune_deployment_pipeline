#requires -Version 5.1
<#
Preview is local only: no module import, signature lookup, authentication, Graph call, or file write.
Request mode consumes a frozen PublicationRequest and revalidates acceptance before Execute.
Legacy explicit parameters remain available for the historical illustrative workflow.
Execute creates an UNASSIGNED app. Reconcile every uncertain result before retrying.
#>
[CmdletBinding(DefaultParameterSetName='Legacy')]
param(
    [Parameter(Mandatory,ParameterSetName='Request')][string]$RequestPath,
    [Parameter(Mandatory,ParameterSetName='Legacy')][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$ApplicationId,
    [Parameter(Mandatory,ParameterSetName='Legacy')][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$ReleaseId,
    [Parameter(Mandatory,ParameterSetName='Legacy')][ValidateNotNullOrEmpty()][string]$DisplayName,
    [Parameter(Mandatory,ParameterSetName='Legacy')][ValidateNotNullOrEmpty()][string]$Publisher,
    [Parameter(Mandatory,ParameterSetName='Legacy')][ValidateNotNullOrEmpty()][string]$AppVersion,
    [Parameter(Mandatory,ParameterSetName='Legacy')][string]$PackagePath,
    [Parameter(Mandatory,ParameterSetName='Legacy')][string]$DetectionScriptPath,
    [Parameter(ParameterSetName='Legacy')][string]$ExpectedPackageSha256,
    [Parameter(ParameterSetName='Legacy')][string]$ExpectedDetectionSha256,
    [Parameter(ParameterSetName='Legacy')][switch]$EnforceDetectionSignature,
    [string]$TenantId,
    [string]$ClientId,
    [switch]$ConfirmedCommercialCloud,
    [switch]$Execute
)
$ErrorActionPreference='Stop'
$defaultReturnCodes=@(
    [ordered]@{returnCode=0;type='success'}
    [ordered]@{returnCode=1707;type='success'}
    [ordered]@{returnCode=3010;type='softReboot'}
    [ordered]@{returnCode=1641;type='hardReboot'}
    [ordered]@{returnCode=1618;type='retry'}
)
$additionalReturnCodes=@(
    [ordered]@{returnCode=60001;type='failed'}
    [ordered]@{returnCode=60008;type='failed'}
    [ordered]@{returnCode=69001;type='failed'}
    [ordered]@{returnCode=1602;type='retry'}
)
$installCommand='Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Auto'
$uninstallCommand='Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Auto'
$description="Managed deployment of $DisplayName"
$architecture='x64';$minimumOS='W11_22H2';$context='system';$runAs32Bit=$false;$timeout=120
$request=$null
if ($PSCmdlet.ParameterSetName -eq 'Request') {
    . (Join-Path $PSScriptRoot '../scripts/Application.Core.ps1')
    $request=Read-AppJson $RequestPath
    Assert-AppRecord $request 'PublicationRequest'
    foreach ($artifact in @(
        @{path=$request.packageManifestPath;sha256=$request.packageManifestSha256}
        @{path=$request.packagePath;sha256=$request.packageSha256}
        @{path=$request.detection.path;sha256=$request.detection.sha256}
    ) + @(if ($null -ne $request.acceptance) {
        @{path=$request.acceptance.path;sha256=$request.acceptance.sha256}
        foreach ($evidence in $request.acceptance.evidenceFiles) {@{path=$evidence.path;sha256=$evidence.sha256}}
    })) {
        Assert-AppUnredirectedPath $artifact.path
        if ($artifact.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $artifact.path).Hash -ine $artifact.sha256) { throw 'Frozen publication input hash mismatch.' }
    }
    $ApplicationId=$request.applicationId;$ReleaseId=$request.releaseId
    if ($ApplicationId -notmatch '^[A-Za-z0-9._-]+$' -or $ReleaseId -notmatch '^[A-Za-z0-9._-]+$') { throw 'Invalid publication marker identity.' }
    $DisplayName=$request.publication.displayName;$Publisher=$request.publication.publisher;$AppVersion=$request.publication.version
    $description=$request.publication.description;$PackagePath=$request.packagePath;$DetectionScriptPath=$request.detection.path
    $ExpectedPackageSha256=$request.packageSha256;$ExpectedDetectionSha256=$request.detection.sha256
    $installCommand=$request.profile.installCommand;$uninstallCommand=$request.profile.uninstallCommand
    $architecture=$request.profile.architecture;$minimumOS=$request.profile.minimumOS;$context=$request.profile.context
    $runAs32Bit=[bool]$request.profile.runAs32Bit;$timeout=$request.profile.maximumInstallationTimeInMinutes
    $EnforceDetectionSignature=[bool]$request.profile.enforceSignatureCheck
    $additionalReturnCodes=@(foreach ($code in $request.profile.returnCodes) {
        if ($code.code -notin @($defaultReturnCodes.returnCode)) {[ordered]@{returnCode=$code.code;type=$code.type}}
    })
}
$marker="ManagedBy=ManualIntuneResearch;ApplicationId=$ApplicationId;ReleaseId=$ReleaseId"
$plan=[ordered]@{
    Operation='CreateUnassignedWin32App';Module='IntuneWin32App/1.5.0';InputMode=$PSCmdlet.ParameterSetName
    ApplicationId=$ApplicationId;ReleaseId=$ReleaseId;DisplayName=$DisplayName;Publisher=$Publisher;AppVersion=$AppVersion
    PackagePath=$PackagePath;SetupFile='Invoke-AppDeployToolkit.exe';DetectionScriptPath=$DetectionScriptPath
    InstallCommandLine=$installCommand;UninstallCommandLine=$uninstallCommand;InstallExperience=$context
    RestartBehavior='basedOnReturnCode';MaximumInstallationTimeInMinutes=$timeout
    EffectiveReturnCodes=@($defaultReturnCodes)+@($additionalReturnCodes)
    Architecture=$architecture;MinimumSupportedWindowsRelease=$minimumOS;Assignments=@();Notes=$marker
    Ready=if ($request) {$request.ready} else {$null}
    MissingEvidence=if ($request) {@($request.missingEvidence)} else {@('Legacy explicit inputs do not use the release acceptance contract.')}
}
if (-not $Execute) {[pscustomobject]$plan;return}
if ($request) {
    if ($request.fixture -or -not $request.ready) { throw 'Publication requires a non-fixture request with completed acceptance evidence.' }
    $parameters=@{PackageManifestPath=$request.packageManifestPath}
    if ($null -ne $request.acceptance) {$parameters.AcceptancePath=$request.acceptance.path}
    if ($request.signedDetectionPath) {$parameters.SignedDetectionPath=$request.signedDetectionPath}
    $revalidated=& (Join-Path $PSScriptRoot '../scripts/Prepare-ApplicationPublication.ps1') @parameters
    if (-not $revalidated.ready -or $revalidated.fixture -or $revalidated.recordHash -cne $request.recordHash) { throw 'Publication request no longer matches its frozen artifacts and acceptance evidence.' }
}
if (-not $ConfirmedCommercialCloud) { throw '1.5.0 hardcodes global endpoints; confirm commercial-cloud compatibility before execution.' }
if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ClientId)) { throw 'TenantId and ClientId are required with Execute.' }
if (Get-Module -Name IntuneWin32App) { throw 'Use a fresh process so existing module/authentication state cannot be reused.' }
foreach ($item in @(@{Path=$PackagePath;Hash=$ExpectedPackageSha256},@{Path=$DetectionScriptPath;Hash=$ExpectedDetectionSha256})) {
    if ($item.Hash -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Supply the approved package and detection SHA256 values.' }
    if ((Get-FileHash -LiteralPath $item.Path).Hash -ine $item.Hash) { throw "Artifact hash mismatch: $($item.Path)" }
}
$parseTokens=$null;$parseErrors=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $DetectionScriptPath).Path,[ref]$parseTokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'Detection script does not parse.' }
if ($EnforceDetectionSignature -and (Get-AuthenticodeSignature -LiteralPath $DetectionScriptPath).Status -ne 'Valid') { throw 'A valid detection signature is required; endpoint publisher trust needs separate testing.' }
Import-Module -Name IntuneWin32App -RequiredVersion 1.5.0 -ErrorAction Stop
$packageMetadata=Get-IntuneWin32AppMetaData -FilePath $PackagePath -WarningAction Stop
if ($packageMetadata.ApplicationInfo.SetupFile -ne 'Invoke-AppDeployToolkit.exe') { throw 'Unexpected package setup entry point.' }
$detection=New-IntuneWin32AppDetectionRuleScript -ScriptFile $DetectionScriptPath -EnforceSignatureCheck ([bool]$EnforceDetectionSignature) -RunAs32Bit $runAs32Bit
$requirement=New-IntuneWin32AppRequirementRule -Architecture $architecture -MinimumSupportedWindowsRelease $minimumOS
$extraCodes=@(foreach ($code in $additionalReturnCodes) {New-IntuneWin32AppReturnCode -ReturnCode $code.returnCode -Type $code.type})
Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -Interactive -Scopes @('DeviceManagementApps.ReadWrite.All','offline_access') -WarningAction Stop | Out-Null
$existing=@(Get-IntuneWin32App -WarningAction Stop | Where-Object {$_.notes -eq $marker})
if ($existing.Count) { throw 'This release already has an app object. Reconcile content, metadata, and state; do not create a duplicate.' }
# Interactive authentication and inventory reads can pause after the initial validation.
# Recheck accepted inputs at the tenant-create boundary instead of trusting their earlier bytes.
if ($request) {
    $revalidated=& (Join-Path $PSScriptRoot '../scripts/Prepare-ApplicationPublication.ps1') @parameters
    if (-not $revalidated.ready -or $revalidated.fixture -or $revalidated.recordHash -cne $request.recordHash) { throw 'Publication request no longer matches its frozen artifacts and acceptance evidence.' }
}
foreach ($item in @(@{Path=$PackagePath;Hash=$ExpectedPackageSha256},@{Path=$DetectionScriptPath;Hash=$ExpectedDetectionSha256})) {
    if ((Get-FileHash -LiteralPath $item.Path).Hash -ine $item.Hash) { throw "Artifact hash mismatch immediately before publication: $($item.Path)" }
}
# The supported profile is explicitly limited to 120 minutes by preparation.
$app=Add-IntuneWin32App -FilePath $PackagePath -DisplayName $DisplayName -Description $description -Publisher $Publisher -AppVersion $AppVersion -Notes $marker -InstallExperience $context -RestartBehavior basedOnReturnCode -MaximumInstallationTimeInMinutes 120 -InstallCommandLine $installCommand -UninstallCommandLine $uninstallCommand -DetectionRule $detection -RequirementRule $requirement -ReturnCode $extraCodes -WarningAction Stop
if (-not $app.id) { throw 'No app ID returned. Publication may be partial: reconcile the release marker in Intune before retrying.' }
$verified=Get-IntuneWin32App -ID $app.id -WarningAction Stop
if (-not $verified.committedContentVersion -or $verified.publishingState -ne 'published') { throw "App $($app.id) needs reconciliation: content is not confirmed published." }
$assignments=Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$($app.id)/assignments" -Headers $Global:AuthenticationHeader
if (@($assignments.value).Count -or $assignments.'@odata.nextLink') { throw "App $($app.id) has assignments; investigate before proceeding." }
[pscustomobject]@{ApplicationId=$ApplicationId;ReleaseId=$ReleaseId;IntuneAppId=$app.id;CommittedContentVersion=$verified.committedContentVersion;State='PublishedUnassigned';PackageSha256=$ExpectedPackageSha256;DetectionSha256=$ExpectedDetectionSha256}
