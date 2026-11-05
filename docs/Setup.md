# Workstation setup

[Back to the start-to-finish guide](Getting-started.md)

Use this page once on each packaging workstation, or when restoring a fresh checkout. Setup prepares local dependencies and offline examples. It does not install either application, authenticate to Microsoft, or create tenant resources.

## 1. Prepare the workstation

| Requirement | Use |
|---|---|
| Windows 11 x64 | The project's initial build and endpoint baseline |
| 64-bit Windows PowerShell 5.1 | Run the documented commands and baseline checks |
| PowerShell 7.5 or later, available as `pwsh.exe` | Required for JSON Schema validation from Windows PowerShell; also supports separate PowerShell 7 runs with string-preserving JSON reads |
| .NET Framework 4.7.2 or later | Required when running the pinned Microsoft Content Prep Tool |
| Git or a downloaded repository ZIP | Obtain the project source |
| Internet access to approved download sources | Restore dependencies; later discovery also contacts vendor services |
| Isolated Windows 11 test machine | Required later for installation and functional testing |

The packaging prerequisite comes from the [Microsoft v1.8.7 README](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/blob/v1.8.7/README.md). Offline source checks and template generation do not require an Intune account or an elevated shell.

Use a nonsynchronized local checkout for routine work. Keep active builds, locks, mutable state, and packages outside OneDrive. If reviewing the existing OneDrive copy, make the required files available locally before running checks.

## 2. Open the repository root

**Existing workspace:** open PowerShell in the folder containing `README.md`, `examples`, `scripts`, and `tests`.

**Fresh checkout:** clone the actual repository URL supplied by its owner, or extract its source ZIP, then open that folder. This project does not prescribe a repository URL.

Run:

```powershell
$repo = (Get-Location).Path
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath (Join-Path $repo 'scripts\Populate-PSADTTemplate.ps1'))) {
    throw 'Open PowerShell in the repository root first.'
}
if (-not [Environment]::Is64BitProcess) {
    throw 'Use a 64-bit PowerShell process.'
}
$PSVersionTable.PSVersion
```

Review the repository scripts before running them. Where your organization permits unsigned reviewed scripts, a process-only execution-policy setting is sufficient:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

This setting ends with the current PowerShell process. It does not override Group Policy or application control. If your environment requires signed code, follow that workflow instead. Do not change machine-wide policy for this project.

## 3. Restore the pinned dependency files

Both `.research/` and `generated-examples/` are [excluded from Git](../.gitignore). A fresh checkout therefore lacks the dependencies and generated examples. If these files already exist, retain them and run the verification steps below.

Download the following exact artifacts from their official sources, or retrieve the same bytes from your organization's approved artifact store. Create the destination folders as needed. **Downloading is a network operation; these are tooling dependencies, not the Firefox or Notepad++ installers.**

| Artifact | Download | Save relative to the repository root |
|---|---|---|
| PSADT 4.1.8 v4 template | [Official release ZIP](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases/download/4.1.8/PSAppDeployToolkit_Template_v4.zip) | `.research/psadt/PSAppDeployToolkit_Template_v4-4.1.8.zip` |
| Evergreen 2610.2859.0 | [Published package](https://www.powershellgallery.com/api/v2/package/Evergreen/2610.2859.0) | `.research/evergreen/Evergreen.2610.2859.0.nupkg` |
| Evergreen definitions v26.11.03.146 | [Release archive](https://github.com/EUCPilots/evergreen-apps/releases/download/v26.11.03.146/evergreen-apps.zip) | `.research/evergreen/evergreen-apps-v26.11.03.146.zip` |
| IntuneWin32App 1.5.0 | [Published package](https://www.powershellgallery.com/api/v2/package/IntuneWin32App/1.5.0) | `.research/intune/IntuneWin32App.1.5.0.nupkg` |
| Content Prep Tool v1.8.7 | [Pinned executable](https://raw.githubusercontent.com/microsoft/Microsoft-Win32-Content-Prep-Tool/v1.8.7/IntuneWinAppUtil.exe) | `.research/intune/IntuneWinAppUtil-1.8.7.exe` |

Use the released **v4 template**, not the v3 ZIP or a raw repository frontend. Keep Evergreen's module and application definitions pinned separately. Do not substitute a newer dependency when an old download fails; use retained approved artifacts or perform the [controlled upgrade process](PSADT-4.1.8-standard.md#verification-and-controlled-toolkit-upgrades).

## 4. Verify downloads before extracting

The following checks use hashes from the committed inspection evidence. A mismatch stops setup. It is not a reason to replace the recorded hash.

```powershell
$psadtEvidence = Get-Content (Join-Path $repo 'evidence\psadt-4.1.8-release.json') -Raw | ConvertFrom-Json
$evergreenEvidence = Get-Content (Join-Path $repo 'evidence\evergreen-2610.2859.0-inspection.json') -Raw | ConvertFrom-Json
$intuneEvidence = Get-Content (Join-Path $repo 'evidence\intunewin32app-1.5.0-inspection.json') -Raw | ConvertFrom-Json

$dependencies = @(
    @{ Path = '.research\psadt\PSAppDeployToolkit_Template_v4-4.1.8.zip'; Hash = $psadtEvidence.archiveSha256; Folder = '.research\psadt\pristine' }
    @{ Path = '.research\evergreen\Evergreen.2610.2859.0.nupkg'; Hash = $evergreenEvidence.publishedModule.sha256; Folder = '.research\evergreen\module' }
    @{ Path = '.research\evergreen\evergreen-apps-v26.11.03.146.zip'; Hash = $evergreenEvidence.definitions.sha256; Folder = '.research\evergreen\definitions' }
    @{ Path = '.research\intune\IntuneWin32App.1.5.0.nupkg'; Hash = $intuneEvidence.package.sha256; Folder = '.research\intune\IntuneWin32App.1.5.0' }
    @{ Path = '.research\intune\IntuneWinAppUtil-1.8.7.exe'; Hash = $intuneEvidence.contentPrepTool.sha256; Folder = $null }
)

foreach ($dependency in $dependencies) {
    $path = Join-Path $repo $dependency.Path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Restore the missing dependency: $path"
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $dependency.Hash) {
        throw "Dependency hash mismatch: $path"
    }
}
'All five dependency hashes match the recorded baseline.'
```

These hashes establish agreement with the previously inspected bytes. Separate provenance and signature observations are in the [source ledger](../evidence/source-ledger.md); an archive hash alone is not independent publisher authentication.

## 5. Extract and verify the local dependency folders

Run this in the same PowerShell session as step 4. It extracts only missing folders, supports both ZIP and NuGet package archives, and compares every extracted file against the verified archive. Existing folders are checked without being overwritten.

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem

foreach ($dependency in $dependencies | Where-Object { $_.Folder }) {
    $archivePath = Join-Path $repo $dependency.Path
    $folderPath = Join-Path $repo $dependency.Folder
    if (-not (Test-Path -LiteralPath $folderPath)) {
        [IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $folderPath)
    }

    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entries = @($archive.Entries | Where-Object { $_.Name })
        $files = @(Get-ChildItem -LiteralPath $folderPath -Recurse -File -Force)
        if ($files.Count -ne $entries.Count) {
            throw "Extracted file count differs: $folderPath"
        }
        foreach ($entry in $entries) {
            $filePath = Join-Path $folderPath $entry.FullName
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                throw "Extracted file missing: $filePath"
            }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $expected = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '')
            } finally {
                $sha.Dispose()
                $stream.Dispose()
            }
            if ((Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash -ine $expected) {
                throw "Extracted file differs: $filePath"
            }
        }
    } finally {
        $archive.Dispose()
    }
}
'All extracted dependency files match their verified archives.'
```

If verification fails, preserve the folder for investigation and restore a clean copy from the approved archive. Do not merge a second extraction into an unverified folder.

Check the two executable signatures without launching them:

```powershell
$executables = @(
    '.research\psadt\pristine\Invoke-AppDeployToolkit.exe'
    '.research\intune\IntuneWinAppUtil-1.8.7.exe'
)
foreach ($relativePath in $executables) {
    $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $repo $relativePath)
    if ($signature.Status -ne 'Valid') {
        throw "Resolve the signature validation failure: $relativePath"
    }
    [pscustomobject]@{
        File = $relativePath
        Status = $signature.Status
        Signer = $signature.SignerCertificate.Subject
    }
}
```

Confirm the PSADT launcher's signer includes `Patch My PC, LLC` and the Content Prep Tool's signer is `Microsoft Corporation`. Signature validation depends on the workstation's certificate trust and revocation access. The customizable root PSADT script is intentionally unsigned; see the [release inspection](PSADT-4.1.8-standard.md#baseline-actually-inspected).

The required layout is now:

```text
.research/
  psadt/
    pristine/Invoke-AppDeployToolkit.ps1
    pristine/Invoke-AppDeployToolkit.exe
    pristine/PSAppDeployToolkit/
  evergreen/
    module/Evergreen.psd1
    definitions/Apps/
    definitions/Manifests/
    definitions/sha256_hashes.csv
  intune/
    IntuneWin32App.1.5.0/IntuneWin32App.psd1
    IntuneWinAppUtil-1.8.7.exe
```

Retain every other extracted file as well. No downloaded PowerShell module has been imported by these steps.

## 6. Inspect the application sources

Each application has one authored definition and editable scripts. Read these before preparing a release:

```powershell
foreach ($app in @('firefox', 'notepadplusplus')) {
    Get-ChildItem -LiteralPath (Join-Path $repo "examples\apps\$app") -File
}
```

Expect `app.json`, `Install.ps1`, `Uninstall.ps1`, `Repair.ps1` and `Detect.template.ps1`. Do not create editable `metadata.json` or `actions.json`; the build generates them internally. Follow [Prepare a release](Prepare-release.md) to create a real release from reviewed installer bytes. The next step's contract tests produce uniquely named offline PSADT copies with explicitly fake payloads; never execute or publish those fixtures.

## 7. Run the baseline checks

Run each test in a separate child process so its test-only sentinel functions cannot affect later commands. The commands below assume the reviewed-script execution approach from step 2.

```powershell
foreach ($test in @(
    'Test-ReferenceSyntax.ps1'
    'Test-ExamplePreviews.ps1'
    'Test-TemplatePopulation.ps1'
    'Test-NativeExampleContract.ps1'
    'Test-ApplicationCore.ps1'
    'Test-ApplicationResolver.ps1'
    'Test-DetectionBinding.ps1'
    'Test-ApplicationBuild.ps1'
    'Test-ManifestPackaging.ps1'
    'Test-ApplicationPublication.ps1'
)) {
    powershell.exe -NoProfile -NonInteractive `
        -File (Join-Path $repo "tests\$test")
    if ($LASTEXITCODE -ne 0) {
        throw "Resolve the failed baseline check before continuing: $test"
    }
}
```

Expect successful results from each test. Tests create uniquely named working directories under `.research/psadt` and `.validation`. They use fake installer bytes and isolated package/Graph mocks; none executes an installer, runs the real packaging tool, authenticates, or accesses Intune. The resolver/build perform full JSON Schema checks as well as semantic checks. The application contract test covers the two supplied applications.

For a separate PowerShell 7 pass, repeat with `pwsh.exe`. Also run `tests/Test-ApplicationDefinitionSchema.ps1` in PowerShell 7 and the general `tests/Test-TemplateHooks.ps1` checks in both runtimes. Inspect skipped link-creation checks explicitly. Historical scope is in [validation results](../evidence/validation-results.md); current migration results are linked from the [implementation plan](Configuration-consolidation-plan.md).

## Common setup problems

| Symptom | Action |
|---|---|
| Missing `.research` file | Restore the exact pinned artifact and extract it into the required layout |
| Dependency hash or extracted-file mismatch | Stop using that copy; investigate or restore approved bytes |
| `schemaVersion 3 app.json` is required | Use the consolidated definition; see [migration](Configuration-migration.md) for retired v2 inputs |
| `Destination already exists` | Keep the existing result; use a new destination for a new build |
| Script blocked by execution policy or application control | Use the organization's approved signing/execution process |
| Evergreen later warns about a missing `.evergreen_version` marker | The manually extracted pinned archive lacks this marker; do not run `Update-Evergreen` merely to silence it |
| A new dependency version seems necessary | Review and adopt a new pin explicitly; do not replace the old baseline in place |

The setup copy of IntuneWin32App is extracted for offline inspection and later packaging. Publication and assignment import the module by name and need a separate module-resolution step, documented in [Publish and roll out](Publish-and-rollout.md#2-prepare-the-releases-publishing-record).

**Next:** return to the [start-to-finish guide](Getting-started.md) to select an application, validate its payload, and prepare a release.

