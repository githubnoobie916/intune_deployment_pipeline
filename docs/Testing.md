# Test a prepared application release

[Walkthrough](Getting-started.md) · [Prepare a release](Prepare-release.md)

Use this page after `Build-Application.ps1` creates a complete build manifest, Source directory and standalone `Detect.ps1`. These procedures change the **test endpoint**. Do not run the generated launcher or application snippets on the packaging workstation. Offline fixture builds cannot establish acceptance or become publishable.

## 1. Prepare the lab and evidence

1. Use disposable Windows 11 x64 machines with snapshots and representative application versions.
2. Load `Build\build-manifest.json`; record its content-based `buildId`, `sourceFolder`, source inventory and `detection.path`/hash. The random workspace directory name is not the release identity.
3. If detection signing is required, sign a **separate copy of the generated, version-bound detector** using your approved infrastructure. Keep the unsigned original unchanged. Test the final signed copy and endpoint publisher trust; retain both hashes.
4. Copy the complete recorded Source directory to `C:\Lab\Application` on the VM. Copy the chosen final detection artifact to `C:\Lab\Detect.ps1` and verify the copied hashes. Keep evidence outside Source.
5. Record the device, OS build, initial app version, user/session state, build ID, operator, and expected result.

The current build contract does not include a stage for signing or editing the generated PSADT deployment script after generation. Packaging rejects such inventory changes. If policy requires that additional signing, resolve the workflow requirement before deployment; do not hand-edit manifests or weaken integrity checks. Upstream toolkit files remain unchanged. [Signing context](PSADT-4.1.8-standard.md#entry-points-prerequisites-and-runtime-behavior).

Use an approved SYSTEM execution method. If permitted, obtain PsExec from [Microsoft Sysinternals](https://learn.microsoft.com/sysinternals/downloads/psexec), review its license and signature, and place the approved executable at `C:\Tools\PsExec64.exe` on the VM. It is a **lab tool**, not a package payload. Open an elevated 64-bit Windows PowerShell 5.1 console on that VM.

The following local PsExec examples use `-s` for SYSTEM and `-w` for the working directory. They omit `-i` so the test does not force the launcher into the user's desktop. This is still a local test, not proof of Intune Management Extension behavior.

## 2. Record initial detection

From that elevated VM console:

```powershell
& 'C:\Tools\PsExec64.exe' -s `
    'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
    -NoProfile -File 'C:\Lab\Detect.ps1'
$initialDetectionExitCode = $LASTEXITCODE
```

Use your approved execution policy/signing setup if the script is blocked. The supplied detection scripts return 0 with output when detected and 1 without output otherwise. They deliberately exit; never dot-source them.

**Record:** output, exit code, expected installed identity, and whether the result matches the machine's starting state. A custom detection script must be tested under the same 64-bit SYSTEM assumptions used by the publisher.

## 3. Test installation

**Executes the application installer on the VM:**

```powershell
& 'C:\Tools\PsExec64.exe' -s -w 'C:\Lab\Application' `
    'C:\Lab\Application\Invoke-AppDeployToolkit.exe' `
    -DeploymentType Install -DeployMode Auto
$installExitCode = $LASTEXITCODE
```

Repeat detection after installation, check the actual installed version/architecture, and exercise representative application functions. Record reboot handling and confirm the vendor installer did not require interaction.

The stock PSADT welcome handles the configured process list. Auto may show prompts, allow deferrals, or close applications depending on the native session/process state. [Exact behavior and limits](Native-PSADT-review.md#native-process-behavior-and-remaining-limitations).

## 4. Test removal independently

Restore the appropriate snapshot or use the accepted installed state. **Executes the vendor uninstaller:**

```powershell
& 'C:\Tools\PsExec64.exe' -s -w 'C:\Lab\Application' `
    'C:\Lab\Application\Invoke-AppDeployToolkit.exe' `
    -DeploymentType Uninstall -DeployMode Auto
$uninstallExitCode = $LASTEXITCODE
```

Repeat detection and check retained user data and removed components against the application's expected behavior. A missing uninstaller follows native failure handling in the supplied samples.

Firefox and Notepad++ do not advertise Repair. Their Repair Main action returns 69001 after the stock welcome; it is not a harmless validation command.

## 5. Complete the scenario checklist

| Scenario | Capture |
|---|---|
| Fresh install and supported upgrade | Installer outcome, correct version, detection, and application functionality |
| Already current or newer | Detection result; direct-launch vendor behavior is a separate test because there is no downgrade guard |
| Application running; process starts/relaunches during deployment | Actual prompts/closure, deferral, unsaved-work impact, and installer outcome |
| No signed-in user; locked session; relevant enrollment scenario | Native mode and actual completion; local PsExec does not reproduce every IME/ESP condition |
| Deferral exhaustion, timeout, failure, and reboot | Actual 1602/1618/failure/3010/1641 behavior where applicable |
| Uninstall and missing uninstaller | Removal result, detection, retained data, and native failure behavior |
| Wrong architecture, language, channel, or partial install | Detection/applicability rejects the unintended state |
| Update ownership and required configuration | Effective Firefox external policy or accepted Notepad++ updater/component state |
| Business workflows | Named application owner accepts required functions |

Restore clean snapshots between incompatible scenarios. Use a later Intune pilot to test delivery, retry timing, enrollment, and Company Portal behavior. [Full acceptance procedure](Native-PSADT-review.md#acceptance-procedure).

## 6. Retain results and bind acceptance

Store the following under `$releaseRoot\Evidence`:

- Build manifest, source-file inventory/hashes, final detection SHA256, installer identity/signature/hash evidence, and dependency pins.
- Scenario results, observed exit codes, screenshots where useful, and relevant logs.
- PSADT logs from the configured path (default `%WinDir%\Logs\Software`), vendor logs, and later IME logs.
- Test limitations or excluded scenarios with reasons, application-owner acceptance, and operator/date.

Have the packaging engineer approve applicable technical scenarios and the application owner approve business functionality. Record external-policy and other prerequisite decisions separately. Changes to deployment sources, payloads or detection logic require a new reviewed build; changes to the signed detection artifact require new final-hash acceptance and relevant trust checks. Retain prior evidence.

After packaging, `Package\package-manifest.json` binds the `.intunewin` hash, tested build, frozen publication settings, detection and packaging-tool provenance. Follow [publication preparation](Publish-and-rollout.md#3-record-actual-acceptance) to complete `Evidence\release-acceptance.json`. It matches the application/build/package/final detection hashes and references named, dated endpoint/business and prerequisite reports by file hash.

The pending [acceptance example](../examples/release-acceptance.example.json) is not an approval. Evidence hashes and record hashes detect mismatches; they do not authenticate a reviewer or prove that testing happened. An operator must review the actual reports. Preparation rejects incomplete or mismatched supplied evidence; fixture packages are always unready.

> The project's chosen Auto profile can display UI. Microsoft documents silent installation as the supported Intune model. Successful local UI tests do not change that support boundary. [Microsoft Win32 guidance](https://learn.microsoft.com/intune/app-management/deployment/add-win32#step-2-program).

## Offline repository checks

These checks run on the build workstation; they do not install either application. Run PowerShell suites in fresh processes because tests define isolated module/network sentinels.

| Checks | Scope |
|---|---|
| `Test-ApplicationDefinitionSchema.ps1` | Definitions, discovery/evidence shapes and rejected values; requires a draft 2020-12-compatible PowerShell 7 validator |
| `Test-ApplicationCore.ps1`, `Test-ApplicationDiscovery.ps1`, `Test-ApplicationResolver.ps1` | Canonical identities, mocked discovery, local evidence and resolution boundaries |
| `Test-ApplicationIdentityScope.ps1`, `Test-CrossRuntimeRecords.ps1` | Identity sensitivity/invariance, source-drift rejection, and PS5/PS7 exchange of retained records |
| `Test-DetectionBinding.ps1` | Permitted version-literal edits, source preservation and invalid binding rejection |
| `Test-TemplatePopulation.ps1`, `Test-TemplateHooks.ps1`, `Test-ApplicationBuild.ps1` | Pristine template integrity, all nine task locations, staging, source drift and immutable build records |
| `Test-ManifestPackaging.ps1`, `Test-ApplicationPublication.ps1`, `Test-ExamplePreviews.ps1` | Mocked execution, frozen settings, acceptance, signing-copy checks, duplicate prevention and preview isolation |
| `Test-NativeExampleContract.ps1`, `Test-ReferenceSyntax.ps1` | Active sample contracts and source/document syntax |
| `Test-Documentation.ps1` | README, agent guidance and documentation local link targets plus PowerShell block parsing; does not validate external links or Markdown anchors |

Use Windows PowerShell 5.1 and PowerShell 7 separately for runtime-compatible suites. Run schema checks in PowerShell 7. See [setup](Setup.md) for dependency and execution-policy prerequisites; a blocked/skipped check is not a pass.

Actual Content Prep execution, cryptographic signing with real certificates, isolated endpoint scenarios and live Intune pilots need separate evidence. Mocked tests establish none of those outcomes.

[Return to the walkthrough](Getting-started.md) · [Publish and roll out](Publish-and-rollout.md)
