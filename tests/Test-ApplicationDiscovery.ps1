#requires -Version 5.1
<# Isolated provider/import mocks exercise discovery without importing Evergreen or making network calls. Run in a fresh process. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$discovery = Join-Path $repo 'examples/Discover-Application.example.ps1'
. (Join-Path $repo 'scripts/Application.Core.ps1')
$testRoot = Join-Path $repo ('.validation/discovery-' + [guid]::NewGuid().ToString('N'))
$definitions = Join-Path $testRoot 'definitions'
$null = New-Item -ItemType Directory -Path $definitions -Force
$manifest = Join-Path $testRoot 'Evergreen.psd1'
[IO.File]::WriteAllText($manifest, "@{ ModuleVersion = '2610.2859.0' }", [Text.UTF8Encoding]::new($false))
$definitionPaths = @{}
foreach ($app in @('firefox','notepadplusplus')) {
    $definitionPaths[$app] = Join-Path $testRoot ($app + '.json')
    Copy-Item -LiteralPath (Join-Path $repo "examples/apps/$app/app.json") -Destination $definitionPaths[$app]
}
$global:DiscoveryTestState = @{Manifest=$manifest;Imports=0;Queries=0;Candidates=@();LastQuery=$null;DuringQuery=$null}
function global:Import-Module {
    [CmdletBinding()]param([string]$Name,[string]$Scope)
    if ($Name -cne $global:DiscoveryTestState.Manifest -or $Scope -cne 'Local') { throw 'Unexpected module import in discovery test.' }
    $global:DiscoveryTestState.Imports++
}
function global:Get-EvergreenApp {
    [CmdletBinding()]param([string]$Name,[hashtable]$AppParams)
    $global:DiscoveryTestState.Queries++
    $global:DiscoveryTestState.LastQuery = @{Name=$Name;AppParams=$AppParams}
    if ($global:DiscoveryTestState.DuringQuery) { & $global:DiscoveryTestState.DuringQuery }
    return $global:DiscoveryTestState.Candidates
}
function global:Invoke-WebRequest { throw 'Unexpected network request in offline discovery test.' }
function global:Invoke-RestMethod { throw 'Unexpected network request in offline discovery test.' }
function global:Connect-MSIntuneGraph { throw 'Unexpected authentication in discovery test.' }
function global:Add-IntuneWin32App { throw 'Unexpected publication in discovery test.' }
$checks = 0
function Assert-Discovery([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw $Message }; $script:checks++
}
function Assert-Rejected([scriptblock]$Action,[string]$Pattern) {
    try { $null = & $Action } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw "Unexpected rejection: $($_.Exception.Message)" }
        $script:checks++; return
    }
    throw "Expected rejection matching $Pattern"
}
function Invoke-Discovery([string]$App='firefox',[string]$OutputPath) {
    $parameters = @{DefinitionPath=$definitionPaths[$App];EvergreenManifestPath=$manifest;DefinitionsPath=$definitions}
    if ($OutputPath) { $parameters.OutputPath = $OutputPath }
    & $discovery @parameters
}
function New-Candidate([string]$Type='msi',[string]$Architecture='x64',[string]$Version='159.0.1',[string]$Uri='https://archive.mozilla.org/example/Firefox.msi',[string]$InstallerType='Default') {
    [pscustomobject]@{Version=$Version;Architecture=$Architecture;Type=$Type;Channel='Current';Language='en-US';InstallerType=$InstallerType;URI=$Uri;Sha256=('a'*64);UnrelatedSecret='must-not-be-persisted'}
}
function Write-TestDefinition([string]$Name,$Definition) {
    $definitionPaths[$Name] = Join-Path $testRoot ($Name + '.json')
    [IO.File]::WriteAllText($definitionPaths[$Name],($Definition|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
}
$originalCache = [Environment]::GetEnvironmentVariable('EVERGREEN_APPS_PATH','Process')
$env:EVERGREEN_APPS_PATH = 'retained-test-cache'
try {
    $beforeHash = (Get-FileHash -LiteralPath $definitionPaths.firefox).Hash
    $global:DiscoveryTestState.Candidates = @((New-Candidate), (New-Candidate -Architecture 'x86'))
    $outputPath = Join-Path $testRoot 'firefox-release.json'
    $release = Invoke-Discovery -OutputPath $outputPath
    Assert-Discovery ($release.recordType -ceq 'DiscoveredRelease' -and $release.applicationId -ceq 'mozilla.firefox.current.x64.en-us') 'Unexpected v3 release identity.'
    Assert-Discovery ($global:DiscoveryTestState.LastQuery.Name -ceq 'MozillaFirefox' -and $global:DiscoveryTestState.LastQuery.AppParams.Language.Count -eq 1 -and $global:DiscoveryTestState.LastQuery.AppParams.Language[0] -ceq 'en-US') 'Firefox language was not mapped to a single-element AppParams array.'
    Assert-Discovery ($release.version -ceq '159.0.1' -and $release.variant.architecture -ceq 'x64') 'Exact Firefox selection failed.'
    Assert-Discovery ((Get-FileHash -LiteralPath $definitionPaths.firefox).Hash -ceq $beforeHash) 'Discovery changed its authored definition.'
    Assert-Discovery ($env:EVERGREEN_APPS_PATH -ceq 'retained-test-cache') 'Discovery did not restore the prior definition cache environment.'
    Assert-Discovery (-not $release.rawMetadata.PSObject.Properties['URI'] -and -not $release.rawMetadata.PSObject.Properties['UnrelatedSecret']) 'Discovery retained unapproved provider fields.'
    Assert-AppJsonSchema -Path $outputPath -SchemaPath (Join-Path $repo 'schemas/discovered-release.v1.schema.json')
    $checks++

    $outputHash = (Get-FileHash -LiteralPath $outputPath).Hash
    $queryCount = $global:DiscoveryTestState.Queries
    Assert-Rejected {Invoke-Discovery -OutputPath $outputPath} 'Output exists'
    Assert-Discovery ($global:DiscoveryTestState.Queries -eq $queryCount -and (Get-FileHash -LiteralPath $outputPath).Hash -ceq $outputHash) 'Existing output was queried again or overwritten.'
    $global:DiscoveryTestState.Candidates = @((New-Candidate -Type 'exe' -Version '8.9.8.1' -Uri 'https://github.com/example/npp.Installer.x64.exe'), (New-Candidate -Type 'exe' -Version '8.9.8.1' -Uri 'https://github.com/example/npp.portable.x64.zip'), (New-Candidate -Type 'exe' -Version '8.9.8.1' -Uri 'https://github.com/example/minimal.Installer.x64.exe' -InstallerType 'Minimal'))
    $nppOutput = Join-Path $testRoot 'notepadplusplus-release.json'
    $nppRelease = Invoke-Discovery -App 'notepadplusplus' -OutputPath $nppOutput
    Assert-Discovery ($nppRelease.version -ceq '8.9.8.1' -and $nppRelease.sourceUrl -ceq 'https://github.com/example/npp.Installer.x64.exe') 'Installer-versus-portable selection failed.'
    Assert-Discovery ($global:DiscoveryTestState.LastQuery.Name -ceq 'NotepadPlusPlus' -and $null -eq $global:DiscoveryTestState.LastQuery.AppParams) 'Notepad++ unexpectedly supplied a Language AppParams value.'
    Assert-AppJsonSchema -Path $nppOutput -SchemaPath (Join-Path $repo 'schemas/discovered-release.v1.schema.json')
    $checks++

    $global:DiscoveryTestState.Candidates = @()
    Assert-Rejected {Invoke-Discovery} 'Expected exactly one installer; found 0'
    Assert-Discovery ($env:EVERGREEN_APPS_PATH -ceq 'retained-test-cache') 'Failure did not restore the prior cache environment.'
    $global:DiscoveryTestState.Candidates = @((New-Candidate),(New-Candidate))
    Assert-Rejected {Invoke-Discovery} 'Expected exactly one installer; found 2'
    $missingLanguage = New-Candidate
    $missingLanguage.PSObject.Properties.Remove('Language')
    $global:DiscoveryTestState.Candidates = @($missingLanguage)
    Assert-Rejected {Invoke-Discovery} 'Expected exactly one installer; found 0'
    foreach ($uri in @('https://archive.mozilla.org/file.msi?token=secret','https://archive.mozilla.org/file.msi#fragment','https://user:secret@archive.mozilla.org/file.msi','https://unapproved.example/file.msi')) {
        $global:DiscoveryTestState.Candidates = @((New-Candidate -Uri $uri))
        Assert-Rejected {Invoke-Discovery} 'allowed HTTPS URL'
    }
    $global:DiscoveryTestState.Candidates = @((New-Candidate -Version 'RateLimited'))
    Assert-Rejected {Invoke-Discovery} 'supported numeric release version'
    $missingHash = New-Candidate
    $missingHash.PSObject.Properties.Remove('Sha256')
    $global:DiscoveryTestState.Candidates = @($missingHash)
    Assert-Rejected {Invoke-Discovery} 'vendor SHA256'
    $nested = New-Candidate
    $nested.InstallerType = @{nested='must-not-be-persisted'}
    $global:DiscoveryTestState.Candidates = @($nested)
    Assert-Rejected {Invoke-Discovery} 'metadata must be a string or null'

    $firefoxText = [IO.File]::ReadAllText($definitionPaths.firefox)
    $pinned = $firefoxText | ConvertFrom-Json
    $pinned.variant.versionPolicy = 'pinned'; $pinned.variant.targetVersion = '158.0.0'
    Write-TestDefinition 'pinned' $pinned
    $global:DiscoveryTestState.Candidates = @((New-Candidate))
    Assert-Rejected {Invoke-Discovery -App 'pinned'} 'does not locate historical installers'
    $global:DiscoveryTestState.Candidates = @((New-Candidate -Version '158.0.0'))
    $pinnedRelease = Invoke-Discovery -App 'pinned'
    Assert-Discovery ($pinnedRelease.version -ceq '158.0.0') 'Matching pinned release was rejected.'
    $legacy = $firefoxText | ConvertFrom-Json; $legacy.schemaVersion = 2
    Write-TestDefinition 'legacy' $legacy
    $queryCount = $global:DiscoveryTestState.Queries
    Assert-Rejected {Invoke-Discovery -App 'legacy'} 'schemaVersion 3.*Migrate'
    Assert-Discovery ($global:DiscoveryTestState.Queries -eq $queryCount) 'Legacy input reached the provider.'

    $changed = $firefoxText | ConvertFrom-Json
    $changed.variant.language = 'fr'
    Write-TestDefinition 'language' $changed
    $frenchCandidate = New-Candidate; $frenchCandidate.Language = 'fr'
    $global:DiscoveryTestState.Candidates = @($frenchCandidate)
    $frenchRelease = Invoke-Discovery -App 'language'
    Assert-Discovery ($frenchRelease.discoveryFingerprint -cne $release.discoveryFingerprint -and $global:DiscoveryTestState.LastQuery.AppParams.Language[0] -ceq 'fr') 'Changed canonical language did not update selection and fingerprint.'
    $changed = $firefoxText | ConvertFrom-Json
    $changed.displayName = 'Reviewed display text'
    $changed.targets.pilotGroupId = '00000000-0000-0000-0000-000000000001'
    Write-TestDefinition 'presentation' $changed
    $global:DiscoveryTestState.Candidates = @((New-Candidate))
    $presentation = Invoke-Discovery -App 'presentation'
    Assert-Discovery ($presentation.discoveryFingerprint -ceq $release.discoveryFingerprint -and $presentation.definitionSha256 -cne $release.definitionSha256) 'Rollout/display changes incorrectly altered discovery identity or failed to retain full provenance.'

    $global:DiscoveryTestState.DuringQuery = { [IO.File]::AppendAllText($definitionPaths.firefox,[Environment]::NewLine) }
    Assert-Rejected {Invoke-Discovery} 'definition changed during discovery'
    $global:DiscoveryTestState.DuringQuery = $null
    [IO.File]::WriteAllText($definitionPaths.firefox,$firefoxText,[Text.UTF8Encoding]::new($false))
    $aliasRelease = & $discovery -RecipePath $definitionPaths.firefox -EvergreenManifestPath $manifest -DefinitionsPath $definitions
    Assert-Discovery ($aliasRelease.applicationId -ceq $release.applicationId) 'RecipePath parameter alias no longer accepts v3 input.'

    [IO.File]::WriteAllText($manifest,"@{ ModuleVersion = '1.0.0' }",[Text.UTF8Encoding]::new($false))
    $queryCount = $global:DiscoveryTestState.Queries
    Assert-Rejected {Invoke-Discovery} 'Evergreen version mismatch'
    Assert-Discovery ($global:DiscoveryTestState.Queries -eq $queryCount) 'A mismatched module pin reached the provider.'
    [IO.File]::WriteAllText($manifest,"@{ ModuleVersion = '2610.2859.0' }",[Text.UTF8Encoding]::new($false))
    $null = New-Item -ItemType Directory -Path (Join-Path $definitions 'Filters')
    Assert-Rejected {Invoke-Discovery} 'Unexpected local filters'
} finally {
    [Environment]::SetEnvironmentVariable('EVERGREEN_APPS_PATH',$originalCache,'Process')
}
[pscustomobject]@{Checks=$checks;Passed=$true;Runtime=$PSVersionTable.PSVersion.ToString();Scope='Mocked discovery only; no module import or network';OutputDirectory=$testRoot}
