# Configuration v3 implementation and validation

Validation date: November 5, 2026 UTC (November 4 Pacific). This record covers the configuration consolidation implementation. Earlier [research/native-v2 results](validation-results.md) remain historical and were not rewritten.

**Status:** implementation, independent review and offline checks passed. No tenant or endpoint operation is part of this validation.

## Delivered behavior

- Each supplied application has one authored `app.json`. Installer arguments and removal paths remain exclusively in editable PowerShell actions.
- Local resolution binds one retained release to PSADT metadata, standalone detection and publication settings. It verifies current installer evidence and captures source/dependency hashes.
- Explicit build creates a fresh complete PSADT copy, internal generated metadata/action inputs, declared payloads, detection and an atomic completion manifest. Native process handling and the existing native-v2 compatibility profile are preserved.
- Manifest packaging checks exact source/detection inventories and pinned tool/module bytes. Frozen publication requests bind acceptance to the exact package and detection; fixtures cannot be ready.
- Old active recipes, metadata, action maps, frozen detectors and the prior illustrative manifest were archived with exact hashes. See [migration details](../docs/Configuration-migration.md).

## Verification matrix

Results are independent runs in Windows PowerShell **5.1.26100.9711** and PowerShell **7.6.9**, unless stated otherwise. PS5 test processes used process-only execution-policy bypass; persistent policy was not changed. Tests use fresh processes to isolate sentinels and mocks.

| Suite | Recorded result | Scope |
|---|---|---|
| ApplicationDefinitionSchema | 48 checks, PS7 | Definition/release/evidence schema positives and negatives |
| ApplicationCore | 16 checks in each runtime | Canonical JSON, shared hash vectors, path validation, retained-record round trip |
| ApplicationResolver | 22 checks in each runtime | Evidence, current signer policy, metadata, action reuse, UTC dates and read-only resolution |
| ApplicationIdentityScope | 20 assertions / 7 cases in each runtime | Relocation and timestamp invariance; changed installer/generator identity; detection/support/installer drift before writes |
| CrossRuntimeRecords | 3 checks; child PS5 and PS7 processes | Identical build/record hashes and each runtime verifying the other's serialized record |
| ApplicationBuild | 31 checks in each runtime | Full record schemas, identity projections, snapshots, collisions, incomplete attempts, locks and exact template/payload inventories |
| NativeExampleContract | 97 checks in each runtime | Both applications, historical frontend hash equality, preserved detection logic, reused task source and manifest preview |
| ManifestPackaging | 11 checks per exercised application/runtime | Real fixture build, pinned module comparison, mocked package output, lock and tamper rejection, request preview and fixture publication rejection |
| ApplicationPublication | 50 checks in each runtime | Mocked acceptance/signing/authentication/Graph, effective values, duplicates, published content and zero assignments |
| ExamplePreviews | Passed in each runtime | Zero boundary calls; 14 published Add parameters, 120-minute limit and nine effective return codes |
| TemplatePopulation | 31 passed in each runtime | Default adapter, native compatibility profile and rejected edits |
| TemplateHooks | 34 passed, 2 skipped in each runtime | All nine task locations and exact framework restoration; real link fixtures skipped as described below |
| ApplicationDiscovery | 34 checks in each runtime | Mocked exact selection, pinned definitions and output boundaries |
| DetectionBinding | 49 checks in each runtime | Safe literal binding and rejection cases; no detector execution |
| ReferenceSyntax | 39 PowerShell files, 28 JSON files and 39 documentation blocks parsed in each runtime | Syntax only |
| Documentation | 18 documents, 173 local links and 40 PowerShell blocks checked in each runtime | Includes README and agent guidance; no workflow commands executed |

Packaging coverage exercised Firefox and Notepad++ in both runtimes across focused runs. Tool execution was mocked; fake `.intunewin` output is explicitly not valid Intune content. The PS5 packaging preview can invoke the read-only PS7 schema validator; it never invokes an installer or Content Prep Tool.

## Independent review and corrections

Review covered configuration ownership, template preservation, all nine task locations, source staging, binding, identity, packaging, readiness, preview isolation and the user walkthrough. No blocking implementation finding remained after these corrections:

- Canonical serialization now agrees across PowerShell versions for provider-wrapped strings, apostrophes, date-looking strings and floating-point values.
- Reused action sources produce one retained snapshot; missing process descriptions do not become null PSADT fields.
- Required MSI evidence must be nonempty. A named installer review also requires a valid UTC timestamp; JSON Schema's format annotation alone did not enforce this.
- A separately signed detector must preserve the unsigned body and remain unchanged during signature inspection.
- A reproduced authentication-window race is closed: frozen request/evidence and raw package/detection hashes are rechecked immediately before creating the Intune app. Seven mocked mutation scenarios assert that creation is never reached.
- The rollout guide now explains how to resume with already prepared acceptance/request records instead of recreating immutable files.

One reviewer identified missing identity-scope tests rather than a demonstrated implementation bug. The new 20-assertion suite closes that coverage gap. Another reviewer checked the final publication race fix independently.

## Generated examples and limits

Local review copies are under ignored `generated-examples/psadt-4.1.8-config-v3/<application>/build/`. Each has `Source/Invoke-AppDeployToolkit.ps1`, a separate `Detect.ps1` and `build-manifest.json`. Their installer payloads are **fake test text**, their manifests remain `fixture: true`, and they must not be executed or published.

The following remain unperformed: actual installer acquisition/identity acceptance for a real release; real Content Prep execution; application installation/uninstallation; SYSTEM/user interaction and reboot scenarios; real signing and endpoint trust; authentication/upload/assignment in Intune; and business-owner acceptance. Hash seals detect mismatches but do not authenticate reviewers. The publisher has no filesystem lock throughout an upload and no resumable tenant transaction.

The real junction and symbolic-link fixture tests were skipped in both runtimes: junction creation returned access denied, and symbolic-link creation required administrator privileges. These cases remain unverified and are not included in the 34 passing hook cases. Local Markdown checks validate target existence and code syntax, not external URLs or anchor fragments.

## Reproduce

Restore the [pinned dependencies](../docs/Setup.md), then run the suites listed in [Testing](../docs/Testing.md#offline-repository-checks) in fresh processes. Do not execute generated deployments on the build workstation. Test output directories under `.validation` and `.research/psadt` are ignored local evidence, not repository dependencies.

The [implementation plan](../docs/Configuration-consolidation-plan.md) records acceptance criteria; the [walkthrough](../docs/Getting-started.md) is the operational entry point. This implementation completes the configuration refactor, not the later scheduling, CI/CD or Intune rollout roadmap.

The [machine-readable validation record](configuration-v3-validation.json) retains the matrix, runtime versions, limitations and SHA-256 snapshot of the 60 authored code/schema/example/fixture files. The generated samples are ignored local artifacts and are not included in that source snapshot.
