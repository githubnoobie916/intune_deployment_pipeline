# Validation results and execution boundaries

Validation date: November 3, 2026, America/Los_Angeles. Recorded UTC times in machine-readable evidence can be November 4. These results validate research inputs and offline examples. They do not certify application installation or tenant operations.

## Native-v2 correction results

The current samples use `official-4.1.8-native-v2` and recipe schema 2. The [review record](../docs/Native-PSADT-review.md) explains the behavior changes. Current results are separate from the historical validation below.

| Check | Result | Evidence |
|---|---|---|
| Source snippets and recipes | Two schema 2 recipes validate; nine owned scripts parse in PowerShell 5.1/7; six Main snippets contain eight invocations of four verified PSADT functions | [Example evidence](native-v2-example-validation.json) |
| Removed custom deployment logic | Custom Pre/Post scripts and Firefox policy payload removed; native process metadata populated; standalone detection hashes unchanged | [Example evidence](native-v2-example-validation.json) |
| Publication and assignment previews | Ten checks pass in both PowerShell 5.1 and 7, with zero sentinel calls; Auto, 120 minutes and nine unique return codes agree with the manifest | [Publication evidence](native-v2-intune-validation.json) |
| Published module compatibility | Fourteen Add command parameters verified; 120 is within the published 1–1440 minute range; only additional return codes supplied | [Publication evidence](native-v2-intune-validation.json) |
| Revised template adapter | 31 tests pass on Windows PowerShell 5.1.26100.9711 and PowerShell 7.6.9, including native-command rejection cases and exact completion-prompt omission | [Adapter evidence](psadt-4.1.8-native-v2-validation.json) |
| Actual native-v2 generation | Both examples generated under Windows PowerShell 5.1 with both opt-in switches; each has 222 files, four native application calls, and 221 other upstream files unchanged; all 222 pristine files unchanged | [Generation hashes and allowed edits](psadt-4.1.8-native-v2-validation.json) |
| Cross-file sample contract | 69 checks pass in both PowerShell versions: source/generated process metadata, Auto commands, timeout, return codes, absent custom Pre/Post/policy payload, unchanged detection, and packaging preview without execution or output | [Final checks](native-v2-final-validation.json), [test source](../tests/Test-NativeExampleContract.ps1) |
| Authored syntax | 17 PowerShell files and six documentation PowerShell blocks parse in both PowerShell versions; JSON parsing is recorded separately in the run evidence | [Final checks](native-v2-final-validation.json) |

No native-v2 endpoint behavior has been executed. Firefox policy remains an external, unverified Intune prerequisite. The deployment no longer rejects a leftover Notepad++ updater at runtime; its absence and any required legacy migration remain mandatory endpoint acceptance checks.

## Historical v1 results and dependency baseline

The following table records the original sample revision and dependency research. The old generated scripts used custom process retry/version checks and Firefox JSON merging. Those application behaviors have been superseded; the original JSON records and `.research` outputs are retained for provenance. Current test source can contain additional cases beyond the historical runs.

| Check | Result | Evidence or reproducible check |
|---|---|---|
| Official PSADT 4.1.8 v4 archive | SHA256 matches release metadata; 222 extracted files inventoried | [Release inventory](psadt-4.1.8-release.json) |
| PSADT Authenticode inspection | 203 executable/module/script/data files checked: 172 Valid, 31 NotSigned; no other status | [Release inventory](psadt-4.1.8-release.json); unsigned customization files are recorded rather than treated as signed |
| Offline template adapter | 11 tests pass on Windows PowerShell 5.1.26100.9711 and PowerShell 7.6.9 | [Detailed test results](psadt-4.1.8-validation.json), [test source](../tests/Test-TemplatePopulation.ps1) |
| Actual example population | Firefox and Notepad++ application sections populated; generated scripts parse; 221 other files unchanged for each; all 222 pristine files unchanged | [Per-example hashes and permitted edits](psadt-4.1.8-validation.json) |
| Evergreen published artifact and definitions | Exact module archive inspected; definition ZIP digest and 1,200 definition-file hashes checked | [Evergreen inspection](evergreen-2610.2859.0-inspection.json) |
| Evergreen live discovery | Exactly one matching candidate for each recipe using the pinned module/definitions under PowerShell 7.6.9 | [Firefox record](evergreen-firefox-discovery.json), [Notepad++ record](evergreen-notepadplusplus-discovery.json) |
| Discovery wrapper and packaging preview | Discovery restores the prior cache environment; relative output follows the PowerShell location; packaging preview creates no output and rejects an incorrect tool hash without executing the tool | [Final example checks and file hashes](evergreen-example-validation.json) |
| IntuneWin32App published artifact | Exact 1.5.0 archive inspected; selected default-branch files compared independently | [Inspection](intunewin32app-1.5.0-inspection.json), [source comparison](intunewin32app-1.5.0-source-parity.json) |
| Intune source and example syntax | 86 module PowerShell/manifest files plus both publication examples parsed in 5.1 and 7; zero errors; 13 named-command and 9 enum checks pass | [PowerShell 5.1 evidence](intunewin32app-1.5.0-syntax-ps5.json), [PowerShell 7 evidence](intunewin32app-1.5.0-syntax-ps7.json) |
| Content Prep Tool | v1.8.7 executable downloaded, hash recorded, Microsoft signature Valid; file version 6.2509.50.0 | [Intune/tool inspection](intunewin32app-1.5.0-inspection.json) |
| Recipe schema | Both recipes accepted; pinned policy without target rejected; executable filter property rejected | PowerShell 7 `Test-Json` against [schema](../schemas/application-recipe.schema.json) |
| Authored script and documentation syntax | Authored PowerShell files, JSON files, and fenced PowerShell documentation examples parse under Windows PowerShell 5.1 | [Syntax-check script](../tests/Test-ReferenceSyntax.ps1); counts are emitted when run |
| Publication and assignment previews | Default paths return local plans under 5.1 and 7; sentinel functions prove no module import, authentication, HTTP or writer command was reached | [Preview tests](../tests/Test-ExamplePreviews.ps1) |
| PSADT commands used in app snippets | 12 application scripts parse; 16 PSADT invocations across four commands match named parameters in the released 4.1.8 module | Static AST comparison only; no toolkit import or endpoint execution |

The original adapter cases covered a full copied template, literal quoting and hostile-looking text, missing metadata, unknown metadata, existing destination refusal, non-pristine template refusal, invalid snippets, snippet path containment, upstream tampering, explicit unsupported repair behavior, and UTF-8-without-BOM Unicode metadata. The Unicode case first reproduced the Windows PowerShell 5.1 decoding error; the adapter now uses explicit text decoding and verifies the resulting literal value.

Historical source review corrected Firefox's distribution-directory option, the original Silent-profile return codes, and channel detection. Native-v2 preserves distribution content but removes the JSON merge, uses Auto with 1602 retry, and moves Firefox configuration to a separate Intune prerequisite. Neither set of offline checks proves endpoint behavior.

## Run the local checks

Run from the repository root in a fresh PowerShell process. The commands below execute only authored offline tests, never populated deployments:

```powershell
# Use an appropriately trusted/signed local-script execution policy in your environment.
.\tests\Test-ReferenceSyntax.ps1
.\tests\Test-ExamplePreviews.ps1
.\tests\Test-TemplatePopulation.ps1
.\tests\Test-NativeExampleContract.ps1
```

The template tests require the verified local `.research/psadt/pristine` dependency and create uniquely named copies under `.research/psadt`. They do not overwrite pristine files or run snippets. Consult the test source for the exact template input and output locations.

The native contract test requires the generated v2 folders and pinned local IntuneWin32App/Content Prep Tool files. It compares source, generated metadata, preview commands, timeout, return codes and unchanged detection hashes. Its packaging preview must create no output or import a module; it does not run the packaging utility.

For this research, the workstation's unsigned-script execution policy initially blocked `-File` validation. Tests were then launched with `-NoProfile -NonInteractive -ExecutionPolicy Bypass` on that test process only. No persistent machine or user policy was changed. This test invocation is not a recommendation to bypass organizational controls.

Schema verification requires a validator supporting JSON Schema draft 2020-12; the local PowerShell 7 `Test-Json` implementation accepted these schemas. Windows PowerShell 5.1 syntax checks do not establish JSON Schema validity by themselves.

## What was not executed

- Firefox or Notepad++ installer downloads, payload Authenticode checks, MSI database inspection, or vendor-binary execution.
- Installation, upgrade, uninstall, repair, running-process closure, prompts, deferrals, reboot behavior, or business-function tests on endpoints.
- PSADT module import or launcher execution. Generated copies contain no application installers.
- Content Prep Tool execution or actual `.intunewin` creation.
- IntuneWin32App module import, Graph authentication, tenant inventory reads, resource creation, content upload, assignments, relationships, or cleanup.
- Scheduled tasks, certificate/app-registration provisioning, Azure infrastructure, or CI/CD setup.

Evergreen alone was loaded from its isolated downloaded package for read-only vendor discovery. It was not installed globally, and its definitions were not automatically updated. No token or secret was needed. Retained discovery hashes describe upstream metadata; they do not mean installer bytes were downloaded and independently validated.

## Interpretation

The official template's integrity and the adapter's permitted-edit behavior have local test evidence. The recipe examples have schema, source and syntax evidence. Tenant-changing code is illustrative and its execution paths are untested. Production use requires the isolated-machine and controlled-pilot acceptance steps in the [engineering report](../docs/Engineering-report.md), plus the remaining tenant and ownership decisions.
