# Project guidance for agents

## Purpose and current state

This repository researches a Windows application lifecycle using Evergreen for discovery, PSAppDeployToolkit (PSADT) for endpoint deployment, and IntuneWin32App for packaging and publication. It implements a local v3 definition/resolution/build workflow, frozen artifact requests, an offline template adapter, and validation tests. Packaging and tenant operations remain explicitly executed examples; this is not a production lifecycle service or a resumable publisher.

The initial profile is Windows 11 x64, machine-wide installation as SYSTEM, PSADT `DeployMode Auto`, and native `AppProcessesToClose`. Current dependency baselines are PSADT 4.1.8 (released v4 template), Evergreen 2610.2859.0 with definitions v26.11.03.146, IntuneWin32App 1.5.0, and Content Prep Tool v1.8.7. These are inspected pins, not claims about the latest available versions.

Follow the user's current scope. An analysis or documentation request does not authorize implementation, deployment, or changes to existing examples. Continue ordinary local work within an authorized implementation task without repeatedly requesting permission. Do not treat this file's roadmap as authorization to implement it.

## Read before changing behavior

- `README.md`: repository overview and current generated examples.
- `docs/Engineering-report.md`: architecture, responsibility boundaries, gaps, and proposed roadmap.
- `docs/PSADT-4.1.8-standard.md` and `docs/Native-PSADT-review.md`: template contract and current sample behavior.
- `docs/Worked-examples.md` and `docs/Intune-operations.md`: application-specific constraints and publication boundaries.
- `evidence/source-ledger.md` and `evidence/validation-results.md`: provenance, historical checks, and untested behavior.
- `evidence/configuration-v3-validation.md` and its JSON record: current consolidation checks, independent review, source snapshot and explicit runtime limits.

Use the inspected release archive and matching tagged source to resolve version-specific behavior. Moving documentation or a matching module version number alone does not establish compatibility. Keep historical findings distinguishable from current verification.

## Repository map

| Location | Responsibility |
|---|---|
| `scripts/Populate-PSADTTemplate.ps1` | Creates and validates a separate application deployment copy; never executes snippets. |
| `examples/apps/<app>/app.json` | One authored definition; adjacent editable action scripts and `Detect.template.ps1` own endpoint logic. |
| `scripts/Resolve-Application.ps1`, `scripts/Build-Application.ps1` | Read-only resolution, followed by preview or explicit fresh local build; generated internal metadata/actions are not authored configuration. |
| `scripts/Prepare-ApplicationPublication.ps1` | Read-only request preparation from package/detection artifacts and separate acceptance evidence. |
| `tests/fixtures/legacy-v2/` | Retired exact configuration/detection inputs retained for migration regression, never an automatic fallback. |
| `examples/*.example.ps1` | Illustrative discovery, packaging, publication, and pilot assignment operations. |
| `schemas/`, `tests/` | Configuration contracts and offline checks. |
| `docs/`, `evidence/` | Design, operational procedures, provenance, and scoped validation results. |
| `.research/`, `generated-examples/`, `.validation/` | Ignored dependencies and generated validation artifacts; may be absent on a fresh checkout. |

## Preserve upstream components

- Never customize the pristine PSADT source template or patch the Evergreen or IntuneWin32App modules. Do not replace their functions at runtime to alter production behavior. Test doubles belong only in isolated tests.
- Use the released PSADT v4 template archive. Do not reconstruct it from the raw frontend script or substitute the v3 compatibility template.
- Populate a fresh deployment copy through the existing adapter. Application metadata and reviewed statements belong only in supported metadata fields and documented Pre/Main/Post task locations. Stage approved installers in `Files` and application support data in `SupportFiles`, with separate inventories and hashes.
- Preserve the default framework: launcher, bundled toolkit, extension module, configuration, assets, strings, initialization, dispatch, welcome/progress behavior, deferrals, error handling, and shutdown. Do not add a shared endpoint framework or move orchestration into PSADT.
- Preserve exact pristine-file verification and validation of permitted generated edits. Do not weaken hashes, inventories, or assertions to accept unexpected changes. Recheck integrity after staging and before packaging when implementing the build operation.
- Keep Evergreen/module/tool versions and definition snapshots pinned throughout a build. Dependency upgrades are separate reviewed changes; they must not mutate previously accepted artifacts.

Known compatibility gap: existing native-v2 examples opt into `-OmitCompletionPrompt`, and their contract test expects that omission. The adapter's default retains the prompt. For strict default-framework preservation, leave this option disabled. Do not describe the existing v2 examples as proof of that stricter profile, or silently rewrite their tests and behavior during unrelated work. Any scoped migration must update the profile, examples, tests, and documentation together.

## Application and Pre/Post contracts

- Actions already support `Install`, `Uninstall`, and `Repair`, each with required `Main` and optional `Pre`/`Post` paths relative to the actions file. Broaden validation of these locations before inventing another hook mechanism.
- Native Pre tasks run after the template's welcome/progress calls. Post is sequential application work, not guaranteed cleanup after failure or session exit. Preserve these semantics.
- The current Firefox and Notepad++ fixtures intentionally use Main only. Keep sample-specific assertions separate from general adapter coverage. New coverage should exercise all nine locations, optional-phase combinations, placement/order, rejection cases, unchanged framework content, and snippet provenance.
- Snippets are trusted executable application code. Parsing and `-ValidateNativeApplicationCommands` are not a sandbox or runtime acceptance. The optional validator currently permits only four native functions and validates snippets independently; it is not a general PSADT capability list.
- Keep standalone Intune detection independent of PSADT and release tracking. Do not replace installed-product detection with pipeline markers. The binder replaces only the reviewed `MinimumVersion` slot; generated deployment metadata, detection and publication use the same retained release.
- Preserve current application boundaries: Firefox policy is managed separately through Intune; its MSI wrapper does not imply MSI uninstall/repair support. Both examples explicitly reject unsupported Repair with 69001, after native welcome behavior. Vendor-default downgrade handling is not a downgrade guarantee.

## Application version tracking and pipeline direction

The local definition, discovery, resolution, build, package and publication-request contracts are implemented. Durable tenant operations, scheduling and promotion remain future work:

- Versioning means supporting deployment of another application version through the discovery, packaging, validation, and publication workflow.
- Track the application version, its deployment package, associated Intune app ID, and pilot/production status so the intended version can be selected and deployed.
- Keep Discover, Build, Validate, Publish, Assign/Pilot, Promote, Status, and Reconcile as explicit operations. Use validated stage outputs as subsequent inputs. Publish unassigned; promote the same tested artifact and content version.
- Use durable operation records, atomic state updates, and one writer per application/tenant. Reconcile uncertain remote results before retrying writes; a returned app ID alone does not prove completed publication. Do not promise arbitrary upload resumption through unchanged module APIs.
- Verify tenant identity, cloud compatibility, content, commands, detection, requirements, return codes, and assignment state. Never infer identity from display names alone. Preserve previous artifacts; recovery is not automatically a supported downgrade.
- Put active state, locks, upload scratch space, and operational artifacts on nonsynchronized storage. This OneDrive repository is not the operational state store. Keep future CI/scheduling as callers of the same operation contracts.

## Execution and PowerShell conventions

- Keep orchestration compatible with 64-bit Windows PowerShell 5.1 unless the task explicitly changes the runtime contract. Install PowerShell 7.5+ as `pwsh.exe` for schema validation and independent PS7 runs. Never skip schema checks when the validator is unavailable. Use `Read-AppJson` to preserve timestamp strings; direct PS7 JSON conversion can change record identity.
- Prefer small explicit operations, structured outputs, literal JSON data, explicit encodings, and `-LiteralPath` for filesystem inputs. Do not evaluate configuration as PowerShell. Preserve UTF-8 data correctly under Windows PowerShell.
- Discovery can access vendor services. Packaging, publication, and assignment examples default to local preview; preserve their no-import/no-authentication/no-mutation boundaries. Do not rely on the inspected module's `-WhatIf` declarations as write protection.
- Never run application snippets or populated deployments on the packaging workstation. Installation acceptance belongs on explicitly selected isolated endpoints. Do not run live tenant operations as routine code validation; execute them only within the user's authorized tenant/target scope.
- Do not persist or log credentials, tokens, private keys, or signed upload/download URLs. Do not infer tenant cloud, group IDs, signer approval, or external-policy verification from example placeholders.

## Validation workflow

Inspect the relevant test and prerequisites first. Run tests in fresh processes because preview tests define sentinel functions. From the repository root, the existing offline checks are:

```powershell
powershell.exe -NoProfile -NonInteractive -File .\tests\Test-ReferenceSyntax.ps1
powershell.exe -NoProfile -NonInteractive -File .\tests\Test-ExamplePreviews.ps1
powershell.exe -NoProfile -NonInteractive -File .\tests\Test-TemplatePopulation.ps1
powershell.exe -NoProfile -NonInteractive -File .\tests\Test-NativeExampleContract.ps1
```

Use `pwsh.exe` instead of `powershell.exe` for separate PowerShell 7 runs. Select checks appropriate to the change; documentation-only work normally needs content/path review rather than deployment tests.

| Check | Prerequisites and effects |
|---|---|
| `Test-ReferenceSyntax.ps1` | Parses authored PowerShell, JSON, and documentation code blocks; does not validate JSON Schema or runtime behavior. |
| `Test-ExamplePreviews.ps1` | Reads pinned IntuneWin32App source under `.research/intune/`; asserts preview isolation without importing the module. |
| `Test-TemplatePopulation.ps1` | Requires verified `.research/psadt/pristine` or an explicit `-TemplatePath`; creates unique test copies/results under `.research/psadt/`; does not execute deployments. |
| `Test-NativeExampleContract.ps1` | Creates both v3 fixture builds, checks preserved commands and the named native-v2 profile, and checks archived migration evidence. Never executes a deployment. |
| `Test-ApplicationCore.ps1`, `Test-ApplicationResolver.ps1`, `Test-DetectionBinding.ps1`, `Test-ApplicationBuild.ps1` | Local identity, evidence, binding, source-preservation and staging checks; fixture bytes are never installers. |
| `Test-ManifestPackaging.ps1`, `Test-ApplicationPublication.ps1` | Local artifact flow with isolated packaging/authentication/Graph mocks; no real tool execution or tenant writes. |
| `Test-ApplicationDiscovery.ps1` | Mocked provider discovery and selection validation. |
| `Test-ApplicationIdentityScope.ps1`, `Test-CrossRuntimeRecords.ps1` | Isolated identity mutations/relocation and shared records verified by both PowerShell engines. |
| `Test-Documentation.ps1` | Local Markdown target existence and source-block parsing; no endpoint execution. |
| `Test-TemplateHooks.ps1` | General nine-location and integrity coverage; report OS-denied real link checks as skipped. |

Run `Test-ApplicationDefinitionSchema.ps1` in PowerShell 7 against `application-definition.v3.schema.json`. The v2 recipe schema is retained only for historical fixtures. Schema validity does not replace semantic checks or establish endpoint behavior.

If dependencies are missing or execution policy blocks a test, report that limitation. Do not silently substitute latest dependencies, change persistent execution policy, or count a skipped check as passed. Historical process-level bypass commands are not the default validation procedure.

For adapter or operations changes, add focused regression coverage for the behavior changed. Keep offline/static, mocked execution, real packaging, endpoint, and live tenant evidence separate. Installer success, upload success, assignment, detection, and business acceptance are different outcomes.

## Change and evidence discipline

- Inspect `git status` before editing. Preserve unrelated work, including untracked source files. Do not reset, clean, or broadly stage the repository as part of a small task.
- Edit source inputs and regenerate outputs through the supported path; do not hand-edit generated deployments. Keep ignored dependencies, packages, logs, and secrets out of source control.
- Keep changes focused. When changing a contract, update its implementation, affected schema/examples/tests, and documentation together. Do not convert recommendations into implemented claims.
- Preserve historical evidence and record new results with runtime, inputs, scope, and limitations. Never reuse a previous passing result as evidence for changed code or fabricate installer, tenant, or endpoint outcomes.
- Report what changed, what was checked, and what remains unverified. Keep this file aligned with implemented behavior as the project evolves.
