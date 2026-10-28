# Privacy and security

AULA Control communicates locally with a supported USB HID receiver. It has no network listener, telemetry, cloud service, or update downloader. Input Monitoring permission allows macOS HID access; the input callback retains only vendor report `13` and discards normal keyboard input reports. The app does not record typed text.

Presets and pre-write snapshots are stored under `~/Library/Application Support/AULA Control`. Snapshots include configuration, device identity, LED colors, and the key matrix. Diagnostic tracing can print this data. These files are not uploaded automatically. Review and redact them before sharing; screenshots or the concise `--diagnose` output are usually sufficient for an initial report.

The receiver is opened without seizing normal typing. Apply requires a complete supported snapshot and a saved backup before its first write. The app does not write key mappings, macros, reset commands, or firmware. It validates packet checksums and returned data, but a transfer failure can leave only part of an operation completed. Backups and read-back are recovery tools, not a guarantee against every communication failure.

The bundled build script uses ad-hoc signing. It does not notarize the application, install it, or reset privacy permissions. A notarized distribution would require a maintainer's Developer ID workflow; no private signing material belongs in this repository.

## Reporting a vulnerability

If the hosting repository offers private vulnerability reporting in its Security tab, use that for sensitive reports. No separate private reporting address is configured in this source distribution. Otherwise, contact the repository maintainers to arrange a private channel before posting sensitive files or exploit details. Ordinary connection and lighting defects belong in the bug-report template.
