# Step-by-step walkthrough

[Documentation home](../README.md) · [Configuration reference](Configuration-reference.md)

Follow one reviewed release from application sources to an unassigned Intune publication request. Start with Firefox or Notepad++. Local static checks and mocked tests do not establish real packaging, endpoint acceptance, signing trust or tenant success; see [validation results](../evidence/configuration-v3-validation.md).

## 1. Set up the workstation

Complete [workstation setup](Setup.md) using the inspected dependency pins. Dependencies and real installers are not downloaded automatically. Keep working artifacts on nonsynchronized storage such as `C:\IntuneLifecycle`.

Use a fresh **64-bit Windows PowerShell 5.1 or PowerShell 7.5+** session. Windows PowerShell also needs installed `pwsh.exe` 7.5+ for the JSON Schema helper. From the repository root:

```powershell
$repo = (Get-Location).Path
$ErrorActionPreference = 'Stop'
$app = 'firefox'
```

Follow your organization's execution policy. Normal `-File` invocation was blocked by `AuthorizationManager` on the inspected host; after that failure, validation used process-only `-ExecutionPolicy Bypass`. This does not change persistent policy. See [setup](Setup.md) for the normal invocation and scoped retry; do not treat a blocked or skipped check as passed.

**Continue when:** the pinned dependencies exist and their recorded integrity checks pass. Historical native-v2 outputs remain reference material; they are not source inputs or prerequisites for a new v3 build.

## 2. Review the authored application

The source is `examples/apps/$app/app.json` plus editable Install, Uninstall, Repair and detection-template scripts. Follow [Add an application](Add-application.md) for a different product and the [configuration reference](Configuration-reference.md) for field ownership.

Review the installer variant, native commands, processes, detection, signer policy, application owner and external prerequisites. Installer arguments belong in the `.ps1` actions. Do not maintain a second recipe, metadata file or action-map file.

The current profile preserves the supplied native-v2 behavior: Windows 11 x64, SYSTEM, `DeployMode Auto`, native process handling and omission of the stock illustrative completion prompt. It does not enable new PSADT functions or alternative deployment profiles.

## 3. Discover, validate and resolve a release

Complete [Prepare a release](Prepare-release.md) in the same session. Discovery queries vendor services; acquisition and installer identity review remain manual. The resolver checks the retained evidence and returns a release-bound record without writing files.

Return with these variables:

| Variable | Contents |
|---|---|
| `$releaseRoot` | New nonsynchronized working directory for this attempt |
| `$resolvedPath` | Saved, hash-bound `ResolvedBuild` record |
| `$buildFolder` | Intended build destination; does not exist yet |
| `$packageFolder` | Intended package destination; does not exist yet |
| `$evidenceFolder` | Installer review and later acceptance evidence |

The build identity is computed from accepted inputs. The workspace's random name is not the publication release identity. `-AllowFixture` is only for offline tests; fixture outputs cannot become publishable releases.

## 4. Preview and build the deployment

Preview the exact retained inputs first:

```powershell
$buildOptions = @{
    ResolvedPath    = $resolvedPath
    TemplatePath    = Join-Path $repo '.research\psadt\pristine'
    DestinationPath = $buildFolder
}
& (Join-Path $repo 'scripts\Build-Application.ps1') @buildOptions
```

After reviewing the preview, create the local build:

```powershell
$build = & (Join-Path $repo 'scripts\Build-Application.ps1') @buildOptions -Execute
$buildManifestPath = Join-Path $buildFolder 'build-manifest.json'
$sourceFolder = $build.sourceFolder
$detectionPath = $build.detection.path
```

This stages the reviewed payloads, populates a fresh official template, checks file inventories and writes standalone release-bound detection. It does not execute deployment scripts or installers. Generated metadata/action maps and `Detect.ps1` are outputs; never edit them in place.

**Continue when:** a complete `build-manifest.json` exists and the static checks pass. Retain a failed build attempt for review and use a fresh destination for the next attempt. [Template contract](PSADT-4.1.8-standard.md).

## 5. Preview and create the package

Use the build manifest, so packaging verifies the source inventory and carries forward the bound profile and detection:

```powershell
$packageOptions = @{
    BuildManifestPath         = $buildManifestPath
    OutputFolder              = $packageFolder
    IntuneWin32AppManifestPath = Join-Path $repo '.research\intune\IntuneWin32App.1.5.0\IntuneWin32App.psd1'
    ContentPrepToolPath        = Join-Path $repo '.research\intune\IntuneWinAppUtil-1.8.7.exe'
}
& (Join-Path $repo 'examples\Package-Application.example.ps1') @packageOptions
```

The preview validates local files and pins without importing the module or running Content Prep. The documented module layout includes the pinned sibling archive, `IntuneWin32App.1.5.0.nupkg`; for a different layout, provide it explicitly with `-IntuneWin32AppPackagePath`. The extracted module must match that archive. After reviewing the preview, execute local packaging:

```powershell
$package = & (Join-Path $repo 'examples\Package-Application.example.ps1') @packageOptions -Execute
$packageManifestPath = Join-Path $packageFolder 'package-manifest.json'
```

`-Execute` runs the pinned Content Prep Tool and writes the `.intunewin` and package manifest. It does not install the application or contact Intune. The output folder must be new and outside `Source`.

**Continue when:** the expected package and `package-manifest.json` exist and hashes match. Package creation does not establish endpoint acceptance.

## 6. Test the exact release and collect approval

Complete [endpoint testing](Testing.md) on explicitly selected isolated Windows 11 x64 machines. Use the complete generated `Source` folder and matching standalone detection. Capture SYSTEM install/upgrade, process handling, detection and uninstall outcomes, plus application-owner acceptance.

Keep finalized build files unchanged. If detection signing is required, create a separate signed copy of the generated detection, test that exact copy and pass its path as `-SignedDetectionPath` below. The preparation script checks its signature and that its unsigned body matches the generated script. Changing deployment source files after building invalidates their manifest; the current workflow does not provide a deployment-source signing stage.

Read the required evidence for this package:

```powershell
$requestOptions = @{ PackageManifestPath = $packageManifestPath }
# If using a reviewed signed detection copy, also set:
# $requestOptions.SignedDetectionPath = $signedDetectionPath
$reviewRequest = & (Join-Path $repo 'scripts\Prepare-ApplicationPublication.ps1') @requestOptions
$reviewRequest | Select-Object ready, missingEvidence, requiredPrerequisites
```

Without acceptance evidence, the request reports `ready: false`. Copy the pending [release acceptance example](../examples/release-acceptance.example.json) to your evidence directory:

```powershell
$acceptancePath = Join-Path $evidenceFolder 'release-acceptance.json'
Copy-Item -LiteralPath (Join-Path $repo 'examples\release-acceptance.example.json') `
    -Destination $acceptancePath
```

Complete it with the exact application/build identity, package hash and final detection hash from `$reviewRequest`. Record passed endpoint and business reviews with named reviewers, dates and retained evidence-file paths/hashes. For each `requiredPrerequisites` item, copy its `hash` into the acceptance entry's `requirementHash` and supply matching approval evidence. These are human-reviewed facts, not values generated from a passing syntax check. [Acceptance contract](Configuration-reference.md).

Firefox's separately managed update policy needs its own evidence, including devices on which installed-product detection skips deployment. Definitions do not create policies, install dependencies or assign applications.

## 7. Freeze and preview the publication request

After the evidence is complete, prepare and explicitly save the request:

```powershell
$requestOptions.AcceptancePath = $acceptancePath
$request = & (Join-Path $repo 'scripts\Prepare-ApplicationPublication.ps1') @requestOptions
if (-not $request.ready) { throw ($request.missingEvidence -join '; ') }

. (Join-Path $repo 'scripts\Application.Core.ps1')
$requestPath = Join-Path $releaseRoot 'publication-request.json'
Write-AppJsonAtomic -Path $requestPath -Value $request

& (Join-Path $repo 'examples\Publish-Unassigned.example.ps1') -RequestPath $requestPath
```

Preparation reads local artifacts/evidence and returns a hash-bound `PublicationRequest`; it does not write files or contact Intune. `Write-AppJsonAtomic` creates the retained record and refuses to overwrite an existing one. Use `Read-AppJson` when reopening retained JSON records so strings remain strings across runtimes. Keep the referenced artifacts and evidence at their retained paths.

The publisher's default preview verifies frozen input hashes and displays the derived settings without module import, authentication or tenant writes. A ready request satisfies the local evidence contract; it is not proof of upload, assignment or successful installation through Intune.

## 8. Publish, assign and observe

Follow [Publish and roll out](Publish-and-rollout.md) for authorized tenant execution in a fresh publisher process. The live interface uses `-RequestPath`, `-Execute`, `-TenantId`, `-ClientId` and `-ConfirmedCommercialCloud`. It creates and uploads an **unassigned** application; execute it only for the explicitly approved tenant and release.

Record the returned app ID and verify published content, metadata, detection and empty assignments. Reconcile any uncertain result before retrying. Pilot assignment is a separate operation and starts an immediate required deployment to the selected device group.

Promote the same tested app ID and content only after the agreed pilot criteria pass. Production targeting, status review and reconciliation remain manual; this repository is not a durable, resumable publishing service.

For the next version, create a new working directory and repeat discovery through acceptance. Retain earlier accepted packages and evidence; recovery does not establish that vendor downgrade behavior is supported.

## Execution boundaries

| Entry point | Default behavior | Explicit next action |
|---|---|---|
| `Discover-Application.example.ps1` | Queries vendor services through pinned Evergreen | `-OutputPath` retains a discovery record; no installer download |
| `Resolve-Application.ps1` | Reads local definition, release, installer and evidence; returns a resolved record | Caller saves the record atomically |
| `Build-Application.ps1` | Local preview and integrity checks | `-Execute` creates a fresh deployment and build manifest |
| `Package-Application.example.ps1` | Local manifest/tool validation; no deployment-module import, installer or Content Prep execution | `-Execute` imports the pinned module and runs Content Prep locally |
| `Prepare-ApplicationPublication.ps1` | Reads local package and optional acceptance/signed detection; returns a request | Caller saves the request atomically |
| `Publish-Unassigned.example.ps1` | Local request preview, no authentication or tenant mutation | `-Execute` authenticates and creates/uploads an unassigned app |
| `Assign-Pilot.example.ps1` | Local preview | `-Execute` creates an immediate required pilot assignment |

[Workstation setup](Setup.md) · [Configuration reference](Configuration-reference.md) · [Troubleshooting](Troubleshooting.md)
