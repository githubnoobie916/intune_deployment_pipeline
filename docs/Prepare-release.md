# Prepare a release

[Walkthrough](Getting-started.md) · [Add an application](Add-application.md) · [Configuration reference](Configuration-reference.md)

This procedure produces a retained `ResolvedBuild` from an authored v3 application, one discovered release, a local installer and reviewed evidence. It does not build, install, package or publish the application.

Use the same supported 64-bit PowerShell session as the walkthrough, with `$repo` set to the repository root and `$app` set to an application folder such as `firefox`. Windows PowerShell 5.1 requires installed `pwsh.exe` 7.5+ for the schema helper; PowerShell 7.5+ can run the workflow directly.

## 1. Copy the application into a fresh workspace

Keep working artifacts outside synchronized folders. The random directory name below identifies this preparation attempt; the resolver later computes the build/release identity from the accepted inputs.

```powershell
$runId = [guid]::NewGuid().ToString('N')
$releaseRoot = Join-Path 'C:\IntuneLifecycle\releases' (Join-Path $app $runId)
$applicationFolder = Join-Path $releaseRoot 'Application'
$evidenceFolder = Join-Path $releaseRoot 'Evidence'
$payloadFolder = Join-Path $releaseRoot 'Payload'
$buildFolder = Join-Path $releaseRoot 'Build'
$packageFolder = Join-Path $releaseRoot 'Package'
if (Test-Path -LiteralPath $releaseRoot) { throw 'Choose a new release workspace.' }
New-Item -ItemType Directory -Path $releaseRoot, $evidenceFolder, $payloadFolder | Out-Null
Copy-Item -LiteralPath (Join-Path $repo "examples\apps\$app") `
    -Destination $applicationFolder -Recurse

$definitionPath = Join-Path $applicationFolder 'app.json'
$releasePath = Join-Path $evidenceFolder 'discovered-release.json'
$installerEvidencePath = Join-Path $evidenceFolder 'installer-evidence.json'
$resolvedPath = Join-Path $releaseRoot 'resolved-build.json'
. (Join-Path $repo 'scripts\Application.Core.ps1')
```

Review the copied `app.json`, actions, support data and `Detect.template.ps1`. Relative paths resolve within the application folder. Complete the owner and independently approved signer policy; sample signer lists intentionally contain no approval. Do not create `$buildFolder` or `$packageFolder` yet.

Installer arguments and uninstaller paths remain in the copied `.ps1` actions. There is no separate authored recipe, metadata file or action-map file in this workflow.

## 2. Discover one installer

The reader validates the v3 schema and supported semantics. **Discovery contacts vendor services** through the pinned Evergreen installation; it does not download an installer.

```powershell
$release = & (Join-Path $repo 'examples\Discover-Application.example.ps1') `
    -DefinitionPath $definitionPath `
    -EvergreenManifestPath (Join-Path $repo '.research\evergreen\module\Evergreen.psd1') `
    -DefinitionsPath (Join-Path $repo '.research\evergreen\definitions') `
    -OutputPath $releasePath

$release | Select-Object applicationId, version, sourceUrl, vendorSha256, variant
```

Review product, architecture, installer type, language and channel. Exactly one matching result is required. Zero or multiple results need corrected selection criteria and a new discovery record. `-RecipePath` is only an alias for `-DefinitionPath`; it accepts v3 definitions, not the retired recipe format.

Discovery validates the selected URL against the declared host policy and requires a vendor SHA-256 when configured. It does not establish downloaded-byte identity, redirect approval, signature trust or product identity.

Keep `versionPolicy: "latest"` when that is the authored selection policy. The retained release record fixes the selected version; do not rewrite the definition to `pinned` after discovery. A deliberately pinned policy must match the returned version. Evergreen does not become a historical-release service when this field changes; use a compatible retained release and its exact installer for an earlier version.

## 3. Acquire and inspect the installer

Use the declared package filename for the local payload:

```powershell
$definition = Read-AppDefinition -Path $definitionPath
$installerName = [string]$definition.payloads.installer.destination
$installerPath = Join-Path $payloadFolder $installerName
$installerPath
```

Use your approved download tool to obtain the exact installer selected by `$release.sourceUrl`, saving it at `$installerPath`. Record and review the original URL, final URL and redirect chain against `validation.allowedDownloadHosts`. Do not retain credentials, tokens or signed URLs in evidence.

Inspect the local file without running it:

```powershell
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw 'Save the selected installer at the displayed path before continuing.'
}
$installerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
$signature = Get-AuthenticodeSignature -LiteralPath $installerPath
$installerHash
$signature | Select-Object Status, StatusMessage,
    @{ Name = 'SignerSubject'; Expression = { $_.SignerCertificate.Subject } }
```

Complete the following review:

| Review | Evidence to retain |
|---|---|
| Download origin | Original/final URLs and the approved redirect chain. |
| Integrity | Actual SHA-256 and the independent vendor checksum when required. |
| Signature | Signature result, certificate details and an independently approved signer policy. Observing a signer is not approval of that signer. |
| Installer identity | Verified product name, exact release version, x64 architecture, language and every MSI property requested by the definition. Use approved inspection tools without executing the installer. |
| Deployment behavior | Supported silent arguments, uninstall identity, repair limitation, upgrade behavior and required external configuration. |

The resolver compares local bytes and current signature policy, but supplied identity and review facts remain human evidence. Do not weaken checks merely to accept an unexpected download. Firefox's MSI wrapper does not imply MSI uninstall or repair support.

## 4. Complete the installer evidence

Start with the pending evidence template:

```powershell
Copy-Item -LiteralPath (Join-Path $repo 'examples\installer-evidence.example.json') `
    -Destination $installerEvidencePath
```

Fill the copy with actual reviewed values. Null placeholders are not approvals.

| Evidence field | Required value |
|---|---|
| `fixture` | `false` for a real release. |
| `applicationId`, `version` | Exact application ID and retained release version. |
| `sha256`, `finalUrl` | Hash of the local installer and the reviewed final download URL. |
| `identity.productName`, `architecture`, `version`, `language` | Independently inspected installer identity matching the definition and release. |
| `identity.msiProperties` | Nonempty values for all `validation.msiPropertiesToRecord` entries; an empty object is appropriate when none are requested. |
| `review.approvedBy`, `review.approvedAtUtc` | The actual reviewer's identity and UTC approval timestamp, for example `2026-11-05T01:30:00Z`; the resolver requires a valid date ending in `Z`. |

Keep supporting review material under `$evidenceFolder`. The [evidence schema](../schemas/installer-evidence.v1.schema.json) and [configuration reference](Configuration-reference.md) define the exact fields. There is no editable `identityReviewStatus` switch that substitutes for evidence.

Before resolution, confirm that action payload filenames, product-specific commands and support files fit this release. Author any corrections in the source copy. Do not manually set `AppVersion` or replace the detection placeholder: the resolver binds both from the accepted release.

## 5. Resolve and retain the build input

Resolution is read-only: it validates local evidence, captures source hashes, binds metadata/detection and returns a hash-bound `ResolvedBuild` record.

```powershell
$resolved = & (Join-Path $repo 'scripts\Resolve-Application.ps1') `
    -DefinitionPath $definitionPath `
    -ReleasePath $releasePath `
    -InstallerPath $installerPath `
    -EvidencePath $installerEvidencePath

Write-AppJsonAtomic -Path $resolvedPath -Value $resolved
$resolved | Select-Object applicationId, buildId, fixture
```

`Write-AppJsonAtomic` saves the complete record explicitly and refuses to overwrite an existing one. Use `Read-AppJson` when reopening retained JSON records; it preserves strings consistently across supported runtimes. Keep referenced inputs at their retained paths. Do not edit the record or its generated values; if a source changes, resolve again and use a new output path/build destination. The build checks for source drift before accepting the record.

`-AllowFixture` exists only for offline tests with explicitly marked fixture evidence. It is not a way to approve an installer, skip review or create a publishable package.

**Continue when:** resolution passes, `fixture` is false, and the saved record matches the reviewed inputs. This establishes local binding and provenance, not endpoint installation or business acceptance.

## 6. Return to the build walkthrough

Keep `$repo`, `$releaseRoot`, `$resolvedPath`, `$buildFolder`, `$packageFolder` and `$evidenceFolder` in the session. Continue at [Preview and build the deployment](Getting-started.md#4-preview-and-build-the-deployment).

The build will generate adapter metadata/action maps, stage the installer and support data, populate a fresh PSADT deployment and emit standalone `Detect.ps1`. Its version, deployment metadata and publication version come from the same accepted release. Later package and acceptance records carry that identity forward.
