# Application definition reference

An application has one authored `app.json` and separate editable PowerShell scripts. Install and uninstall arguments belong in those scripts. Generated metadata and action maps are build records; do not maintain another editable copy of the same settings.

The version 3 contract is defined by [the schema](../schemas/application-definition.v3.schema.json). See the [Firefox definition](../examples/apps/firefox/app.json), [Notepad++ definition](../examples/apps/notepadplusplus/app.json), and [implementation plan](Configuration-consolidation-plan.md). This reference describes the contract and its operation boundaries. Schema acceptance alone does not establish that a release, payload, endpoint or publication is accepted.

## Files and ownership

```text
examples/apps/firefox/
  app.json                  Authored application definition
  Install.ps1               Editable application installation statements
  Uninstall.ps1             Editable application removal statements
  Repair.ps1                Editable repair or unsupported-repair statements
  Detect.template.ps1        Editable standalone detection with a version slot
```

Additional Pre/Post snippets and support files may live below the same application directory. The build copies and hashes reviewed inputs. Generated `metadata.generated.json`, `actions.generated.json`, `Detect.ps1` and deployment files belong to a separate release directory. Retired v2 inputs are retained under `tests/fixtures/legacy-v2`; see [migration](Configuration-migration.md).

## Field consumption

The tables identify each field's owner and consumer. A **policy gate** requires evidence or a separate operational decision; it is not an executable action. A declared requirement never runs installation logic or creates an Intune resource by itself.

### Identity and ownership

| Field | Owner and consumer |
|---|---|
| `schemaVersion` | Contract selector; version 3 is required by the new definition workflow. |
| `id` | Engineer; stable application/variant identity for release matching and provenance. Do not identify releases by display name alone. |
| `publisher` | Engineer; generates PSADT `AppVendor` and publication publisher. |
| `productName` | Engineer; generates PSADT `AppName`. Firefox uses `Firefox`. |
| `displayName` | Engineer; publication display name. Firefox uses `Mozilla Firefox (x64 en-US)`. |
| `description` | Engineer; descriptive review/publication metadata. |
| `ownership.team`, `ownership.contact` | Engineer; responsibility and operational documentation. A null contact remains unresolved. |
| `ownership.recipeRevision` | Engineer; definition revision and provenance. This is not the vendor version or package revision. |

### Discovery and release selection

| Field | Owner and consumer |
|---|---|
| `source.provider` | Fixed to `Evergreen`; other providers require an implementation change. |
| `source.application` | Engineer; Evergreen application identifier. |
| `source.moduleVersion`, `source.definitionsRelease` | Reviewed dependency pins; discovery verifies both independently. |
| `source.selectionMap` | Maps provider output properties to canonical variant values: `Architecture` → `architecture`, `Type` → `installerType`, optional `Channel` → `channel`, optional `Language` → `language`. It contains field names, not duplicated values. |
| `source.selectionConstants` | Provider-specific filters with no equivalent canonical value. Supports `InstallerType` and `UriSuffix`; Notepad++ retains `Default` and `.Installer.x64.exe` to distinguish its installer. |
| `source.parameterMap` | Optional `Language` → `language` maps the canonical value into Evergreen's language parameter. Use an empty object when the application has no such parameter. |
| `variant.edition` | Engineer; variant identity and review evidence. It does not introduce an unsupported Evergreen filter. |
| `variant.channel` | Engineer; variant identity and mapped discovery filter where configured. Notepad++ records the upstream latest non-prerelease selection; no nonexistent `Channel` output filter is invented. |
| `variant.language` | Engineer; canonical PSADT language and mapped discovery value where supported. `Multi` denotes the supplied Notepad++ package. |
| `variant.architecture` | Fixed to `x64`; derives PSADT architecture, detection profile and Intune architecture requirement. |
| `variant.installerType` | `msi` or `exe`; discovery selector and payload validation expectation. It does not generate installation commands. |
| `variant.versionPolicy` | `latest` selects the current matching result; `pinned` requires the explicitly selected version. Retained releases remain separate records. |
| `variant.targetVersion` | Null for `latest`; a numeric version string for `pinned`. The new workflow does not overwrite this field after discovery. |

Discovery must return exactly one matching installer. The resolved release locks its version and installer identity. Metadata, detection and publication consume that release; a later discovery must not silently alter an accepted artifact.

### Installer validation policy

| Field | Owner and consumer |
|---|---|
| `validation.allowedDownloadHosts` | Engineer; resolution checks recorded original/final hosts. The download reviewer must separately inspect redirects. A host list does not itself download or validate bytes. |
| `validation.requireVendorSha256` | Engineer; requires retained vendor checksum evidence and comparison with downloaded bytes. |
| `validation.requireAuthenticode` | Engineer; requires signature evidence and approved signer evaluation. |
| `validation.approvedSignerSubjects` | Engineer-approved signer policy. The examples intentionally contain no approval; do not infer one from the observed signer. |
| `validation.expectedProductName` | Engineer; installer identity expectation. It may differ from the short PSADT product name. |
| `validation.msiPropertiesToRecord` | Engineer; required MSI metadata inventory. Empty for the EXE example. MSI metadata does not imply MSI uninstall or repair support. |

Architecture expectations come from `variant.architecture`. Actual signature/product/architecture results and reviewer decisions belong to release evidence. There is no authored `identityReviewStatus` that can turn unverified bytes into an accepted installer.

### PSADT metadata and endpoint profile

| Field | Owner and consumer |
|---|---|
| `toolkit.version`, `toolkit.profile` | Fixed to `4.1.8` and `official-4.1.8-native-v2`. The profile retains the existing samples' completion-prompt omission; it does not prove strict preservation of that stock prompt. |
| `toolkit.packageRevision` | Engineer; generates `AppRevision`. Increment deliberately for a revised package of a vendor release. |
| `toolkit.scriptVersion`, `toolkit.scriptDate`, `toolkit.scriptAuthor` | Engineer; generates the corresponding PSADT script metadata. The build does not insert the current date automatically. |
| `toolkit.requireAdmin` | Fixed to true; generates `RequireAdmin` for the supported machine-wide profile. |
| `toolkit.successExitCodes`, `toolkit.rebootExitCodes` | Engineer; generates PSADT application success/reboot arrays. These are separate from Intune's result classifications. |
| `deployment.context` | Fixed to `system`; effective Intune installation context. |
| `deployment.mode` | Fixed to `Auto`; derives launcher command mode. Do not maintain launcher command strings separately. |
| `deployment.processes` | Engineer; the sole process list, mapped to native `AppProcessesToClose`. Each entry requires `name` and may include `description`; an empty array closes no listed applications. |
| `deployment.deferral.policy` | Fixed to `template-default`; no custom deferral deadline or alternate close-process implementation is supported. |
| `deployment.repair.supported`, `deployment.repair.reason` | Capability declaration and review gate. The current contract supports explicit unsupported repair only; the editable Repair snippet implements the response. |
| `deployment.prerequisites` | Human review gates; no script is generated or executed from these strings. Notepad++ retains its Plugins Admin and legacy-updater migration decision. |
| `deployment.externalPolicyPrerequisites` | Required external settings (`provider`, `setting`, `requiredValue`); separate policy/tenant evidence proves them. The definition does not create or verify the policy. |

The supported profile remains Windows 11 x64, SYSTEM, Auto, and native process handling. The schema rejects other profiles instead of allowing fields that appear to work but are ignored. Broader platform, repair, interaction or requirement support needs a reviewed implementation change.

### Actions, payloads and standalone detection

| Field | Owner and consumer |
|---|---|
| `actions.Install`, `actions.Uninstall`, `actions.Repair` | Each requires `Main`; optional `Pre` and `Post` point to editable snippets. The build produces the contained action map consumed by the template adapter. |
| `payloads.installer.destination` | Engineer; one staged filename under PSADT `Files`, such as `Firefox.msi`. The application script must use this reviewed alias. |
| `payloads.support[].source` | Engineer; reviewed source file under the application directory. |
| `payloads.support[].destination` | Engineer; contained relative destination under PSADT `SupportFiles`. |
| `detection.source` | Engineer; editable standalone detection source path. |
| `detection.binding` | Fixed to `MinimumVersion`; identifies the single supported top-level version assignment. |
| `detection.versionFormat` | Fixed to `numeric`; the selected release must satisfy the examples' reviewed numeric comparison contract. |
| `detection.runAs32Bit` | Fixed to false; generated detection runs in the supported 64-bit profile. |
| `detection.enforceSignatureCheck` | Publication detection-signature setting; declaring true does not sign a script. Bind the version before signing and retain the final artifact hash. |

All referenced source paths are relative to the application directory and must remain inside it. The schema checks basic relative-path syntax; the resolver/build must also reject redirected paths, missing/non-file inputs, reserved names and destination collisions. Support files and installers must not overwrite upstream template files.

Actions are reviewed PowerShell statements, not generated command strings. Use PSADT functions appropriate to their task location. Native Pre runs after welcome/progress; Post is sequential work and is not guaranteed cleanup after failure. The adapter's optional native validator currently permits four commands; consolidation does not broaden that capability. See the [PSADT standard](PSADT-4.1.8-standard.md).

Detection remains independent of PSADT. The build changes only the approved version literal in a copied detection source, verifies the remaining text is unchanged, and produces standalone `Detect.ps1`. Unknown version formats or changed binding structures must fail; they do not authorize arbitrary expression evaluation.

### Publication settings and rollout policy

| Field | Owner and consumer |
|---|---|
| `intune.requirements.minimumSupportedOperatingSystem` | Fixed to `W11_22H2`; effective publication requirement. Architecture derives from the variant. |
| `intune.requirements.applicability` | Fixed to `fresh-or-upgrade`; update-only applicability requires additional implementation. |
| `intune.returnCodes` | Engineer; effective Intune result mappings. Semantic validation must reject duplicate code numbers and incompatible PSADT policy. |
| `intune.maximumInstallationTimeInMinutes` | Fixed to 120; preserves the supported native-v2 publication profile. |
| `targets.pilotGroupId`, `targets.productionGroupId` | Rollout configuration; null means unresolved. These fields do not assign or promote applications. |
| `update.strategy` | Fixed to `new-app-per-release`; publication creates an unassigned application only through an explicit authorized operation. |
| `update.selfUpdater` | Fixed to `centrally-controlled`; operational policy backed by application configuration/external-policy evidence. |
| `update.retainedSuccessfulReleases` | Retention policy; this declaration does not delete artifacts or tenant applications. |
| `update.productionApprovalRequired` | Fixed to true; promotion policy. Approval evidence is separate. |
| `update.downgradeHandling` | Fixed to `vendor-default`; retained packages do not guarantee a supported downgrade. |

Tenant/cloud selection, credentials, application IDs, assignment outcomes and acceptance decisions belong to explicit operation inputs and records. Build credentials remain separate from publishing credentials. The package identity excludes rollout-only changes; exact definition hashes remain available for provenance.

## Validation and migration boundaries

The [discovered-release schema](../schemas/discovered-release.v1.schema.json) describes the immutable selection result: application identity, definition provenance, discovery fingerprint, raw version, variant, pinned discovery dependencies and vendor checksum. Provider metadata is restricted to known scalar values; the unsigned source URL is recorded separately. Discovery is not installer acceptance.

The [installer-evidence schema](../schemas/installer-evidence.v1.schema.json) holds the downloaded SHA-256, unsigned final URL, reviewed product/architecture/version/language identity, MSI properties where applicable, and reviewer information. The [pending example](../examples/installer-evidence.example.json) deliberately uses a replacement application ID, version `0.0.0`, and null evidence/approval fields. Replace these only with actual evidence. Null means incomplete; runtime acceptance must reject it. Schema validity of this empty record is not approval.

An explicit fixture record remains unsuitable for publication even when its fields are complete. Non-fixture acceptance requires matching evidence and actual installer-byte/signature checks; an approval string copied into JSON cannot replace those checks. Query strings, fragments and user information are prohibited in persisted source/final URLs. Keep sensitive or signed URLs out of records and logs.

Run the schema checks in PowerShell 7 with a draft 2020-12-compatible `Test-Json`:

```powershell
pwsh.exe -NoProfile -NonInteractive -File .\tests\Test-ApplicationDefinitionSchema.ps1
```

The schema rejects unknown fields, old command declarations, metadata overrides, missing actions and unsupported profiles. Semantic checks still have to verify dates/version bounds, unique code numbers, source containment, action/detection bindings, release identity, evidence, hashes and consumer compatibility. Schema validity is not a runtime test.

The new workflow rejects schema version 2 with a migration message and does not guess precedence between app.json and legacy recipe/metadata/actions files. The low-level template adapter retains its explicit generated-input contract. Historical validation records remain historical evidence.

Build input identity includes commands, detection, payloads, support data, effective build settings and generator/tool pins. Publication uses frozen generated settings and accepted artifact hashes. Changes to an authored script after finalization require a new reviewed build; they must not silently modify a frozen publication request.

Use `Read-AppJson` and `Write-AppJsonAtomic` from `scripts/Application.Core.ps1` when retaining records. Canonical hashes preserve arrays, scalar types, property-order independence and UTF-8 text across PS5.1/PS7; they are integrity checks, not digital signatures or authenticated approvals. Output `.intunewin` hashes are recorded after packaging and never feed back into the build ID. Equal build identities do not promise byte-identical encrypted package recreation.

Resolution/build/manifest packaging validate schemas locally. On PS5.1 that includes a read-only `pwsh.exe` validator process. Previews do not import deployment modules, invoke the Content Prep Tool or installers, authenticate, write output, or contact Intune. Explicit signed-detection preparation also verifies Authenticode, which can use the host's certificate trust services.
