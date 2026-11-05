# Retired v2 fixtures

These files are byte-for-byte copies of retired example configuration and frozen detection sources. They support historical hash and migration regression checks; they are not active application definitions or runnable release bundles.

The [migration manifest](migration-manifest.json) records each original path, archived path, and SHA-256 hash. Original historical evidence remains under [`evidence`](../../../evidence).

The archived [v2 build manifest](build-manifest.example.json) remains an unperformed illustration. Legacy preview tests retain its command/timeout/return-code comparisons; the current builder uses the v1 generated-record schema instead.

Use [`examples/apps`](../../../examples/apps) for current `app.json` definitions and editable PowerShell scripts. See [Configuration migration](../../../docs/Configuration-migration.md) for field ownership and migration steps.
