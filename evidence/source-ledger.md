# Source ledger for the Intune lifecycle research

Inspection date: November 3, 2026 in America/Los_Angeles; UTC acquisition timestamps in JSON evidence can fall on November 4. This ledger distinguishes published artifacts from repository source and moving documentation. Local evidence records are authoritative for the bytes inspected; a website's current default branch is not a substitute for those bytes.

The native Auto revision uses the same pinned dependencies. Its decisions and reviewed changes are recorded in the [native sample review](../docs/Native-PSADT-review.md); current and historical test results are separated in the [validation summary](validation-results.md).

## Published artifacts and repository baselines

| Source | Version or immutable reference | Claim supported and evidence level |
|---|---|---|
| [PSADT release](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases/tag/4.1.8) and [release metadata](https://api.github.com/repos/PSAppDeployToolkit/PSAppDeployToolkit/releases/tags/4.1.8) | Tag `4.1.8`, commit `af17af7ad3e30a9fe7635cf063b7eebfc065c7de` | Published release exists. Dedicated v4 template asset, separate from v3 compatibility and source archives. Archive retrieved and SHA256 compared with release metadata. |
| [Official v4 template archive](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases/download/4.1.8/PSAppDeployToolkit_Template_v4.zip) | SHA256 `50cb8d32973fc7648060a48cad63912ecb5caca5a70754f37e83aa06bd380283` | Exact extracted template and toolkit used for offline population checks. File/signature inventory recorded locally. No launcher or installer executed. |
| [Evergreen Gallery package](https://www.powershellgallery.com/packages/Evergreen/2610.2859.0) | `2610.2859.0`; package SHA256 `366747bcdfc0cb19d7f3f3a7583d1e74a426b32c259e51c59a4a26ef1b9c7ffe` | Published manifest/functions inspected from downloaded archive without installing the module. Download validation gaps attributed to this package, not inferred from main. |
| [Evergreen default-branch snapshot](https://github.com/EUCPilots/evergreen-module/tree/56699ec976e77a8031f1d93fc8c5eda22ceae085) | Commit `56699ec976e77a8031f1d93fc8c5eda22ceae085` | Source comparison only. Same manifest version does not establish published parity; newer Save-EvergreenApp behavior differs. |
| [Evergreen application definitions](https://github.com/EUCPilots/evergreen-apps/releases/tag/v26.11.03.146) | Release `v26.11.03.146` | Separate executable-definition dependency, retrieved/hash-verified. Firefox and Notepad++ selection contracts inspected. |
| [IntuneWin32App Gallery package](https://www.powershellgallery.com/packages/IntuneWin32App/1.5.0) | `1.5.0`; package SHA256 `2cb7137ba5039981d35e43e3cfd7c75128cb37ce1ec1bbf5248376d42cfc738b` | Published functions inspected from downloaded archive without module installation, authentication or tenant access. |
| [IntuneWin32App source snapshot](https://github.com/MSEndpointMgr/IntuneWin32App/tree/cff3196000e5bab3943c6c1e1937f05817fd0908) | Commit `cff3196000e5bab3943c6c1e1937f05817fd0908` | Comparison/reference implementation; published bytes separately inspected before assigning release-specific findings. |
| [Microsoft Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/releases/tag/v1.8.7) | Release `v1.8.7`; PE file version `6.2509.50.0`; SHA256 `c1ba45b5cb939e84af064bb7ff4b38fb3dfe33c8dc1078fd9b157672eae671f6` | Downloaded executable has Valid Microsoft Authenticode signature. Windows runtime, packaging scope and executable provenance inspected. Utility not executed. |

Hashes computed locally establish artifact identity. For archives without a separately published expected hash, a local hash alone does not constitute independent publisher authentication. PSADT release metadata and Authenticode checks provide separate evidence where recorded.

## PSADT tagged implementation

All links in this section target 4.1.8. Current documentation may describe later releases; tagged inline help and implementation settle version-specific command behavior.

| Primary source | Supported claims |
|---|---|
| [README](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/README.md) | Supported runtime, v4.1 user-session UI architecture and ServiceUI changes. |
| [Module manifest](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/PSAppDeployToolkit.psd1) | Exact module version and PowerShell version requirement. |
| [New-ADTTemplate](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Public/New-ADTTemplate.ps1) | Distribution structure, copying, frontend transformations and customizable copies. |
| [v4 frontend](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Frontend/v4/Invoke-AppDeployToolkit.ps1) | Application metadata, designated action sections, parameter values, zero-config gating, framework exception handling. Exact released frontend bytes are separately inventoried. |
| [Launcher implementation](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSADT.Invoke/PSADT.Invoke/Invoke.cs) | PowerShell selection, launcher arguments, wait and exit-code behavior. |
| [Configuration](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Config/config.psd1) | MSI switches, log paths, defer/timeout codes and UI defaults. |
| [Start-ADTProcess](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Public/Start-ADTProcess.ps1) | Process arguments, exit handling, pass-through and session exit status. |
| [Start-ADTMsiProcess](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Public/Start-ADTMsiProcess.ps1) | Install/uninstall/repair API, MSI arguments and file resolution. |
| [Show-ADTInstallationWelcome](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSAppDeployToolkit/Public/Show-ADTInstallationWelcome.ps1) | Close/defer/deadline parameters and interaction with mode. |
| [DeploymentSession implementation](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/blob/4.1.8/src/PSADT/PSADT/Module/DeploymentSession.cs#L675-L838) | Auto becomes Silent when configured processes are absent; remaining Auto becomes Interactive. Earlier OOBE/ESP/no-user conditions can select Silent. Source-verified; contrary frontend-help wording is not used. Endpoint behavior remains untested. |
| [Published Add-IntuneWin32App](https://www.powershellgallery.com/packages/IntuneWin32App/1.5.0/Content/Public%5CAdd-IntuneWin32App.ps1) | `MaximumInstallationTimeInMinutes` is an integer, defaults to 60 and accepts 1–1440; the sample's 120-minute choice is source-valid, not a measured runtime result. ReturnCode appends to built-in mappings. |

## Microsoft service contracts

These are moving Microsoft Learn documents, fetched during this research. The service behavior they describe must be rechecked before operational rollout or module upgrades. Reading documentation is not a tenant compatibility test.

| Primary source | Supported claims |
|---|---|
| [Win32 app management](https://learn.microsoft.com/intune/app-management/deployment/win32) | Silent installation support boundary and managed endpoint prerequisites. |
| [Create a Win32 package](https://learn.microsoft.com/intune/app-management/deployment/create-win32-package) | Content Prep Tool inputs, included files and MSI metadata behavior. |
| [Add and assign Win32 applications](https://learn.microsoft.com/intune/app-management/deployment/add-win32) | Commands, contexts, requirements, detection stdout/stderr/exit contract, dependency and return-code behavior. |
| [Supersedence](https://learn.microsoft.com/intune/app-management/deployment/configure-win32-supersedence) | Relationships, targeting, available-app auto-update conditions and relationship limits. |
| [Troubleshooting](https://learn.microsoft.com/intune/app-management/deployment/troubleshoot-win32) | IME logs, collection and detection/installation troubleshooting. |
| [Create win32LobApp](https://learn.microsoft.com/graph/api/intune-apps-win32lobapp-create?view=graph-rest-1.0) | Delegated/application permission baseline for app creation. The inspected module itself uses beta endpoints. |
| [Assign mobileApp](https://learn.microsoft.com/graph/api/intune-shared-mobileapp-assign?view=graph-rest-beta) | Assignment API and permissions. |
| [Assignment-filter lookup](https://learn.microsoft.com/graph/api/intune-policyset-deviceandappmanagementassignmentfilter-list?view=graph-rest-beta) | Optional filter-read permissions. |
| [Role-scope-tag lookup](https://learn.microsoft.com/graph/api/intune-rbac-rolescopetag-list?view=graph-rest-beta) | Optional scope-tag lookup permissions. |

## Vendor and framework evidence

| Primary source | Supported claims |
|---|---|
| [Firefox Evergreen definition](https://github.com/EUCPilots/evergreen-apps/blob/v26.11.03.146/Apps/Get-MozillaFirefox.ps1) | Actual channel/language/architecture/type fields and checksum discovery. |
| [Notepad++ Evergreen definition](https://github.com/EUCPilots/evergreen-apps/blob/v26.11.03.146/Apps/Get-NotepadPlusPlus.ps1) | GitHub latest-release selection and absence of arbitrary channel/language output. |
| [Firefox MSI deployment](https://support.mozilla.org/en-US/kb/deploy-firefox-msi-installers) | EXE-wrapper nature of MSI, supported properties and unsupported uninstall/repair. |
| [Firefox silent uninstall](https://support.mozilla.org/en-US/kb/silently-install-uninstall-firefox-enterprise) | Vendor helper executable and `/S` uninstall argument. |
| [Mozilla DisableAppUpdate](https://firefox-admin-docs.mozilla.org/reference/policies/disableappupdate/) and [policy configuration](https://firefox-admin-docs.mozilla.org/guides/policies-configuration/) | Supported update policy and policy deployment forms. Separate Intune management is the user's selected design; no policy resource has been created or its effect tested. The older policy-template landing page directs readers to this administrator reference. |
| [Notepad++ command documentation](https://github.com/notepad-plus-plus/npp-usermanual/blob/master/content/docs/command-prompt.md) | Case-sensitive silent switch and updater/component consequences. Moving documentation; validate chosen installer version. |
| [IntuneAppFactory source](https://github.com/MSEndpointMgr/IntuneAppFactory/tree/632e04311326fffae1c1b75f26f994b9ca2fb5c9) | Checked-in v3 toolkit/layout, Azure/pipeline dependencies and population method. |
| [IntuneAppFactory v4 issue](https://github.com/MSEndpointMgr/IntuneAppFactory/issues/40) | Maintainer/community tracking of v4 compatibility; issue status is contextual, not proof of implementation. |
| [PSPackageFactory source](https://github.com/aaronparker/packagefactory/tree/4d807cb4c3f4d3f1fa25abb97dd58a5b444277be) | Mixed toolkit/template versions, packaging entry point and executable recipe filtering. |

## Evidence interpretation

Archive inspection, file hashing, Authenticode checks, AST parsing, schema checks and offline population tests establish specific local properties. They do not establish that an installer is currently trusted by an organization, that a deployed app works, that Conditional Access permits authentication, or that Graph uploads/assignments succeed. Consult the [validation results](validation-results.md) for executed checks and explicit exclusions.
