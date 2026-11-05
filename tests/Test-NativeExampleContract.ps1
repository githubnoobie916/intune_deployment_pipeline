#requires -Version 5.1
<# Current definitions -> real resolver/build fixtures; preserves native-v2 behavior and historical evidence. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = Split-Path -Parent $PSScriptRoot
. (Join-Path $repository 'scripts\Application.Core.ps1')
. (Join-Path $PSScriptRoot 'ApplicationTest.Fixtures.ps1')
$testRoot = Join-Path $repository ('.validation\native-contract-' + [guid]::NewGuid().ToString('N'))
$script:checkCount = 0
function Assert-Contract([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }; $script:checkCount++
}
function Get-CodeSignature($Codes, [string]$NumberProperty) {
    @($Codes | ForEach-Object { '{0}:{1}' -f $_.$NumberProperty, $_.type } | Sort-Object) -join '|'
}
$historicalManifest = Read-AppJson (Join-Path $repository 'tests/fixtures/legacy-v2/build-manifest.example.json')
$historicalDetection = Read-AppJson (Join-Path $repository 'evidence/evergreen-example-validation.json')
$historicalNative = Read-AppJson (Join-Path $repository 'evidence/psadt-4.1.8-native-v2-validation.json')
$migration = Read-AppJson (Join-Path $repository 'tests/fixtures/legacy-v2/migration-manifest.json')
Assert-Contract ((Get-FileHash -LiteralPath (Join-Path $repository $migration.buildManifest.archived)).Hash -ieq $migration.buildManifest.sha256) 'Archived historical manifest changed.'
foreach ($entry in $migration.files) {
    Assert-Contract (-not (Test-Path -LiteralPath (Join-Path $repository $entry.original))) "Superseded active authoring input remains: $($entry.original)"
    Assert-Contract ((Get-FileHash -LiteralPath (Join-Path $repository $entry.archived)).Hash -ieq $entry.sha256) "Historical fixture changed: $($entry.archived)"
}
$expectedInstall = 'Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Auto'
$expectedUninstall = 'Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Auto'
# Explicit legacy preview coverage remains; request-mode boundaries have their own focused tests.
$preview = & (Join-Path $repository 'examples/Publish-Unassigned.example.ps1') -ApplicationId 'contract.example' -ReleaseId 'offline-v3' -DisplayName 'Offline contract' -Publisher 'Example' -AppVersion '1.0' -PackagePath 'not-created.intunewin' -DetectionScriptPath 'not-executed.ps1'
Assert-Contract ($preview.InstallCommandLine -ceq $expectedInstall -and $preview.UninstallCommandLine -ceq $expectedUninstall) 'Publisher preview commands differ.'
Assert-Contract ($preview.MaximumInstallationTimeInMinutes -eq 120) 'Publisher preview timeout differs.'
Assert-Contract ($historicalManifest.output.installCommand -ceq $expectedInstall -and $historicalManifest.output.uninstallCommand -ceq $expectedUninstall -and $historicalManifest.output.maximumInstallationTimeInMinutes -eq 120) 'Historical manifest profile changed.'
$apps = @(@{Folder='firefox';Process='firefox'}, @{Folder='notepadplusplus';Process='notepad++'})
$fixtures = @{}
foreach ($app in $apps) {
    $definition = Read-AppDefinition (Join-Path $repository ('examples/apps/'+$app.Folder+'/app.json'))
    $fixture = New-ApplicationTestBuild -Root (Join-Path $testRoot $app.Folder) -Application $app.Folder
    $fixtures[$app.Folder] = $fixture
    $resolved = Read-AppJson $fixture.ResolvedPath
    $build = $fixture.Build
    $metadata = $resolved.metadata
    Assert-Contract ($definition.schemaVersion -eq 3 -and $definition.ownership.recipeRevision -eq '3') 'Active definition is not v3.'
    Assert-Contract ($definition.toolkit.profile -ceq 'official-4.1.8-native-v2' -and $definition.deployment.mode -ceq 'Auto') 'Native-v2 profile changed.'
    Assert-Contract ($build.profile.installCommand -ceq $expectedInstall -and $build.profile.uninstallCommand -ceq $expectedUninstall -and $build.profile.maximumInstallationTimeInMinutes -eq 120) 'Resolved build commands or timeout differ.'
    Assert-Contract ($definition.deployment.deferral.policy -ceq 'template-default' -and @($definition.deployment.deferral.PSObject.Properties).Count -eq 1) 'Deferrals no longer inherit native defaults.'
    Assert-Contract ($definition.update.downgradeHandling -ceq 'vendor-default' -and $null -eq $definition.update.PSObject.Properties['downgradeAllowed']) 'Unsupported downgrade guarantee remains.'
    Assert-Contract (@($metadata.AppProcessesToClose).Count -eq 1 -and $metadata.AppProcessesToClose[0].Name -ceq $app.Process) 'Native process metadata is missing or incorrect.'
    Assert-Contract ($definition.deployment.processes[0].name -ceq $metadata.AppProcessesToClose[0].Name -and $definition.deployment.processes[0].description -ceq $metadata.AppProcessesToClose[0].Description) 'Definition and generated process metadata disagree.'
    Assert-Contract ($metadata.AppRevision -eq '02' -and $metadata.AppScriptVersion -eq '1.1.0') 'Application script/package revision changed.'
    foreach ($operation in @('Install','Uninstall','Repair')) {
        Assert-Contract (@($definition.actions.$operation.PSObject.Properties).Count -eq 1 -and $null -ne $definition.actions.$operation.PSObject.Properties['Main']) 'Sample unexpectedly acquired Pre/Post actions.'
    }
    foreach ($removed in @('Pre.ps1','Post.ps1','policies.json','metadata.json','actions.json','Detect.ps1')) {
        Assert-Contract (-not (Test-Path -LiteralPath (Join-Path $repository ('examples/apps/'+$app.Folder+'/'+$removed)))) "Superseded active sample source remains: $removed"
    }
    Assert-Contract (@($definition.payloads.support).Count -eq 0) 'Sample unexpectedly contains support payloads.'
    Assert-Contract ($null -eq $definition.deployment.PSObject.Properties['install'] -and $null -eq $definition.deployment.PSObject.Properties['uninstall']) 'Duplicate executable command configuration remains.'
    $codeSignature = Get-CodeSignature $definition.intune.returnCodes 'code'
    Assert-Contract ((Get-CodeSignature $preview.EffectiveReturnCodes 'returnCode') -ceq $codeSignature -and (Get-CodeSignature $build.profile.returnCodes 'code') -ceq $codeSignature) 'Publisher or resolved build return codes differ.'
    Assert-Contract ((Get-CodeSignature $historicalManifest.output.effectiveReturnCodes 'returnCode') -ceq $codeSignature) 'Historical return-code behavior changed.'
    Assert-Contract (@($definition.intune.returnCodes | Group-Object code | Where-Object Count -gt 1).Count -eq 0) 'Duplicate return codes.'
    Assert-Contract (@($definition.intune.returnCodes | Where-Object { $_.code -eq 1602 -and $_.type -eq 'retry' }).Count -eq 1) '1602 is not a single retry mapping.'
    $oldPath = 'examples/apps/'+$app.Folder+'/Detect.ps1'
    $oldHash = @($historicalDetection.fileHashes | Where-Object path -CEQ $oldPath)
    $archivedDetector = Join-Path $repository ('tests/fixtures/legacy-v2/apps/'+$app.Folder+'/Detect.ps1')
    Assert-Contract ($oldHash.Count -eq 1 -and (Get-FileHash -LiteralPath $archivedDetector).Hash -ieq $oldHash[0].sha256) 'Historical standalone detector changed.'
    $oldText = [IO.File]::ReadAllText($archivedDetector)
    $templateText = [IO.File]::ReadAllText((Join-Path $repository ('examples/apps/'+$app.Folder+'/Detect.template.ps1')))
    $expectedTemplate = $oldText.Replace('# Frozen example version observed 2026-11-03. Re-resolve this literal for each approved build.', '# Build-time version placeholder; bind from the accepted release before signing or publication.')
    $expectedTemplate = [regex]::Replace($expectedTemplate, '(?m)^\$MinimumVersion = \[version\]''[^'']+''', '$MinimumVersion = [version]''__RESOLVED_VERSION__''')
    Assert-Contract ($templateText -ceq $expectedTemplate) 'Detection logic changed outside its comment/version binding.'
    Assert-Contract ([IO.File]::ReadAllText($build.detection.path) -ceq $templateText.Replace("'__RESOLVED_VERSION__'", ("'"+$build.release.version+"'"))) 'Generated detection differs from the accepted release.'
    Assert-Contract ($metadata.AppVersion -ceq $build.release.version -and $build.detection.version -ceq $build.release.version -and $build.publication.version -ceq $build.release.version) 'Release versions diverged.'
    $generatedScript = Join-Path $build.sourceFolder 'Invoke-AppDeployToolkit.ps1'
    $oldGenerated = @($historicalNative.generatedExamples | Where-Object application -eq $app.Folder)
    Assert-Contract ($oldGenerated.Count -eq 1 -and (Get-FileHash -LiteralPath $generatedScript).Hash -ieq $oldGenerated[0].adapterResult.GeneratedScriptSha256) 'Current frontend differs from approved native-v2 bytes.'
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($generatedScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Contract ($parseErrors.Count -eq 0) 'Generated script syntax error.'
    $table = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.HashtableAst]}, $true) | Where-Object { $_.KeyValuePairs.Item1.Value -contains 'AppVendor' })
    Assert-Contract ($table.Count -eq 1) 'Generated metadata table is ambiguous.'
    $processPair = $table[0].KeyValuePairs | Where-Object { $_.Item1.Value -eq 'AppProcessesToClose' }
    $processes = @($processPair.Item2.PipelineElements[0].Expression.SafeGetValue())
    Assert-Contract ($processes.Count -eq 1 -and $processes[0].Name -ceq $app.Process) 'Generated native process metadata differs.'
    $text = [IO.File]::ReadAllText($generatedScript)
    Assert-Contract (-not $text.Contains('You can customize text to appear at the end')) 'Native-v2 completion-prompt profile changed.'
    Assert-Contract (-not [regex]::IsMatch($text, '(?m)^\s*if\s*\(Get-Process|ConvertFrom-Json|ConvertTo-Json|WriteAllText|Get-Item.*VersionInfo|no downgrade attempted')) 'Removed custom logic returned.'
    Assert-Contract (-not (Test-Path -LiteralPath (Join-Path $build.sourceFolder 'SupportFiles/policies.json'))) 'Firefox policy payload was staged.'
    Assert-Contract ($build.fixture -and $build.validation.static -and -not $build.validation.endpoint -and -not $build.validation.business) 'Fixture claims runtime acceptance.'
}
$firefox = Read-AppDefinition (Join-Path $repository 'examples/apps/firefox/app.json')
$policy = @($firefox.deployment.externalPolicyPrerequisites)
Assert-Contract ($policy.Count -eq 1 -and $policy[0].provider -ceq 'Intune' -and $policy[0].setting -ceq 'DisableAppUpdate' -and $policy[0].requiredValue -eq $true) 'Firefox external policy prerequisite changed.'
Assert-Contract ($null -eq $policy[0].PSObject.Properties['verificationStatus'] -and $null -eq $policy[0].PSObject.Properties['policyId']) 'Policy verification returned to authored intent.'
# General hook coverage is separate from the Main-only application fixture assertions.
$shared = New-ApplicationTestInputs -Root (Join-Path $testRoot 'shared-phases')
$sharedDefinition = Read-AppJson $shared.DefinitionPath
$sharedDefinition.actions.Install | Add-Member -NotePropertyName Pre -NotePropertyValue 'Shared.ps1'
$sharedDefinition.actions.Install | Add-Member -NotePropertyName Post -NotePropertyValue 'Shared.ps1'
[IO.File]::WriteAllText((Join-Path $shared.ApplicationRoot 'Shared.ps1'), "Write-ADTLogEntry -Message 'Shared phase fixture'", [Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText($shared.DefinitionPath, ($sharedDefinition | ConvertTo-Json -Depth 80), [Text.UTF8Encoding]::new($false))
$sharedResolved = & (Join-Path $repository 'scripts/Resolve-Application.ps1') -DefinitionPath $shared.DefinitionPath -ReleasePath $shared.ReleasePath -InstallerPath $shared.InstallerPath -EvidencePath $shared.EvidencePath -AllowFixture
Assert-Contract (@($sharedResolved.inputs | Where-Object { $_.role -eq 'action' -and $_.relativePath -ceq 'Shared.ps1' }).Count -eq 1) 'Repeated action source was not deduplicated.'
$sharedResolvedPath = Join-Path $shared.Root 'resolved-shared.json'
Write-AppJsonAtomic $sharedResolvedPath $sharedResolved
$sharedBuild = & (Join-Path $repository 'scripts/Build-Application.ps1') -ResolvedPath $sharedResolvedPath -TemplatePath (Join-Path $repository '.research/psadt/pristine') -DestinationPath (Join-Path $shared.Root 'build') -Execute
$sharedScript = [IO.File]::ReadAllText((Join-Path $sharedBuild.sourceFolder 'Invoke-AppDeployToolkit.ps1'))
Assert-Contract ([regex]::Matches($sharedScript, 'Shared phase fixture').Count -eq 2) 'Shared source did not populate both declared task locations.'
Assert-Contract (@($sharedBuild.inputSnapshots | Where-Object relativePath -CEQ 'Shared.ps1').Count -eq 1) 'Shared action produced duplicate snapshots.'
# Guards are installed after fixture creation; packaging preview must not invoke any of them.
function Import-Module { throw 'Preview must not import a publishing module.' }
function New-IntuneWin32AppPackage { throw 'Preview must not run content preparation.' }
function Connect-MSIntuneGraph { throw 'Preview must not authenticate.' }
function Invoke-RestMethod { throw 'Preview must not invoke HTTP.' }
function Invoke-WebRequest { throw 'Preview must not invoke HTTP.' }
$previewOutput = Join-Path $testRoot 'package-preview'
$packagePreview = & (Join-Path $repository 'examples/Package-Application.example.ps1') -BuildManifestPath $fixtures.firefox.BuildManifestPath -OutputFolder $previewOutput -IntuneWin32AppManifestPath (Join-Path $repository '.research/intune/IntuneWin32App.1.5.0/IntuneWin32App.psd1') -ContentPrepToolPath (Join-Path $repository '.research/intune/IntuneWinAppUtil-1.8.7.exe')
Assert-Contract ($packagePreview.installCommand -ceq $expectedInstall -and $packagePreview.uninstallCommand -ceq $expectedUninstall -and $packagePreview.setupFile -ceq 'Invoke-AppDeployToolkit.exe') 'Manifest-driven packaging preview disagrees with publication.'
Assert-Contract (-not (Test-Path -LiteralPath $previewOutput)) 'Packaging preview created output.'
[pscustomobject]@{Passed=$true;PowerShellVersion=$PSVersionTable.PSVersion.ToString();Checks=$script:checkCount;Applications=@($apps.Folder);HistoricalDetectionPreserved=$true;DetectionLogicPreserved=$true;Artifacts=$testRoot;Limitation='Offline fixture and contract checks only; no deployment, packaging, module import, authentication or tenant operation.'}
