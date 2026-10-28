# Changelog

## 1.4.3 — unreleased

- Prepare the project for public source distribution under MIT with project-level attribution.
- Replace the personal application identifier with `org.aulacontrol.AulaControl`.
- Separate transport, snapshot, lighting-operation, wire-format, preset, and diagnostic code.
- Document supported hardware, protocol offsets, preservation guarantees, color presentation, troubleshooting, and validation limits.
- Make preview verification independent of hardware and remove fixed local capture directories.
- Add tests for display/device color separation and backward-compatible presets.
- Add macOS CI, issue templates, release packaging, and source-only packaging.
- Read the displayed version from bundle metadata and strip debugging symbols containing local paths from release executables.

## Earlier development

The initial implementation added main effects, preset storage, per-key painting, and radio report handling. Subsequent development corrected palette layout and transfer lengths, improved input buffering and retries, added independent auxiliary zones, and adopted configuration-before-palette ordering for built-in main lighting.

Color testing established the difference between pastel RGB mixtures and the seven full-scale device colors. The interface now uses one softer display palette for swatches and preview lighting while preserving exact RGB values in device writes and saved presets. Earlier private build versions are not represented as published releases here.
