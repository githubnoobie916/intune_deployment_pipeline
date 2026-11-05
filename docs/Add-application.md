# Add an application

[Walkthrough](Getting-started.md) · [Configuration reference](Configuration-reference.md) · [Prepare a release](Prepare-release.md)

Create one version 3 application definition and its editable sources. Adding a definition does not establish installer correctness, endpoint acceptance or permission to publish.

## 1. Copy a starting application

Run from the repository root in a supported 64-bit PowerShell session. Choose a new folder and stable application ID; keep the supplied examples unchanged.

```powershell
$repo = (Get-Location).Path
$app = 'myapp'
$appFolder = Join-Path $repo "examples\apps\$app"
if (Test-Path -LiteralPath $appFolder) {
    throw 'Choose a new application folder or review the existing definition.'
}
Copy-Item -LiteralPath (Join-Path $repo 'examples\apps\notepadplusplus') `
    -Destination $appFolder -Recurse
```

The authored files are:

```text
examples/apps/myapp/
  app.json
  Install.ps1
  Uninstall.ps1
  Repair.ps1
  Detect.template.ps1
```

Replace all copied product assumptions. Firefox's MSI is an EXE wrapper; its vendor uninstaller and unsupported repair behavior are not general MSI guidance. [Application-specific details](Worked-examples.md).

## 2. Set application settings once

Edit `app.json`, retaining `schemaVersion: 3`. The [configuration reference](Configuration-reference.md) defines every supported field and its consumer.

| Fields | What to author |
|---|---|
| `id`, `publisher`, `productName`, `displayName`, `description` | Stable identity, PSADT product metadata and a distinct portal display name. |
| `ownership` | Owning team/contact and definition revision. |
| `variant` | Edition, channel, language, x64 architecture and installer type. Normal discovery uses `versionPolicy: "latest"` with `targetVersion: null`. |
| `source` | Pinned Evergreen application and explicit selection/parameter mappings to `variant`. Use supported selection constants only. |
| `validation` | Approved hosts, checksum/signature requirements, approved signer subjects, expected product name and MSI properties to inspect. |
| `toolkit` | Pinned toolkit/profile, package revision, script version/date/author and toolkit exit-code handling. These are separate from the discovered application version. |
| `deployment.processes` | The single process list mapped to native `AppProcessesToClose`; names omit `.exe`. |
| `actions` | Relative paths to Install/Uninstall/Repair task snippets. |
| `payloads` | Installer filename under `Files`, plus reviewed support sources and destinations under `SupportFiles`. |
| `detection` | Detection-template path and the supported version-binding/signature settings. |
| `intune` | Supported requirements, result-code classifications and installation timeout. Launcher commands are derived. |
| Prerequisites, `targets`, `update` | Required external work and rollout intent. These fields do not create policies, dependencies or assignments. |

The supported profile is Windows 11 x64, SYSTEM, `Auto`, PSADT 4.1.8 and `official-4.1.8-native-v2`. Unsupported alternatives fail validation. Keep dependency upgrades and new deployment profiles as separate changes.

For example, author processes only here:

```json
"processes": [
  { "name": "myapp", "description": "My Application" }
]
```

Use an empty array when appropriate. Do not create editable `metadata.json` or `actions.json` files alongside `app.json`; the build generates its adapter inputs. Do not add installer arguments or installed uninstaller paths to JSON.

## 3. Edit the commands and task locations

`Install.ps1` owns installer arguments and application installation steps. `Uninstall.ps1` owns the verified uninstall method and installed executable path. The current profile retains explicit unsupported Repair, returning `69001` after native welcome behavior.

Keep the payload alias consistent with the script: if `payloads.installer.destination` is `MyApp.msi`, installation reads that file from `$adtSession.DirFiles`. Support data uses declared destinations under `$adtSession.DirSupportFiles`. Payload declarations stage files; action scripts perform configuration changes.

The action map lives inside `app.json`:

```json
"actions": {
  "Install": { "Main": "Install.ps1" },
  "Uninstall": { "Main": "Uninstall.ps1" },
  "Repair": { "Main": "Repair.ps1" }
}
```

Each operation requires `Main` and may add `Pre` and `Post` paths relative to `app.json`, for example `"Pre": "Pre-Install.ps1"`. Native Pre tasks run **after** the template's welcome/progress calls. Post is sequential application work; it is not guaranteed cleanup after a failure or session exit. The supplied Firefox and Notepad++ examples intentionally use Main only.

The current build enables the adapter's native-command validator. It supports `Start-ADTMsiProcess`, `Start-ADTProcess`, `Write-ADTLogEntry` and `Close-ADTSession`, plus limited assignments and interpolation. Validation is per snippet and is not a sandbox or a general PSADT capability list. Additional functions require a separately reviewed validator extension.

Retain native process handling and framework initialization, dispatch, deferrals, error handling and shutdown. The named compatibility profile omits only the stock illustrative completion prompt; the low-level adapter's default retains it. [Template contract](PSADT-4.1.8-standard.md) · [Native behavior](Native-PSADT-review.md).

Never execute snippets directly on the packaging workstation. Endpoint tests use the complete generated deployment on isolated machines.

## 4. Write the standalone detection template

Edit `Detect.template.ps1` to verify the actual installed product, architecture, version and any relevant channel/language identity. It must remain independent of PSADT and pipeline state.

Retain one plain top-level version assignment:

```powershell
$MinimumVersion = [version]'__RESOLVED_VERSION__'
```

This is a source placeholder, not a detection script ready for an endpoint. Resolution binds the reviewed release version; building writes standalone `Detect.ps1`. Do not manually replace the placeholder for each release or edit generated detection afterward.

The initial binder supports canonical numeric .NET versions with two to four components. Other vendor formats require a separately reviewed mapping. A vendor release number is not automatically the installed executable's file version; verify the comparison during endpoint acceptance.

Successful Intune detection emits nonempty output and exits `0`; not-detected exits `1` without success output. Test absent, incomplete, older, matching and newer installations. Use a child process for detection tests because the script exits. Keep editable sources in valid UTF-8; the build emits detection with a BOM for Windows PowerShell.

## 5. Review and validate

The v3 reader performs schema and semantic checks; those checks do not prove executable application behavior. Configure an independently approved signer policy and inspect the installer rather than copying identity assumptions from discovery.

Record required application or external-policy work in the definition. For example, Firefox's `DisableAppUpdate` policy is managed separately through Intune, including machines whose installed version causes detection to skip deployment. Publication preparation requires evidence for declared prerequisites; the build does not deploy them.

Add application-specific tests alongside the general schema, resolver, detection-binding and template-hook tests. Run checks in fresh processes; keep PowerShell 5.1 and 7 results distinct. Then follow [Prepare a release](Prepare-release.md) to discover, validate and resolve one version.
