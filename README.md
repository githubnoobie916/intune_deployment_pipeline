# Manual Intune application lifecycle

Discover Windows application releases with Evergreen, generate deployments from the official PSAppDeployToolkit (PSADT) 4.1.8 template, and prepare Intune packages and unassigned publication requests.

**Start here: [Step-by-step walkthrough](docs/Getting-started.md).**

Each application has one authored `app.json` and editable PowerShell actions. The local resolver binds a reviewed release to deployment metadata and standalone detection; build and publication records carry those settings forward. This is a manual engineering workflow, not a production lifecycle service. Actual packaging, endpoint installation, signing trust and live Intune operations require separate evidence; see [validation results](evidence/configuration-v3-validation.md).

## Documentation

| I want to… | Read |
|---|---|
| Follow one release through the workflow | [Step-by-step walkthrough](docs/Getting-started.md) |
| Restore the pinned dependencies | [Workstation setup](docs/Setup.md) |
| Add or change an application | [Add an application](docs/Add-application.md) |
| Understand fields, records and supported behavior | [Configuration reference](docs/Configuration-reference.md) |
| Discover and validate a local installer | [Prepare a release](docs/Prepare-release.md) |
| Test the exact deployment and detection | [Endpoint testing](docs/Testing.md) |
| Publish, assign a pilot and promote | [Publish and roll out](docs/Publish-and-rollout.md) |
| Resolve a failed step | [Troubleshooting](docs/Troubleshooting.md) |

## Included applications

| Application | Authored definition | Editable actions and detection template |
|---|---|---|
| Firefox x64 en-US MSI | [app.json](examples/apps/firefox/app.json) | [Application files](examples/apps/firefox/) |
| Notepad++ x64 EXE | [app.json](examples/apps/notepadplusplus/app.json) | [Application files](examples/apps/notepadplusplus/) |

Installer arguments and uninstaller paths belong only in the action scripts. `app.json` owns the process list, payload destinations, metadata and publication settings. Generated metadata/action maps and release-bound `Detect.ps1` files are build outputs.

Both applications retain SYSTEM deployment, native `AppProcessesToClose`, `DeployMode Auto` and the named native-v2 compatibility profile, which omits the stock illustrative completion prompt. Firefox update policy remains separately managed through Intune. Real installer payloads are not distributed with this repository.

Local v3 reference outputs belong under the ignored `generated-examples/psadt-4.1.8-config-v3/` directory. Earlier native-v2 outputs and evidence are historical records, not proof for regenerated artifacts.

## Runtime and boundaries

Use 64-bit Windows PowerShell 5.1 or PowerShell 7.5+ for local orchestration. Windows PowerShell also requires installed `pwsh.exe` 7.5+ for the JSON Schema validation helper. The inspected pins remain PSADT 4.1.8, Evergreen 2610.2859.0 with definitions v26.11.03.146, IntuneWin32App 1.5.0 and Content Prep Tool v1.8.7; they are not claims about the latest versions.

Discovery contacts vendor services. Resolution and publication-request preparation read local inputs. Build, packaging and publication default to preview; their `-Execute` paths have different effects. Publication creates an unassigned app; targeting is separate. See [execution boundaries](docs/Getting-started.md#execution-boundaries).

Keep build work, packages, locks and operational records on nonsynchronized storage such as `C:\IntuneLifecycle`. Credentials and signing keys stay outside application definitions and artifacts.

## Reference material

- [Engineering report](docs/Engineering-report.md) — architecture, responsibilities and remaining roadmap.
- [Configuration consolidation plan](docs/Configuration-consolidation-plan.md) — migration design and acceptance criteria.
- [PSADT standard](docs/PSADT-4.1.8-standard.md) — template integrity and permitted edits.
- [Worked examples](docs/Worked-examples.md) — application-specific behavior.
- [Intune operations](docs/Intune-operations.md) — authentication and lifecycle boundaries.
- [Native PSADT review](docs/Native-PSADT-review.md), [framework assessment](docs/Framework-assessment.md) and [source ledger](evidence/source-ledger.md).
