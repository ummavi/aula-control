# Development guide

## Source layout

`AulaCore` contains Foundation/IOKit device code and is also available as a Swift package library product. `AulaControl` is the SwiftUI application. UI display colors do not participate in protocol serialization.

| File or directory | Responsibility |
| --- | --- |
| `Sources/AulaCore/Lighting.swift` | RGB values, effect metadata, configuration fields, palette construction, and write order |
| `Sources/AulaCore/WirelessProtocol.swift` | Report framing, checksums, read assembly, and write retries |
| `Sources/AulaCore/HIDConnection.swift` | Device selection, input callback ownership, queues, reads, and writes |
| `Sources/AulaCore/KeyboardSnapshot.swift` | Device snapshots, decoded settings, LED mappings, and local backups |
| `Sources/AulaCore/KeyboardLighting.swift` | Main Apply and backup restoration with verification |
| `Sources/AulaCore/AuxiliaryLighting.swift` | Zone fields, changed-control merging, and auxiliary previews |
| `Sources/AulaCore/LightingPreview.swift` | Illustrative main-effect sampling and outline fade behavior |
| `Sources/AulaControl/AppModel.swift` | UI drafts, serialized device work, preset operations, and status updates |
| `Sources/AulaControl/Preset.swift` | Portable preset data |
| `Sources/AulaControl/Diagnostics.swift` | Offline and hardware command-line checks |
| `Sources/AulaControl/AppTheme.swift` | UI theme, display-color mapping, sliders, and color picker |
| `Sources/AulaControl/KeyboardPreview.swift` | Key layout, radial light rendering, and painting interaction |
| `Tests` | Hardware-independent protocol, recovery, preview, and preset tests |

The UI model captures the requested settings before dispatching work to its serial queue. On completion it replaces a draft only if that draft still matches the captured request. This prevents a completed Apply from discarding edits made while the transfer was running. Multi-zone Apply reports completed zones if a later zone fails.

HID input delivery uses a separate queue so synchronous output calls do not block their own acknowledgements. The report callback owns an independent inbox object. Cancellation completes before the callback context and report buffer are freed. Do not re-register the callback after activation or cancellation: IOKit asserts in that state.

## Build and offline checks

```sh
swift test
./scripts/build.sh
'build/AULA Control.app/Contents/MacOS/AulaControl' --help
'build/AULA Control.app/Contents/MacOS/AulaControl' --check-preset-format
'build/AULA Control.app/Contents/MacOS/AulaControl' --verify-previews
```

None of these commands needs a receiver or writes keyboard settings. The preview check renders the live SwiftUI/Canvas view and compares frames for static and animated effects. To save selected comparison frames, add `--output-dir .aula-local/preview-check`.

The formatter configuration is in `.swift-format`. With a toolchain that includes `swift format`:

```sh
swift format format --in-place --recursive Sources Tests Package.swift scripts/make-icon.swift
```

GitHub Actions is configured to build and test on Apple silicon and Intel macOS runners. Remote jobs require the project to be pushed to a GitHub repository; a local build does not establish that those jobs have passed. Runner labels follow GitHub's [hosted-runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

To regenerate the project-owned icon from its drawing script:

```sh
swift scripts/make-icon.swift "$PWD"
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

Fonts and third-party license files live in `Resources`. Preserve their notices when changing packaging or replacing assets.

## Rendering documentation images

```sh
mkdir -p docs/images
'build/AULA Control.app/Contents/MacOS/AulaControl' \
  --render-preview docs/images/lighting.png --demo
```

This renders an offline example without accessing the receiver or loading personal device data. For local investigation, use `--snapshot PATH` instead of `--demo` to render an existing backup. An unreadable or invalid snapshot fails the command rather than silently showing defaults. Optional `--zone sideStrips`, `--zone lightBar`, `--tab Presets`, and `--preview-paint` select other views.

## Reading real hardware

```sh
'build/AULA Control.app/Contents/MacOS/AulaControl' --diagnose
'build/AULA Control.app/Contents/MacOS/AulaControl' --check-ui-connection
```

These read device data without changing settings. `--diagnose` saves a local snapshot and prints its path with the home directory abbreviated to `~`. The UI connection check verifies the worker-queue read path and all 108 displayed LED mappings. Permission granted to a process launched from a terminal does not prove that a separately launched installed app has its own Input Monitoring grant.

`AULA_TRACE_HID=1` prints vendor reports to stderr. Logs can contain configuration and mapping data; inspect and redact them before sharing. Keep local captures under `.aula-local`, which is ignored by Git.

## Commands that write settings

```sh
'build/AULA Control.app/Contents/MacOS/AulaControl' --verify-hardware
'build/AULA Control.app/Contents/MacOS/AulaControl' --verify-ui
'build/AULA Control.app/Contents/MacOS/AulaControl' --restore-backup PATH
```

The first two temporarily change lighting and attempt to restore the saved state even after a test failure. They compare returned configuration and color data, not physical LED appearance. They require a connected supported keyboard and should be run deliberately on hardware available for testing. Restoration can itself fail if communication is interrupted; the pre-write snapshot remains available locally.

`--restore-backup` replaces the saved 128-byte configuration and color data, including auxiliary and other configuration fields. It does not restore or write key mappings. It rebuilds reserved palette bytes in the canonical OEM format. See [the protocol reference](PROTOCOL.md) for ordering and preservation guarantees.

## Preset format

Import and export use a single JSON object. The local preset library is an array of those objects. A preset contains:

| Field | Meaning |
| --- | --- |
| `id` | UUID; importing assigns a new local ID |
| `name` | Display name |
| `settings.effect` | Main wire effect ID |
| `settings.brightness` | 0–4; legacy imported values up to 9 are clamped to 4 |
| `settings.speed` | 0–4 |
| `settings.colorful` | Built-in multicolor selection |
| `settings.color` | Device RGB object with integer `r`, `g`, `b` channels, 0–255 |
| `settings.keys` | LED-index-to-RGB map; indices 0–125 |
| `auxiliary` | Optional `sideStrips` and `lightBar` settings |

Each auxiliary entry contains `effect`, `colorIndex`, `brightness`, and `speed`. Omitting `auxiliary` keeps older main-only presets readable and leaves auxiliary drafts alone when loading one. Import rejects files at or above 1 MB and settings outside the accepted ranges. The [example preset](../examples/green-reactive.json) contains no device dump or personal data.

Backups are internal `KeyboardSnapshot` objects containing configuration, palette, key map, identity, per-key colors, time, and optional battery status. They are not interchangeable with presets and should not be edited by hand. Their dates use Foundation's default JSON Date encoding.

## Protocol changes

Consult [PROTOCOL.md](PROTOCOL.md) and [VALIDATION.md](VALIDATION.md) before changing wire behavior. Preserve the backed-up state, change one hypothesis at a time, and compare native Fn operations where possible. Record physical observations separately from echoed packets and stored values. Do not generalize F99 or F108 Pro fields to this receiver solely because framing looks similar.
