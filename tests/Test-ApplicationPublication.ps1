#requires -Version 5.1
<# Local fixture bytes and isolated module/Graph mocks only. No real packaging, authentication, upload or endpoint acceptance occurs. Run in a fresh process. #>
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts/Application.Core.ps1')
$prepare=Join-Path $repo 'scripts/Prepare-ApplicationPublication.ps1'
$publisher=Join-Path $repo 'examples/Publish-Unassigned.example.ps1'
$testRoot=Join-Path $repo ('.validation/publication-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $testRoot
$checks=0
function Assert-Pub([bool]$Condition,[string]$Message) {if(-not $Condition){throw $Message};$script:checks++}
function Assert-Rejected([scriptblock]$Action,[string]$Pattern) {
    try {$null=& $Action} catch {if($_.Exception.Message -notmatch $Pattern){throw "Unexpected rejection: $($_.Exception.Message)"};$script:checks++;return}
    throw "Expected rejection: $Pattern"
}
function Write-TestJson([string]$Name,$Value,[switch]$Seal) {
    if($Seal){$Value | Add-Member -NotePropertyName recordHash -NotePropertyValue (Get-AppRecordHash $Value) -Force}
    $path=Join-Path $testRoot $Name
    [IO.File]::WriteAllText($path,($Value|ConvertTo-Json -Depth 70),[Text.UTF8Encoding]::new($false))
    return $path
}
$definition=Read-AppJson (Join-Path $repo 'examples/apps/firefox/app.json')
$packagePath=Join-Path $testRoot 'fixture.intunewin'
$detectorPath=Join-Path $testRoot 'Detect.ps1'
[IO.File]::WriteAllText($packagePath,'Offline fixture bytes; not a valid Intune package.')
[IO.File]::WriteAllText($detectorPath,"Write-Output 'Fixture detection'; exit 0",[Text.UTF8Encoding]::new($true))
$profile=[pscustomobject]@{name='official-4.1.8-native-v2';setupFile='Invoke-AppDeployToolkit.exe';installCommand='Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Auto';uninstallCommand='Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Auto';context='system';architecture='x64';minimumOS='W11_22H2';maximumInstallationTimeInMinutes=120;returnCodes=$definition.intune.returnCodes;runAs32Bit=$false;enforceSignatureCheck=$false}
$package=[pscustomobject]@{
    schemaVersion=1;recordType='ApplicationPackage';applicationId=$definition.id;buildId=('b'*64);fixture=$true
    buildRecordHash=('c'*64);buildManifestPath=(Join-Path $testRoot 'unused-build-manifest.json');definition=$definition
    release=[pscustomobject]@{applicationId=$definition.id;version='159.0.1'};profile=$profile
    publication=[pscustomobject]@{displayName=$definition.displayName;publisher=$definition.publisher;description=$definition.description;version='159.0.1'}
    detection=[pscustomobject]@{path=$detectorPath;sha256=(Get-FileHash -LiteralPath $detectorPath).Hash;sourceSha256=('d'*64);version='159.0.1'}
    packagePath=$packagePath;sha256=(Get-FileHash -LiteralPath $packagePath).Hash;packagingOnly=$true;installationTested=$false
}
$manifest=Write-TestJson 'package-manifest.json' $package -Seal
$global:PublicationTestState=@{Execute=$false;SignatureCalls=0;DuringSignature=$null;DuringAuthentication=$null;MutationPath=$null;BoundaryCalls=0;Added=$null;Existing=$false;Assignments=@();PublishingState='published'}
function global:Get-AuthenticodeSignature { [CmdletBinding()]param([string]$LiteralPath) $global:PublicationTestState.SignatureCalls++;throw 'Unexpected signature verification in default preview.' }
function global:Import-Module { [CmdletBinding()]param([string]$Name,[version]$RequiredVersion) $global:PublicationTestState.BoundaryCalls++;throw 'Unexpected module import in preview.' }
function global:Connect-MSIntuneGraph {throw 'Unexpected authentication in preview.'}
function global:Invoke-RestMethod {throw 'Unexpected network call in preview.'}
function global:Invoke-WebRequest {throw 'Unexpected network call in preview.'}
function global:Add-IntuneWin32AppAssignmentGroup {throw 'Assignment is never authorized by publication.'}
$beforeFiles=@(Get-ChildItem -LiteralPath $testRoot -File | ForEach-Object {$_.FullName})
$request=& $prepare -PackageManifestPath $manifest
Assert-Pub ($request.fixture -and -not $request.ready -and $request.missingEvidence.Count -ge 2) 'Fixture or missing acceptance was treated as publish-ready.'
Assert-Pub ($request.releaseId -ceq $package.buildId -and $request.requiredPrerequisites.Count -eq 1) 'Request did not retain release identity and policy prerequisite.'
Assert-Pub ($global:PublicationTestState.SignatureCalls -eq 0 -and $global:PublicationTestState.BoundaryCalls -eq 0) 'Default preparation crossed its local boundary.'
Assert-Pub (@(Compare-Object $beforeFiles @(Get-ChildItem -LiteralPath $testRoot -File | ForEach-Object {$_.FullName})).Count -eq 0) 'Preparation wrote files.'
Assert-AppRecord $request 'PublicationRequest';$checks++
$requestPath=Write-TestJson 'fixture-request.json' $request
$preview=& $publisher -RequestPath $requestPath
Assert-Pub ($preview.InputMode -ceq 'Request' -and -not $preview.Ready -and $preview.Assignments.Count -eq 0) 'Request preview lost its readiness or assignment boundary.'
Assert-Rejected {& $publisher -RequestPath $requestPath -Execute} 'non-fixture request'
Assert-Rejected {& $publisher -RequestPath $requestPath -DisplayName 'conflict'} 'Parameter set cannot be resolved'
$unsealed=Read-AppJson $manifest;$unsealed.publication.displayName='tampered'
$unsealedPath=Write-TestJson 'unsealed.json' $unsealed
Assert-Rejected {& $prepare -PackageManifestPath $unsealedPath} 'Invalid or changed ApplicationPackage'
$savedPackage=[IO.File]::ReadAllBytes($packagePath)
[IO.File]::AppendAllText($packagePath,'tampered')
Assert-Rejected {& $prepare -PackageManifestPath $manifest} 'hash mismatch'
Assert-Rejected {& $publisher -RequestPath $requestPath} 'hash mismatch'
[IO.File]::WriteAllBytes($packagePath,$savedPackage)

$evidencePath=Join-Path $testRoot 'acceptance-evidence.txt'
[IO.File]::WriteAllText($evidencePath,'Synthetic test evidence. No endpoint or business acceptance was performed.')
$evidence=[pscustomobject]@{path=$evidencePath;sha256=(Get-FileHash -LiteralPath $evidencePath).Hash}
$review=[pscustomobject]@{passed=$true;approvedBy='Test fixture reviewer';approvedAtUtc='2026-11-05T00:00:00Z';evidence=$evidence}
$acceptance=[pscustomobject]@{schemaVersion=1;recordType='ReleaseAcceptance';applicationId=$package.applicationId;buildId=$package.buildId;packageSha256=$package.sha256;detectionSha256=$package.detection.sha256;endpoint=$review;business=$review;prerequisites=@([pscustomobject]@{requirementHash=$request.requiredPrerequisites[0].hash;approvedBy='Test fixture reviewer';approvedAtUtc='2026-11-05T00:00:00Z';evidence=$evidence})}
$acceptancePath=Write-TestJson 'acceptance.json' $acceptance
$fixtureAccepted=& $prepare -PackageManifestPath $manifest -AcceptancePath $acceptancePath
Assert-Pub (-not $fixtureAccepted.ready -and $fixtureAccepted.fixture) 'Approval incorrectly made a fixture publishable.'

# A synthetic non-fixture marker is used only to exercise mocked execution below.
$package.fixture=$false
$acceptedManifest=Write-TestJson 'accepted-package.json' $package -Seal
$ready=& $prepare -PackageManifestPath $acceptedManifest -AcceptancePath $acceptancePath
Assert-Pub ($ready.ready -and -not $ready.fixture -and $ready.acceptance.evidenceFiles.Count -eq 3) 'Complete matching evidence was not bound to the request.'
$readyPath=Write-TestJson 'ready-request.json' $ready
$inconsistent=Read-AppJson $acceptedManifest
($inconsistent.profile.returnCodes | Where-Object code -eq 69001).type='success'
$inconsistentPath=Write-TestJson 'inconsistent-profile.json' $inconsistent -Seal
Assert-Rejected {& $prepare -PackageManifestPath $inconsistentPath -AcceptancePath $acceptancePath} 'disagrees with the packaged definition'
$preview=& $publisher -RequestPath $readyPath
Assert-Pub ($preview.Ready -and $preview.DisplayName -ceq $definition.displayName -and $preview.InstallExperience -ceq 'system') 'Frozen metadata/profile were not used in preview.'
Assert-Pub ($global:PublicationTestState.BoundaryCalls -eq 0 -and $global:PublicationTestState.SignatureCalls -eq 0) 'Request preparation or preview invoked a forbidden boundary.'
$savedEvidence=[IO.File]::ReadAllBytes($evidencePath)
[IO.File]::AppendAllText($evidencePath,'changed')
Assert-Rejected {& $publisher -RequestPath $readyPath} 'hash mismatch'
Assert-Rejected {& $prepare -PackageManifestPath $acceptedManifest -AcceptancePath $acceptancePath} 'hash mismatch'
[IO.File]::WriteAllBytes($evidencePath,$savedEvidence)
$badAcceptance=Read-AppJson $acceptancePath;$badAcceptance.detectionSha256='e'*64
$badAcceptancePath=Write-TestJson 'wrong-acceptance.json' $badAcceptance
Assert-Rejected {& $prepare -PackageManifestPath $acceptedManifest -AcceptancePath $badAcceptancePath} 'does not match this exact'
$badAcceptance=Read-AppJson $acceptancePath;$badAcceptance.prerequisites=@()
$badAcceptancePath=Write-TestJson 'missing-prerequisite.json' $badAcceptance
Assert-Rejected {& $prepare -PackageManifestPath $acceptedManifest -AcceptancePath $badAcceptancePath} 'prerequisite has no matching'
$badAcceptance=Read-AppJson $acceptancePath;$badAcceptance.endpoint.passed=$false
$badAcceptancePath=Write-TestJson 'failed-endpoint.json' $badAcceptance
Assert-Rejected {& $prepare -PackageManifestPath $acceptedManifest -AcceptancePath $badAcceptancePath} 'Acceptance has not passed'

$authoredSource=Join-Path $testRoot 'app.json'
$null=Write-TestJson 'app.json' $definition
[IO.File]::AppendAllText($authoredSource,' intentionally invalid source edit after finalization')
$unchanged=& $prepare -PackageManifestPath $acceptedManifest -AcceptancePath $acceptancePath
Assert-Pub ($unchanged.recordHash -ceq $ready.recordHash) 'Preparation reread mutable application authoring instead of its frozen package definition.'
$signatureRequired=Read-AppJson $acceptedManifest;$signatureRequired.profile.enforceSignatureCheck=$true;$signatureRequired.definition.detection.enforceSignatureCheck=$true
$signatureManifest=Write-TestJson 'signature-package.json' $signatureRequired -Seal
$unsignedRequest=& $prepare -PackageManifestPath $signatureManifest -AcceptancePath $acceptancePath
Assert-Pub (-not $unsignedRequest.ready -and ($unsignedRequest.missingEvidence -join ' ') -match 'signed detection') 'Required signing was silently treated as ready.'
$signedPath=Join-Path $testRoot 'Detect.signed.ps1'
$body=[IO.File]::ReadAllText($detectorPath)
[IO.File]::WriteAllText($signedPath,$body+"`r`n# SIG # Begin signature block`r`n# AAAA`r`n# SIG # End signature block`r`n",[Text.UTF8Encoding]::new($true))
$global:PublicationTestState.SignatureStatus='Valid'
function global:Get-AuthenticodeSignature { [CmdletBinding()]param([string]$LiteralPath) $global:PublicationTestState.SignatureCalls++;if($global:PublicationTestState.DuringSignature){& $global:PublicationTestState.DuringSignature $LiteralPath};[pscustomobject]@{Status=$global:PublicationTestState.SignatureStatus} }
$signedAcceptance=Read-AppJson $acceptancePath;$signedAcceptance.detectionSha256=(Get-FileHash -LiteralPath $signedPath).Hash
$signedAcceptancePath=Write-TestJson 'signed-acceptance.json' $signedAcceptance
$signedRequest=& $prepare -PackageManifestPath $signatureManifest -AcceptancePath $signedAcceptancePath -SignedDetectionPath $signedPath
Assert-Pub ($signedRequest.ready -and $signedRequest.detection.sha256 -ine $ready.detection.sha256) 'Signed final detection hash was not bound to acceptance.'
$signedRequestPath=Write-TestJson 'signed-request.json' $signedRequest
$signatureCount=$global:PublicationTestState.SignatureCalls
$null=& $publisher -RequestPath $signedRequestPath
Assert-Pub ($global:PublicationTestState.SignatureCalls -eq $signatureCount) 'Publisher preview performed a signature lookup.'
$global:PublicationTestState.SignatureStatus='NotSigned'
Assert-Rejected {& $prepare -PackageManifestPath $signatureManifest -AcceptancePath $signedAcceptancePath -SignedDetectionPath $signedPath} 'valid Authenticode'
$global:PublicationTestState.SignatureStatus='Valid'
[IO.File]::WriteAllText($signedPath,$body+"`r`n# SIG # Begin signature block`r`n# AAAA`r`n# SIG # End signature block`r`n",[Text.UTF8Encoding]::new($true))
$global:PublicationTestState.DuringSignature={param($Path) [IO.File]::AppendAllText($Path,"# changed during signature validation`r`n")}
Assert-Rejected {& $prepare -PackageManifestPath $signatureManifest -SignedDetectionPath $signedPath} 'changed during signature verification|hash mismatch'
$global:PublicationTestState.DuringSignature=$null
[IO.File]::WriteAllText($signedPath,"Write-Output 'changed body'`r`n# SIG # Begin signature block`r`n# AAAA`r`n# SIG # End signature block`r`n",[Text.UTF8Encoding]::new($true))
Assert-Rejected {& $prepare -PackageManifestPath $signatureManifest -SignedDetectionPath $signedPath} 'preserve the unsigned body'

function global:Get-Module { [CmdletBinding()]param([string]$Name) return @() }
function global:Import-Module { [CmdletBinding()]param([string]$Name,[version]$RequiredVersion) if($Name -cne 'IntuneWin32App' -or $RequiredVersion -ne [version]'1.5.0'){throw 'Unexpected import'};$global:PublicationTestState.BoundaryCalls++ }
function global:Get-IntuneWin32AppMetaData { [CmdletBinding()]param([string]$FilePath) [pscustomobject]@{ApplicationInfo=[pscustomobject]@{SetupFile='Invoke-AppDeployToolkit.exe'}} }
function global:New-IntuneWin32AppDetectionRuleScript { [CmdletBinding()]param([string]$ScriptFile,[bool]$EnforceSignatureCheck,[bool]$RunAs32Bit) $global:PublicationTestState.Detection=$PSBoundParameters;[pscustomobject]@{kind='fixture-detection'} }
function global:New-IntuneWin32AppRequirementRule { [CmdletBinding()]param([string]$Architecture,[string]$MinimumSupportedWindowsRelease) $global:PublicationTestState.Requirement=$PSBoundParameters;[pscustomobject]@{kind='fixture-requirement'} }
function global:New-IntuneWin32AppReturnCode { [CmdletBinding()]param([int]$ReturnCode,[string]$Type) [pscustomobject]@{returnCode=$ReturnCode;type=$Type} }
function global:Connect-MSIntuneGraph { [CmdletBinding()]param([string]$TenantID,[string]$ClientID,[switch]$Interactive,[string[]]$Scopes) $global:PublicationTestState.Auth=$PSBoundParameters;$global:AuthenticationHeader=@{Authorization='synthetic test header; not a token'};if($global:PublicationTestState.DuringAuthentication){& $global:PublicationTestState.DuringAuthentication} }
function global:Get-IntuneWin32App {
    [CmdletBinding()]param([string]$ID)
    if($ID){return [pscustomobject]@{id=$ID;committedContentVersion='1';publishingState=$global:PublicationTestState.PublishingState}}
    if($global:PublicationTestState.Existing){return [pscustomobject]@{notes=$global:PublicationTestState.Marker}}
    return @()
}
function global:Add-IntuneWin32App {
    [CmdletBinding()]param([string]$FilePath,[string]$DisplayName,[string]$Description,[string]$Publisher,[string]$AppVersion,[string]$Notes,[string]$InstallExperience,[string]$RestartBehavior,[int]$MaximumInstallationTimeInMinutes,[string]$InstallCommandLine,[string]$UninstallCommandLine,$DetectionRule,$RequirementRule,$ReturnCode)
    $global:PublicationTestState.Added=$PSBoundParameters
    return [pscustomobject]@{id='00000000-0000-0000-0000-000000000001'}
}
function global:Invoke-RestMethod {
    [CmdletBinding()]param([string]$Method,[string]$Uri,$Headers)
    if($Method -cne 'Get' -or $Uri -cne 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/00000000-0000-0000-0000-000000000001/assignments'){throw 'Unexpected mocked Graph operation.'}
    return [pscustomobject]@{value=$global:PublicationTestState.Assignments;'@odata.nextLink'=$null}
}
$execute=@{RequestPath=$readyPath;Execute=$true;ConfirmedCommercialCloud=$true;TenantId='test-tenant';ClientId='test-client'}
$result=& $publisher @execute
Assert-Pub ($result.State -ceq 'PublishedUnassigned' -and $result.CommittedContentVersion -ceq '1') 'Mocked publication did not verify committed content and zero assignments.'
$added=$global:PublicationTestState.Added
Assert-Pub ($added.Description -ceq $definition.description -and $added.InstallCommandLine -ceq $profile.installCommand -and $added.InstallExperience -ceq 'system' -and $added.MaximumInstallationTimeInMinutes -eq 120) 'Effective frozen settings were not applied.'
Assert-Pub ($added.ReturnCode.Count -eq 4 -and @($added.ReturnCode | Where-Object returnCode -in @(0,1707,3010,1641,1618)).Count -eq 0) 'Built-in return codes were duplicated.'
Assert-Pub ($global:PublicationTestState.Requirement.Architecture -ceq 'x64' -and $global:PublicationTestState.Detection.ScriptFile -ceq $detectorPath -and -not $global:PublicationTestState.Detection.RunAs32Bit) 'Detection or requirement mapping changed.'

# Interactive authentication can pause after the initial checks. Any changed accepted input
# must stop before the tenant-create boundary, including evidence and the legacy hash inputs.
foreach($changedPath in @($packagePath,$detectorPath,$evidencePath,$acceptancePath,$acceptedManifest)) {
    $savedBytes=[IO.File]::ReadAllBytes($changedPath)
    $global:PublicationTestState.Added=$null
    $global:PublicationTestState.MutationPath=$changedPath
    $global:PublicationTestState.DuringAuthentication={ [IO.File]::AppendAllText($global:PublicationTestState.MutationPath,' changed while authentication was pending') }
    try {
        Assert-Rejected {& $publisher @execute} 'hash mismatch|Invalid or changed|no longer matches|JSON|json'
        Assert-Pub ($null -eq $global:PublicationTestState.Added) "Changed request input reached app creation after authentication: $changedPath"
    } finally {
        [IO.File]::WriteAllBytes($changedPath,$savedBytes)
        $global:PublicationTestState.DuringAuthentication=$null
    }
}
$legacyExecute=@{
    ApplicationId=$package.applicationId;ReleaseId=$package.buildId;DisplayName=$definition.displayName;Publisher=$definition.publisher;AppVersion=$package.release.version
    PackagePath=$packagePath;DetectionScriptPath=$detectorPath;ExpectedPackageSha256=$package.sha256;ExpectedDetectionSha256=$package.detection.sha256
    Execute=$true;ConfirmedCommercialCloud=$true;TenantId='test-tenant';ClientId='test-client'
}
foreach($changedPath in @($packagePath,$detectorPath)) {
    $savedBytes=[IO.File]::ReadAllBytes($changedPath)
    $global:PublicationTestState.Added=$null
    $global:PublicationTestState.MutationPath=$changedPath
    $global:PublicationTestState.DuringAuthentication={ [IO.File]::AppendAllText($global:PublicationTestState.MutationPath,' changed while authentication was pending') }
    try {
        Assert-Rejected {& $publisher @legacyExecute} 'hash mismatch'
        Assert-Pub ($null -eq $global:PublicationTestState.Added) "Changed legacy artifact reached app creation after authentication: $changedPath"
    } finally {
        [IO.File]::WriteAllBytes($changedPath,$savedBytes)
        $global:PublicationTestState.DuringAuthentication=$null
    }
}
$global:PublicationTestState.Existing=$true;$global:PublicationTestState.Marker=$preview.Notes;$global:PublicationTestState.Added=$null
Assert-Rejected {& $publisher @execute} 'Reconcile content'
Assert-Pub ($null -eq $global:PublicationTestState.Added) 'Existing app marker caused another create.'
$global:PublicationTestState.Existing=$false;$global:PublicationTestState.PublishingState='processing'
Assert-Rejected {& $publisher @execute} 'needs reconciliation'
$global:PublicationTestState.PublishingState='published';$global:PublicationTestState.Assignments=@([pscustomobject]@{id='unexpected'})
Assert-Rejected {& $publisher @execute} 'has assignments'
[pscustomobject]@{Checks=$checks;Passed=$true;Runtime=$PSVersionTable.PSVersion.ToString();Scope='Local fixtures only; no real packaging, signatures, endpoint tests, authentication or tenant calls';OutputDirectory=$testRoot}
