# Contributing

AULA Control currently targets the plain F108 through its 2.4 GHz receiver. Reports from other units are useful, but shared USB IDs alone do not establish compatibility. Start with the [protocol reference](docs/PROTOCOL.md), [source guide](docs/DEVELOPMENT.md), and [validation limits](docs/VALIDATION.md).

## Development

Build on macOS with Swift 5.9 or later:

```sh
swift test
./scripts/build.sh
'build/AULA Control.app/Contents/MacOS/AulaControl' --verify-previews
```

These checks do not require hardware or alter keyboard settings. Format Swift with the repository's `.swift-format` configuration when your toolchain includes `swift format`. Keep changes focused and explain the observed problem, resulting behavior, and validation in the pull request.

Tests should exercise meaningful behavior: dropped packets, inconsistent snapshots, field preservation, color-data separation, or file-format compatibility. Avoid assertions that only repeat constants from the implementation.

## Hardware and protocol work

Use deliberate, bounded experiments on hardware available for testing. Read and back up the complete configuration before writing. Preserve unrelated fields and key mappings. Identify the keyboard model, receiver IDs, firmware identity, connection mode, command bytes, expected change, and returned difference.

Record physical LED behavior separately from the app preview, packet echoes, and read-back. Compare one change at a time, and use native Fn operations as a reference where possible. A matching snapshot does not prove that the active lighting changed. Claims about new models need device-specific evidence rather than assumptions copied from F99 or F108 Pro sources.

Keep raw captures outside tracked files. `.aula-local` is ignored for this purpose. If a small fixture is needed, construct or sanitize it and explain which properties it represents. Do not commit personal presets, complete device dumps, proprietary driver binaries, or copied manual PDFs.

## Interface changes

Preserve the [design rules](docs/STYLE.md): black surfaces, square controls, radial lighting beneath flat key faces, and persistent neutral borders. Device RGB and display colors have separate roles. Verify that a visual change does not change the value sent to the keyboard or saved in a preset.

## Bug reports

Use the issue template and include reproducible steps, exact model/version information, the lighting zone, selected controls, error text, and visible hardware behavior. Read-only `--diagnose` output is usually enough to start. Redact personal paths and avoid posting raw backups or a preset library unless a specific sanitized fixture is needed.

## License and attribution

Contributions to project code are under the [MIT license](LICENSE). Preserve third-party notices and identify the source and license of any added assets or substantial borrowed code. The project uses a neutral bundle identifier and project-level attribution; do not introduce maintainer-specific paths, account names, or signing identities into shared files.
