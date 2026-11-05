#requires -Version 5.1
<# Offline coverage of the adapter's general task locations; never executes a deployment. #>
[CmdletBinding()]
param([string]$TemplatePath, [string]$CaseFilter = '*')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (!$TemplatePath) { $TemplatePath = Join-Path $PSScriptRoot '..\.research\psadt\pristine' }
$TemplatePath = (Resolve-Path -LiteralPath $TemplatePath).ProviderPath.TrimEnd('\')
$adapter = Join-Path $PSScriptRoot '..\scripts\Populate-PSADTTemplate.ps1'
$testRoot = Join-Path $PSScriptRoot ('..\.research\psadt\hook-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$testRoot = (Resolve-Path -LiteralPath $testRoot).ProviderPath
$sourceRoot = Join-Path $testRoot 'sources'
$null = New-Item -ItemType Directory -Path $sourceRoot
$results = [System.Collections.Generic.List[object]]::new()
$operations = @('Install', 'Uninstall', 'Repair')
$phases = @('Pre', 'Main', 'Post')
$labels = @{ Install=@('Pre-Installation','Installation','Post-Installation'); Uninstall=@('Pre-Uninstallation','Uninstallation','Post-Uninstallation'); Repair=@('Pre-Repair','Repair','Post-Repair') }
$sourceHashes = @{}
function Assert-True([bool]$Condition, [string]$Message) { if (!$Condition) { throw $Message } }
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false)) }
function Write-Json($Value, [string]$Path) { Write-Text $Path ($Value | ConvertTo-Json -Depth 10) }
function Test-Case([string]$Name, [scriptblock]$Body) {
    if ($Name -notlike $CaseFilter) { return }
    try { & $Body; $results.Add([pscustomobject]@{name=$Name;status='passed'}); Write-Host "PASS $Name" }
    catch { $results.Add([pscustomobject]@{name=$Name;status='failed';error=$_.Exception.Message}); Write-Host "FAIL $Name : $($_.Exception.Message)" }
}
function New-Actions([string[]]$IncludedPhases = @('Main')) {
    $actions = [ordered]@{}
    # Deliberately reverse JSON property order; insertion order belongs to the template.
    foreach ($operation in @('Repair','Uninstall','Install')) {
        $actions[$operation] = [ordered]@{}
        foreach ($phase in @('Post','Main','Pre')) {
            if ($phase -in $IncludedPhases) { $actions[$operation][$phase] = "$operation-$phase.ps1" }
        }
    }
    return $actions
}
function Invoke-Population([string]$Name, $Actions) {
    $actionsPath = Join-Path $sourceRoot ($Name + '.json')
    Write-Json $Actions $actionsPath
    $actionsHash = (Get-FileHash -LiteralPath $actionsPath -Algorithm SHA256).Hash
    $result = & $adapter -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot $Name) -MetadataPath $metadataPath -ActionsPath $actionsPath -ValidateNativeApplicationCommands
    Assert-True ((Get-FileHash -LiteralPath $actionsPath -Algorithm SHA256).Hash -ceq $actionsHash) 'The authored action map changed.'
    return $result
}
function Get-Parsed([string]$Text) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    Assert-True ($errors.Count -eq 0) 'Generated content does not parse.'
    return $ast
}
function Assert-Rejected([string]$Name, $Actions, [string]$Pattern) {
    $actionsPath = Join-Path $sourceRoot ($Name + '.json')
    Write-Json $Actions $actionsPath
    $destination = Join-Path $testRoot $Name
    $rejected = $false
    try { $null = & $adapter -TemplatePath $TemplatePath -DestinationPath $destination -MetadataPath $metadataPath -ActionsPath $actionsPath -ValidateNativeApplicationCommands }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $rejected = $true
    }
    Assert-True $rejected 'Malformed or uncontained input was accepted.'
    Assert-True (!(Test-Path -LiteralPath $destination)) 'Rejected input created a deployment directory.'
}
$metadata = [ordered]@{ AppVendor='Hook fixture'; AppName='Hook fixture'; AppVersion='1.2.3'; AppArch='x64'; AppLang='en-US'; AppRevision='01'; AppScriptVersion='1.0.0'; AppScriptDate='2026-11-03'; AppScriptAuthor='Offline test'; AppProcessesToClose=@(); RequireAdmin=$true }
$metadataPath = Join-Path $sourceRoot 'metadata.json'
Write-Json $metadata $metadataPath
$sourceHashes[$metadataPath] = (Get-FileHash -LiteralPath $metadataPath -Algorithm SHA256).Hash
foreach ($operation in $operations) {
    foreach ($phase in $phases) {
        $path = Join-Path $sourceRoot "$operation-$phase.ps1"
        # Non-ASCII, LF-only, no-BOM input exercises decoding and normalized insertion.
        $message = "HOOK:$operation.$phase " + [char]0x00E9 + [char]0x6771
        Write-Text $path ("# Reviewed $operation.$phase`nWrite-ADTLogEntry -Message '$message' -Severity 1`n")
        $sourceHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
}
# These isolated sentinels make accidental execution fail without importing PSADT.
function Write-ADTLogEntry { throw 'A snippet was executed during offline population.' }
function Start-ADTProcess { throw 'An application process was started during offline population.' }
function Start-ADTMsiProcess { throw 'An MSI process was started during offline population.' }
function Close-ADTSession { throw 'A deployment session was closed during offline population.' }
$pristine = [IO.File]::ReadAllText((Join-Path $TemplatePath 'Invoke-AppDeployToolkit.ps1'))
$pristineAst = Get-Parsed $pristine
$manifest = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\evidence\psadt-4.1.8-release.json')) | ConvertFrom-Json
function Assert-Population($Result, $Actions) {
    $generated = [IO.File]::ReadAllText((Join-Path $result.DestinationPath 'Invoke-AppDeployToolkit.ps1'))
    $ast = Get-Parsed $generated
    $expectedCount = @($Actions.Values | ForEach-Object { $_.Keys }).Count
    Assert-True ($result.Passed -and $result.NativeApplicationCommandsValidated -and $result.NativeApplicationCommandCount -eq $expectedCount) 'The expected native calls were not validated.'
    Assert-True ($result.Snippets.Count -eq $expectedCount) 'Snippet provenance is incomplete.'
    Assert-True (!$result.OmitCompletionPrompt) 'General hook coverage must retain the default completion prompt.'
    $insertions = [System.Collections.Generic.List[object]]::new()
    foreach ($operation in $operations) {
        $function = @($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]}, $true) | Where-Object Name -eq ($operation + '-ADTDeployment'))
        Assert-True ($function.Count -eq 1) "Missing deployment function: $operation"
        $previousOffset = -1
        for ($phaseIndex = 0; $phaseIndex -lt $phases.Count; $phaseIndex++) {
            $phase = $phases[$phaseIndex]
            $hook = @($function[0].Body.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Write-ADTLogEntry'}, $true) | Where-Object { $_.Extent.Text.Contains("HOOK:$operation.$phase ") })
            if (!$Actions[$operation].Contains($phase)) {
                Assert-True ($hook.Count -eq 0) "Unrequested hook was inserted: $operation.$phase"
                continue
            }
            Assert-True ($hook.Count -eq 1 -and $hook[0].Extent.StartOffset -gt $previousOffset) "Wrong placement/order for $operation.$phase"
            Assert-True ($hook[0].Parent.Parent -eq $function[0].Body.EndBlock) "Hook $operation.$phase is not sequential top-level application work."
            $previousOffset = $hook[0].Extent.StartOffset
            $evidence = @($result.Snippets | Where-Object section -eq "$operation.$phase")
            Assert-True ($evidence.Count -eq 1 -and $evidence[0].path -ceq $actions[$operation][$phase]) "Wrong source path for $operation.$phase"
            Assert-True ($evidence[0].sha256 -ieq $sourceHashes[(Join-Path $sourceRoot $evidence[0].path)]) "Wrong source hash for $operation.$phase"
            $marker = '## <Perform ' + $labels[$operation][$phaseIndex] + ' tasks here>'
            $markerOffset = $generated.IndexOf($marker, [StringComparison]::Ordinal)
            Assert-True ($markerOffset -ge 0 -and $markerOffset -eq $generated.LastIndexOf($marker, [StringComparison]::Ordinal)) "Task marker is not unique: $operation.$phase"
            $source = [IO.File]::ReadAllText((Join-Path $sourceRoot $Actions[$operation][$phase]))
            $inserted = "`r`n" + (($source.TrimEnd() -split '\r?\n' | ForEach-Object { '    ' + $_ }) -join "`r`n")
            $start = $markerOffset + $marker.Length
            Assert-True ($generated.Substring($start, $inserted.Length) -ceq $inserted) "Reviewed source was not inserted intact at $operation.$phase"
            $insertions.Add([pscustomobject]@{start=$start;length=$inserted.Length})
            if ($phase -eq 'Pre') {
                foreach ($name in @('Show-ADTInstallationWelcome','Show-ADTInstallationProgress')) {
                    $nativeCalls = @($function[0].Body.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]}, $true) | Where-Object { $_.GetCommandName() -eq $name })
                    Assert-True ($nativeCalls.Count -ge 1) "Missing native $name in $operation"
                    foreach ($call in $nativeCalls) { Assert-True ($call.Extent.EndOffset -lt $hook[0].Extent.StartOffset) "$operation.Pre moved before native welcome/progress." }
                }
            }
        }
    }
    # Independently remove only the exact reviewed insertion text, then restore the
    # specific metadata value slots. The remaining script must equal pristine text.
    $restored = $generated
    foreach ($insertion in ($insertions | Sort-Object start -Descending)) { $restored = $restored.Remove($insertion.start, $insertion.length) }
    $restoredAst = Get-Parsed $restored
    $originalTable = @($pristineAst.FindAll({param($n) $n -is [Management.Automation.Language.HashtableAst]}, $true) | Where-Object { $_.KeyValuePairs.Item1.Value -contains 'AppVendor' })
    $outputTable = @($restoredAst.FindAll({param($n) $n -is [Management.Automation.Language.HashtableAst]}, $true) | Where-Object { $_.KeyValuePairs.Item1.Value -contains 'AppVendor' })
    Assert-True ($originalTable.Count -eq 1 -and $outputTable.Count -eq 1) 'The metadata table is ambiguous.'
    $metadataEdits = foreach ($key in $metadata.Keys) {
        $originalPair = @($originalTable[0].KeyValuePairs | Where-Object { $_.Item1.Value -ceq $key })
        $outputPair = @($outputTable[0].KeyValuePairs | Where-Object { $_.Item1.Value -ceq $key })
        Assert-True ($originalPair.Count -eq 1 -and $outputPair.Count -eq 1) "The metadata slot is ambiguous: $key"
        $extent = $outputPair[0].Item2.Extent
        [pscustomobject]@{start=$extent.StartOffset;length=$extent.EndOffset-$extent.StartOffset;text=$originalPair[0].Item2.Extent.Text}
    }
    foreach ($edit in ($metadataEdits | Sort-Object start -Descending)) { $restored = $restored.Remove($edit.start, $edit.length).Insert($edit.start, $edit.text) }
    Assert-True ($restored -ceq $pristine) 'Framework text changed outside reviewed hooks and metadata slots.'
    $outputFiles = @(Get-ChildItem -LiteralPath $result.DestinationPath -Recurse -Force -File)
    Assert-True ($outputFiles.Count -eq $manifest.files.Count) 'The generated file inventory changed.'
    foreach ($file in $manifest.files) {
        if ($file.path -eq 'Invoke-AppDeployToolkit.ps1') { continue }
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $result.DestinationPath $file.path) -Algorithm SHA256).Hash -ieq $file.sha256) "Upstream file changed: $($file.path)"
    }
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $result.DestinationPath 'Invoke-AppDeployToolkit.ps1') -Algorithm SHA256).Hash -ieq $result.GeneratedScriptSha256) 'Generated script provenance does not match the file.'
    foreach ($path in $sourceHashes.Keys) { Assert-True ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq $sourceHashes[$path]) "Authored source changed: $path" }
    Assert-True (@(Get-Module -Name PSAppDeployToolkit,PSAppDeployToolkit.Extensions).Count -eq 0) 'Population imported endpoint modules.'
}
foreach ($combination in @(
    @{name='all-hooks';phases=@('Pre','Main','Post')},
    @{name='main-only';phases=@('Main')},
    @{name='pre-main';phases=@('Pre','Main')},
    @{name='main-post';phases=@('Main','Post')}
)) {
    Test-Case ('Hook combination preserves order, provenance and framework: ' + $combination.name) {
        $actions = New-Actions $combination.phases
        Assert-Population (Invoke-Population $combination.name $actions) $actions
    }
}
Test-Case 'Optional phases may differ between operations' {
    $actions = New-Actions $phases
    $actions.Install.Remove('Post')
    $actions.Uninstall.Remove('Pre')
    Assert-Population (Invoke-Population 'mixed-phases' $actions) $actions
}
$badMaps = @(
    @{name='unknown-operation';change={param($a) $a.Other=@{Main='Install-Main.ps1'}};pattern='Unsupported action operation'},
    @{name='wrong-case-operation';change={param($a) $a.Remove('Install'); $a.install=@{Main='Install-Main.ps1'}};pattern='Unsupported action operation'},
    @{name='empty-operation';change={param($a) $a.Install=@{}};pattern='Required action missing: Install.Main'},
    @{name='null-operation';change={param($a) $a.Install=$null};pattern='Required action missing: Install.Main'},
    @{name='scalar-operation';change={param($a) $a.Install='Install-Main.ps1'};pattern='Required action missing: Install.Main'},
    @{name='array-operation';change={param($a) $a.Install=@(@{Main='Install-Main.ps1'})};pattern='Required action missing: Install.Main|Unsupported action operation'},
    @{name='unknown-phase';change={param($a) $a.Install.Before='Install-Pre.ps1'};pattern='Unsupported action phase'},
    @{name='wrong-case-phase';change={param($a) $a.Install.pre='Install-Pre.ps1'};pattern='Unsupported action phase'},
    @{name='null-main';change={param($a) $a.Install.Main=$null};pattern='Unsupported action phase'},
    @{name='empty-main';change={param($a) $a.Install.Main=''};pattern='Unsupported action phase'},
    @{name='whitespace-pre';change={param($a) $a.Install.Pre='  '};pattern='Unsupported action phase'},
    @{name='array-phase';change={param($a) $a.Install.Post=@('Install-Post.ps1')};pattern='Unsupported action phase'},
    @{name='object-phase';change={param($a) $a.Install.Post=@{path='Install-Post.ps1'}};pattern='Unsupported action phase'},
    @{name='numeric-phase';change={param($a) $a.Repair.Main=42};pattern='Unsupported action phase'}
)
foreach ($case in $badMaps) {
    Test-Case ('Reject malformed action map: ' + $case.name) {
        $actions = New-Actions
        & $case.change $actions
        Assert-Rejected $case.name $actions $case.pattern
    }
}
foreach ($operation in $operations) {
    Test-Case ('Reject missing operation: ' + $operation) {
        $actions = New-Actions
        $actions.Remove($operation)
        Assert-Rejected ('missing-' + $operation) $actions ('Required action missing: ' + $operation + '.Main')
    }
    Test-Case ('Reject optional phases without Main: ' + $operation) {
        $actions = New-Actions $phases
        $actions[$operation].Remove('Main')
        Assert-Rejected ('missing-main-' + $operation) $actions ('Required action missing: ' + $operation + '.Main')
    }
}
Write-Text (Join-Path $sourceRoot 'empty.ps1') " `r`n`t"
Write-Text (Join-Path $sourceRoot 'invalid.ps1') 'if ('
Write-Text (Join-Path $sourceRoot 'nonnative.ps1') 'Get-Process -Name hook-fixture'
Write-Text (Join-Path $testRoot 'outside.ps1') "Write-ADTLogEntry -Message 'outside action root'"
$pathCases = @(
    @{name='missing-file';operation='Install';phase='Pre';path='not-present.ps1';pattern='Cannot find path|does not exist'},
    @{name='empty-file';operation='Repair';phase='Post';path='empty.ps1';pattern='Snippet must not be empty'},
    @{name='invalid-syntax';operation='Uninstall';phase='Pre';path='invalid.ps1';pattern='Snippet does not parse'},
    @{name='parent-traversal';operation='Install';phase='Main';path='..\outside.ps1';pattern='Snippet path must remain'},
    # Windows PowerShell can reject the combined rooted path in GetFullPath before
    # the adapter's explicit containment guard; both must leave no destination.
    @{name='absolute-path';operation='Repair';phase='Post';path=(Join-Path $sourceRoot 'Repair-Post.ps1');pattern='Snippet path must remain|The given path''s format is not supported'},
    @{name='root-relative-path';operation='Uninstall';phase='Pre';path='\outside.ps1';pattern='Snippet path must remain'},
    @{name='nonnative-pre';operation='Install';phase='Pre';path='nonnative.ps1';pattern='Native application'},
    @{name='nonnative-post';operation='Repair';phase='Post';path='nonnative.ps1';pattern='Native application'}
)
foreach ($case in $pathCases) {
    Test-Case ('Reject invalid snippet reference: ' + $case.name) {
        $actions = New-Actions
        $actions[$case.operation][$case.phase] = $case.path
        Assert-Rejected $case.name $actions $case.pattern
    }
}
$outsideRoot = Join-Path $testRoot 'outside-actions'
$null = New-Item -ItemType Directory -Path $outsideRoot
Write-Text (Join-Path $outsideRoot 'outside.ps1') "Write-ADTLogEntry -Message 'redirected source'"
foreach ($linkCase in @(
    @{name='junction-ancestor';type='Junction';target=$outsideRoot;reference='junction-ancestor\outside.ps1'},
    @{name='symbolic-file';type='SymbolicLink';target=(Join-Path $outsideRoot 'outside.ps1');reference='symbolic-file'}
)) {
    $caseName = 'Reject redirected snippet path: ' + $linkCase.name
    if ($caseName -notlike $CaseFilter) { continue }
    try { $null = New-Item -ItemType $linkCase.type -Path (Join-Path $sourceRoot $linkCase.name) -Target $linkCase.target -ErrorAction Stop }
    catch {
        $results.Add([pscustomobject]@{name=$caseName;status='skipped';reason=('Link fixture could not be created: ' + $_.Exception.Message)})
        Write-Host "SKIP $caseName : $($_.Exception.Message)"
        continue
    }
    Test-Case $caseName {
        $actions = New-Actions
        $actions.Install.Pre = $linkCase.reference
        Assert-Rejected $linkCase.name $actions 'Snippet paths cannot use symbolic links or junctions'
    }
}
Test-Case 'Every pristine file and reviewed source remains unchanged after the suite' {
    Assert-True (@(Get-ChildItem -LiteralPath $TemplatePath -Recurse -Force -File).Count -eq $manifest.files.Count) 'Pristine inventory count changed.'
    foreach ($file in $manifest.files) { Assert-True ((Get-FileHash -LiteralPath (Join-Path $TemplatePath $file.path) -Algorithm SHA256).Hash -ieq $file.sha256) "Pristine file changed: $($file.path)" }
    foreach ($path in $sourceHashes.Keys) { Assert-True ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq $sourceHashes[$path]) "Authored source changed: $path" }
}
$summary = [ordered]@{runUtc=[datetime]::UtcNow.ToString('o');powershell=$PSVersionTable.PSVersion.ToString();is64BitProcess=[Environment]::Is64BitProcess;testRoot=$testRoot;passed=@($results | Where-Object status -eq 'passed').Count;failed=@($results | Where-Object status -eq 'failed').Count;skipped=@($results | Where-Object status -eq 'skipped').Count;tests=$results.ToArray();limitation='Offline adapter coverage only; no snippet, deployment, installer, packaging or tenant execution.'}
Write-Json $summary (Join-Path $testRoot 'results.json')
$summary | ConvertTo-Json -Depth 10
if ($summary.failed) { throw "$($summary.failed) template hook tests failed." }
