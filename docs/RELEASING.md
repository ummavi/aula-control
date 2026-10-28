# Release guide

The source tree is prepared for an MIT-licensed release. These scripts produce local artifacts; they do not create a remote repository, push commits, or publish a release.

## Validate

```sh
swift test
./scripts/build.sh
'build/AULA Control.app/Contents/MacOS/AulaControl' --check-preset-format
'build/AULA Control.app/Contents/MacOS/AulaControl' --verify-previews
```

Review [validation coverage](VALIDATION.md) before writing release claims. Offline tests establish protocol and preview behavior, not the physical behavior of every keyboard or effect. GitHub Actions checks both configured macOS architectures after the repository is hosted; until those jobs run, report Intel support as unverified.

The version and build number live in `Resources/Info.plist`; the interface reads its displayed version from the bundle. The neutral bundle identifier is `org.aulacontrol.AulaControl`. Changing the bundle identifier or ad-hoc code signature can require a new Input Monitoring grant. Keep the installed app stable while testing permissions.

## Package

```sh
./scripts/package-release.sh
python3 scripts/package-source.py
```

The binary script builds and verifies an ad-hoc signed bundle, produces an architecture-specific ZIP in `build`, and writes a SHA-256 sidecar. It builds for the current host architecture; it does not produce a universal binary or claim notarization. The bundle includes the project license, protocol notices, font license, and palette license.

The source script includes only the public source, tests, resources, documentation, examples, scripts, templates, and project metadata. Archive metadata omits local account names and UID/GID data. It excludes build output, Git history/configuration, personal presets, and device backups. Do not zip the entire development directory as a substitute.

The release build disables compiler debug information and strips linker debugging symbols from the distributed executable before signing it. Those symbols can otherwise retain absolute object-file paths. Still inspect the final artifacts before publication: source text, screenshots, executable metadata, and ZIP contents can expose information through different channels. Keep private development archives and raw hardware captures outside the public source tree.

## Review before publishing

Confirm that source and binary ZIPs contain the intended files and required notices, that the app signature verifies after extraction, and that release notes describe signing and supported architectures accurately. Do not include debug symbols or a compiler build directory in the release archive. Third-party copyright names are required credits and should remain even when maintainer identity is omitted.

For an anonymous public identity, choose the hosting account and Git author identity deliberately before committing or pushing. A neutral source tree does not hide an account name, commit email, hosting profile, or future Developer ID certificate identity. The local preparation scripts do not set a personal commit author or configure a remote.

Developer ID signing and notarization are a separate distribution decision. If added later, store credentials outside the repository and document the release process. The [Apple code-signing documentation](https://developer.apple.com/documentation/security/code-signing-services) is the primary reference.
