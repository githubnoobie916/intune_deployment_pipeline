# Troubleshooting

[Walkthrough](Getting-started.md) · [Documentation home](../README.md)

Stop at the failed stage, preserve the result, and correct its inputs. Do not turn a failed validation into a successful deployment by removing checks.

| Symptom | Action |
|---|---|
| Missing `.research` or generated samples after cloning | These are excluded from Git. Complete [setup](Setup.md); a source checkout does not contain dependencies or installers. |
| Script execution is blocked | Use your organization's approved signing/execution policy. If permitted for reviewed local files, use a process-scoped policy; do not weaken machine policy or bypass application control. |
| JSON parses but the recipe is invalid | Run the separate PowerShell 7 schema check in [application setup](Add-application.md). Syntax checks are not schema validation. |
| Discovery finds zero or multiple candidates | Inspect actual Evergreen fields and correct selectors. Require exactly one intended installer; do not select the first result. [Release preparation](Prepare-release.md). |
| A pinned version differs from discovery | Use its retained approved release record/artifact, or prepare a new release. Do not silently replace the pinned version. |
| Download URL, hash, signer, or product identity differs | Keep the file out of Source and review the vendor change. Do not approve a signer solely because it signed the downloaded file. |
| Template hash/inventory mismatch | Restore the exact released v4 template from verified dependencies. A raw repository frontend or previously generated script is not the pristine template. |
| Destination/output already exists | Select a new release/build directory. The examples intentionally refuse to overwrite Source or Package outputs. |
| Native command validation rejects an action | Check full function/parameter names and the four-function allowlist. Additional PSADT functions need an adapter change and tests. [Application setup](Add-application.md). |
| New app passes parsing but baseline contract checks do not cover it | Add application-specific contract and endpoint checks. The existing contract test explicitly checks Firefox and Notepad++. |
| Metadata, detection, and discovered version differ | Use the same retained release through Resolve and Build. Do not edit generated metadata or detection. A version mismatch must stop the build. |
| Packaging rejects changed/missing files | Manifest mode checks the complete generated source inventory and detection hash. Start a fresh reviewed build for intended edits; never update inventory hashes merely to accept drift. |
| `Build implementation changed` or `Packaging implementation changed` | Generator code or schemas changed after resolution. Resolve and build a fresh attempt using the reviewed implementation. |
| Module content differs from the verified archive | Restore the exact published package bytes; a matching manifest version is insufficient. For alternate layouts, pass `-IntuneWin32AppPackagePath` explicitly. |
| A build/package lock exists | Check the earlier process and retained attempt first. Do not delete a live lock; use a new destination after reconciliation. |
| Fixture or missing acceptance blocks publication | Supply real reviewed artifacts plus named endpoint/business/prerequisite evidence. Fixture flags are not an approval switch. |
| Intune module is already loaded or cannot be found | Start a fresh Windows PowerShell 5.1 publisher process and use the reviewed module-discovery setup in [publication](Publish-and-rollout.md). |
| Native deferral/timeout returns 1602/1618 | These are retry outcomes in the sample mapping, not installation success. Inspect the native prompt and retry behavior. |
| Unsupported Repair returns 69001 | Expected for these two examples. Repair is not an advertised operation and can run its stock welcome before failing. |
| Same/newer installed app skips configuration changes | Detection can prevent the wrapper from running. Apply separately managed policy/remediation; do not force a downgrade to deliver configuration. |
| Publication or assignment times out, or its result is uncertain | Record the release marker/app ID and inspect Intune before retrying. There is no resumable transaction or automatic reconciliation. |
| App already exists for the release | Reconcile its content/settings/assignments. Do not generate a new release ID merely to evade the duplicate check. |
| Pilot assignment script rejects existing assignments | Expected: it accepts only an unassigned app. Use the reviewed manual promotion/reconciliation procedure. |
| App was uploaded but devices fail | Separate published content, targeting/applicability, download, installer exit, detection, and business acceptance. Collect endpoint and IME evidence. |

## Recovery record

Retain the release ID, application ID, approved hashes, intended operation, timestamp, operator, returned result/error, and known Intune app ID. For uncertain tenant writes, keep the existing identity until reconciliation determines what happened.

Removing targeting does not guarantee cancellation of an already-started installation. Retaining an older package does not prove downgrade support. Follow the application's tested recovery procedure.

[Operational recovery details](Intune-operations.md#state-retries-and-operational-acceptance) · [Source and validation evidence](../evidence/configuration-v3-validation.md)
