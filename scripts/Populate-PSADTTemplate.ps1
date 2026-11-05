#requires -Version 5.1
<#
.SYNOPSIS
Creates an offline working copy of the exact official PSADT 4.1.8 v4 template.
.DESCRIPTION
Only allowlisted metadata values, task insertion points, and an opt-in exact completion
prompt removal change. Native command validation is an opt-in sample style check.
Snippets are trusted, reviewed application code. They are parsed, never executed here.
No toolkit import, installer execution, packaging, authentication or tenant operation occurs.
The evidence manifest and this adapter are trusted repository inputs, not a sandbox.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TemplatePath,
    [Parameter(Mandatory)][string]$DestinationPath,
    [Parameter(Mandatory)][string]$MetadataPath,
    [Parameter(Mandatory)][string]$ActionsPath,
    [switch]$OmitCompletionPrompt,
    [switch]$ValidateNativeApplicationCommands
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$expectedScriptHash='3E6DB6941A332E1212AD88EC1A715D3D56A7A94F31F1CBFA0C261FE3CECFF67A'
$expectedArchiveHash='50cb8d32973fc7648060a48cad63912ecb5caca5a70754f37e83aa06bd380283'

function Read-JsonObject([string]$Path) {
    # Windows PowerShell otherwise decodes UTF8-without-BOM JSON as ANSI.
    $value=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath) | ConvertFrom-Json
    if ($null -eq $value -or $value -isnot [pscustomobject]) { throw "JSON must contain an object: $Path" }
    return $value
}
function ConvertTo-Literal($Value) {
    if ($Value -is [string]) { return "'" + $Value.Replace("'","''") + "'" }
    if ($Value -is [bool]) { return '$' + $Value.ToString().ToLowerInvariant() }
    if ($Value -is [int] -or $Value -is [long]) { return $Value.ToString([cultureinfo]::InvariantCulture) }
    throw 'Only explicitly typed values can be rendered as metadata.'
}
function Get-ParsedScript([string]$Text, [string]$Description) {
    $tokens=$null; $errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw "$Description does not parse: $($errors[0].Message)" }
    return [pscustomobject]@{Ast=$ast;Tokens=$tokens}
}
function Assert-NativeApplicationCommands($Ast, [hashtable]$CommandParameters) {
    # A deliberately small sample-style grammar, not a PowerShell security sandbox.
    $nodeTypes=@('ScriptBlockAst','NamedBlockAst','AssignmentStatementAst','CommandExpressionAst','PipelineAst','CommandAst','CommandParameterAst','StringConstantExpressionAst','ConstantExpressionAst','ExpandableStringExpressionAst','VariableExpressionAst','SubExpressionAst','StatementBlockAst','MemberExpressionAst')
    $nodes=@($Ast.FindAll({param($n) $true},$true))
    $locals=@{}
    foreach($node in $nodes) {
        if ($node.GetType().Name -notin $nodeTypes) { throw "Native application style rejects $($node.GetType().Name)." }
        if ($node -is [System.Management.Automation.Language.AssignmentStatementAst]) {
            if ($node.Parent -ne $Ast.EndBlock -or $node.Operator -ne 'Equals' -or $node.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { throw 'Native application assignments must set simple local variables.' }
            $name=$node.Left.VariablePath.UserPath
            if ($name -notmatch '^[a-zA-Z][a-zA-Z0-9_]*$' -or $name -in @('adtSession','true','false','null','ErrorActionPreference','ProgressPreference','PSModuleAutoLoadingPreference','PSDefaultParameterValues','PSNativeCommandArgumentPassing','PSNativeCommandUseErrorActionPreference','OutputEncoding','OFS','PWD','HOME','Host','ExecutionContext','MyInvocation','PSBoundParameters','PSScriptRoot','PSCommandPath','PSVersionTable','Args','Input','Matches','LASTEXITCODE','Error','NestedPromptLevel','PID','ShellId','StackTrace','Profile')) { throw "Native application assignment target is reserved or scoped: $name" }
            $locals[$name]=$true
        }
    }
    $count=0
    foreach($node in $nodes) {
        if ($node -is [System.Management.Automation.Language.ScriptBlockAst] -and $node -ne $Ast) { throw 'Native application style rejects executable blocks.' }
        if ($node -is [System.Management.Automation.Language.NamedBlockAst] -and $node -ne $Ast.EndBlock) { throw 'Native application style accepts only ordinary statements.' }
        if ($node -is [System.Management.Automation.Language.PipelineAst] -and ($node.PipelineElements.Count -ne 1 -or ($node.PSObject.Properties['Background'] -and $node.Background))) { throw 'Native application style rejects pipelines and background execution.' }
        if ($node -is [System.Management.Automation.Language.CommandExpressionAst] -and $node.Redirections.Count) { throw 'Native application style rejects redirection.' }
        if ($node -is [System.Management.Automation.Language.MemberExpressionAst]) {
            if ($node.Static -or $node.Expression -isnot [System.Management.Automation.Language.VariableExpressionAst] -or $node.Expression.VariablePath.UserPath -ne 'adtSession' -or $node.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $node.Member.Value -notin @('DirFiles','DirSupportFiles','AppName','AppVersion')) { throw 'Native application style permits only named session data reads.' }
        }
        if ($node -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $name=$node.VariablePath.UserPath
            if ($node.Splatted -or ($name -notmatch '^env:[a-zA-Z_][a-zA-Z0-9_]*$' -and $name -notin @('adtSession','true','false','null') -and !$locals.ContainsKey($name))) { throw "Native application style rejects variable reference: $name" }
        }
        if ($node -is [System.Management.Automation.Language.SubExpressionAst]) {
            $statements=@($node.SubExpression.Statements)
            if ($statements.Count -ne 1 -or $statements[0] -isnot [System.Management.Automation.Language.PipelineAst] -or $statements[0].PipelineElements.Count -ne 1 -or $statements[0].PipelineElements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst]) { throw 'Native application interpolation must contain a single data expression.' }
        }
        if ($node -is [System.Management.Automation.Language.CommandAst]) {
            $name=$node.GetCommandName()
            if ($node.InvocationOperator -ne 'Unknown' -or !$name -or !$CommandParameters.ContainsKey($name) -or $node.CommandElements[0] -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $node.Parent -isnot [System.Management.Automation.Language.PipelineAst] -or $node.Parent.Parent -ne $Ast.EndBlock -or $node.Redirections.Count) { throw 'Native application commands must be direct top-level calls to the four approved functions.' }
            $seen=@{}
            foreach($parameter in @($node.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] })) {
                if ($parameter.ParameterName -notin $CommandParameters[$name] -or $seen.ContainsKey($parameter.ParameterName)) { throw "Native application parameter is not a unique full released parameter name: $name -$($parameter.ParameterName)" }
                $seen[$parameter.ParameterName]=$true
            }
            $count++
        }
    }
    return $count
}
function Assert-Inventory([string]$Root, $Expected, [switch]$AllowPopulatedScript) {
    $entries=@(Get-ChildItem -LiteralPath $Root -Recurse -Force)
    # OneDrive cloud files also carry ReparsePoint; reject path redirection, not cloud storage.
    if (@($entries | Where-Object { $_.PSObject.Properties['LinkType'] -and $_.LinkType }).Count) { throw 'Symbolic links and junctions are not allowed in the template.' }
    $files=@($entries | Where-Object { !$_.PSIsContainer })
    if ($files.Count -ne $Expected.Count) { throw 'Upstream file inventory count mismatch.' }
    foreach($item in $Expected) {
        $path=Join-Path $Root $item.path
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing upstream file: $($item.path)" }
        if ($AllowPopulatedScript -and $item.path -eq 'Invoke-AppDeployToolkit.ps1') { continue }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $item.sha256) { throw "Upstream file hash mismatch: $($item.path)" }
    }
}
function Assert-NoRedirectedAncestors([string]$Path) {
    $candidate=$Path
    while ($candidate) {
        if (Test-Path -LiteralPath $candidate) {
            $item=Get-Item -LiteralPath $candidate -Force
            if ($item.PSObject.Properties['LinkType'] -and $item.LinkType) { throw 'Build paths cannot traverse symbolic links or junctions.' }
        }
        $parent=[IO.Path]::GetDirectoryName($candidate.TrimEnd('\','/'))
        if ($parent -eq $candidate) { break }
        $candidate=$parent
    }
}

$source=(Resolve-Path -LiteralPath $TemplatePath).ProviderPath.TrimEnd('\','/')
$destination=[IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)).TrimEnd('\','/')
if (Test-Path -LiteralPath $destination) { throw 'Destination already exists; choose a new clean build directory.' }
if ($destination.Equals($source,[StringComparison]::OrdinalIgnoreCase) -or $destination.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Destination must be outside the pristine template.' }
Assert-NoRedirectedAncestors $source
Assert-NoRedirectedAncestors $destination
$scriptPath=Join-Path $source 'Invoke-AppDeployToolkit.ps1'
if ((Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash -ne $expectedScriptHash) { throw 'Pristine template hash does not match the official 4.1.8 v4 release.' }
$manifest=Read-JsonObject (Join-Path $PSScriptRoot '..\evidence\psadt-4.1.8-release.json')
if ($manifest.version -ne '4.1.8' -or $manifest.archiveSha256 -ne $expectedArchiveHash -or $manifest.files.Count -ne 222) { throw 'Unexpected trusted release manifest.' }
Assert-Inventory $source $manifest.files
$original=[IO.File]::ReadAllText($scriptPath)
$parsed=Get-ParsedScript $original 'Pristine script'
$nativeParameters=@{}
$nativeCommandCount=0
if ($ValidateNativeApplicationCommands) {
    $moduleParsed=Get-ParsedScript ([IO.File]::ReadAllText((Join-Path $source 'PSAppDeployToolkit\PSAppDeployToolkit.psm1'))) 'Released module'
    foreach($name in @('Start-ADTMsiProcess','Start-ADTProcess','Write-ADTLogEntry','Close-ADTSession')) {
        $definition=@($moduleParsed.Ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | Where-Object Name -eq $name)
        if ($definition.Count -ne 1 -or !$definition[0].Body.ParamBlock) { throw "Native application command definition unavailable in release: $name" }
        $nativeParameters[$name]=@($definition[0].Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    }
}
$metadata=Read-JsonObject $MetadataPath
$required=@('AppVendor','AppName','AppVersion','AppArch','AppLang','AppRevision','AppScriptVersion','AppScriptDate','AppScriptAuthor')
$stringKeys=$required+@('InstallName','InstallTitle')
$allowed=$stringKeys+@('AppSuccessExitCodes','AppRebootExitCodes','AppProcessesToClose','RequireAdmin')
foreach($key in $required) {
    $property=$metadata.PSObject.Properties[$key]
    if ($null -eq $property -or $property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($property.Value)) { throw "Required metadata is missing or empty: $key" }
}
$scriptVersion=$null
if (![version]::TryParse($metadata.AppScriptVersion,[ref]$scriptVersion)) { throw 'AppScriptVersion must be a .NET version string.' }
$scriptDate=[datetime]::MinValue
if (![datetime]::TryParseExact($metadata.AppScriptDate,'yyyy-MM-dd',[cultureinfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$scriptDate)) { throw 'AppScriptDate must be yyyy-MM-dd.' }
if ($metadata.AppScriptAuthor -eq '<author name>') { throw 'Required metadata AppScriptAuthor still contains the upstream placeholder.' }
$tables=@($parsed.Ast.FindAll({param($n) $n -is [System.Management.Automation.Language.HashtableAst]},$true) | Where-Object { $_.KeyValuePairs.Item1.Value -contains 'AppVendor' })
if ($tables.Count -ne 1) { throw 'Unexpected template metadata structure.' }
$edits=[System.Collections.Generic.List[object]]::new()
if ($OmitCompletionPrompt) {
    $prompts=@($parsed.Ast.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Show-ADTInstallationPrompt'},$true))
    if ($prompts.Count -ne 1) { throw 'Unexpected stock completion prompt count.' }
    $promptIf=$prompts[0].Parent
    while ($promptIf -and $promptIf -isnot [System.Management.Automation.Language.IfStatementAst]) { $promptIf=$promptIf.Parent }
    $expectedPrompt=@'
if (!$adtSession.UseDefaultMsi)
    {
        Show-ADTInstallationPrompt -Message 'You can customize text to appear at the end of an install or remove it completely for unattended installations.' -ButtonRightText 'OK' -NoWait
    }
'@ -replace '\r?\n',"`r`n"
    $owner=if ($promptIf) { $promptIf.Parent }
    while ($owner -and $owner -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $owner=$owner.Parent }
    if (!$promptIf -or $promptIf.Extent.Text -cne $expectedPrompt -or !$owner -or $owner.Name -cne 'Install-ADTDeployment') { throw 'Unexpected stock completion prompt structure or text.' }
    $edits.Add([pscustomobject]@{Start=$promptIf.Extent.StartOffset;Length=$promptIf.Extent.EndOffset-$promptIf.Extent.StartOffset;Text='';Kind='OmitCompletionPrompt'})
}
foreach($property in $metadata.PSObject.Properties) {
    $key=$property.Name; $value=$property.Value
    if ($key -cnotin $allowed) { throw "Unsupported metadata field: $key" }
    if ($key -in $stringKeys) {
        if ($value -isnot [string]) { throw "Metadata must be a string: $key" }
        $literal=ConvertTo-Literal $value
    } elseif ($key -eq 'RequireAdmin') {
        if ($value -isnot [bool]) { throw 'RequireAdmin must be a JSON boolean.' }
        $literal=ConvertTo-Literal $value
    } elseif ($key -in @('AppSuccessExitCodes','AppRebootExitCodes')) {
        if ($value -isnot [array] -or !$value.Count) { throw "$key must be a nonempty integer array." }
        $literals=foreach($code in $value) {
            if (($code -isnot [int] -and $code -isnot [long]) -or $code -lt 0 -or $code -gt [int]::MaxValue) { throw "$key contains an invalid exit code." }
            ConvertTo-Literal $code
        }
        $literal='@('+($literals -join ', ')+')'
    } else {
        if ($value -isnot [array]) { throw 'AppProcessesToClose must be an array.' }
        $literals=foreach($process in $value) {
            if ($process -is [string] -and ![string]::IsNullOrWhiteSpace($process)) { ConvertTo-Literal $process; continue }
            if ($process -isnot [pscustomobject] -or @($process.PSObject.Properties | Where-Object Name -cnotin @('Name','Description')).Count -or $null -eq $process.PSObject.Properties['Name'] -or $process.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($process.Name)) { throw 'Invalid AppProcessesToClose object.' }
            $entry='@{ Name = '+(ConvertTo-Literal $process.Name)
            if ($null -ne $process.PSObject.Properties['Description']) {
                if ($process.Description -isnot [string]) { throw 'Process Description must be a string.' }
                $entry+='; Description = '+(ConvertTo-Literal $process.Description)
            }
            $entry+' }'
        }
        $literal='@('+($literals -join ', ')+')'
    }
    $pairs=@($tables[0].KeyValuePairs | Where-Object { $_.Item1.Value -ceq $key })
    if ($pairs.Count -ne 1) { throw "Unexpected metadata slot: $key" }
    $extent=$pairs[0].Item2.Extent
    $edits.Add([pscustomobject]@{Start=$extent.StartOffset;Length=$extent.EndOffset-$extent.StartOffset;Text=$literal;Kind="Metadata.$key"})
}

$actionsFile=(Resolve-Path -LiteralPath $ActionsPath).ProviderPath
$actionsRoot=Split-Path -Parent $actionsFile
$actions=Read-JsonObject $actionsFile
foreach($operation in @('Install','Uninstall','Repair')) {
    $property=$actions.PSObject.Properties[$operation]
    if ($null -eq $property -or $null -eq $property.Value -or $null -eq $property.Value.PSObject.Properties['Main']) { throw "Required action missing: $operation.Main" }
}
$labels=@{Install=@{Pre='Pre-Installation';Main='Installation';Post='Post-Installation'};Uninstall=@{Pre='Pre-Uninstallation';Main='Uninstallation';Post='Post-Uninstallation'};Repair=@{Pre='Pre-Repair';Main='Repair';Post='Post-Repair'}}
$snippetEvidence=[System.Collections.Generic.List[object]]::new()
foreach($operation in $actions.PSObject.Properties) {
    if ($operation.Name -cnotin @('Install','Uninstall','Repair') -or $operation.Value -isnot [pscustomobject]) { throw "Unsupported action operation: $($operation.Name)" }
    foreach($phase in $operation.Value.PSObject.Properties) {
        if ($phase.Name -cnotin @('Pre','Main','Post') -or $phase.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($phase.Value)) { throw "Unsupported action phase: $($phase.Name)" }
        $snippetPath=[IO.Path]::GetFullPath((Join-Path $actionsRoot $phase.Value))
        if ([IO.Path]::IsPathRooted($phase.Value) -or !$snippetPath.StartsWith($actionsRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Snippet path must remain within the reviewed actions directory.' }
        $snippetItem=Get-Item -LiteralPath $snippetPath
        $ancestor=$snippetItem
        while($null -ne $ancestor -and $ancestor.FullName.StartsWith($actionsRoot,[StringComparison]::OrdinalIgnoreCase)) {
            if ($ancestor.PSObject.Properties['LinkType'] -and $ancestor.LinkType) { throw 'Snippet paths cannot use symbolic links or junctions.' }
            $ancestor=if ($ancestor -is [IO.FileInfo]) { $ancestor.Directory } else { $ancestor.Parent }
        }
        $snippet=[IO.File]::ReadAllText($snippetPath)
        if ([string]::IsNullOrWhiteSpace($snippet)) { throw 'Snippet must not be empty.' }
        $snippetParsed=Get-ParsedScript $snippet 'Snippet'
        if ($snippetParsed.Ast.ParamBlock -or $snippetParsed.Ast.BeginBlock -or $snippetParsed.Ast.ProcessBlock) { throw 'Snippet must contain only application statements, not script parameters or named blocks.' }
        if ($ValidateNativeApplicationCommands) { $nativeCommandCount+=Assert-NativeApplicationCommands $snippetParsed.Ast $nativeParameters }
        $marker='## <Perform '+$labels[$operation.Name][$phase.Name]+' tasks here>'
        $matches=@($parsed.Tokens | Where-Object { $_.Kind -eq 'Comment' -and $_.Text -ceq $marker })
        if ($matches.Count -ne 1) { throw "Expected unique documented task marker: $marker" }
        $function=@($parsed.Ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | Where-Object Name -eq ($operation.Name+'-ADTDeployment'))
        $offset=$matches[0].Extent.EndOffset
        if ($function.Count -ne 1 -or $offset -le $function[0].Body.Extent.StartOffset -or $offset -ge $function[0].Body.Extent.EndOffset) { throw 'Task marker is outside its expected deployment function.' }
        $insert="`r`n"+(($snippet.TrimEnd() -split '\r?\n' | ForEach-Object { '    '+$_ }) -join "`r`n")
        $edits.Add([pscustomobject]@{Start=$offset;Length=0;Text=$insert;Kind=($operation.Name+'.'+$phase.Name)})
        $snippetEvidence.Add([pscustomobject]@{section=($operation.Name+'.'+$phase.Name);path=$phase.Value;sha256=(Get-FileHash -LiteralPath $snippetPath).Hash.ToLowerInvariant()})
    }
}
$ordered=@($edits | Sort-Object Start)
$previousEnd=0; $delta=0
foreach($edit in $ordered) {
    if ($edit.Start -lt $previousEnd) { throw 'Allowed edit extents overlap.' }
    $edit | Add-Member -NotePropertyName GeneratedStart -NotePropertyValue ($edit.Start+$delta)
    $previousEnd=$edit.Start+$edit.Length; $delta+=$edit.Text.Length-$edit.Length
}
$generated=$original
foreach($edit in ($ordered | Sort-Object Start -Descending)) { $generated=$generated.Remove($edit.Start,$edit.Length).Insert($edit.Start,$edit.Text) }
$null=Get-ParsedScript $generated 'Generated script'
# Reverse only permitted edits: exact equality proves framework/control-flow text survived.
$restored=$generated
foreach($edit in ($ordered | Sort-Object GeneratedStart -Descending)) { $restored=$restored.Remove($edit.GeneratedStart,$edit.Text.Length).Insert($edit.GeneratedStart,$original.Substring($edit.Start,$edit.Length)) }
if ($restored -cne $original) { throw 'Generated script differs outside explicitly permitted edit extents.' }

$null=New-Item -ItemType Directory -Path $destination
Get-ChildItem -LiteralPath $source -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force }
$outputScript=Join-Path $destination 'Invoke-AppDeployToolkit.ps1'
[IO.File]::WriteAllText($outputScript,$generated,[Text.UTF8Encoding]::new($true))
if ([IO.File]::ReadAllText($outputScript) -cne $generated) { throw 'Written script differs from validated content.' }
Assert-Inventory $destination $manifest.files -AllowPopulatedScript
Assert-Inventory $source $manifest.files
[pscustomobject]@{
    Passed=$true; TemplateVersion='4.1.8'; DestinationPath=$destination
    PristineScriptSha256=$expectedScriptHash.ToLowerInvariant()
    GeneratedScriptSha256=(Get-FileHash -LiteralPath $outputScript).Hash.ToLowerInvariant()
    UnchangedUpstreamFileCount=$manifest.files.Count-1
    OmitCompletionPrompt=[bool]$OmitCompletionPrompt
    NativeApplicationCommandsValidated=[bool]$ValidateNativeApplicationCommands
    NativeApplicationCommandCount=$nativeCommandCount
    AllowedEdits=@($ordered | Select-Object Kind,Start,Length,GeneratedStart)
    Snippets=$snippetEvidence.ToArray()
    Limitation='Offline structural validation only; no deployment, installer or tenant test performed.'
}
