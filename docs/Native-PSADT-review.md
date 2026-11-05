# Native PSADT 4.1.8 sample review and corrections

This review records the native-v2 corrections: use `DeployMode Auto` and `AppProcessesToClose`, keep application actions in native PSADT functions, manage Firefox policies separately through Intune, and remove custom downgrade prevention. The current v3 configuration workflow preserves those endpoint decisions while consolidating authored settings in `app.json` and generating release-bound metadata/detection. Build orchestration and standalone Intune detection remain independent PowerShell. Installation, uninstallation and live Intune behavior remain untested.

## Review findings and resulting changes

| Finding in the original samples | Correction |
|---|---|
| Empty `AppProcessesToClose` plus duplicated `Get-Process` checks returning 1618 | Populate native process definitions for `firefox` and `notepad++`. Remove custom Pre sections and retain the template's welcome calls. |
| Custom version inspection and early no-downgrade exit | Remove the guard. Independent detection still accepts an eligible installed version at least as new as the target; manually running an older package follows vendor behavior. |
| Firefox JSON parsing, merging and direct file writes | Remove the policy payload and Post section. Record `DisableAppUpdate=true` as a separate Intune policy prerequisite whose policy ID and enforcement evidence remain pending. |
| Custom executable and leftover-updater postconditions | Move checks to endpoint acceptance. A remaining Notepad++ updater still fails acceptance; the package does not silently delete it or certify the upgrade. |
| Firefox MSI arguments replaced toolkit defaults | Append vendor properties with `Start-ADTMsiProcess -AdditionalArgumentList`, preserving the released MSI defaults. |
| Handwritten uninstaller existence checks | Invoke the vendor uninstaller with `Start-ADTProcess`; missing executable and process failures use native error handling. An absent application is not promised to produce a successful manual uninstall. |
| Stock illustrative completion text becomes visible with Auto | Omit exactly the stock prompt block through the adapter's opt-in `-OmitCompletionPrompt` switch. No replacement prompt or custom UI is added. |
| Silent-only command examples and 1602 classified as failure | Use Auto consistently; classify native 1602 deferral as retry. Retain built-in 1618 retry without duplicate mappings. |
| 55-minute native welcome timeout inside a 60-minute Intune limit | Use 120 minutes in the effective publication profile, preview and manifest. Preserve PSADT configuration defaults. |

The sample application sections need only `Start-ADTMsiProcess`, `Start-ADTProcess`, `Write-ADTLogEntry` and `Close-ADTSession`, together with simple data assignments and interpolation. The opt-in native-command validation checks those snippets against the released function signatures. It is a conformance check for reviewed source, not a security sandbox. It does not restrict or rewrite PowerShell used by the upstream template, build scripts or independent Intune detection.

## Native process behavior and remaining limitations

The tagged 4.1.8 implementation, rather than contradictory portions of the frontend help, establishes Auto behavior:

- With the configured process list populated and none running, Auto becomes Silent.
- With a configured process running, Auto becomes Interactive when earlier session checks permit it.
- OOBE, detected active user ESP, and SYSTEM/session 0 without a suitable interactive user can select Silent before process evaluation.
- Mode selection occurs during initialization. It does not continuously reevaluate mode or block application relaunch.

[Tagged session implementation](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSADT/PSADT/Module/DeploymentSession.cs#L675-L838)

Installation retains three native deferrals, disk-space checking and prompt persistence. Uninstall retains the native 60-second close countdown. Silent fallback and a process started after mode selection can cause native forced closure; `PromptToSave` and `BlockExecution` are not enabled by these samples. These defaults do not promise preservation of unsaved work. [Released frontend](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Frontend/v4/Invoke-AppDeployToolkit.ps1), [welcome implementation](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Public/Show-ADTInstallationWelcome.ps1)

Only Install and Uninstall are advertised operations. Unsupported Repair still logs and exits 69001 using native functions. Its stock welcome executes first and can prompt or close processes; the implementation deliberately does not change dispatch, extensions or the framework to make Repair side-effect-free.

The requested Auto profile uses PSADT's built-in UI, without ServiceUI. Microsoft documents silent installation as the supported Intune model; native toolkit capability does not change that boundary. [Microsoft Win32 guidance](https://learn.microsoft.com/intune/app-management/deployment/win32)

The publication timeout is an engineering choice, not an endpoint performance result. `MaximumInstallationTimeInMinutes` accepts 1–1440 in the published module; 120 provides headroom beyond the stock 3,300-second welcome timeout. A future pilot must still measure complete elapsed time. Native deferrals return 1602 and prompt timeout returns 1618; Intune retries can consume the three deferrals over short intervals rather than days. [PSADT configuration](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Config/config.psd1), [published app-creation function](https://www.powershellgallery.com/packages/IntuneWin32App/1.5.0/Content/Public%5CAdd-IntuneWin32App.ps1), [Intune return codes](https://learn.microsoft.com/intune/app-management/deployment/add-win32)

Firefox's separate policy acceptance must confirm effective `DisableAppUpdate=true`, including already-installed machines whose version detection skips the package. The package neither merges JSON nor substitutes registry policy. Existing distribution content is preserved with the vendor MSI property `REMOVE_DISTRIBUTION_DIR=false`. [Mozilla policy](https://firefox-admin-docs.mozilla.org/reference/policies/disableappupdate/), [MSI properties](https://support.mozilla.org/en-US/kb/deploy-firefox-msi-installers)

## Contract and evidence

Native-v2 originally used recipe schema version 2; those inputs and their checks are now historical migration fixtures. Current sources use the [v3 application definition](Configuration-reference.md), which retains Auto, `template-default` deferrals, a 120-minute Intune limit, external policy prerequisites and `vendor-default` downgrade handling. Vendor-default does not mean the vendor supports a downgrade. The current discovery wrapper accepts v3 definitions, and the resolver/build bind one accepted release into generated metadata, standalone detection and frozen publication settings. Removed process/downgrade guarantees must not be reintroduced through configuration wording.

The adapter retains the stock completion prompt when `-OmitCompletionPrompt` is omitted. The named `official-4.1.8-native-v2` profile opts into its removal and native application-command validation; the v3 build deliberately retains that profile. It therefore does not prove strict stock-prompt preservation. Edits remain limited to approved metadata, designated task sections and that exact prompt block. The other 221 upstream files, including modules, configuration, extensions and launchers, remain unchanged; all 222 pristine files are rechecked. Installer/support staging adds declared payload files with separate hashes.

Follow the [walkthrough](Getting-started.md) for the current definition → resolver → build path. The builder creates internal `metadata.generated.json` and `actions.generated.json`; only `app.json` and referenced scripts are authored. New reference outputs use `generated-examples/psadt-4.1.8-config-v3/`. Earlier native-v2 outputs, migrated fixtures and JSON evidence remain historical records. Current results and exclusions appear in the [validation summary](../evidence/configuration-v3-validation.md); a previous passing run is not proof for changed scripts.

## Acceptance procedure

Offline checks cover supported PowerShell runtimes, definition validity, native-command/parameter conformance, exact Auto/process metadata, timeout/return-code consistency, preview isolation, release binding, permitted template differences and pristine integrity. Historical native-v2 detection hashes are preserved as compatibility evidence. The current authored sources are detection templates; generated detection versions are bound to the accepted release. General Pre/Main/Post coverage is separate from the two Main-only applications; Pre runs after welcome/progress and Post is sequential work, not guaranteed cleanup.

Before operational use, record the following on isolated Windows 11 x64 machines under SYSTEM with the packaged launcher:

| Scenario | Evidence required |
|---|---|
| No configured app running | Auto selects Silent; no stock illustrative prompt appears. |
| App running with usable user session | Native welcome appears; install deferral and user-driven closure behave as documented. |
| No user, locked session, OOBE/ESP | Record actual mode, UI availability and native process behavior; do not infer success from a hidden prompt. |
| Deferral, exhaustion and timeout | Capture 1602/1618, deferral state, elapsed time and future Intune retry behavior. |
| Process starts after initialization or relaunches | Record closure and installer behavior; no claim of continuous process protection. |
| Uninstall and missing uninstaller | Verify native countdown, vendor removal, retained user data and native failure on a missing executable. |
| Fresh, older, equal and newer installed version | Validate vendor behavior and independent detection; no wrapper downgrade guard is expected. |
| Unsupported Repair | Do not advertise it; record 69001 and the fact that welcome can precede failure. |
| Firefox configuration | Verify the separate Intune policy is effective and conflicting existing policy is resolved. |
| Notepad++ configuration | Verify updater omission and accepted Plugins Admin behavior; reject unapproved legacy-updater migration paths. |
| Installer failure and reboot codes | Capture failures, 3010/1641 handling, logs and post-install detection. |

Historical native-v2 examples contained no installer payloads. Current offline builds may stage explicitly marked fixture bytes; those fixtures are not approved installers and cannot be published. Passing offline checks does not establish real package creation, installation, upload, targeting or business acceptance. Release acceptance must retain actual endpoint, owner and prerequisite evidence for the exact artifact.
