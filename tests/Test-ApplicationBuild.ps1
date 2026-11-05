#requires -Version 5.1
<# Offline staging with a deliberately fake payload. No deployment or packaging execution. #>
[CmdletBinding()]
param([string]$TemplatePath)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
. (Join-Path $repository 'scripts\Application.Core.ps1')
. (Join-Path $repository 'scripts\Bind-ApplicationDetection.ps1')
. (Join-Path $PSScriptRoot 'ApplicationTest.Fixtures.ps1')
if (-not $TemplatePath) { $TemplatePath = Join-Path $repository '.research\psadt\pristine' }
$builder = Join-Path $repository 'scripts\Build-Application.ps1'
$testRoot = Join-Path $repository ('.validation\application-build-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$fixture = New-ApplicationTestInputs -Root (Join-Path $testRoot 'inputs') -IncludeSupport
$fixtureRoot = $fixture.ApplicationRoot
$checks = 0
function Assert-BuildCondition([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message }; $script:checks++ }
function Save-Resolved($Value, [string]$Name, [switch]$RefreshIdentity) {
    $copy = Read-AppJson $fixture.ResolvedPath
    foreach ($property in $Value.PSObject.Properties) { $copy.($property.Name) = $property.Value }
    if ($RefreshIdentity) {
        foreach ($field in @('applicationId','metadata','actions','implementations')) { $copy.identity.$field = $copy.$field }
        $identityInputs = [Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach ($entry in $copy.inputs) { $identityInputs[$entry.role+'|'+$entry.relativePath+'|'+$entry.destination] = $entry | Select-Object role,relativePath,sha256,destination }
        $copy.identity.inputs = @($identityInputs.Values)
        $copy.buildId = Get-AppObjectHash $copy.identity
    }
    $copy.PSObject.Properties.Remove('recordHash')
    $copy | Add-Member -NotePropertyName recordHash -NotePropertyValue (Get-AppObjectHash $copy)
    $path = Join-Path $testRoot $Name
    Write-AppJsonAtomic $path $copy
    return $path
}
function Assert-BuildRejected([scriptblock]$Operation, [string]$Message, [string]$ExpectedError = '.') {
    $rejected = $false
    try { & $Operation | Out-Null } catch { if ($_.Exception.Message -notmatch $ExpectedError) { throw "Unexpected rejection for ${Message}: $($_.Exception.Message)" }; $rejected = $true }
    Assert-BuildCondition $rejected $Message
}
function Update-EmbeddedReferences($Node, [string]$Location) {
    if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) { return }
    if ($Node -is [array]) { foreach ($item in $Node) { Update-EmbeddedReferences $item $Location }; return }
    foreach ($property in $Node.PSObject.Properties) {
        if ($property.Name -eq '$ref' -and ([string]$property.Value).StartsWith('#/')) { $property.Value = '#/$defs/' + $Location + '/' + $property.Value.Substring(2) }
        else { Update-EmbeddedReferences $property.Value $Location }
    }
}
foreach ($schemaName in @('resolved-build','application-build')) {
    $recordSchema = Read-AppJson (Join-Path $repository "schemas\$schemaName.v1.schema.json")
    foreach ($snapshot in @(@{file='application-definition.v3.schema.json';location='applicationDefinition'},@{file='discovered-release.v1.schema.json';location='discoveredRelease'})) {
        $sourceSchema = Read-AppJson (Join-Path $repository ('schemas\'+$snapshot.file))
        $sourceSchema.PSObject.Properties.Remove('$schema'); $sourceSchema.PSObject.Properties.Remove('$id')
        Update-EmbeddedReferences $sourceSchema $snapshot.location
        Assert-BuildCondition ((Get-AppObjectHash $sourceSchema) -ceq (Get-AppObjectHash $recordSchema.'$defs'.($snapshot.location))) "Embedded schema snapshot drifted: $schemaName / $($snapshot.location)"
    }
}
$resolved = $fixture.Resolved
$inputs = $resolved.inputs
$resolvedPath = $fixture.ResolvedPath
$destination = Join-Path $testRoot 'build'
$before = @(Get-ChildItem -LiteralPath $testRoot -Recurse -Force).Count
$preview = & $builder -ResolvedPath $resolvedPath -TemplatePath $TemplatePath -DestinationPath $destination
Assert-BuildCondition ($preview.operation -eq 'BuildApplication' -and -not $preview.executed) 'Preview contract differs.'
Assert-BuildCondition ((@(Get-ChildItem -LiteralPath $testRoot -Recurse -Force).Count -eq $before) -and -not (Test-Path -LiteralPath $destination)) 'Preview wrote files.'
$built = & $builder -ResolvedPath $resolvedPath -TemplatePath $TemplatePath -DestinationPath $destination -Execute
Assert-BuildCondition ($built.recordType -eq 'ApplicationBuild' -and $built.fixture -eq $true) 'Build did not retain fixture state.'
Assert-BuildCondition (Test-Path -LiteralPath (Join-Path $destination 'build-manifest.json')) 'Completion manifest missing.'
Assert-BuildCondition ($built.sourceInventory.Count -eq 224) 'Unexpected source inventory.'
Assert-BuildCondition ((Get-FileHash -LiteralPath (Join-Path $built.sourceFolder 'Files\Firefox.msi')).Hash -ieq @($inputs | Where-Object role -eq 'installer')[0].sha256) 'Installer changed.'
Assert-BuildCondition ((Get-FileHash -LiteralPath $built.detection.path).Hash -ieq $resolved.detection.GeneratedSha256) 'Detection changed.'
Assert-BuildCondition ($built.detection.path -notlike ($built.sourceFolder + '\*')) 'Detection is inside package source.'
$sealed = Read-AppJson (Join-Path $destination 'build-manifest.json'); $seal = $sealed.recordHash; $sealed.PSObject.Properties.Remove('recordHash')
Assert-BuildCondition ((Get-AppObjectHash $sealed) -eq $seal) 'Build manifest seal differs.'
Assert-BuildRejected { & $builder -ResolvedPath $resolvedPath -TemplatePath $TemplatePath -DestinationPath $destination -Execute } 'Existing destination accepted.' 'Destination exists'
$tampered = Read-AppJson $resolvedPath; $tampered.metadata.AppName = 'Unsealed change'
$tamperedPath = Join-Path $testRoot 'tampered.json'; Write-AppJsonAtomic $tamperedPath $tampered
Assert-BuildRejected { & $builder -ResolvedPath $tamperedPath -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'tampered') } 'Tampered record accepted.' 'Invalid or changed ResolvedBuild'
$badShape = Read-AppJson $resolvedPath; $badShape.metadata.AppArch = 'arm64'
$badShapePath = Save-Resolved $badShape 'bad-shape.json'
Assert-BuildRejected { & $builder -ResolvedPath $badShapePath -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'bad-shape') } 'Unsupported schema value accepted.' 'Schema|Test-Json'
$badIdentity = Read-AppJson $resolvedPath; $badIdentity.buildId = '0' * 64
$badIdentityPath = Save-Resolved $badIdentity 'bad-identity.json'
Assert-BuildRejected { & $builder -ResolvedPath $badIdentityPath -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'bad-identity') } 'Incorrect buildId accepted.' 'identity hash differs'
$splitIdentity = Read-AppJson $resolvedPath; $splitIdentity.metadata.AppName = 'Detached metadata'
$splitIdentityPath = Save-Resolved $splitIdentity 'split-identity.json'
Assert-BuildRejected { & $builder -ResolvedPath $splitIdentityPath -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'split-identity') } 'Metadata outside build identity accepted.' 'metadata differs from its build identity'
$splitDefinition = Read-AppJson $resolvedPath; $splitDefinition.definition.productName = 'Detached name'
$splitDefinitionPath = Save-Resolved $splitDefinition 'split-definition.json'
Assert-BuildRejected { & $builder -ResolvedPath $splitDefinitionPath -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'split-definition') } 'Metadata outside definition accepted.' 'PSADT metadata differs'
$badImplementation = Read-AppJson $resolvedPath; $badImplementation.implementations[0].sha256 = '0' * 64
$badImplementationPath = Save-Resolved $badImplementation 'implementation-drift.json' -RefreshIdentity
Assert-BuildRejected { & $builder -ResolvedPath $badImplementationPath -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'implementation-drift') } 'Implementation drift accepted.' 'Build implementation changed'
$collision = Read-AppJson $resolvedPath; @($collision.inputs | Where-Object role -eq 'support')[0].destination = 'SupportFiles/Add Supporting Files Here.txt'
$collisionPath = Save-Resolved $collision 'collision.json' -RefreshIdentity
Assert-BuildRejected { & $builder -ResolvedPath $collisionPath -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'collision') -Execute } 'Upstream payload collision accepted.' 'Payload collides'
Assert-BuildCondition (-not (Test-Path -LiteralPath (Join-Path $testRoot 'collision'))) 'Collision created an output directory.'
$traversal = Read-AppJson $resolvedPath; @($traversal.inputs | Where-Object role -eq 'installer')[0].destination = 'Files/../Invoke-AppDeployToolkit.ps1'
$traversalPath = Save-Resolved $traversal 'traversal.json' -RefreshIdentity
Assert-BuildRejected { & $builder -ResolvedPath $traversalPath -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'traversal') } 'Payload path traversal accepted.' 'Schema|Test-Json'
$lockedDestination = Join-Path $testRoot 'locked'
[IO.File]::WriteAllText(($lockedDestination + '.build.lock'), 'existing attempt')
Assert-BuildRejected { & $builder -ResolvedPath $resolvedPath -TemplatePath $TemplatePath -DestinationPath $lockedDestination -Execute } 'Existing lock accepted.' 'build lock exists'
Assert-BuildCondition ([IO.File]::ReadAllText(($lockedDestination + '.build.lock')) -ceq 'existing attempt') 'Existing lock changed.'
$invalidNative = Read-AppJson $resolvedPath
$badAction = Join-Path $fixtureRoot 'InvalidAction.ps1'
[IO.File]::WriteAllText($badAction, 'throw ''Application code must never run on the build host''')
$invalidNative.inputs[0].source = $badAction
$invalidNative.inputs[0].sha256 = (Get-FileHash -LiteralPath $badAction).Hash.ToLowerInvariant()
$invalidNativePath = Save-Resolved $invalidNative 'invalid-native.json' -RefreshIdentity
$failedDestination = Join-Path $testRoot 'incomplete'
Assert-BuildRejected { & $builder -ResolvedPath $invalidNativePath -TemplatePath $TemplatePath -DestinationPath $failedDestination -Execute } 'Unsupported native snippet accepted.' 'Native application style rejects'
Assert-BuildCondition ((Test-Path -LiteralPath (Join-Path $failedDestination 'build-attempt.json')) -and -not (Test-Path -LiteralPath (Join-Path $failedDestination 'build-manifest.json')) -and -not (Test-Path -LiteralPath ($failedDestination + '.build.lock'))) 'Failed attempt was not retained as incomplete with its lock released.'
$changedTemplate = Join-Path $testRoot 'changed-template'
Copy-Item -LiteralPath $TemplatePath -Destination $changedTemplate -Recurse
[IO.File]::WriteAllText((Join-Path $changedTemplate 'Unexpected.txt'), 'not upstream')
Assert-BuildRejected { & $builder -ResolvedPath $resolvedPath -TemplatePath $changedTemplate -DestinationPath (Join-Path $testRoot 'extra-template-file') } 'Extra template file accepted.' 'Unexpected file inventory'
[IO.File]::Delete((Join-Path $changedTemplate 'Unexpected.txt'))
[IO.File]::AppendAllText((Join-Path $changedTemplate 'Invoke-AppDeployToolkit.ps1'), "`r`n# unexpected upstream change")
Assert-BuildRejected { & $builder -ResolvedPath $resolvedPath -TemplatePath $changedTemplate -DestinationPath (Join-Path $testRoot 'changed-template-file') } 'Changed template file accepted.' 'Build content changed'
[IO.File]::AppendAllText((Join-Path $fixtureRoot 'Install.ps1'), "`r`n# drift")
Assert-BuildRejected { & $builder -ResolvedPath $resolvedPath -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'drift') -Execute } 'Changed input accepted.' 'Resolved input changed'
Assert-BuildCondition (-not (Test-Path -LiteralPath (Join-Path $testRoot 'drift'))) 'Input drift created an output directory.'
[pscustomobject]@{Passed=$true;Checks=$checks;PowerShellVersion=$PSVersionTable.PSVersion.ToString();Artifacts=$testRoot;Limitation='Offline fixture staging only; no payload, deployment, packaging, or tenant execution.'}
