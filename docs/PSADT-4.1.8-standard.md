# PSADT 4.1.8 deployment standard and verified template population

This standard uses the official **v4 deployment template from release 4.1.8**, preserves its framework within the named customization contract, and populates a separate copy for every application build. The v3 application workflow retains the native-v2 endpoint profile: Windows 11 x64, SYSTEM, `-DeployMode Auto`, native process handling, unattended vendor installers and omission of the stock illustrative completion prompt. The low-level adapter default retains that prompt; the compatibility profile is not proof of strict upstream-default preservation. This is a pinned baseline, not a permanent toolkit freeze. **No installer or PSADT deployment has been executed for this research.**

## Baseline actually inspected

The [official 4.1.8 release](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases/tag/4.1.8) was published on 2026-01-14 at tag commit `af17af7ad3e30a9fe7635cf063b7eebfc065c7de`. The separate `PSAppDeployToolkit_Template_v3.zip` is a compatibility template and is not this design's baseline. The [release asset](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases/download/4.1.8/PSAppDeployToolkit_Template_v4.zip) was downloaded and inspected on November 3, 2026 Pacific time.

| Measured item | Result |
|---|---|
| Release archive | `PSAppDeployToolkit_Template_v4.zip`, 9,447,412 bytes |
| Archive SHA-256 | `50cb8d32973fc7648060a48cad63912ecb5caca5a70754f37e83aa06bd380283` |
| Archive verification | Matches digest advertised by [GitHub release metadata](https://api.github.com/repos/PSAppDeployToolkit/PSAppDeployToolkit/releases/tags/4.1.8) |
| Extracted files | 222 |
| Default deployment script SHA-256 | `3e6db6941a332e1212ad88ec1a715d3d56a7a94f31f1cbfa0c261fe3cecff67a` |
| Authenticode check scope | 203 `.exe`, `.dll`, `.ps1`, `.psm1`, `.psd1` files |
| Signature results | 172 `Valid`, 31 `NotSigned`; no other result |
| Launcher signature | Valid; subject includes `Patch My PC, LLC` |
| Root deployment script | Unsigned, intentionally customizable |

The complete file hashes and signature observations are in `evidence/psadt-4.1.8-release.json`. Signature status describes the host's verification at inspection time; it is not a perpetual revocation guarantee. Hash agreement with release metadata establishes consistency with the inspected release, not immunity from an upstream compromise.

The ignored local inspection copy is `.research/psadt/pristine`. Preserve it unchanged. Archive bytes, extracted files, and test working copies belong in controlled artifact storage rather than source control. This repository stores their manifest, adapter, tests, and explanations.

The raw tagged frontend is **not byte-identical to the distributed template**. [New-ADTTemplate in 4.1.8](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Public/New-ADTTemplate.ps1) copies the frontend, assets/configuration/strings, creates payload directories, strips signatures from customizable copies, copies the bundled module separately, and adjusts frontend import paths/date. Use the released v4 ZIP rather than reconstructing the package from a raw script. Moving website documentation may describe later changes; tagged source/help and this archive take precedence for 4.1.8.

## Directory and immutability boundary

The actual top level of the extracted archive is:

```text
Invoke-AppDeployToolkit.exe
Invoke-AppDeployToolkit.ps1
Assets/
Config/config.psd1
Files/
PSAppDeployToolkit/
PSAppDeployToolkit.Extensions/
Strings/
SupportFiles/
```

Preserve every release file, including files below these directories. Approved installer payloads belong in `Files`; application support data belongs in `SupportFiles`. The low-level adapter copies the full release except for approved frontend edits and does not stage payloads. `Build-Application.ps1` invokes that adapter, then stages the declared installer/support files with separate inventories and hashes, rejects upstream-file collisions and verifies the complete source again. It does not download or execute installers. The current v3 contract stages one installer plus support files; additional bundled installer roles require a reviewed extension.

Treat `PSAppDeployToolkit/**`, the launcher, and the supplied extension module as immutable. Although the toolkit supports extension modules, **this implementation adds no shared endpoint framework**. Shared organizational helpers belong on the build host: selection, validation, literal serialization, hashing, packaging and state reconciliation. Application installation/configuration logic belongs in that application's reviewed snippets inserted into the official script. Root `Config`, `Assets` and `Strings` are official customization copies, distinct from corresponding files inside the bundled module. Any later root configuration/branding change needs an explicit allowlist and validation; the included adapter does not yet make those edits.

## Metadata and designated application sections

These are real fields from the [4.1.8 frontend](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Frontend/v4/Invoke-AppDeployToolkit.ps1), not invented placeholders:

| Definition/resolved value | Actual field | Source of value |
|---|---|---|
| Publisher | `AppVendor` | Engineer, checked against installer identity |
| Application name | `AppName` | Engineer |
| Resolved release version | `AppVersion` | Discovery, cross-checked against installer |
| Architecture/language | `AppArch`, `AppLang` | Explicit selection, validated payload |
| Packaging revision | `AppRevision` | Engineer/build policy |
| Deployment-script revision/date/owner | `AppScriptVersion`, `AppScriptDate`, `AppScriptAuthor` | Reviewed `toolkit` fields in `app.json` |
| Accepted installer codes | `AppSuccessExitCodes`, `AppRebootExitCodes` | Vendor evidence and tests |
| Applications whose closure PSADT should manage | `AppProcessesToClose` | `deployment.processes` in `app.json`; see native closure behavior below |
| Administrator requirement | `RequireAdmin` | Installation context; true for initial SYSTEM profile |
| Optional title overrides | `InstallName`, `InstallTitle` | Engineer; normally leave default |

Leave `DeployAppScriptFriendlyName`, `DeployAppScriptParameters`, and `DeployAppScriptVersion` untouched. Do not insert fictitious session fields for Evergreen URIs, Intune IDs, detection rules, deferrals or prerequisites. Those belong to build/publish state or explicit application commands.

The table describes low-level adapter fields, not extra v3 authoring options. The [application schema](../schemas/application-definition.v3.schema.json) and [configuration reference](Configuration-reference.md) define which settings are authored; the resolver generates supported metadata and the builder writes `Inputs/application/metadata.generated.json`. Do not maintain another editable metadata file. `AppVersion` comes from the accepted release, and the same version binds standalone detection and publication.

**Populating `AppName` disables Zero-Config MSI.** The stock zero-config blocks remain intact but inactive. Explicitly insert the application's MSI/EXE commands. This prevents accidental auto-selection when multiple MSI files or prerequisites exist in `Files`.

The official functions `Install-ADTDeployment`, `Uninstall-ADTDeployment`, and `Repair-ADTDeployment` each contain Pre/Main/Post task comments. The adapter inserts code directly after the relevant comment. Pre runs after the native welcome/progress calls; Post is sequential work, not guaranteed cleanup after failure or exit. Preserve phase assignments, welcome/progress behavior, zero-config blocks, initialization, dispatch, session handling and outer exception handling.

The existing install `$saiwParams` is the real application UX configuration location: default values allow three deferrals and enable disk-space checking/prompt persistence. Native-v2 leaves that invocation unchanged. The final install prompt explicitly allows customization/removal. The opt-in `-OmitCompletionPrompt` adapter switch removes only the exact pristine `if (!$adtSession.UseDefaultMsi) { Show-ADTInstallationPrompt ... }` extent containing the stock placeholder. It verifies the unique command, enclosing Install function, full expected text and pristine frontend hash before editing. Omitting the switch preserves the prompt. No other framework, configuration or extension-module change is permitted.

## Offline adapter contract and trust model

The normal application workflow uses [Resolve and Build](Getting-started.md), which produce the adapter's internal inputs. The low-level `scripts/Populate-PSADTTemplate.ps1` interface remains available for focused adapter work. For example, a separate review copy can consume already generated inputs from a retained build:

```powershell
$generatedInputs = 'C:\IntuneLifecycle\releases\app\attempt\Build\Inputs\application'
.\scripts\Populate-PSADTTemplate.ps1 `
    -TemplatePath '.\.research\psadt\pristine' `
    -DestinationPath 'C:\IntuneLifecycle\releases\app\attempt\AdapterReview' `
    -MetadataPath (Join-Path $generatedInputs 'metadata.generated.json') `
    -ActionsPath (Join-Path $generatedInputs 'actions.generated.json') `
    -OmitCompletionPrompt `
    -ValidateNativeApplicationCommands
```

The paths above illustrate the generated-input contract, not a second authoring workflow. The destination must not exist and must be outside the pristine template. A rejected or failed build must never be promoted. Re-run with a new directory; the adapter does not recursively delete old output. The adapter requires PowerShell 5.1+, reads local files, writes a working copy and emits a validation result. It does not import PSADT, run snippets, execute installers, authenticate, package, publish or assign. Its result alone is not a complete build manifest.

Metadata is a flat JSON object. All fields in the table are supported. The nine identity/script fields through `AppScriptAuthor` are required; `AppScriptVersion` must parse as a .NET version and `AppScriptDate` must be `yyyy-MM-dd`. Application release versions remain strings because vendor versioning is not universally numeric. Unsupported keys, incorrect types and the stock author placeholder are rejected. `AppProcessesToClose` accepts strings or objects containing `Name` and optional `Description`.

Actions are **paths to trusted, reviewed code files**, not executable expressions embedded in JSON:

```json
{
  "Install": { "Pre": "pre-install.ps1", "Main": "install.ps1" },
  "Uninstall": { "Pre": "pre-uninstall.ps1", "Main": "uninstall.ps1" },
  "Repair": { "Main": "repair.ps1" }
}
```

Operation names are `Install`, `Uninstall`, `Repair`; phase names are `Pre`, `Main`, `Post`. Each operation requires an explicit `Main` snippet. Author these paths in `app.json`, relative to its directory. The builder snapshots the reviewed scripts beside `actions.generated.json`, preserving the adapter's relative-path contract. Both supplied applications intentionally remain Main only. Unsupported Repair logs and fails with `69001`; its unchanged welcome runs first and can prompt or close applications, so do not advertise Repair. The adapter rejects paths outside the generated action-map directory and redirected links/junctions. Ordinary OneDrive cloud-backed source files remain supported; operational artifacts still belong on nonsynchronized storage.

The adapter parses snippets and the final script. **Parsing is not code authorization or a sandbox.** Reviewed snippets can install software, modify configuration and execute PowerShell on endpoints when deployed. Code review must reject snippet commands that override toolkit functions/session lifecycle, import unapproved helpers, expose secrets, or use unsafe process-closing behavior. Build-host privileges and endpoint privileges are distinct; the population process never needs to execute snippets.

`-ValidateNativeApplicationCommands` is an optional, deliberately narrow sample-conformance check. It accepts direct top-level calls only to `Start-ADTMsiProcess`, `Start-ADTProcess`, `Write-ADTLogEntry` and `Close-ADTSession`, together with simple local assignments, literal data and data interpolation. Every named parameter must be a full canonical parameter declared in the exact released function's AST; aliases and abbreviations are rejected. The module is parsed as text, never imported. Helper functions, conditional/loop/try blocks, method calls, dynamic invocation, splatting, pipelines, redirection, executable scriptblocks and command substitution are rejected. Session data reads are limited to `DirFiles`, `DirSupportFiles`, `AppName` and `AppVersion`; assignments to session data or reserved/scoped variables are rejected. This checker is not a general validator for all legitimate PSADT functions, a PowerShell sandbox, or a guarantee that accepted installer arguments are safe. Review the command targets, vendor arguments, outcomes and payloads separately. Omit the switch only for other explicitly reviewed application styles; do not claim such output passed the native sample check.

The implementation gates the pristine frontend against its exact release hash, then verifies all 222 files against the trusted source-controlled inventory. It reads JSON as UTF-8 independently of Windows PowerShell's legacy ANSI default, finds the metadata hashtable with the AST, replaces only the value extents of explicitly supported keys, renders strings as literal single-quoted text, and escapes embedded apostrophes by doubling them. Numeric/boolean/array values use typed serialization. It matches unique task-comment tokens inside their expected deployment functions and adds code only there. Edits are applied by offset, not broad text replacement.

After population, the adapter parses the script and reverses exactly the allowed edit spans in memory. Equality with the pristine source proves that text outside those spans is unchanged. It checks written content, checks all 221 other files byte-for-byte, then rechecks all pristine-source hashes. This detects unauthorized framework/configuration edits and missing/extra upstream files. The trusted manifest and adapter themselves require normal source-control review and integrity protection.

The script's stock import uses `ModuleVersion = '4.1.8'`, a minimum-version requirement, and falls back to `PSModulePath` if its local module is absent. Preserve that code. The package build gate must guarantee the exact bundled module is present and unchanged so deployment never depends on the fallback. A different release or regenerated template hash requires a new adapter revision and regression tests.

## Entry points, prerequisites and runtime behavior

The [tagged prerequisites](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/README.md) state Windows 10/11, PowerShell 5.1+ and .NET Framework 4.7.2+. The [module manifest](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/PSAppDeployToolkit.psd1) specifies PowerShell `5.1.14393.0`; the [launcher project](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSADT.Invoke/PSADT.Invoke/PSADT.Invoke.csproj) targets .NET Framework 4.7.2, AnyCPU and native ARM64 preference. Toolkit architecture support does not imply installer architecture support. Windows 11 x64 is the tested-design target; ARM64, x86 and per-user packages require their own later acceptance profiles.

Local orchestration supports 64-bit Windows PowerShell 5.1 or PowerShell 7.5+, with separately pinned dependencies. The v3 reader requires installed `pwsh.exe` 7.5+ for schema validation when called from Windows PowerShell. Offline checks under each runtime are separate from actual packaging and endpoint execution. On endpoints, the toolkit is bundled; Evergreen and IntuneWin32App are not endpoint dependencies. The framework's .NET/PowerShell requirements do not install themselves.

Use `Invoke-AppDeployToolkit.exe` as the `.intunewin` setup entry point and these exact commands:

```text
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Auto
Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Auto
```

For an application with verified repair support, the local repair entry point is `Invoke-AppDeployToolkit.exe -DeploymentType Repair -DeployMode Auto`. Neither supplied application supports repair: its Main snippet returns `69001`, after the stock welcome. Do not expose a repair action merely because the generic template accepts the parameter.

The script also accepts `-DeployMode Auto`, `Interactive`, `NonInteractive`, `-SuppressRebootPassThru`, `-TerminalServerMode`, and `-DisableLogging`. The launcher supports `/Core` for installed PowerShell 7, `/32` for x86 Windows PowerShell, and `/Debug` for interactive troubleshooting; `/Core` and `/32` cannot be combined. The [launcher source](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSADT.Invoke/PSADT.Invoke/Invoke.cs) shows it can inherit a PowerShell 7 ancestor even without `/Core`. Therefore reproduce the actual IME invocation from the intended shell/context rather than assuming a launch from a PowerShell 7 console is equivalent.

The launcher waits and returns the PowerShell process exit code. Its default execution-policy bypass does not override WDAC or AppLocker and is not an integrity control. If policy requires a signed customized deployment script, a separately reviewed signing stage must be added before using this workflow: the current closed build inventory rejects editing or signing that generated file in place. Publication preparation supports a separate signed detection copy with unchanged unsigned body and retained final hash. Keep keys outside payloads and never rewrite or re-sign upstream files as an application-specific change.

## User interaction and running applications

**ServiceUI is unnecessary for 4.1.8.** The [tagged README](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/README.md) explains the v4.1 redesign: interaction runs in the user's session while privileged deployment stays separate. Do not add ServiceUI binaries or old v3 launcher guidance.

This toolkit capability does not supersede [Microsoft's statement that interactive Win32 app installations are unsupported](https://learn.microsoft.com/intune/app-management/deployment/win32). The user selected native PSADT Auto prompts/deferrals with that support boundary understood. This is not a claim of Microsoft support for interactive Win32 installation. Keep vendor installers unattended and validate the exact SYSTEM/IME behavior in the lab before deployment.

The actual [4.1.8 session logic](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSADT/PSADT/Module/DeploymentSession.cs#L675-L838) selects Silent when configured processes are not running. When a configured process is running and a suitable user session is available, Auto resolves to Interactive. OOBE, detected active user ESP, or SYSTEM/session 0 with no suitable user and a noninteractive host selects Silent first. An empty process list does not ordinarily select Silent. Auto is the default; the commands above state it explicitly. The released frontend help lines 17/19 invert the running-process condition; use the implementation and endpoint tests. Explicit Interactive can fail when no suitable user is available and is not interchangeable with Auto.

**Silent does not mean non-disruptive.** [Show-ADTInstallationWelcome](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Public/Show-ADTInstallationWelcome.ps1) can stop configured applications without a user prompt in silent mode. The template calls its welcome logic **before** the designated pre-installation task insertion point. Therefore a pre-installation check is too late if the same processes were already configured in `AppProcessesToClose`.

Native-v2 metadata configures `@{ Name = 'firefox'; Description = 'Mozilla Firefox' }` or `@{ Name = 'notepad++'; Description = 'Notepad++' }` in `AppProcessesToClose`. Names omit `.exe`. The toolkit owns discovery, prompting and closure; the samples contain no custom `Get-Process`, process retry gate or newer-version skip. This replaces the earlier empty-process-list/custom-retry sample design. It does not preserve that design's process behavior.

Default Install welcome permits three deferrals. Default Uninstall and Repair welcome supplies a 60-second process-close countdown and does not enable deferral. Silent/NonInteractive welcome force-closes configured running applications without that countdown. Interactive Close also force-closes by default; `PromptToSave` is not enabled. Remaining applications the interactive user cannot close can also be force-closed. Auto's initial process snapshot is not a continuous guard: an application started after Auto selects Silent can be closed without prompting. Stock welcome does not enable `BlockExecution`, so users can also relaunch afterward. Accept these native behaviors explicitly in endpoint tests; do not describe the result as lossless, non-disruptive or guaranteed to prompt every running user.

The examples rely on independent Intune minimum-version detection to avoid unnecessary same/newer-version deployment. There is no deployment-time downgrade guard: direct invocation or a supersedence/detection change can still run the pinned installer against a newer app. The vendor's response must be tested. Firefox updater policy is managed separately through central policy; these scripts do not merge or overwrite `policies.json`. Notepad++ uses the vendor `/noUpdater` selection. Direct native vendor-uninstaller calls let a missing path follow toolkit failure handling; they do not manufacture successful removal from an absent file.

Actual deferral parameters belong on the existing welcome invocation: `AllowDefer`, `DeferTimes`, `DeferDays`, `DeferDeadline`, and `DeferRunInterval` (a TimeSpan). The [configuration defaults](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Config/config.psd1) are `1602` on deferral, `1618` on prompt timeout and 3,300 seconds for the dialog timeout. Native-v2 preserves these defaults and the template's three deferrals. Intune retry mapping is separate. A future interval setting can reduce repeated prompts but does not reschedule Intune or replace deadline/assignment design. Test repeated retries, exhaustion, clocks/time zones, no-user sessions and user changes.

## Installer commands, failures, reboots and logging

Use v4 functions. For a normal MSI with validated metadata and vendor support:

```powershell
Start-ADTMsiProcess -Action Install -FilePath 'Example-x64.msi' `
    -AdditionalArgumentList 'ALLUSERS=1' -ExitOnProcessFailure
```

`AdditionalArgumentList` adds to the default MSI arguments; `ArgumentList` replaces them. The [4.1.8 MSI function](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Public/Start-ADTMsiProcess.ps1) supports install, uninstall, patch and repair with files or appropriate product identities. Product-code uninstall is only correct when the installer is a genuine registered MSI product; an MSI wrapper around another installer may require a vendor EXE uninstaller. Repair must be validated, not inferred from `.msi` file extension.

For an EXE, use `Start-ADTProcess -FilePath 'Example.exe' -ArgumentList '<vendor-verified switches>' -ExitOnProcessFailure`. Switches are specific to the actual installer. Use `-WaitForChildProcesses` only after verifying bootstrapper behavior; do not use `-NoWait` for a normal deployment that must await completion. These are syntax-verified patterns, not tested installations. [4.1.8 process function](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Public/Start-ADTProcess.ps1)

Default success is `0`; reboot outcomes are `1641` and `3010`. The toolkit's MSI defaults suppress installer-controlled reboot with `REBOOT=ReallySuppress /QN`. Keep Intune responsible for the organizational restart policy. Omit `SuppressRebootPassThru` so reboot outcomes can reach Intune; do not copy old `AllowRebootPassThru` examples. A vendor EXE needs its own verified no-restart switch. A 1641 outcome means the installer may already have initiated restart; classifying it cannot undo that action.

Use `-ExitOnProcessFailure` when native installer failures must survive: the process function can close the session with that code. Otherwise a terminating failure can reach the untouched template catch and result in `60001`. Initialization failures use `60008`. The [session closing code](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSADT/PSADT/Module/DeploymentSession.cs) preserves reboot outcomes unless suppressed and normalizes accepted success outcomes. Configure Intune explicitly for `0` success, `3010` soft reboot, `1641` hard reboot, `1618` retry, optionally `1602` retry for the approved deferral policy, and framework/native failures as failed. PSADT's internal `FastRetry` label does not configure Intune.

**Reboot state is not automatically sticky across every installer call.** Later successful process invocations can overwrite the session's earlier exit code. For the initial standard, prefer separately detected Intune prerequisite dependencies. A bundled multi-installer package requires reviewed and tested aggregation in the designated application sections, including an early-reboot case, later success, later failure, and post-install actions. This adapter deliberately adds no custom final-close framework to solve that problem. Retaining a previous package also does not guarantee vendor downgrade support.

Default toolkit logs are under `%WinDir%\Logs\Software`; MSI logs inherit that location when no separate MSI log path is configured, with verbose `/L*V` logging. The root config controls rotation/history and optional compression. Treat command lines, stdout and configuration payloads as potentially sensitive; use supported secure argument logging options where appropriate and never package authentication secrets. Collect toolkit, vendor installer, IME and application diagnostic logs together with application/build IDs when investigating failures. A zero exit code plus detection still does not establish business-function acceptance.

## Verification and controlled toolkit upgrades

`tests/Test-TemplatePopulation.ps1` performs only offline checks against the real released template: complete-copy integrity, safe literal quoting including hostile-looking input and newlines, non-ASCII metadata encoded as UTF-8 without a BOM, parse success, required/unknown metadata rejection, refusal to overwrite, rejection of non-pristine templates, invalid snippet rejection, path containment and upstream-file tampering rejection. Native-v2 adds exact optional completion-If removal, preservation when omitted, accepted native statements, rejected custom/executable constructs, exact released parameter checks, optional validator behavior and rejection of a changed stock prompt. It leaves uniquely named test artifacts under `.research/psadt`. The test suite never launches the populated deployment.

`Test-TemplateHooks.ps1` separately covers all nine task locations, optional combinations, ordering, source provenance, malformed maps, path containment, empty/missing actions and unchanged framework content. Main-only application assertions remain separate. Some native link-creation cases can be unavailable on the validation host; recorded skips are not passes.

Historical `evidence/psadt-4.1.8-validation.json` and `evidence/psadt-4.1.8-native-v2-validation.json` remain unchanged. The older working copies under `generated-examples/psadt-4.1.8-auto-v2/` used both opt-in switches, contained 222 files and no vendor payloads, and preserved all 221 non-frontend files. Current v3 reference output belongs under `generated-examples/psadt-4.1.8-config-v3/`, with input snapshots, detection and manifests outside its package `Source`. Explicit offline fixture payloads do not establish installer validity or publication readiness. The [validation summary](../evidence/configuration-v3-validation.md) records current checks separately.

The historical native-v2 suite passed **31/31 tests on Windows PowerShell 5.1.26100.9711 and 31/31 on PowerShell 7.6.9**. Both original complete examples were populated by Windows PowerShell 5.1.26100.9711, each with four validated application-level native commands. The completion omission and rejection checks were first observed failing before their implementations, then passed. These historical structural results do not validate changed v3 sources or endpoint execution.

Endpoint acceptance remains mandatory: fresh install; supported-version upgrade; same/newer-version behavior; independent detection before/after install and uninstall; removal; supported repair; SYSTEM/no-user behavior; running applications; deferrals/retries where enabled; reboot codes; architecture/language variants; failure/partial-change recovery; and business-owner functional checks. Run the exact packaged launcher and command line in isolated Windows test machines. On the build host, limit checks to artifact authenticity, installer metadata, script structure, package metadata and policy compliance.

A PSADT upgrade gets a new pristine release directory, archive/file hashes, source review and adapter revision. Compare function parameters, template extension points, defaults, launch behavior, UI/session changes, failure codes and security/release issues. Test representative MSI, EXE/bootstrapper, prerequisite, reboot and interaction cases. Adopt on future builds first, then explicitly select existing releases for rebuild when security, compatibility or an approved behavior correction justifies redeployment. Never silently replace toolkit files inside an already-approved artifact. A template-only rebuild changes build identity even if the vendor application version is unchanged; document whether it needs an actual endpoint rerun and detection/promotion changes.

If a requested customization requires replacing initialization or dispatch, changing bundled framework files, or installing an always-present shared endpoint module, stop that application's build and present options. Such work is outside the template-population contract and requires explicit agreement.
