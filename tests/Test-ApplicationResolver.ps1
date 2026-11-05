#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
. (Join-Path $repository 'scripts/Application.Core.ps1')
$scratch = Join-Path $repository ('.validation/resolver-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
$definitionPath = Join-Path $repository 'examples/apps/firefox/app.json'
$definition = Read-AppDefinition $definitionPath
$payload = Join-Path $scratch 'installer.msi'
[IO.File]::WriteAllText($payload, 'OFFLINE TEST FIXTURE - not an installer')
$hash = (Get-FileHash -LiteralPath $payload).Hash.ToLowerInvariant()
$release = [pscustomobject]@{
    schemaVersion=1;recordType='DiscoveredRelease';applicationId=$definition.id;definitionSha256=(Get-FileHash $definitionPath).Hash.ToLowerInvariant()
    discoveryFingerprint=Get-AppDiscoveryFingerprint $definition;version='159.0.1';sourceUrl='https://archive.mozilla.org/example.msi';vendorSha256=$hash
    variant=$definition.variant;evergreenModuleVersion=$definition.source.moduleVersion;definitionsRelease=$definition.source.definitionsRelease
    discoveredAtUtc='2026-11-05T00:00:00Z';rawMetadata=@{}
}
$evidence = [pscustomobject]@{
    schemaVersion=1;recordType='InstallerEvidence';fixture=$true;applicationId=$definition.id;version=$release.version;sha256=$hash
    finalUrl=$release.sourceUrl;identity=@{productName=$definition.validation.expectedProductName;architecture='x64';version=$release.version;language='en-US';msiProperties=@{}}
    review=@{approvedBy='Offline fixture';approvedAtUtc='2026-11-05T00:00:00Z'}
}
$releasePath = Join-Path $scratch 'release.json'; $evidencePath = Join-Path $scratch 'installer-evidence.json'
Write-AppJsonAtomic $releasePath $release; Write-AppJsonAtomic $evidencePath $evidence
$resolver = Join-Path $repository 'scripts/Resolve-Application.ps1'
$inputs = @{DefinitionPath=$definitionPath;ReleasePath=$releasePath;InstallerPath=$payload;EvidencePath=$evidencePath}
$resolved = & $resolver @inputs -AllowFixture
if (-not $resolved.fixture -or $resolved.metadata.AppVersion -ne '159.0.1' -or $resolved.metadata.AppProcessesToClose[0].Name -ne 'firefox') { throw 'Resolved metadata mismatch.' }
Assert-AppRecord $resolved 'ResolvedBuild'
$again = & $resolver @inputs -AllowFixture
if ($again.buildId -cne $resolved.buildId) { throw 'Stable inputs changed identity.' }
$rejected = $false
try { & $resolver @inputs | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Fixture accepted without explicit opt-in.' }
[IO.File]::AppendAllText($payload, 'tampered')
$rejected = $false
try { & $resolver @inputs -AllowFixture | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Changed payload accepted.' }
$checks = 5
$results = [Collections.Generic.List[object]]::new()
function Assert-Resolver($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function New-ResolverFixture([string]$Name) {
    $caseRoot = Join-Path $scratch $Name
    $appRoot = Join-Path $caseRoot 'application'
    $null = New-Item -ItemType Directory -Path $caseRoot
    Copy-Item -LiteralPath (Split-Path -Parent $definitionPath) -Destination $appRoot -Recurse
    $installerPath = Join-Path $caseRoot 'installer.msi'
    [IO.File]::WriteAllText($installerPath, 'OFFLINE TEST FIXTURE - not an installer')
    [pscustomobject]@{
        Root=$caseRoot;DefinitionPath=(Join-Path $appRoot 'app.json');ReleasePath=(Join-Path $caseRoot 'release.json')
        EvidencePath=(Join-Path $caseRoot 'evidence.json');InstallerPath=$installerPath
        Definition=(Read-AppJson $definitionPath);Release=(Read-AppJson $releasePath);Evidence=(Read-AppJson $evidencePath)
    }
}
function Save-ResolverFixture($Case) {
    foreach ($item in @(@{path=$Case.DefinitionPath;value=$Case.Definition}, @{path=$Case.ReleasePath;value=$Case.Release}, @{path=$Case.EvidencePath;value=$Case.Evidence})) {
        # These are disposable test inputs; production atomic writes remain unchanged.
        [IO.File]::WriteAllText($item.path, ($item.value | ConvertTo-Json -Depth 80), [Text.UTF8Encoding]::new($false))
    }
}
function Invoke-ResolverFixture($Case, [switch]$NonFixture) {
    Save-ResolverFixture $Case
    & $resolver -DefinitionPath $Case.DefinitionPath -ReleasePath $Case.ReleasePath -InstallerPath $Case.InstallerPath -EvidencePath $Case.EvidencePath -AllowFixture:(-not $NonFixture)
}
function Assert-ResolverRejected([scriptblock]$Body, [string]$Pattern) {
    $rejected = $false
    try { & $Body | Out-Null } catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; $rejected = $true }
    Assert-Resolver $rejected 'The resolver accepted invalid or incomplete inputs.'
}
function Set-CompletedTestEvidence($Case) {
    # This synthetic record only exercises evidence gates. No real installer is accepted.
    $Case.Evidence.fixture = $false
    $Case.Evidence.review.approvedBy = 'Synthetic test reviewer'
    foreach ($property in $Case.Definition.validation.msiPropertiesToRecord) {
        $Case.Evidence.identity.msiProperties | Add-Member -NotePropertyName $property -NotePropertyValue ('Synthetic inspected ' + $property) -Force
    }
}
function Test-ResolverCase([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:checks++; $results.Add([pscustomobject]@{name=$Name;passed=$true}); Write-Host "PASS $Name" }
    catch { $results.Add([pscustomobject]@{name=$Name;passed=$false;error=$_.Exception.Message}); Write-Host "FAIL $Name : $($_.Exception.Message)" }
}
Test-ResolverCase 'Name-only native processes do not generate null descriptions' {
    $case = New-ResolverFixture 'name-only-process'
    $case.Definition.deployment.processes = @([pscustomobject]@{name='firefox'})
    $result = Invoke-ResolverFixture $case
    Assert-Resolver ($result.metadata.AppProcessesToClose[0].Name -ceq 'firefox') 'The process name changed.'
    Assert-Resolver (!$result.metadata.AppProcessesToClose[0].Contains('Description')) 'Optional Description was emitted as null.'
}
Test-ResolverCase 'Blank required MSI evidence is rejected before signature evaluation' {
    $case = New-ResolverFixture 'blank-msi'
    Set-CompletedTestEvidence $case
    $case.Definition.validation.requireAuthenticode = $false
    $case.Evidence.identity.msiProperties.ProductCode = '  '
    Assert-ResolverRejected { Invoke-ResolverFixture $case -NonFixture } 'Required inspected MSI property was not completed: ProductCode'
}
Test-ResolverCase 'Equivalent action property order preserves build identity' {
    $case = New-ResolverFixture 'action-order'
    $case.Definition.actions.Install | Add-Member -NotePropertyName Pre -NotePropertyValue $case.Definition.actions.Install.Main
    $first = Invoke-ResolverFixture $case
    $case.Definition.actions = [pscustomobject][ordered]@{
        Repair=$case.Definition.actions.Repair;Uninstall=$case.Definition.actions.Uninstall
        Install=[pscustomobject][ordered]@{Pre=$case.Definition.actions.Install.Pre;Main=$case.Definition.actions.Install.Main}
    }
    $second = Invoke-ResolverFixture $case
    Assert-Resolver ($first.buildId -ceq $second.buildId) 'Reordering action/phase properties changed build identity.'
}
Test-ResolverCase 'Target edits preserve build identity and action edits change it' {
    $case = New-ResolverFixture 'source-versus-target'
    $first = Invoke-ResolverFixture $case
    $case.Definition.targets.pilotGroupId = '11111111-2222-3333-4444-555555555555'
    $targetChanged = Invoke-ResolverFixture $case
    Assert-Resolver ($first.buildId -ceq $targetChanged.buildId) 'A rollout target edit changed the payload build identity.'
    Assert-Resolver ($first.definitionSha256 -cne $targetChanged.definitionSha256) 'Target edit disappeared from provenance.'
    $actionPath = Join-Path (Split-Path -Parent $case.DefinitionPath) $case.Definition.actions.Install.Main
    [IO.File]::AppendAllText($actionPath, "`r`n# reviewed test action revision`r`n", [Text.UTF8Encoding]::new($false))
    $actionChanged = Invoke-ResolverFixture $case
    Assert-Resolver ($targetChanged.buildId -cne $actionChanged.buildId) 'An action source edit did not change build identity.'
    Assert-Resolver ($first.discoveryFingerprint -ceq $actionChanged.discoveryFingerprint) 'An action edit unexpectedly changed discovery intent.'
}
Test-ResolverCase 'Changed signer policy revalidates the retained installer against the current policy' {
    $case = New-ResolverFixture 'changed-signer-policy'
    Set-CompletedTestEvidence $case
    $case.Definition.validation.requireAuthenticode = $true
    $case.Definition.validation.approvedSignerSubjects = @('CN=Synthetic Approved Signer')
    $signatureProbe = [pscustomobject]@{Calls=0}
    function Get-AuthenticodeSignature {
        param([string]$LiteralPath)
        Assert-Resolver ($LiteralPath -ceq $case.InstallerPath) 'Signature validation inspected a different file.'
        $signatureProbe.Calls++
        [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Synthetic Approved Signer'}}
    }
    $accepted = Invoke-ResolverFixture $case -NonFixture
    Assert-Resolver ($signatureProbe.Calls -eq 1 -and $accepted.provenance.authenticode.status -ceq 'Valid') 'The current signer policy was not evaluated.'
    $case.Definition.validation.approvedSignerSubjects = @('CN=Different Approved Signer')
    Assert-ResolverRejected { Invoke-ResolverFixture $case -NonFixture } 'Installer Authenticode signature or approved signer does not satisfy policy'
    Assert-Resolver ($signatureProbe.Calls -eq 2) 'The changed policy reused an earlier signature decision.'
}
foreach ($scenario in @(
    @{name='evidence-application';change={param($c) $c.Evidence.applicationId='other.application'};pattern='Installer evidence does not match'},
    @{name='evidence-version';change={param($c) $c.Evidence.version='158.0.1'};pattern='Installer evidence does not match'},
    @{name='identity-version';change={param($c) $c.Evidence.identity.version='158.0.1'};pattern='Reviewed installer identity does not match'},
    @{name='identity-product';change={param($c) $c.Evidence.identity.productName='Other product'};pattern='Reviewed installer identity does not match'},
    @{name='pending-hash';change={param($c) $c.Evidence.sha256=$null};pattern='Installer evidence does not match'},
    @{name='pending-url';change={param($c) $c.Evidence.finalUrl=$null};pattern='Download identity requires'},
    @{name='pending-identity';change={param($c) $c.Evidence.identity=$null};pattern='Reviewed installer identity does not match'}
)) {
    Test-ResolverCase ('Reject incomplete or mismatched evidence: ' + $scenario.name) {
        $case = New-ResolverFixture $scenario.name
        & $scenario.change $case
        Assert-ResolverRejected { Invoke-ResolverFixture $case } $scenario.pattern
    }
}
foreach ($field in @('approvedBy','approvedAtUtc')) {
    Test-ResolverCase ('Reject pending named review: ' + $field) {
        $case = New-ResolverFixture ('pending-' + $field)
        Set-CompletedTestEvidence $case
        $case.Definition.validation.requireAuthenticode = $false
        $case.Evidence.review.$field = $null
        Assert-ResolverRejected { Invoke-ResolverFixture $case -NonFixture } 'Installer identity requires named, dated engineer review'
    }
}
function Get-ResolverInventoryHash([string]$Root) {
    $inventory = @(foreach ($item in (Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName)) {
        [pscustomobject]@{path=$item.FullName.Substring($Root.Length);directory=$item.PSIsContainer;hash=$(if (!$item.PSIsContainer) { (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash } else { $null })}
    })
    Get-AppObjectHash $inventory
}
Test-ResolverCase 'Resolution creates no files or directories and leaves all local input bytes unchanged' {
    $case = New-ResolverFixture 'read-only-resolution'
    Save-ResolverFixture $case
    $before = Get-ResolverInventoryHash $case.Root
    $null = & $resolver -DefinitionPath $case.DefinitionPath -ReleasePath $case.ReleasePath -InstallerPath $case.InstallerPath -EvidencePath $case.EvidencePath -AllowFixture
    Assert-Resolver ($before -ceq (Get-ResolverInventoryHash $case.Root)) 'Successful resolution changed local input files or created outputs.'
    $case.Definition.actions.Install.Main = 'missing-action.ps1'
    Save-ResolverFixture $case
    $beforeRejected = Get-ResolverInventoryHash $case.Root
    Assert-ResolverRejected { & $resolver -DefinitionPath $case.DefinitionPath -ReleasePath $case.ReleasePath -InstallerPath $case.InstallerPath -EvidencePath $case.EvidencePath -AllowFixture } 'Required source file missing'
    Assert-Resolver ($beforeRejected -ceq (Get-ResolverInventoryHash $case.Root)) 'Rejected resolution changed local inputs or created outputs.'
}
Test-ResolverCase 'Named installer review requires an actual UTC timestamp' {
    $case = New-ResolverFixture 'invalid-review-date'
    Set-CompletedTestEvidence $case
    $case.Definition.validation.requireAuthenticode = $false
    $case.Evidence.review.approvedAtUtc = 'not-a-date'
    Assert-ResolverRejected { Invoke-ResolverFixture $case -NonFixture } 'Installer identity requires named, dated engineer review'
}
Test-ResolverCase 'A reviewed action source can serve multiple task locations without duplicate snapshots' {
    $case = New-ResolverFixture 'reused-action'
    $case.Definition.actions.Uninstall.Main = $case.Definition.actions.Install.Main
    $resolved = Invoke-ResolverFixture $case
    Assert-Resolver (@($resolved.inputs | Where-Object { $_.role -eq 'action' -and $_.relativePath -eq $case.Definition.actions.Install.Main }).Count -eq 1) 'A reused action produced duplicate snapshot inputs.'
}
$summary = [pscustomobject]@{Passed=(@($results | Where-Object { !$_.passed }).Count -eq 0);Checks=$checks;Failed=@($results | Where-Object { !$_.passed }).Count;Runtime=$PSVersionTable.PSVersion.ToString();Scratch=$scratch;Tests=$results.ToArray()}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $scratch 'results.json') -Encoding UTF8
$summary
if (-not $summary.Passed) { throw "$($summary.Failed) resolver regression tests failed." }
