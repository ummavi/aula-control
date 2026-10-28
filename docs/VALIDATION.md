# Validation and limits

The implementation was developed against one plain F108 through receiver `3554:FA09`, identity prefix `03 00 00 00 01 BA`. This is evidence for that device and format, not a compatibility claim for every receiver sharing those IDs.

## Automated coverage

Offline tests cover report checksums, invalid and missing pages, duplicate handling, consistency across retries, repeated writes after lost echoes, stop-on-failure behavior, field ranges, and preservation of unrelated configuration bytes. They also check palette reserved regions and per-effect offsets, the 378-byte per-key plane layout, Apply/restoration order, auxiliary changed-control merging, preset compatibility, animated sampling, and fades into neutral key borders.

Application tests check that display swatches select the verified device RGB values, share their presentation colors with the preview, fade monotonically to black, and transition continuously through the spectrum. Preset tests ensure UI presentation colors never replace stored device RGB and that older main-only presets remain readable.

`--verify-previews` compares frames of the live UI without receiver access. Unit tests and preview checks cannot measure the keyboard's physical color or establish radio reliability on another setup.

## Physical checks recorded during development

| Behavior | Evidence and scope |
| --- | --- |
| Native effect control | Fn + backslash changed styles and the effect field |
| Main Solid colors | Custom red, green, and blue visibly changed |
| Main brightness | Zero turned the main lighting off; maximum green was visibly bright |
| Breathing and Rainbow | Green breathing and moving rainbow were observed |
| Reactive color | Changing only RGB from `A6F2BA` to `00FF00` produced green at the same effect, selector, brightness, speed, and transfer order |
| Per-key painting | Green keys with red W/A/S/D were observed |
| Seven standard RGB colors | Per-key red, green, blue, yellow, magenta, cyan, and white were observed together and confirmed |
| Mixed-color comparison | Pure green in the typing area and `A6F2BA` on the numpad reproduced the color difference simultaneously; the mixed color was later identified as white rather than pink/purple |
| Side strips | Solid red/green, color cycling, moving colors, and Off were observed |
| Light bar | Solid red/blue, moving colors, color cycling, Breathing, and Off were observed |
| Auxiliary parameter fields | Native Fn changes identified brightness and speed offsets separately |
| Cross-zone preservation | Main Apply retained visible red side strips and a blue bar while unrelated configuration and mapping data matched |

These observations were recorded separately from receiver snapshots. No colorimeter, calibrated camera measurement, or exhaustive speed/brightness response curve was used. Appearance of every built-in animated mode has not been individually checked. The displayed battery percentage is only available when the receiver sends a recognized status report.

## OEM comparison

The official plain F108 driver package inspected during development was `AULA F108 Setup v2.0 20241008.exe`. Its configuration file matched the receiver identity and model. The extracted `OemDrv.exe` SHA-256 was `92821d43a829b3c44e9120f67f20bacd44763fdfd1d01c948161323a477ee279`.

Inspection established the generic configuration table, RGB row layout, channel indices, palette marker position, exact per-key transfer length, and configuration-before-palette Apply order. Selected OEM x86 serializer routines were also executed offline with USB calls replaced by capture stubs. For the captured input used in that check, the 128-byte configuration, 512-byte palette, and 47 configuration/palette reports matched the app's generated data exactly.

This was a comparison of selected serialization routines, not execution of the entire Windows application or proof that arbitrary RGB values have a calibrated physical appearance. The copyrighted executable and temporary development captures are not part of this repository.

## Known limits

- F108 Pro, Bluetooth configuration, wired configuration, macros, and firmware updates are not implemented.
- Other firmware revisions may differ even when USB IDs match.
- The preview is illustrative and uses a shared UI display palette rather than literal device RGB.
- Receiver echoes and returned settings do not confirm visible LED appearance.
- Intermediate RGB mixtures can look substantially different from their screen appearance.
- Palette restoration rebuilds reserved regions instead of promising byte-for-byte restoration of invalid padding.
- The connection label is based on the last successful read.
- Locally ad-hoc signed updates can require a new Input Monitoring grant.
- Intel CI is configured, but its first remote run remains to be verified after publication.

## Local 1.4.3 release preparation

The local preparation run passed 30 tests: 24 core tests and 6 application tests. The release bundle built and passed strict code-signature verification. Offline live-preview verification passed for Solid and all 17 animated main effects. The documentation screenshot was generated from offline demo settings and visually inspected.

The source ZIP was extracted into a fresh directory, where all tests, the bundle build, and the preset-format diagnostic passed. The binary ZIP was extracted separately; its signature and preset diagnostic also passed. Scans found no remaining developer account name or absolute home-directory path in the public files, packaged executable, or either ZIP's file contents. Local documentation links and Swift formatting checks passed.

This cleanup did not rerun hardware-writing diagnostics or change the installed app, keyboard settings, or privacy grants. Hardware observations above remain the earlier development evidence. Hosted CI and Intel execution have not run as part of this local preparation.
