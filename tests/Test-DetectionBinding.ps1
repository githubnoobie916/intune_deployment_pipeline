#requires -Version 5.1
<# Offline binding checks only. Application detection is parsed, never executed. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
. (Join-Path $repository 'scripts\Bind-ApplicationDetection.ps1')
$testRoot = Join-Path $repository ('.validation\detection-binding-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$encoding = [Text.UTF8Encoding]::new($true, $true)
$checks = 0
function Assert-BindingCondition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Assert-BindingRejected {
    param([string]$Text, [string]$Version = '1.2.3', [string]$Label)
    $path = Join-Path $testRoot ([guid]::NewGuid().ToString('N') + '.ps1')
    [IO.File]::WriteAllText($path, $Text, $encoding)
    $rejected = $false
    try { Get-BoundApplicationDetection -SourcePath $path -Version $Version | Out-Null }
    catch { $rejected = $true }
    Assert-BindingCondition $rejected ("Invalid binding was accepted: $Label")
}
$placeholder = "'__RESOLVED_VERSION__'"
$assignment = '$MinimumVersion = [version]' + $placeholder
foreach ($app in @('firefox', 'notepadplusplus')) {
    $path = Join-Path $repository "examples\apps\$app\Detect.template.ps1"
    $originalBytesHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $original = [IO.File]::ReadAllText($path, $encoding)
    foreach ($version in @('1.2.3', '159.0.1.7')) {
        $bound = Get-BoundApplicationDetection -SourcePath $path -Version $version
        Assert-BindingCondition ($bound.Text -ceq $original.Replace($placeholder, "'$version'")) 'Binding changed content outside the literal.'
        Assert-BindingCondition ($bound.SourceSha256 -ieq $originalBytesHash) 'Source hash differs.'
        Assert-BindingCondition ($bound.Version -ceq $version) 'Version result differs.'
        $output = Join-Path $testRoot "$app-$version.ps1"
        [IO.File]::WriteAllText($output, $bound.Text, $encoding)
        Assert-BindingCondition ($bound.GeneratedSha256 -ieq (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash) 'Generated UTF-8 BOM hash differs.'
        $tokens = $null; $errors = $null
        [Management.Automation.Language.Parser]::ParseInput($bound.Text, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-BindingCondition ($errors.Count -eq 0) 'Bound detection does not parse.'
    }
    Assert-BindingCondition ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $originalBytesHash) 'Source was modified.'
}
Assert-BindingRejected -Text '$OtherVersion = [version]''__RESOLVED_VERSION__''' -Label missing
Assert-BindingRejected -Text ($assignment + "`n" + $assignment) -Label duplicate
Assert-BindingRejected -Text ($assignment.Replace('__RESOLVED_VERSION__', '1.2.3')) -Label altered
Assert-BindingRejected -Text ($assignment.Replace('[version]', '[string]')) -Label type
Assert-BindingRejected -Text ($assignment.Replace($placeholder, "('__RESOLVED_' + 'VERSION__')")) -Label expression
Assert-BindingRejected -Text ('if ($true) { ' + $assignment + ' }') -Label nested
Assert-BindingRejected -Text ($assignment + '`n$MinimumVersion = [version]''9.9'''.Replace('`n', "`n")) -Label reassignment
Assert-BindingRejected -Text ($assignment + "`nfunction Read-Version { param(`$MinimumVersion) }") -Label shadowed
Assert-BindingRejected -Text ($assignment + "`n`$script:MinimumVersion = [version]'9.9'") -Label scoped
Assert-BindingRejected -Text ($assignment + "`n`$MinimumVersion++") -Label increment
Assert-BindingRejected -Text ($assignment + "`nforeach (`$MinimumVersion in @('1.0')) { }") -Label loop
Assert-BindingRejected -Text ($assignment + "`nSet-Variable -Name ('Minimum' + 'Version') -Value '9.9'") -Label dynamicVariableWrite
Assert-BindingRejected -Text ($assignment + "`nSet-Item -Path Variable:MinimumVersion -Value '9.9'") -Label providerWrite
Assert-BindingRejected -Text ($assignment + "`nUpdate-Version -Value ([ref]`$MinimumVersion)") -Label referenceWrite
Assert-BindingRejected -Text ($assignment + "`n# SIG # Begin signature block`n# old signature`n# SIG # End signature block") -Label signedSource
foreach ($version in @('1', '1.2-beta', '1.2.3.4.5', '-1.2', '1.2;exit 0', ' 1.2', '01.2', '1.2147483648')) {
    Assert-BindingRejected -Text $assignment -Version $version -Label "unsupported version $version"
}
$unicodeText = '# ' + [char]0x03A9 + [char]0x65E5 + "`r`n" + $assignment + "`r`nthrow 'SOURCE MUST NOT EXECUTE'`r`n"
$unicodePath = Join-Path $testRoot 'unicode.ps1'
[IO.File]::WriteAllText($unicodePath, $unicodeText, $encoding)
$unicodeResult = Get-BoundApplicationDetection -SourcePath $unicodePath -Version '2.3'
Assert-BindingCondition ($unicodeResult.Text -ceq $unicodeText.Replace($placeholder, "'2.3'")) 'Unicode, line endings, or non-binding statements changed.'
Assert-BindingCondition ([IO.File]::ReadAllText($unicodePath, $encoding) -ceq $unicodeText) 'Unicode source changed.'
$noBomPath = Join-Path $testRoot 'no-bom.ps1'
[IO.File]::WriteAllText($noBomPath, $unicodeText, [Text.UTF8Encoding]::new($false, $true))
$noBomResult = Get-BoundApplicationDetection -SourcePath $noBomPath -Version '2.3'
Assert-BindingCondition ($noBomResult.GeneratedSha256 -ceq $unicodeResult.GeneratedSha256) 'Output encoding depends on source BOM.'
$invalidUtf8Path = Join-Path $testRoot 'invalid-utf8.ps1'
[IO.File]::WriteAllBytes($invalidUtf8Path, [byte[]]@(0xFF, 0xFE, 0x41, 0x00))
$rejectedEncoding = $false
try { Get-BoundApplicationDetection -SourcePath $invalidUtf8Path -Version '1.2' | Out-Null } catch { $rejectedEncoding = $true }
Assert-BindingCondition $rejectedEncoding 'Non-UTF-8 source was accepted.'
[pscustomobject]@{ Passed = $true; Checks = $checks; PowerShellVersion = $PSVersionTable.PSVersion.ToString(); Artifacts = $testRoot; Limitation = 'Static binding only; detection and installation were not executed.' }
