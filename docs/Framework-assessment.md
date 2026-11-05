# Existing framework assessment

Assessment date: November 3, 2026. These projects contain useful patterns, but neither inspected default branch is a verified drop-in implementation of the requested pristine PSADT 4.1.8 template-population approach. Version and path findings below come from source, not repository descriptions alone.

| Candidate | Inspected revision and actual integration | Recommendation |
|---|---|---|
| MSEndpointMgr/IntuneAppFactory | `632e04311326fffae1c1b75f26f994b9ca2fb5c9`; Evergreen and IntuneWin32App with Azure DevOps/Azure dependencies; checked-in PSADT engine declares **3.7.0**, using `AppDeployToolkit` and `Deploy-Application.*` layout | Reference architecture only; port the concepts into small manual operations, not the v3 scripts |
| aaronparker/packagefactory / PSPackageFactory | `4d807cb4c3f4d3f1fa25abb97dd58a5b444277be`; Evergreen, VcRedist, IntuneWin32App; bundled PSADT module declares **4.1.0**, while application template declares **3.9.3** and packaging retains v3 launcher assumptions | Reference patterns only; mixed layouts require explicit migration and regression tests before adoption |

## IntuneAppFactory

The checked-in engine identifies itself as version 3.7.0, and template validation explicitly expects `Source/AppDeployToolkit`, `Deploy-Application.exe`, `Deploy-Application.exe.config`, and `Deploy-Application.ps1`. Replacing just the toolkit directory with 4.1.8 would leave incompatible assumptions. [Engine source](https://github.com/MSEndpointMgr/IntuneAppFactory/blob/632e04311326fffae1c1b75f26f994b9ca2fb5c9/Templates/Framework/Source/AppDeployToolkit/AppDeployToolkitMain.ps1), [layout validation](https://github.com/MSEndpointMgr/IntuneAppFactory/blob/632e04311326fffae1c1b75f26f994b9ca2fb5c9/Scripts/Test-TemplatesFolder.ps1).

Its module bootstrap installs or updates Evergreen, IntuneWin32App, Az.Storage, Az.Resources and MSGraphRequest. Its scripts read Azure DevOps build variables and emit pipeline controls. These are unnecessary dependencies for the user's current manual stage. Its population script uses broad regex substitutions in scripts, which does not satisfy the required checked extension-point population method. [Module bootstrap](https://github.com/MSEndpointMgr/IntuneAppFactory/blob/632e04311326fffae1c1b75f26f994b9ca2fb5c9/Scripts/Install-Modules.ps1), [population source](https://github.com/MSEndpointMgr/IntuneAppFactory/blob/632e04311326fffae1c1b75f26f994b9ca2fb5c9/Scripts/Prepare-AppPackageFolder.ps1).

The open [v4.1.0 feature request #40](https://github.com/MSEndpointMgr/IntuneAppFactory/issues/40) supports treating v4 migration as unfinished, but an issue is not itself proof of runtime behavior. Reuse the separation of download, preparation, publish, assignments and archive operations. Reimplement those boundaries with explicit local paths, pinned tools and state, preserving the official v4.1.8 template.

## PSPackageFactory

The included PSADT module manifest says 4.1.0; `template/Source/Deploy-Application.ps1` is a v3.9.3 template. The main packager looks for `Invoke-AppDeployToolkit.ps1`, yet selects `Deploy-Application.exe` as setup entry. Its default toolkit path includes a `Toolkit` subdirectory absent from the inspected repository tree. These are concrete integration mismatches; compatibility cannot be established by the presence of a v4 module alone. [Module manifest](https://github.com/aaronparker/packagefactory/blob/4d807cb4c3f4d3f1fa25abb97dd58a5b444277be/PSAppDeployToolkit/PSAppDeployToolkit.psd1), [v3 template](https://github.com/aaronparker/packagefactory/blob/4d807cb4c3f4d3f1fa25abb97dd58a5b444277be/template/Source/Deploy-Application.ps1), [packager](https://github.com/aaronparker/packagefactory/blob/4d807cb4c3f4d3f1fa25abb97dd58a5b444277be/New-Win32Package.ps1).

The packager also evaluates recipe `Filter` strings with `Invoke-Expression`. Its version checks cast display versions to `[version]` and look for a GUID in app notes. Reuse identity markers, manifests, working/output separation and app-versus-update concepts, but replace executable configuration with typed selectors, arbitrary-version casts with explicit comparison policy, and version-only duplicate checks with build fingerprints. The current architecture should separate build from tenant reads and publication. [Identity/version checks](https://github.com/aaronparker/packagefactory/blob/4d807cb4c3f4d3f1fa25abb97dd58a5b444277be/New-Win32Package.psm1).

An old open [ServiceUI request #59](https://github.com/aaronparker/packagefactory/issues/59) dates to October 2024. It should not drive a 4.1.8 design; use the actual 4.1.8 implementation and its cross-session UI capabilities. Likewise, historical issue claims about bundled versions or vulnerabilities must be checked against the inspected revision rather than repeated as current facts.

## Compatibility work if either is reconsidered

1. Replace v3 template/launcher/path assumptions with the exact official 4.1.8 deployment distribution, leaving upstream framework files pristine.
2. Replace broad substitution with the checked metadata/section population adapter; migrate each app's commands and validate 4.1.8 parameter names.
3. Pin published modules and the independently versioned Evergreen definitions. Validate actual archives rather than equating default-branch manifests with released code.
4. Split offline build, read-only planning, unassigned publication and assignments. Add persisted operation state, duplicate reconciliation, retries and immutable artifacts.
5. Rework detection, return codes, running-app behavior, update-only requirements and self-updater policy, then complete representative endpoint tests.

This is more work than borrowing a few patterns while implementing the user's small manual workflow. No Azure infrastructure, pipeline, or commercial packaging system is required for that starting point.
