#requires -Version 5.1
<#
Offline behavioral checks of the default publication/assignment preview paths.
No Intune module is imported and no requests are sent. Application artifacts are
not required; the extracted pinned module source is read for static checks only.
Run in a fresh PowerShell process; sentinel functions exist only for this test.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$script:previewBoundaryCalls = 0

# These functions fail immediately if the scripts cross the preview boundary.
function Import-Module { $script:previewBoundaryCalls++; throw 'Preview attempted module import.' }
function Connect-MSIntuneGraph { $script:previewBoundaryCalls++; throw 'Preview attempted authentication.' }
function Invoke-RestMethod { $script:previewBoundaryCalls++; throw 'Preview attempted HTTP access.' }
function Invoke-WebRequest { $script:previewBoundaryCalls++; throw 'Preview attempted HTTP access.' }
function Add-IntuneWin32App { $script:previewBoundaryCalls++; throw 'Preview attempted publication.' }
function Add-IntuneWin32AppAssignmentGroup { $script:previewBoundaryCalls++; throw 'Preview attempted assignment.' }
function Invoke-MSGraphOperation { $script:previewBoundaryCalls++; throw 'Preview attempted Graph access.' }
function Set-Content { $script:previewBoundaryCalls++; throw 'Preview attempted a file write.' }
function Add-Content { $script:previewBoundaryCalls++; throw 'Preview attempted a file write.' }
function Out-File { $script:previewBoundaryCalls++; throw 'Preview attempted a file write.' }
function New-Item { $script:previewBoundaryCalls++; throw 'Preview attempted an item write.' }
function Set-Item { $script:previewBoundaryCalls++; throw 'Preview attempted an item write.' }
function Remove-Item { $script:previewBoundaryCalls++; throw 'Preview attempted an item deletion.' }
function Copy-Item { $script:previewBoundaryCalls++; throw 'Preview attempted an item copy.' }
function Move-Item { $script:previewBoundaryCalls++; throw 'Preview attempted an item move.' }

$publish = @(& (Join-Path $repository 'examples\Publish-Unassigned.example.ps1') `
    -ApplicationId 'example.app' -ReleaseId 'example-build' -DisplayName 'Example App' `
    -Publisher 'Example Publisher' -AppVersion '1.0' `
    -PackagePath 'Z:\nonexistent\application.intunewin' `
    -DetectionScriptPath 'Z:\nonexistent\Detect.ps1')
if ($publish.Count -ne 1 -or $publish[0].Operation -ne 'CreateUnassignedWin32App') {
    throw 'Publication preview did not return one plan.'
}
if (@($publish[0].Assignments).Count -ne 0) { throw 'Publication preview has implicit assignments.' }
if ($publish[0].InstallCommandLine -ne 'Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Auto' -or
    $publish[0].UninstallCommandLine -ne 'Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Auto') {
    throw 'Preview commands differ from the reviewed PSADT entry point.'
}
if ($publish[0].MaximumInstallationTimeInMinutes -ne 120) { throw 'Preview timeout must be 120 minutes.' }
$expectedCodes = @{ 0 = 'success'; 1707 = 'success'; 3010 = 'softReboot'; 1641 = 'hardReboot';
    1618 = 'retry'; 1602 = 'retry'; 60001 = 'failed'; 60008 = 'failed'; 69001 = 'failed' }
$actualCodes = @{}
foreach ($code in $publish[0].EffectiveReturnCodes) {
    if ($actualCodes.ContainsKey([int]$code.returnCode)) { throw "Duplicate return-code mapping: $($code.returnCode)" }
    $actualCodes.Add([int]$code.returnCode, [string]$code.type)
}
if ($actualCodes.Count -ne $expectedCodes.Count) { throw 'Unexpected number of return-code mappings.' }
foreach ($code in $expectedCodes.Keys) {
    if ($actualCodes[$code] -cne $expectedCodes[$code]) { throw "Incorrect return-code mapping: $code" }
}

$assign = @(& (Join-Path $repository 'examples\Assign-Pilot.example.ps1') `
    -ApplicationId 'example.app' -ReleaseId 'example-build' `
    -IntuneAppId '00000000-0000-0000-0000-000000000001' `
    -PilotGroupId '00000000-0000-0000-0000-000000000002')
if ($assign.Count -ne 1 -or $assign[0].Operation -ne 'AssignRequiredPilot' -or $assign[0].Intent -ne 'required') {
    throw 'Assignment preview did not return the explicit pilot plan.'
}
if ($script:previewBoundaryCalls -ne 0) { throw 'A preview boundary call was attempted and suppressed.' }

# Retain the historical v2 profile comparison independently of the current generated-record contract.
$manifest = Get-Content -LiteralPath (Join-Path $repository 'tests\fixtures\legacy-v2\build-manifest.example.json') -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 2 -or -not $manifest.exampleOnly -or $manifest.state -ne 'IllustrativeNotBuilt' -or
    $manifest.output.installCommand -ne $publish[0].InstallCommandLine -or
    $manifest.output.uninstallCommand -ne $publish[0].UninstallCommandLine -or
    $manifest.output.maximumInstallationTimeInMinutes -ne $publish[0].MaximumInstallationTimeInMinutes) {
    throw 'Illustrative manifest version/state/commands/timeout disagree with the preview.'
}
$manifestCodes = @{}
foreach ($code in $manifest.output.effectiveReturnCodes) {
    if ($manifestCodes.ContainsKey([int]$code.returnCode)) { throw 'Duplicate manifest return-code mapping.' }
    $manifestCodes.Add([int]$code.returnCode, [string]$code.type)
}
if ($manifestCodes.Count -ne $actualCodes.Count) { throw 'Manifest return-code count disagrees with the preview.' }
foreach ($code in $actualCodes.Keys) {
    if ($manifestCodes[$code] -cne $actualCodes[$code]) { throw "Manifest return-code mapping differs: $code" }
}

# Read ASTs only: never import or invoke the downloaded module to inspect its contract.
$sourcePath = Join-Path $repository '.research\intune\IntuneWin32App.1.5.0\Public\Add-IntuneWin32App.ps1'
$defaultCodesPath = Join-Path $repository '.research\intune\IntuneWin32App.1.5.0\Private\Get-IntuneWin32AppDefaultReturnCode.ps1'
$parsed = @{}
foreach ($path in @($sourcePath, $defaultCodesPath, (Join-Path $repository 'examples\Publish-Unassigned.example.ps1'))) {
    $tokens = $null
    $errors = $null
    $parsed[$path] = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Source does not parse: $path" }
}
$definition = $parsed[$sourcePath].Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Add-IntuneWin32App'
}, $true)
$timeoutParameter = @($definition.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'MaximumInstallationTimeInMinutes' })
if ($timeoutParameter.Count -ne 1 -or $timeoutParameter[0].StaticType -ne [int]) { throw 'Published timeout parameter is not the expected integer.' }
$range = @($timeoutParameter[0].Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateRange' })
if ($range.Count -ne 1 -or $range[0].PositionalArguments[0].SafeGetValue() -ne 1 -or
    $range[0].PositionalArguments[1].SafeGetValue() -ne 1440 -or $timeoutParameter[0].DefaultValue.SafeGetValue() -ne 60) {
    throw 'Published timeout range/default differs from the reviewed 1.5.0 contract.'
}
$publishAst = $parsed[(Join-Path $repository 'examples\Publish-Unassigned.example.ps1')]
$addCalls = @($publishAst.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Add-IntuneWin32App'
}, $true))
if ($addCalls.Count -ne 1) { throw 'Expected exactly one publication command.' }
$publishedNames = @($definition.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
$checkedParameterCount = 0
$timeoutFound = $false
for ($i = 1; $i -lt $addCalls[0].CommandElements.Count; $i++) {
    $element = $addCalls[0].CommandElements[$i]
    if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
    if ($element.ParameterName -eq 'WarningAction') { continue } # Common PowerShell parameter.
    if ($publishedNames -notcontains $element.ParameterName) { throw "Unknown published Add parameter: $($element.ParameterName)" }
    $checkedParameterCount++
    if ($element.ParameterName -eq 'MaximumInstallationTimeInMinutes') {
        $timeoutFound = $true
        if ($addCalls[0].CommandElements[$i + 1].SafeGetValue() -ne $publish[0].MaximumInstallationTimeInMinutes) {
            throw 'Execution timeout differs from the preview.'
        }
    }
}
if (-not $timeoutFound) { throw 'Publication must explicitly set its timeout.' }
$publishedDefaults = @($parsed[$defaultCodesPath].FindAll({ param($node)
    $node -is [System.Management.Automation.Language.HashtableAst]
}, $true) | ForEach-Object { $_.SafeGetValue() })
if ($publishedDefaults.Count -ne 5) { throw 'Unexpected published default return-code count.' }
foreach ($code in $publishedDefaults) {
    if ($actualCodes[[int]$code.returnCode] -cne $code.type) { throw 'Preview differs from published default return-code mappings.' }
}

[pscustomobject]@{
    Passed = $true
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Checks = @('Publish default returns one local plan', 'Publication has zero assignments',
        'Exact PSADT Auto commands', '120-minute preview and execution timeout',
        'Nine unique return codes including 1602/1618 retry and 69001 failed',
        'Published Add parameter names and timeout integer/range/default match AST',
        'Five published default return codes match preview', 'Unbuilt v2 manifest agrees with publication preview',
        'Assignment default returns explicit pilot plan',
        'No module import, authentication, HTTP, mutation or file-write sentinel reached')
    EffectiveReturnCodes = $publish[0].EffectiveReturnCodes
    AddNamedParametersChecked = $checkedParameterCount
    MaximumInstallationTimeInMinutes = $publish[0].MaximumInstallationTimeInMinutes
    PublishedTimeoutRange = @(1, 1440)
    PreviewBoundaryCalls = $script:previewBoundaryCalls
    NotTested = 'Execute paths, module runtime, Graph authentication, upload and assignment behavior'
}
