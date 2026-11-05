#requires -Version 5.1
<# Dot-source to load the binder. It only reads/parses trusted source; it never executes detection. #>
function Get-BoundApplicationDetection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$Version
    )
    # This binding contract deliberately supports canonical numeric .NET versions only.
    # Other vendor formats require a separately reviewed mapping before calling this function.
    $parsedVersion = $null
    if ($Version -cnotmatch '^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){1,3}$' -or
        -not [version]::TryParse($Version, [ref]$parsedVersion)) {
        throw 'Detection version must be a canonical numeric .NET version with two to four components.'
    }
    $resolvedPath = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).ProviderPath
    $sourceBytes = [IO.File]::ReadAllBytes($resolvedPath)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $offset = 0
    if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) { $offset = 3 }
    try { $source = $utf8.GetString($sourceBytes, $offset, $sourceBytes.Length - $offset) }
    catch { throw 'Detection source must use valid UTF-8 encoding, with or without a BOM.' }
    if ($source -match '(?m)^\s*# SIG # Begin signature block') { throw 'Bind an unsigned detection template before signing the generated detection.' }
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Detection source has PowerShell parser errors.' }
    $bindingVariables = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.VariableExpressionAst] -and
        $node.VariablePath.UserPath -match '(^|:)MinimumVersion$'
    }, $true))
    if (@($bindingVariables | Where-Object { $_.VariablePath.UserPath -ine 'MinimumVersion' }).Count) {
        throw 'The MinimumVersion binding cannot use a scoped or provider-qualified variable.'
    }
    $assignments = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $null -ne $node.Left.Find({
            param($part)
            $part -is [Management.Automation.Language.VariableExpressionAst] -and
            $part.VariablePath.UserPath -match '(^|:)MinimumVersion$'
        }, $true)
    }, $true))
    if ($assignments.Count -ne 1) { throw 'Detection requires exactly one MinimumVersion assignment.' }
    $assignment = $assignments[0]
    if (-not [object]::ReferenceEquals($assignment.Parent, $ast.EndBlock) -or
        $assignment.Operator -ne [Management.Automation.Language.TokenKind]::Equals -or
        $assignment.Left -isnot [Management.Automation.Language.VariableExpressionAst] -or
        $assignment.Right -isnot [Management.Automation.Language.CommandExpressionAst] -or
        $assignment.Right.Redirections.Count) {
        throw 'MinimumVersion must be one plain top-level assignment.'
    }
    $cast = $assignment.Right.Expression
    if ($cast -isnot [Management.Automation.Language.ConvertExpressionAst] -or $cast.Type.TypeName.FullName -ine 'version') {
        throw 'MinimumVersion must use the explicit [version] cast.'
    }
    $literal = $cast.Child
    if ($literal -isnot [Management.Automation.Language.StringConstantExpressionAst] -or
        $literal.StringConstantType -ne [Management.Automation.Language.StringConstantType]::SingleQuoted -or
        $literal.Value -cne '__RESOLVED_VERSION__') {
        throw 'MinimumVersion must contain the single-quoted __RESOLVED_VERSION__ placeholder.'
    }
    # Reject structural shadowing, reference passing and visible writes to the binding.
    # This is a source contract, not a security sandbox or proof of arbitrary script behavior.
    foreach ($variable in $bindingVariables) {
        if ($variable.Parent -is [Management.Automation.Language.ParameterAst] -or
            ($variable.Parent -is [Management.Automation.Language.ForEachStatementAst] -and [object]::ReferenceEquals($variable.Parent.Variable, $variable)) -or
            ($variable.Parent -is [Management.Automation.Language.UnaryExpressionAst] -and $variable.Parent.TokenKind.ToString() -match 'PlusPlus|MinusMinus')) {
            throw 'MinimumVersion cannot be redeclared, shadowed, or incremented.'
        }
        for ($ancestor = $variable.Parent; $null -ne $ancestor -and $ancestor -isnot [Management.Automation.Language.StatementAst]; $ancestor = $ancestor.Parent) {
            if ($ancestor -is [Management.Automation.Language.ConvertExpressionAst] -and $ancestor.Type.TypeName.FullName -ieq 'ref') {
                throw 'MinimumVersion cannot be passed by reference.'
            }
        }
    }
    $variableWriters = @('Set-Variable', 'New-Variable', 'Clear-Variable', 'Remove-Variable', 'sv', 'set', 'nv', 'clv', 'rv')
    $providerWriters = @('Set-Item', 'New-Item', 'Clear-Item', 'Remove-Item', 'Copy-Item', 'Move-Item', 'Rename-Item', 'si', 'ni', 'cli', 'ri', 'cpi', 'mi', 'rni', 'sp', 'Set-ItemProperty')
    foreach ($command in @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true))) {
        $commandName = [string]$command.GetCommandName()
        $commandName = ($commandName -split '\\')[-1]
        if ($commandName -in $variableWriters) { throw 'Variable-writing commands are unsupported in a bound detection template.' }
        if ($commandName -in $providerWriters -and @($command.FindAll({
            param($node)
            $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -match '^(?:Microsoft\.PowerShell\.Core\\)?Variable:'
        }, $true)).Count) { throw 'Variable-provider writes are unsupported in a bound detection template.' }
    }
    if (@($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.MemberExpressionAst] -and
        $node.Member -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Member.Value -ieq 'PSVariable'
    }, $true)).Count) { throw 'Direct session variable access is unsupported in a bound detection template.' }
    $replacement = "'$Version'"
    $text = $source.Substring(0, $literal.Extent.StartOffset) + $replacement + $source.Substring($literal.Extent.EndOffset)
    $generatedTokens = $null; $generatedErrors = $null
    [Management.Automation.Language.Parser]::ParseInput($text, [ref]$generatedTokens, [ref]$generatedErrors) | Out-Null
    if ($generatedErrors.Count) { throw 'Bound detection has PowerShell parser errors.' }
    # The caller writes Text with UTF8Encoding(true, true), then signs if required.
    $outputEncoding = [Text.UTF8Encoding]::new($true, $true)
    $outputBytes = [byte[]]($outputEncoding.GetPreamble() + $outputEncoding.GetBytes($text))
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $sourceHash = [BitConverter]::ToString($sha256.ComputeHash($sourceBytes)).Replace('-', '').ToLowerInvariant()
        $generatedHash = [BitConverter]::ToString($sha256.ComputeHash($outputBytes)).Replace('-', '').ToLowerInvariant()
    } finally { $sha256.Dispose() }
    [pscustomobject]@{ Text = $text; SourceSha256 = $sourceHash; GeneratedSha256 = $generatedHash; Version = $Version }
}
