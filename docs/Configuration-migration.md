# Migrate application configuration to v3

Use one `app.json` beside the editable application scripts. The current workflow generates PSADT metadata and the action mapping from that definition; it does not require a second authored `metadata.json` or `actions.json`.

For a new application, start with [Add an application](Add-application.md). For an existing v2 application, follow the steps below, then continue with [Prepare a release](Prepare-release.md).

## 1. Keep the executable scripts as the command source

Retain reviewed `Install.ps1`, `Uninstall.ps1`, and `Repair.ps1`. Installer arguments and the installed uninstaller path belong in these scripts.

The old recipe repeated commands that the template adapter did not read. When old recipe text and a script disagree, review the executable script and the vendor's supported behavior before approving the v3 definition. Do not silently merge conflicting strings or assume the old recipe controlled the generated deployment.

The build inserts these scripts into the template's declared task locations. It does not infer installer behavior from arbitrary PowerShell or generate competing install/uninstall commands.

## 2. Consolidate the authored fields

Create `app.json` using one of the current [Firefox](../examples/apps/firefox/app.json) or [Notepad++](../examples/apps/notepadplusplus/app.json) definitions.

| Earlier input | Current owner |
|---|---|
| `examples/recipes/<application>.json` | `examples/apps/<application>/app.json`, schema version 3 |
| `metadata.json`: vendor, name, architecture, language | Definition publisher, product name, and variant fields |
| `metadata.json`: package/script revisions, author, date, exit codes | Definition `toolkit` fields |
| `metadata.json`: `AppProcessesToClose` | Definition `deployment.processes`, mapped to native PSADT metadata |
| `metadata.json`: `AppVersion` | The accepted release; resolved metadata is generated |
| `actions.json` | Definition `actions`; paths are relative to the application directory |
| Recipe install/uninstall arguments | Editable application scripts only |
| Recipe installer filename | `payloads.installer.destination`; keep the script's payload reference consistent with this staging name |
| Frozen detection version | Generated from the accepted release through the detection template |

Keep fields that have different meanings: `productName` supplies PSADT's application name, while `displayName` is the Intune presentation name. Vendor version, recipe revision, package revision, and script revision are separate values.

Application scripts can use existing `Pre`, `Main`, and `Post` mappings. Each operation requires `Main`; `Pre` and `Post` are optional. A reviewed source file can be referenced by more than one location. It is snapshotted once and inserted at each declared location.

Native Pre work runs after the template's welcome/progress behavior. Post work is sequential application work, not guaranteed failure cleanup. The current optional native-command validator remains deliberately limited; consolidation does not expand its supported functions. See [the PSADT standard](PSADT-4.1.8-standard.md).

## 3. Convert the detection source

Keep the installed-product detection logic in `Detect.template.ps1`. Its version binding must be the supported top-level assignment:

```powershell
$MinimumVersion = [version]'__RESOLVED_VERSION__'
```

The resolver validates and substitutes this one literal from the accepted release. The build creates a standalone `Detect.ps1` outside the package source. It requires no PSADT module or recipe on the endpoint.

Current binding supports canonical numeric .NET versions with two to four components. Review a separate mapping before introducing vendor versions that do not match that contract. Bind before signing; changing a signed script invalidates its signature.

## 4. Validate and rebuild through the current workflow

Validate the v3 definition, resolve the accepted installer and release, preview the build, then create a fresh build directory. Follow the [step-by-step workflow](Getting-started.md) for commands.

Do not edit generated `Inputs/application/metadata.generated.json`, `actions.generated.json`, or the populated PSADT frontend. Change the authored definition or application script, resolve a new build, and keep the previous accepted artifacts.

Resolved records and build manifests are generated evidence. They preserve the selected version, hashes, effective settings, and implementation pins; they are not another configuration file to maintain manually. Application IDs, content versions, assignments, and observed deployment outcomes remain separate operational facts.

Schema v2 is not automatically converted or accepted by the current resolver. This avoids silent precedence rules when old recipe, metadata, and script values disagree.

## What changed in the supplied examples

The superseded recipe, metadata, action mapping, and frozen detector files were copied byte for byte into [legacy test fixtures](../tests/fixtures/legacy-v2/README.md), hash-verified, and removed from their active example locations. Their original and archived paths and SHA-256 hashes are recorded in the [migration manifest](../tests/fixtures/legacy-v2/migration-manifest.json). Historical evidence files were retained unchanged.

The old illustrative v2 build manifest is also retained in those fixtures. The active [build manifest reference](../examples/build-manifest.example.json) now points to the current schema and generator; it is deliberately not a consumable build record. A separate [operational state example](../examples/operational-record.example.json) shows where future tenant, assignment, approval, and observation data belong. Neither example claims that a build or tenant operation occurred.

Both current application build paths were verified with deliberately fake installer bytes before retiring the old inputs. At the original example versions, the generated PSADT frontends matched the recorded native-v2 hashes exactly. Detection templates preserve the prior detection logic, changing only the version comment and approved binding literal.

| Existing contract | Current regression coverage |
|---|---|
| Native process handling and sample action placement | Definition → resolved metadata → generated frontend AST; Main-only sample assertions |
| PSADT frontend behavior | Generated frontend SHA-256 compared with historical native-v2 evidence |
| Detection behavior | Historical detector hashes plus exact template/binding comparison |
| Auto commands, timeout, return codes, and setup entry point | Resolved build profile, retained legacy preview, and manifest-driven packaging preview |
| No accidental configuration payload or downgrade guarantee | Current definition and generated source checks |
| Reused action source | One frozen source snapshot inserted into multiple declared phases |

These checks exercise local parsing, generation, integrity, and preview behavior. They do not establish installer execution, real packaging, Intune publication, endpoint success, or business acceptance.

The current profile remains `official-4.1.8-native-v2`, including its explicit omission of the stock completion prompt. Strict preservation of that prompt is a separate profile change; this migration does not claim to implement it.
