#requires -Version 7.0
<# Uses Test-Json with draft 2020-12 support. Reads definitions only; no application or tenant operations. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$schema = Join-Path $repo 'schemas/application-definition.v3.schema.json'
$checks = 0

function Assert-SchemaResult {
    param([object]$Definition, [bool]$Expected, [string]$Name)
    $errors = @()
    $actual = Test-Json -Json ($Definition | ConvertTo-Json -Depth 30) -SchemaFile $schema `
        -ErrorAction SilentlyContinue -ErrorVariable errors
    if ($actual -ne $Expected) { throw "Schema expectation failed: $Name. $($errors -join ' ')" }
    $script:checks++
}

$firefoxText = Get-Content -LiteralPath (Join-Path $repo 'examples/apps/firefox/app.json') -Raw -Encoding UTF8
foreach ($app in @('firefox', 'notepadplusplus')) {
    $definition = Get-Content -LiteralPath (Join-Path $repo "examples/apps/$app/app.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-SchemaResult $definition $true "$app active definition"
}
$pinned = $firefoxText | ConvertFrom-Json
$pinned.variant.versionPolicy = 'pinned'
$pinned.variant.targetVersion = '159.0.1'
Assert-SchemaResult $pinned $true 'explicit numeric pinned release'
$hooks = $firefoxText | ConvertFrom-Json
foreach ($operation in @('Install', 'Uninstall', 'Repair')) {
    $hooks.actions.$operation | Add-Member -NotePropertyName Pre -NotePropertyValue "Actions/Pre-$operation.ps1"
    $hooks.actions.$operation | Add-Member -NotePropertyName Post -NotePropertyValue "Actions/Post-$operation.ps1"
}
$hooks.payloads.support = @([pscustomobject]@{source='Configuration/policy.json';destination='Configuration/policy.json'})
Assert-SchemaResult $hooks $true 'all nine task locations and contained support paths'

$cases = @(
    @{Name='v2 definition'; Change={param($d) $d.schemaVersion=2}},
    @{Name='unknown root value'; Change={param($d) $d | Add-Member -NotePropertyName unknown -NotePropertyValue 'value'}},
    @{Name='legacy installer command'; Change={param($d) $d.deployment | Add-Member -NotePropertyName install -NotePropertyValue @{arguments='/S'}}},
    @{Name='legacy metadata file'; Change={param($d) $d.toolkit | Add-Member -NotePropertyName metadataFile -NotePropertyValue 'metadata.json'}},
    @{Name='raw metadata override'; Change={param($d) $d.toolkit | Add-Member -NotePropertyName AppVendor -NotePropertyValue 'Other'}},
    @{Name='unknown profile'; Change={param($d) $d.toolkit.profile='unreviewed-profile'}},
    @{Name='unsupported mode'; Change={param($d) $d.deployment.mode='Silent'}},
    @{Name='unsupported architecture'; Change={param($d) $d.variant.architecture='arm64'}},
    @{Name='duplicated detection architecture'; Change={param($d) $d.detection | Add-Member -NotePropertyName architecture -NotePropertyValue 'x64'}},
    @{Name='mutable validation approval'; Change={param($d) $d.validation | Add-Member -NotePropertyName identityReviewStatus -NotePropertyValue 'approved'}},
    @{Name='unsupported repair'; Change={param($d) $d.deployment.repair.supported=$true}},
    @{Name='missing main action'; Change={param($d) $d.actions.Install.PSObject.Properties.Remove('Main')}},
    @{Name='unknown action phase'; Change={param($d) $d.actions.Install | Add-Member -NotePropertyName Finally -NotePropertyValue 'Finally.ps1'}},
    @{Name='escaping action'; Change={param($d) $d.actions.Install.Main='../outside.ps1'}},
    @{Name='nested escaping action'; Change={param($d) $d.actions.Install.Main='Actions/../../outside.ps1'}},
    @{Name='absolute action'; Change={param($d) $d.actions.Install.Main='C:\outside.ps1'}},
    @{Name='rooted action'; Change={param($d) $d.actions.Install.Main='/outside.ps1'}},
    @{Name='alternate stream'; Change={param($d) $d.actions.Install.Main='Install.ps1:stream'}},
    @{Name='installer destination directory'; Change={param($d) $d.payloads.installer.destination='Files/Firefox.msi'}},
    @{Name='empty installer alias'; Change={param($d) $d.payloads.installer.destination=''}},
    @{Name='invalid selection mapping'; Change={param($d) $d.source.selectionMap.Language='architecture'}},
    @{Name='duplicate selection authority'; Change={param($d) $d.source.selectionConstants | Add-Member -NotePropertyName Architecture -NotePropertyValue 'x64'}},
    @{Name='missing installer selector'; Change={param($d) $d.source.selectionMap.PSObject.Properties.Remove('Type')}},
    @{Name='latest with target'; Change={param($d) $d.variant.targetVersion='159.0.1'}},
    @{Name='pinned without target'; Change={param($d) $d.variant.versionPolicy='pinned'}},
    @{Name='nonnumeric pinned version'; Change={param($d) $d.variant.versionPolicy='pinned';$d.variant.targetVersion='159.0-beta'}},
    @{Name='unsupported detection binding'; Change={param($d) $d.detection.binding='OtherVersion'}},
    @{Name='unsupported requirement'; Change={param($d) $d.intune.requirements.applicability='update-only'}},
    @{Name='invalid target group'; Change={param($d) $d.targets.pilotGroupId='replace-me'}}
)
foreach ($case in $cases) {
    $definition = $firefoxText | ConvertFrom-Json
    $null = & $case.Change $definition
    Assert-SchemaResult $definition $false $case.Name
}

# These synthetic in-memory records test shape only. They are not installer acceptance evidence.
$schema = Join-Path $repo 'schemas/discovered-release.v1.schema.json'
$definition = $firefoxText | ConvertFrom-Json
$release = [pscustomobject]@{
    schemaVersion=1;recordType='DiscoveredRelease';applicationId=$definition.id
    definitionSha256=('a'*64);discoveryFingerprint=('b'*64);version='159.0.1'
    sourceUrl='https://archive.mozilla.org/example/Firefox.msi';vendorSha256=('c'*64)
    variant=$definition.variant;evergreenModuleVersion='2610.2859.0'
    definitionsRelease='v26.11.03.146';discoveredAtUtc='2026-11-05T00:00:00Z'
    rawMetadata=[pscustomobject]@{Version='159.0.1';Architecture='x64';Type='msi'}
}
Assert-SchemaResult $release $true 'synthetic discovered record'
$releaseJson = $release | ConvertTo-Json -Depth 20
foreach ($badUrl in @('http://archive.mozilla.org/file.msi','https://archive.mozilla.org/file.msi?token=secret','https://archive.mozilla.org/file.msi#fragment','https://user:secret@archive.mozilla.org/file.msi')) {
    $changed = $releaseJson | ConvertFrom-Json
    $changed.sourceUrl = $badUrl
    Assert-SchemaResult $changed $false 'reject unsafe persisted discovery URL'
}
$changed = $releaseJson | ConvertFrom-Json
$changed.rawMetadata | Add-Member -NotePropertyName URI -NotePropertyValue 'https://example.invalid/?token=secret'
Assert-SchemaResult $changed $false 'reject provider URI persistence'
$changed = $releaseJson | ConvertFrom-Json
$changed.rawMetadata.Version = @{nested='value'}
Assert-SchemaResult $changed $false 'reject nested provider metadata'
$changed = $releaseJson | ConvertFrom-Json
$changed.discoveryFingerprint = 'unverified'
Assert-SchemaResult $changed $false 'reject invalid discovery fingerprint'

$schema = Join-Path $repo 'schemas/installer-evidence.v1.schema.json'
$evidenceText = Get-Content -LiteralPath (Join-Path $repo 'examples/installer-evidence.example.json') -Raw -Encoding UTF8
Assert-SchemaResult ($evidenceText | ConvertFrom-Json) $true 'pending evidence shape is valid but is not acceptance'
$fixture = $evidenceText | ConvertFrom-Json
$fixture.fixture = $true
$fixture.applicationId = $definition.id
$fixture.version = '159.0.1'
$fixture.sha256 = 'c'*64
$fixture.finalUrl = 'https://archive.mozilla.org/example/Firefox.msi'
$fixture.identity = [pscustomobject]@{productName='Mozilla Firefox';architecture='x64';version='159.0.1';language='en-US';msiProperties=[pscustomobject]@{ProductName='Mozilla Firefox'}}
$fixture.review.approvedBy = 'Schema test fixture; not approval'
$fixture.review.approvedAtUtc = '2026-11-05T00:00:00Z'
Assert-SchemaResult $fixture $true 'synthetic completed fixture shape'
$fixtureJson = $fixture | ConvertTo-Json -Depth 20
foreach ($badUrl in @('https://archive.mozilla.org/file.msi?token=secret','https://archive.mozilla.org/file.msi#fragment','https://user:secret@archive.mozilla.org/file.msi')) {
    $changed = $fixtureJson | ConvertFrom-Json
    $changed.finalUrl = $badUrl
    Assert-SchemaResult $changed $false 'reject unsafe persisted final URL'
}
$changed = $fixtureJson | ConvertFrom-Json
$changed.identity | Add-Member -NotePropertyName accepted -NotePropertyValue $true
Assert-SchemaResult $changed $false 'reject invented acceptance flag'
$changed = $fixtureJson | ConvertFrom-Json
$changed.identity.msiProperties | Add-Member -NotePropertyName ArbitraryValue -NotePropertyValue 'unknown'
Assert-SchemaResult $changed $false 'reject unknown MSI property'
[pscustomobject]@{Checks=$checks;Passed=$true;Runtime=$PSVersionTable.PSVersion.ToString();Scope='Definition, discovery and installer-evidence JSON Schema only; no runtime, installer or tenant validation'}
