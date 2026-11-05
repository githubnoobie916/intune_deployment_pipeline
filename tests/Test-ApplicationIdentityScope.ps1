#requires -Version 5.1
<# Offline identity/staging checks. Uses an isolated repository copy and fake installer bytes. #>
[CmdletBinding()]
param([string]$TemplatePath)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
if (-not $TemplatePath) { $TemplatePath = Join-Path $repository '.research/psadt/pristine' }
$TemplatePath = (Resolve-Path -LiteralPath $TemplatePath).ProviderPath
$testRoot = Join-Path $repository ('.validation/identity-scope-' + [guid]::NewGuid().ToString('N'))
$isolatedRepository = Join-Path $testRoot 'repository'
[IO.Directory]::CreateDirectory($isolatedRepository) | Out-Null
foreach ($folder in @('scripts','schemas')) {
    Copy-Item -LiteralPath (Join-Path $repository $folder) -Destination (Join-Path $isolatedRepository $folder) -Recurse
}
foreach ($folder in @('evidence','examples','examples/apps','tests')) {
    [IO.Directory]::CreateDirectory((Join-Path $isolatedRepository $folder)) | Out-Null
}
foreach ($relative in @('evidence/psadt-4.1.8-release.json','evidence/intunewin32app-1.5.0-inspection.json','examples/Package-Application.example.ps1','tests/ApplicationTest.Fixtures.ps1')) {
    [IO.File]::Copy((Join-Path $repository $relative), (Join-Path $isolatedRepository $relative), $false)
}
Copy-Item -LiteralPath (Join-Path $repository 'examples/apps/firefox') -Destination (Join-Path $isolatedRepository 'examples/apps/firefox') -Recurse
. (Join-Path $isolatedRepository 'scripts/Application.Core.ps1')
. (Join-Path $isolatedRepository 'tests/ApplicationTest.Fixtures.ps1')
$resolver = Join-Path $isolatedRepository 'scripts/Resolve-Application.ps1'
$builder = Join-Path $isolatedRepository 'scripts/Build-Application.ps1'
$checks = 0
$results = [Collections.Generic.List[object]]::new()
function Assert-IdentityScope([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Save-TestJson([string]$Path, $Value) {
    # Existing disposable inputs may change; production record writers remain exclusive.
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 80), [Text.UTF8Encoding]::new($false))
}
function Resolve-TestInputs($Fixture) {
    & $resolver -DefinitionPath $Fixture.DefinitionPath -ReleasePath $Fixture.ReleasePath -InstallerPath $Fixture.InstallerPath -EvidencePath $Fixture.EvidencePath -AllowFixture
}
function Get-TestInventoryHash([string]$Root) {
    $entries = @(foreach ($item in (Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName)) {
        [pscustomobject]@{path=$item.FullName.Substring($Root.Length);directory=$item.PSIsContainer;sha256=$(if (-not $item.PSIsContainer) { (Get-FileHash -LiteralPath $item.FullName).Hash } else { $null })}
    })
    Get-AppObjectHash $entries
}
function Test-IdentityCase([string]$Name, [scriptblock]$Body) {
    try { & $Body; $results.Add([pscustomobject]@{name=$Name;passed=$true}); Write-Host "PASS $Name" }
    catch { $results.Add([pscustomobject]@{name=$Name;passed=$false;error=$_.Exception.Message}); Write-Host "FAIL $Name : $($_.Exception.Message)" }
}
$baseline = New-ApplicationTestInputs -Root (Join-Path $testRoot 'baseline') -IncludeSupport
Test-IdentityCase 'Relocating the workspace and application inputs preserves build identity' {
    $relocatedRoot = Join-Path $testRoot 'relocated'
    Copy-Item -LiteralPath $baseline.Root -Destination $relocatedRoot -Recurse
    $relocatedRepository = Join-Path $testRoot 'relocated-repository'
    Copy-Item -LiteralPath $isolatedRepository -Destination $relocatedRepository -Recurse
    $relocated = [pscustomobject]@{
        DefinitionPath=(Join-Path $relocatedRoot 'application/app.json');ReleasePath=(Join-Path $relocatedRoot 'release.json')
        EvidencePath=(Join-Path $relocatedRoot 'installer-evidence.json');InstallerPath=(Join-Path $relocatedRoot 'Firefox.msi')
    }
    $result = & (Join-Path $relocatedRepository 'scripts/Resolve-Application.ps1') -DefinitionPath $relocated.DefinitionPath -ReleasePath $relocated.ReleasePath -InstallerPath $relocated.InstallerPath -EvidencePath $relocated.EvidencePath -AllowFixture
    Assert-IdentityScope ($result.sourceRoot -cne $baseline.Resolved.sourceRoot) 'Relocation did not change source paths.'
    Assert-IdentityScope ($result.buildId -ceq $baseline.Resolved.buildId) 'Absolute source paths changed build identity.'
    Assert-IdentityScope ($result.definitionSha256 -ceq $baseline.Resolved.definitionSha256) 'Relocation changed definition bytes.'
}
Test-IdentityCase 'Discovery timestamp changes provenance without changing build identity' {
    $release = Read-AppJson $baseline.ReleasePath
    $release.discoveredAtUtc = '2026-11-06T00:00:00Z'
    Save-TestJson $baseline.ReleasePath $release
    $result = Resolve-TestInputs $baseline
    Assert-IdentityScope ($result.buildId -ceq $baseline.Resolved.buildId) 'Discovery time changed build identity.'
    Assert-IdentityScope ($result.provenance.releaseSha256 -cne $baseline.Resolved.provenance.releaseSha256) 'Changed discovery provenance was not retained.'
}
Test-IdentityCase 'Reviewed replacement installer bytes at the same version create a new identity' {
    $fixture = New-ApplicationTestInputs -Root (Join-Path $testRoot 'same-version-payload')
    [IO.File]::AppendAllText($fixture.InstallerPath, ' CHANGED OFFLINE FIXTURE BYTES')
    $replacementHash = (Get-FileHash -LiteralPath $fixture.InstallerPath).Hash.ToLowerInvariant()
    $release = Read-AppJson $fixture.ReleasePath
    $evidence = Read-AppJson $fixture.EvidencePath
    # Synthetic updated review/checksum evidence; this does not accept any real installer.
    $release.vendorSha256 = $replacementHash
    $evidence.sha256 = $replacementHash
    $evidence.review.approvedAtUtc = '2026-11-06T00:00:00Z'
    Save-TestJson $fixture.ReleasePath $release
    Save-TestJson $fixture.EvidencePath $evidence
    $result = Resolve-TestInputs $fixture
    Assert-IdentityScope ($result.release.version -ceq $fixture.Resolved.release.version) 'The test changed application version.'
    Assert-IdentityScope ($result.buildId -cne $fixture.Resolved.buildId) 'Replacement installer bytes reused the old identity.'
    Assert-IdentityScope (@($result.inputs | Where-Object role -eq 'installer')[0].sha256 -ceq $replacementHash) 'Replacement payload hash was not frozen.'
}
foreach ($role in @('detection','support','installer')) {
    Test-IdentityCase ("Post-resolution $role drift fails before Build writes") {
        $fixture = New-ApplicationTestInputs -Root (Join-Path $testRoot ('drift-' + $role)) -IncludeSupport
        $inputFile = @($fixture.Resolved.inputs | Where-Object role -eq $role)[0]
        [IO.File]::AppendAllText($inputFile.source, "`r`n# CHANGED OFFLINE FIXTURE")
        $before = Get-TestInventoryHash $fixture.Root
        $destination = Join-Path $fixture.Root 'build'
        $rejected = $false
        try { & $builder -ResolvedPath $fixture.ResolvedPath -TemplatePath $TemplatePath -DestinationPath $destination -Execute | Out-Null }
        catch {
            if ($_.Exception.Message -notmatch '^Resolved input changed:') { throw }
            $rejected = $true
        }
        Assert-IdentityScope $rejected "Changed $role source was accepted."
        Assert-IdentityScope (-not (Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath ($destination + '.build.lock'))) 'Rejected drift created a build directory or lock.'
        Assert-IdentityScope ((Get-TestInventoryHash $fixture.Root) -ceq $before) 'Rejected drift changed existing local files.'
    }
}
Test-IdentityCase 'An isolated generator implementation edit changes identity without changing detection bytes' {
    $fixture = New-ApplicationTestInputs -Root (Join-Path $testRoot 'generator-change')
    $relative = 'scripts/Bind-ApplicationDetection.ps1'
    $isolatedBinder = Join-Path $isolatedRepository $relative
    [IO.File]::AppendAllText($isolatedBinder, "`r`n# ISOLATED TEST IMPLEMENTATION REVISION`r`n", [Text.UTF8Encoding]::new($false))
    $result = Resolve-TestInputs $fixture
    Assert-IdentityScope ($result.buildId -cne $fixture.Resolved.buildId) 'An implementation edit reused the old identity.'
    Assert-IdentityScope ($result.detection.GeneratedSha256 -ceq $fixture.Resolved.detection.GeneratedSha256) 'The comment-only test edit changed generated detection.'
    $beforePin = @($fixture.Resolved.implementations | Where-Object path -eq $relative)[0].sha256
    $afterPin = @($result.implementations | Where-Object path -eq $relative)[0].sha256
    Assert-IdentityScope ($beforePin -cne $afterPin) 'The implementation pin did not capture changed bytes.'
}
$summary = [pscustomobject]@{
    Passed=(@($results | Where-Object { -not $_.passed }).Count -eq 0);Checks=$checks;Cases=$results.Count
    Failed=@($results | Where-Object { -not $_.passed }).Count;Runtime=$PSVersionTable.PSVersion.ToString();Artifacts=$testRoot;Tests=$results.ToArray()
    Limitation='Offline fixture identities and pre-write rejection only; no installer, deployment, real packaging, signing, or tenant execution.'
}
Write-AppJsonAtomic (Join-Path $testRoot 'results.json') $summary
$summary
if (-not $summary.Passed) { throw "$($summary.Failed) identity scope cases failed." }
