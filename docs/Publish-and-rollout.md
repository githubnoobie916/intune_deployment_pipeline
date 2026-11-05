# Publish and roll out an application

[Walkthrough](Getting-started.md) · [Testing](Testing.md) · [Operational details](Intune-operations.md)

Start with a finalized `package-manifest.json` and the matching endpoint/business test evidence. Publication, assignment, installation and business acceptance are separate outcomes.

If you completed the walkthrough through [Freeze and preview the publication request](Getting-started.md#7-freeze-and-preview-the-publication-request), keep its existing acceptance and request records. Confirm tenant access in Step 1, then continue at [Step 4](#4-save-separate-operator-and-target-inputs). Steps 2–3 below prepare those records when they do not yet exist; do not overwrite or recreate an accepted request.

> Tenant execution remains untested in this project. The scripts provide local previews and explicit mutation steps; they do not provide resumable uploads, distributed locking, an authenticated approval service or automatic recovery.

## 1. Confirm tenant access

An Intune administrator must confirm the commercial Microsoft cloud, tenant/client IDs, required consent, Intune RBAC scope and approved pilot group before execution. IntuneWin32App 1.5.0 hardcodes global endpoints.

Use a dedicated public-client app registration with the reviewed localhost redirect. Interactive delegated authentication requests `DeviceManagementApps.ReadWrite.All` and `offline_access`. Do not supply a client secret or use the module's broader default scope list. [Registration and permission details](Intune-operations.md#authentication-and-permissions).

## 2. Load the frozen package

In the build session, use the paths from the walkthrough:

```powershell
Set-Location -LiteralPath $repo
. .\scripts\Application.Core.ps1
$packageManifestPath = Join-Path $packageFolder 'package-manifest.json'
$requestPath = Join-Path $releaseRoot 'publication-request.json'
$acceptancePath = Join-Path $releaseRoot 'Evidence\release-acceptance.json'

$requestOptions = @{ PackageManifestPath = $packageManifestPath }
$candidate = .\scripts\Prepare-ApplicationPublication.ps1 @requestOptions
$candidate | Select-Object applicationId, buildId, ready, missingEvidence
$candidate.requiredPrerequisites | Format-List
```

This reads package/detection hashes and frozen settings; it does not reread an authored app.json, write files or contact Intune. `ready = false` is expected before acceptance. A fixture remains unpublishable even after adding evidence.

If detection signing is required, create a **separate signed copy** of the already bound detector and test that exact file. Add its path before preparing the candidate:

```powershell
$requestOptions.SignedDetectionPath = Read-Host 'Absolute path of the separately signed detection script'
$candidate = .\scripts\Prepare-ApplicationPublication.ps1 @requestOptions
```

This explicit option performs Authenticode verification. Only an appended recognized signature block and trailing newlines may differ from the retained unsigned body. Preparation rejects body changes or changes during verification. It does not sign anything. [Signing and test boundaries](Testing.md#1-prepare-the-lab-and-evidence).

## 3. Record actual acceptance

Create a pending record using [the acceptance example](../examples/release-acceptance.example.json), with artifact identity derived from the candidate:

```powershell
$acceptance = Read-AppJson "$repo\examples\release-acceptance.example.json"
$acceptance.applicationId = $candidate.applicationId
$acceptance.buildId = $candidate.buildId
$acceptance.packageSha256 = $candidate.packageSha256
$acceptance.detectionSha256 = $candidate.detection.sha256
Write-AppJsonAtomic -Path $acceptancePath -Value $acceptance
```

Open that record and complete it **after reviewing real results**:

| Field | Required content |
|---|---|
| `endpoint` | `passed = true`, named technical reviewer, UTC approval date, and the endpoint report's `evidence.path` / `evidence.sha256` |
| `business` | `passed = true`, named application owner, UTC approval date, and the business report's path/hash |
| `prerequisites` | One confirmation for every `candidate.requiredPrerequisites` entry: `requirementHash`, reviewer, UTC date and evidence path/hash |

Use each requirement's exact `hash` as `requirementHash`. Firefox requires evidence of its external update policy; Notepad++ requires its updater/Plugins Admin decision. Use absolute evidence paths or paths contained below the acceptance record's directory. Compute report hashes with `Get-FileHash -Algorithm SHA256`. The [schema](../schemas/release-acceptance.v1.schema.json) gives the exact object shape.

Leave `passed` false while checks remain incomplete. Supplied incomplete, mismatched or missing-prerequisite acceptance is rejected. These locally trusted records and hashes detect mismatches; they do not authenticate the reviewer or prove the reports' conclusions.

Prepare and save the completed request:

```powershell
$requestOptions.AcceptancePath = $acceptancePath
$request = .\scripts\Prepare-ApplicationPublication.ps1 @requestOptions
if (-not $request.ready -or $request.fixture) {
    throw ($request.missingEvidence -join [Environment]::NewLine)
}
Write-AppJsonAtomic -Path $requestPath -Value $request
```

Keep the request and its referenced evidence immutable. Its `releaseId` is the content-based `buildId`, not the random working-directory name. Never invent a new ID for a publication retry.

## 4. Save separate operator and target inputs

Tenant/client IDs, current targeting and operation results belong in `State`. They are not package metadata. The app definition's targets are planning data; these approved operational inputs control the manual assignment step.

Make the reviewed local module discoverable without importing it:

```powershell
$stateRoot = Join-Path $releaseRoot 'State'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
$moduleRoot = Join-Path $releaseRoot 'Modules'
$moduleParent = Join-Path $moduleRoot 'IntuneWin32App'
$moduleVersionPath = Join-Path $moduleParent '1.5.0'
if (Test-Path -LiteralPath $moduleVersionPath) {
    throw 'Verify and reuse the existing reviewed module copy; do not overwrite it.'
}
New-Item -ItemType Directory -Path $moduleParent -Force | Out-Null
Copy-Item -LiteralPath "$repo\.research\intune\IntuneWin32App.1.5.0" `
    -Destination $moduleVersionPath -Recurse

$operatorInputs = [ordered]@{
    Repo = $repo
    ModuleRoot = $moduleRoot
    RequestPath = $requestPath
    TenantId = Read-Host 'Confirmed commercial-cloud tenant ID'
    ClientId = Read-Host 'Approved public-client application ID'
    PilotGroupId = [string][guid](Read-Host 'Approved pilot device group object ID')
}
Write-AppJsonAtomic -Path (Join-Path $stateRoot 'operator-inputs.json') -Value $operatorInputs
```

Keep tokens, credentials and private keys out of these records. Review group membership and approval policy separately. Only one operator should publish this application at a time; publication has no durable operation lock.

## 5. Preview in a fresh publishing shell

Open a new 64-bit Windows PowerShell 5.1 process and use your approved execution policy. Do not import IntuneWin32App or authenticate first.

Run this session-loading block before publication or pilot assignment:

```powershell
$releaseRoot = Read-Host 'Absolute path of the reviewed release workspace'
$operatorPath = Join-Path $releaseRoot 'State\operator-inputs.json'
$operatorInputs = Get-Content -LiteralPath $operatorPath -Raw -Encoding UTF8 | ConvertFrom-Json
$repo = $operatorInputs.Repo
Set-Location -LiteralPath $repo
. .\scripts\Application.Core.ps1
$requestPath = $operatorInputs.RequestPath
$request = Read-AppJson $requestPath
Assert-AppRecord $request 'PublicationRequest'

$env:PSModulePath = '{0};{1}' -f $operatorInputs.ModuleRoot, (Join-Path $PSHOME 'Modules')
$available = @(Get-Module -ListAvailable -Name IntuneWin32App |
    Where-Object { $_.Version -eq [version]'1.5.0' })
$expectedModuleBase = Join-Path $operatorInputs.ModuleRoot 'IntuneWin32App\1.5.0'
if ($available.Count -ne 1 -or $available[0].ModuleBase -ine $expectedModuleBase) {
    throw 'Expected exactly the reviewed IntuneWin32App 1.5.0 copy.'
}
if (Get-Module -Name IntuneWin32App) { throw 'Use a fresh PowerShell process.' }
$publishOptions = @{
    RequestPath = $requestPath
    TenantId = $operatorInputs.TenantId
    ClientId = $operatorInputs.ClientId
}
.\examples\Publish-Unassigned.example.ps1 @publishOptions | Format-List
```

Confirm the build marker, version, commands, detection, SYSTEM/x64/Auto profile, 120-minute limit, return codes and empty assignments. Request preview rechecks local hashes; it performs no module import, signature lookup, authentication, network call or file write. It does not validate tenant access.

Request mode cannot be mixed with legacy display-name, command-policy or artifact-hash parameters. Changes to authored app.json or action scripts do not change this frozen request.

## 6. Publish one unassigned app

**Tenant-changing step.** Record the operator, intended operation, request/build identity and approval reference in your operation journal first.

```powershell
$publicationPath = Join-Path $releaseRoot 'State\publication-result.json'
if (Test-Path -LiteralPath $publicationPath) {
    throw 'A result already exists. Reconcile the recorded app instead of creating another.'
}
$publication = .\examples\Publish-Unassigned.example.ps1 @publishOptions `
    -ConfirmedCommercialCloud -Execute
Write-AppJsonAtomic -Path $publicationPath -Value $publication
$publication | Format-List
```

Execution regenerates the request from its frozen package/evidence inputs and requires an exact match before authentication and again immediately before app creation. It rechecks raw package/detection hashes after authentication, checks the existing release marker, then verifies committed content, `published` state and zero assignments. The expected result is `PublishedUnassigned` with an app ID and committed content version.

Independently inspect that exact Intune app ID, commands, detection, requirements and assignments. An uncertain result or failed local result write requires reconciliation; absence of a local record does not prove that creation failed. The package manifest's `packagingTools` records packaging provenance; it does not prove installation or tenant acceptance.

## 7. Assign and observe the pilot

Start another fresh shell and reload [the session inputs](#5-preview-in-a-fresh-publishing-shell). Confirm the pilot group's current membership, observation period, failure thresholds and stop criteria.

```powershell
$publication = Read-AppJson (Join-Path $releaseRoot 'State\publication-result.json')
if ($publication.State -ne 'PublishedUnassigned' -or
    $publication.ApplicationId -cne $request.applicationId -or
    $publication.ReleaseId -cne $request.releaseId) {
    throw 'Publication does not match the reviewed request.'
}
$pilotOptions = @{
    IntuneAppId = [guid]$publication.IntuneAppId
    PilotGroupId = [guid]$operatorInputs.PilotGroupId
    ApplicationId = $request.applicationId
    ReleaseId = $request.releaseId
    TenantId = $operatorInputs.TenantId
    ClientId = $operatorInputs.ClientId
}
.\examples\Assign-Pilot.example.ps1 @pilotOptions | Format-List
```

Confirm `Intent = required`, `Availability = Immediate` and the exact group/app IDs. The supported requirement is fresh-install-or-upgrade: eligible devices where the app is absent can receive it.

**Tenant-changing step: starts an immediate required pilot deployment.**

```powershell
$pilotPath = Join-Path $releaseRoot 'State\pilot-result.json'
if (Test-Path -LiteralPath $pilotPath) { throw 'Pilot result exists; reconcile before retrying.' }
$pilot = .\examples\Assign-Pilot.example.ps1 @pilotOptions `
    -ConfirmedCommercialCloud -Execute
Write-AppJsonAtomic -Path $pilotPath -Value $pilot
```

The assignment example verifies the release marker/content, rejects pre-existing assignments and confirms the requested pilot target. `PilotAssigned` confirms targeting, not installation. Collect device outcomes, detection, application functionality, update-control state and relevant logs.

## 8. Promote the same tested content

After documented pilot criteria pass and the application owner approves:

1. Open the recorded app ID in the Intune admin center.
2. Review old-release overlap, exclusions, dependencies, supersedence, Company Portal visibility and enrollment/ESP references.
3. Add the approved production targeting to the **same app ID and content version**, preserving intended pilot targeting.
4. Save the change, record it in the operation journal and monitor production against the stop criteria.

Saving production assignments changes the tenant and can deploy applications. Production promotion is manual. Do not rerun the pilot script against an already assigned app; it deliberately rejects that state. Do not rebuild or replace content between pilot and production.

[Microsoft app monitoring](https://learn.microsoft.com/en-us/intune/app-management/monitor-assignments) · [Assignment procedure](https://learn.microsoft.com/en-us/intune/app-management/deployment/assign-groups) · [Release strategy](Intune-operations.md#release-strategy-and-controlled-updates)

## 9. Reconcile failures and subsequent releases

| Situation | Required next step |
|---|---|
| Timeout, interruption, authentication failure or missing result | Inspect the tenant by stored app ID and exact release marker before retrying any write. |
| Existing app with incomplete content | Preserve its ID; an administrator must decide repair or controlled cleanup. Upload resumption is not implemented. |
| Multiple matching apps | Stop and resolve app identities, content and assignments explicitly. |
| Assignment exists after an uncertain result | Confirm group, intent and every assignment; do not blindly repeat the command. |
| Pilot/production failure | Stop promotion, contain targeting and use a tested recovery procedure. An old package does not guarantee downgrade support. |
| Changed installer, action, detector or build policy | Create and test a new build. Retain the old artifact and its evidence. |

Reconcile this exact marker from the saved request:

```text
ManagedBy=ManualIntuneResearch;ApplicationId=<applicationId>;ReleaseId=<buildId>
```

A marker alone does not establish completed publication. Check content, commands, detection, requirements and assignments. Keep operational state outside synchronized storage. [Recovery details](Intune-operations.md#state-retries-and-operational-acceptance).
