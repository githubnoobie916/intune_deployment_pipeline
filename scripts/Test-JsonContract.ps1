#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$JsonPath, [Parameter(Mandatory)][string]$SchemaPath)
$ErrorActionPreference = 'Stop'
try {
    if (-not (Test-Json -Json ([IO.File]::ReadAllText($JsonPath)) -SchemaFile $SchemaPath)) { throw 'JSON Schema validation failed.' }
} catch { [Console]::Error.WriteLine($_.ToString()); exit 1 }
