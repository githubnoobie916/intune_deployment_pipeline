#requires -Version 5.1
[CmdletBinding()]
param([string]$TemplatePath, [string]$CaseFilter='*')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (!$TemplatePath) { $TemplatePath = Join-Path $PSScriptRoot '..\.research\psadt\pristine' }
$adapter = Join-Path $PSScriptRoot '..\scripts\Populate-PSADTTemplate.ps1'
$testRoot = Join-Path $PSScriptRoot ('..\.research\psadt\tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$results = [System.Collections.Generic.List[object]]::new()
function Assert-True([bool]$Condition, [string]$Message) { if (!$Condition) { throw $Message } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    if ($Name -notlike $CaseFilter) { return }
    try { & $Body; $results.Add([pscustomobject]@{name=$Name;passed=$true}); Write-Host "PASS $Name" }
    catch { $results.Add([pscustomobject]@{name=$Name;passed=$false;error=$_.Exception.Message}); Write-Host "FAIL $Name : $($_.Exception.Message)" }
}
function Assert-Rejected([scriptblock]$Body, [string]$Pattern) {
    $rejected = $false
    try { & $Body | Out-Null } catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; $rejected = $true }
    Assert-True $rejected 'Operation unexpectedly succeeded.'
}
function Write-Json($Value, [string]$Name) {
    $path = Join-Path $testRoot $Name
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}
$metadata = [ordered]@{
    AppVendor='Example'; AppName='Example'; AppVersion='1.2.3'; AppArch='x64'; AppLang='EN'
    AppRevision='01'; AppScriptVersion='1.0.0'; AppScriptDate='2026-11-03'; AppScriptAuthor='Test Engineer'
    AppProcessesToClose=@(); RequireAdmin=$true
}
$metadataPath = Write-Json $metadata 'metadata.json'
Set-Content -LiteralPath (Join-Path $testRoot 'install.ps1') -Value "Write-ADTLogEntry -Message 'Illustrative install only'" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $testRoot 'uninstall.ps1') -Value "Write-ADTLogEntry -Message 'Illustrative uninstall only'" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $testRoot 'repair.ps1') -Value 'Close-ADTSession -ExitCode 69001' -Encoding UTF8
$actionsPath = Write-Json @{Install=@{Main='install.ps1'};Uninstall=@{Main='uninstall.ps1'};Repair=@{Main='repair.ps1'}} 'actions.json'
$pristineHash = (Get-FileHash -LiteralPath (Join-Path $TemplatePath 'Invoke-AppDeployToolkit.ps1')).Hash
$successPath = Join-Path $testRoot 'valid'
Test-Case 'Populates a full copy; generated script parses; complete pristine source unchanged' {
    $result = & $adapter -TemplatePath $TemplatePath -DestinationPath $successPath -MetadataPath $metadataPath -ActionsPath $actionsPath
    Assert-True ($result.Passed -eq $true) 'Missing validation result.'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $TemplatePath 'Invoke-AppDeployToolkit.ps1')).Hash -eq $pristineHash) 'Pristine script changed.'
    $tokens=$null; $errors=$null
    $null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $successPath 'Invoke-AppDeployToolkit.ps1'),[ref]$tokens,[ref]$errors)
    Assert-True ($errors.Count -eq 0) 'Generated script does not parse.'
    Assert-True (Test-Path -LiteralPath (Join-Path $successPath 'PSAppDeployToolkit\PSAppDeployToolkit.psm1')) 'Bundled module missing.'
    Assert-True ($result.UnchangedUpstreamFileCount -eq 221) 'Unexpected upstream file inventory.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $successPath 'Invoke-AppDeployToolkit.ps1')).Contains('You can customize text to appear at the end of an install')) 'Default build removed the stock completion prompt.'
}
Test-Case 'Metadata is literal data even with apostrophes, newline, dollar expansion and command text' {
    $hostile = "O'Connor `$(throw 'should-never-run')`r`nSecond line"
    $metadata.AppName=$hostile
    $path=Write-Json $metadata 'hostile.json'; $destination=Join-Path $testRoot 'hostile'
    $null=& $adapter -TemplatePath $TemplatePath -DestinationPath $destination -MetadataPath $path -ActionsPath $actionsPath
    $tokens=$null; $errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $destination 'Invoke-AppDeployToolkit.ps1'),[ref]$tokens,[ref]$errors)
    $table=$ast.FindAll({param($node) $node -is [System.Management.Automation.Language.HashtableAst]},$true) | Where-Object { $_.KeyValuePairs.Item1.Value -contains 'AppVendor' } | Select-Object -First 1
    $pair=$table.KeyValuePairs | Where-Object { $_.Item1.Value -eq 'AppName' }
    Assert-True ($pair.Item2.PipelineElements[0].Expression.Value -ceq $hostile) 'Literal value did not round-trip.'
    $metadata.AppName='Example'
}
Test-Case 'UTF8 without BOM preserves non-ASCII metadata on Windows PowerShell' {
    # Construct Unicode by code point so this test file is itself safe under Windows PowerShell's ANSI default.
    $unicodeName='M'+[char]0x00FC+'nchen '+[char]0x2014+' '+[char]0x6771+[char]0x4EAC
    $copy=@{}; foreach($entry in $metadata.GetEnumerator()){ $copy[$entry.Key]=$entry.Value }; $copy.AppName=$unicodeName
    $path=Join-Path $testRoot 'unicode-no-bom.json'
    [IO.File]::WriteAllText($path,($copy | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $destination=Join-Path $testRoot 'unicode-no-bom'
    $null=& $adapter -TemplatePath $TemplatePath -DestinationPath $destination -MetadataPath $path -ActionsPath $actionsPath
    $tokens=$null; $errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $destination 'Invoke-AppDeployToolkit.ps1'),[ref]$tokens,[ref]$errors)
    $table=$ast.FindAll({param($node) $node -is [System.Management.Automation.Language.HashtableAst]},$true) | Where-Object { $_.KeyValuePairs.Item1.Value -contains 'AppVendor' } | Select-Object -First 1
    $pair=$table.KeyValuePairs | Where-Object { $_.Item1.Value -eq 'AppName' }
    Assert-True ($pair.Item2.PipelineElements[0].Expression.SafeGetValue() -ceq $unicodeName) 'UTF8 metadata was corrupted by ANSI decoding.'
}
Test-Case 'Missing required metadata fails before destination is created' {
    $bad=@{}; foreach($entry in $metadata.GetEnumerator()){ $bad[$entry.Key]=$entry.Value }; $bad.Remove('AppVersion')
    $path=Write-Json $bad 'missing.json'; $destination=Join-Path $testRoot 'missing'
    Assert-Rejected { & $adapter -TemplatePath $TemplatePath -DestinationPath $destination -MetadataPath $path -ActionsPath $actionsPath } 'Required metadata'
    Assert-True (!(Test-Path -LiteralPath $destination)) 'Rejected input created output.'
}
Test-Case 'Unknown metadata field is rejected' {
    $bad=@{}; foreach($entry in $metadata.GetEnumerator()){ $bad[$entry.Key]=$entry.Value }; $bad['DeployAppScriptVersion']='9.0.0'
    $path=Write-Json $bad 'unknown.json'
    Assert-Rejected { & $adapter -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'unknown') -MetadataPath $path -ActionsPath $actionsPath } 'Unsupported metadata'
}
Test-Case 'Existing destination is never overwritten' {
    Assert-Rejected { & $adapter -TemplatePath $TemplatePath -DestinationPath $successPath -MetadataPath $metadataPath -ActionsPath $actionsPath } 'Destination already exists'
}
Test-Case 'Previously populated template is rejected by exact pristine hash' {
    Assert-Rejected { & $adapter -TemplatePath $successPath -DestinationPath (Join-Path $testRoot 'second-generation') -MetadataPath $metadataPath -ActionsPath $actionsPath } 'Pristine template hash'
}
Test-Case 'Invalid snippet is rejected before output creation' {
    Set-Content -LiteralPath (Join-Path $testRoot 'invalid.ps1') -Value 'if (' -Encoding UTF8
    $path=Write-Json @{Install=@{Main='invalid.ps1'};Uninstall=@{Main='uninstall.ps1'};Repair=@{Main='repair.ps1'}} 'invalid-actions.json'
    Assert-Rejected { & $adapter -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'invalid-snippet') -MetadataPath $metadataPath -ActionsPath $path } 'Snippet does not parse'
}
Test-Case 'Snippet paths cannot escape reviewed action directory' {
    $path=Write-Json @{Install=@{Main='..\outside.ps1'};Uninstall=@{Main='uninstall.ps1'};Repair=@{Main='repair.ps1'}} 'escape-actions.json'
    Assert-Rejected { & $adapter -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'escaped') -MetadataPath $metadataPath -ActionsPath $path } 'Snippet path must remain'
}
Test-Case 'Unexpected mutation to a bundled upstream file is rejected' {
    $copy=Join-Path $testRoot 'tampered'
    Copy-Item -LiteralPath $TemplatePath -Destination $copy -Recurse
    $upstream=Join-Path $copy 'PSAppDeployToolkit\PSAppDeployToolkit.psm1'
    (Get-Item -LiteralPath $upstream).IsReadOnly=$false
    Add-Content -LiteralPath $upstream -Value '# unauthorized mutation' -Encoding UTF8
    Assert-Rejected { & $adapter -TemplatePath $copy -DestinationPath (Join-Path $testRoot 'tampered-output') -MetadataPath $metadataPath -ActionsPath $actionsPath } 'Upstream file hash mismatch'
}
Test-Case 'Repair behavior must be explicit even when unsupported' {
    $path=Write-Json @{Install=@{Main='install.ps1'};Uninstall=@{Main='uninstall.ps1'}} 'missing-repair.json'
    Assert-Rejected { & $adapter -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'missing-repair') -MetadataPath $metadataPath -ActionsPath $path } 'Required action missing: Repair.Main'
}
Test-Case 'Native v2 omits only the exact stock completion If extent' {
    $destination=Join-Path $testRoot 'omit-prompt'
    $result=& $adapter -TemplatePath $TemplatePath -DestinationPath $destination -MetadataPath $metadataPath -ActionsPath $actionsPath -OmitCompletionPrompt
    $tokens=$null; $errors=$null
    $original=[IO.File]::ReadAllText((Join-Path $TemplatePath 'Invoke-AppDeployToolkit.ps1'))
    $ast=[System.Management.Automation.Language.Parser]::ParseInput($original,[ref]$tokens,[ref]$errors)
    $prompt=@($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Show-ADTInstallationPrompt'},$true))
    $block=$prompt[0].Parent; while($block -isnot [System.Management.Automation.Language.IfStatementAst]) { $block=$block.Parent }
    $removed=@($result.AllowedEdits | Where-Object Kind -eq 'OmitCompletionPrompt')
    Assert-True ($removed.Count -eq 1 -and $removed[0].Start -eq $block.Extent.StartOffset -and $removed[0].Length -eq ($block.Extent.EndOffset-$block.Extent.StartOffset)) 'Removal did not match the exact pristine If extent.'
    $generated=[IO.File]::ReadAllText((Join-Path $destination 'Invoke-AppDeployToolkit.ps1'))
    Assert-True (!$generated.Contains('You can customize text to appear at the end of an install')) 'Stock prompt remains.'
    Assert-True ($result.OmitCompletionPrompt -and !$result.NativeApplicationCommandsValidated -and $result.UnchangedUpstreamFileCount -eq 221) 'Incorrect validation record.'
}
Test-Case 'Native v2 accepts four released commands with simple assignment and interpolation' {
    $snippet=@'
$installerPath = "$($adtSession.DirFiles)\Example.msi"
Start-ADTMsiProcess -Action Install -FilePath $installerPath -AdditionalArgumentList 'ALLUSERS=1' -ExitOnProcessFailure
Start-ADTProcess -FilePath "$env:ProgramFiles\Example\uninstall.exe" -ArgumentList '/S' -WaitForChildProcesses -ExitOnProcessFailure
Write-ADTLogEntry -Message 'Native example' -Severity 1
Close-ADTSession -ExitCode 69001
'@
    Set-Content -LiteralPath (Join-Path $testRoot 'native.ps1') -Value $snippet -Encoding UTF8
    $path=Write-Json @{Install=@{Main='native.ps1'};Uninstall=@{Main='uninstall.ps1'};Repair=@{Main='repair.ps1'}} 'native-actions.json'
    $result=& $adapter -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'native') -MetadataPath $metadataPath -ActionsPath $path -OmitCompletionPrompt -ValidateNativeApplicationCommands
    Assert-True ($result.NativeApplicationCommandsValidated -and $result.NativeApplicationCommandCount -eq 6) 'Native validation did not check every call.'
}
$nonNativeCases=[ordered]@{
    'custom command'='Get-Process -Name firefox'
    'helper definition'="function Local-Helper { Write-ADTLogEntry -Message 'x' }"
    'conditional block'="if (`$true) { Write-ADTLogEntry -Message 'x' }"
    'method call'='Write-ADTLogEntry -Message ([IO.File]::ReadAllText("x"))'
    'dynamic invocation'="& 'Write-ADTLogEntry' -Message 'x'"
    'executable scriptblock'="Write-ADTLogEntry -Message { Get-Process }"
    'command interpolation'='Write-ADTLogEntry -Message "$(Get-Process)"'
    'assigned command'='$value = Get-Process'
    'pipeline'="Write-ADTLogEntry -Message 'x' | Write-ADTLogEntry"
    'redirection'="Write-ADTLogEntry -Message 'x' > output.txt"
    'splatting'='Start-ADTProcess @arguments'
    'unknown parameter'="Start-ADTProcess -FilePath 'example.exe' -InventedSwitch"
    'abbreviated parameter'="Start-ADTProcess -File 'example.exe'"
    'framework mutation'="`$adtSession.AppName = 'Changed'"
    'automatic variable assignment'="`$ErrorActionPreference = 'Continue'"
    'scoped assignment'="`$env:PATH = 'Changed'"
}
foreach($case in $nonNativeCases.GetEnumerator()) {
    Test-Case ('Native v2 rejects '+$case.Key) {
        Set-Content -LiteralPath (Join-Path $testRoot 'non-native.ps1') -Value $case.Value -Encoding UTF8
        $path=Write-Json @{Install=@{Main='non-native.ps1'};Uninstall=@{Main='uninstall.ps1'};Repair=@{Main='repair.ps1'}} 'non-native-actions.json'
        $destination=Join-Path $testRoot ('rejected-'+($case.Key -replace ' ','-'))
        Assert-Rejected { & $adapter -TemplatePath $TemplatePath -DestinationPath $destination -MetadataPath $metadataPath -ActionsPath $path -ValidateNativeApplicationCommands } 'Native application'
        Assert-True (!(Test-Path -LiteralPath $destination)) 'Rejected native style created output.'
    }
}
Test-Case 'Native v2 validation remains opt-in for reviewed custom snippets' {
    Set-Content -LiteralPath (Join-Path $testRoot 'trusted-custom.ps1') -Value 'Get-Process -Name example-app' -Encoding UTF8
    $path=Write-Json @{Install=@{Main='trusted-custom.ps1'};Uninstall=@{Main='uninstall.ps1'};Repair=@{Main='repair.ps1'}} 'trusted-custom-actions.json'
    $result=& $adapter -TemplatePath $TemplatePath -DestinationPath (Join-Path $testRoot 'trusted-custom') -MetadataPath $metadataPath -ActionsPath $path
    Assert-True (!$result.NativeApplicationCommandsValidated) 'Native style unexpectedly imposed without its switch.'
}
Test-Case 'Native v2 rejects a changed stock prompt before creating output' {
    $copy=Join-Path $testRoot 'changed-prompt'
    Copy-Item -LiteralPath $TemplatePath -Destination $copy -Recurse
    $path=Join-Path $copy 'Invoke-AppDeployToolkit.ps1'
    (Get-Item -LiteralPath $path).IsReadOnly=$false
    [IO.File]::WriteAllText($path,([IO.File]::ReadAllText($path).Replace('Show-ADTInstallationPrompt -Message','Write-Host -Object')),[Text.UTF8Encoding]::new($true))
    $destination=Join-Path $testRoot 'changed-prompt-output'
    Assert-Rejected { & $adapter -TemplatePath $copy -DestinationPath $destination -MetadataPath $metadataPath -ActionsPath $actionsPath -OmitCompletionPrompt } 'Pristine template hash'
    Assert-True (!(Test-Path -LiteralPath $destination)) 'Mismatched prompt created output.'
}
$summary=[ordered]@{runUtc=[datetime]::UtcNow.ToString('o');powershell=$PSVersionTable.PSVersion.ToString();testRoot=$testRoot;passed=@($results | Where-Object passed).Count;failed=@($results | Where-Object { !$_.passed }).Count;tests=$results.ToArray()}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $testRoot 'results.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
if ($summary.failed -gt 0) { throw "$($summary.failed) template population tests failed." }
