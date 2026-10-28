import AppKit
import AulaCore
import SwiftUI

/// Command-line checks. Hardware-writing modes are explicitly named.
enum Diagnostics {
    @MainActor
    static func handleCommandLine() {
        let arguments = CommandLine.arguments
        if arguments.contains("--help") {
            print(
                """
                AULA Control — macOS lighting control for the plain AULA F108

                Launch without arguments to open the interface.

                Offline commands (no receiver access):
                  --help                       Show this help
                  --check-preset-format        Check legacy and current preset encoding
                  --verify-previews            Check live preview animation without hardware
                  --render-preview FILE.png    Render the interface without hardware
                    --demo                     Use example rainbow settings
                    --snapshot FILE.json       Use an existing keyboard snapshot
                    --tab TAB                   Lighting, Presets, or Device & shortcuts
                    --zone ZONE                 sideStrips or lightBar (default: main keys)
                    --preview-paint             Display the per-key editor

                Read-only receiver commands (may save a local snapshot):
                  --diagnose                   Read identity, settings, and LED mappings
                  --check-ui-connection        Read through the UI worker and check mappings

                Commands that WRITE to the keyboard:
                  --verify-hardware            Temporarily change lighting, then restore
                  --verify-ui                  Exercise UI Apply, then restore
                  --restore-backup FILE.json   Restore saved configuration and colors

                Options:
                  --output-dir DIRECTORY       Save preview-check frames in this directory
                  AULA_TRACE_HID=1              Log vendor reports to stderr

                See docs/TROUBLESHOOTING.md and docs/PROTOCOL.md for details.
                """)
            exit(0)
        }
        let modes = [
            "--check-preset-format", "--verify-ui", "--verify-previews",
            "--check-ui-connection", "--render-preview", "--restore-backup",
            "--diagnose", "--verify-hardware",
        ].filter(arguments.contains)
        guard modes.count <= 1 else {
            fputs("Choose one diagnostic command at a time. Use --help for usage.\n", stderr)
            exit(2)
        }
        switch modes.first {
        case "--check-preset-format": checkPresetFormat()
        case "--verify-ui": verifyUI()
        case "--verify-previews": verifyUI(applyLighting: false)
        case "--check-ui-connection": checkUIConnection()
        case "--render-preview": renderPreview()
        case "--restore-backup": restoreBackup()
        case "--diagnose": run(verify: false)
        case "--verify-hardware": run(verify: true)
        default: break
        }
    }

    private static func option(_ name: String) throws -> String? {
        let arguments = CommandLine.arguments
        guard let position = arguments.firstIndex(of: name) else { return nil }
        guard position + 1 < arguments.count, !arguments[position + 1].hasPrefix("--") else {
            throw AulaError.message("\(name) requires a value. Use --help for usage.")
        }
        return arguments[position + 1]
    }

    /// Keep account names out of diagnostic output intended for issue reports.
    private static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path + "/"
        return url.path.hasPrefix(home) ? "~/" + url.path.dropFirst(home.count) : url.path
    }
    static func checkPresetFormat() -> Never {
        do {
            let encoder = JSONEncoder()
            let legacy = Preset(name: "Legacy", settings: LightingSettings())
            let oldData = try encoder.encode(legacy)
            let old = try JSONDecoder().decode(Preset.self, from: oldData)
            guard old.auxiliary == nil, old.settings == legacy.settings else {
                throw AulaError.message("Legacy preset did not decode")
            }
            let zones = [
                "sideStrips": AuxiliaryLightingSettings(effect: 3, colorIndex: 0),
                "lightBar": AuxiliaryLightingSettings(effect: 4, colorIndex: 2),
            ]
            let current = Preset(name: "All zones", settings: legacy.settings, auxiliary: zones)
            let decoded = try JSONDecoder().decode(Preset.self, from: encoder.encode(current))
            guard decoded.auxiliary == zones, decoded.settings == legacy.settings else {
                throw AulaError.message("All-zone preset did not round-trip")
            }
            print("PASS: legacy presets decode; all-zone presets retain main lighting and both auxiliary zones")
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    /// Exercise the same model, worker queue and live Canvas used by the app.
    @MainActor
    static func verifyUI(applyLighting: Bool = true) -> Never {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        let model = AppModel(loadPresets: false)
        func waitForOperation() throws {
            let deadline = Date().addingTimeInterval(25)
            while model.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            if model.busy { throw AulaError.message("UI operation timed out") }
            if let error = model.error { throw AulaError.message(error) }
        }
        let rect = NSRect(x: 0, y: 0, width: 1180, height: 340)
        // Isolate the preview from text cursors, focus rings, and form layout changes.
        let host = NSHostingView(rootView: KeyboardPreview(model: model).preferredColorScheme(.dark))
        host.frame = rect
        let window = NSWindow(
            contentRect: rect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "AULA Control · verification"
        window.contentView = host
        window.center()
        window.orderFront(nil)
        func imageData() throws -> Data {
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: rect) else {
                throw AulaError.message("Could not capture UI")
            }
            host.cacheDisplay(in: rect, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw AulaError.message("Could not encode UI")
            }
            return png
        }
        var original: KeyboardSnapshot?
        var failure: Error?
        var attemptedWrite = false
        do {
            let outputDirectory = try option("--output-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
            if let outputDirectory {
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            }
            if applyLighting {
                model.connect()
                try waitForOperation()
                guard let snapshot = model.snapshot else { throw AulaError.message("UI has no keyboard snapshot") }
                guard KeyCap.all.count == 108, KeyCap.all.allSatisfy({ snapshot.ledIndicesByUsage[$0.usage] != nil })
                else {
                    throw AulaError.message("The displayed keyboard contains an unmapped key")
                }
                original = snapshot
                _ = try snapshot.backup()
                print("PASS: UI connected through its worker queue")
            } else {
                model.settings.color = RGB(0, 255, 0)
                model.status = "Offline preview verification"
                print("Checking previews without receiver access")
            }
            for effect in LightingEffect.all where LightingPreview.animates(effect.id) || effect.id == 1 {
                model.settings.effect = effect.id
                model.settings.brightness = 4
                model.settings.speed = 2
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                var first = try imageData()
                var second = first
                let animated = LightingPreview.animates(effect.id)
                var matchedExpectation = false
                // SwiftUI/Canvas can finish its initial draw after the first capture,
                // especially on hosted runners. Require a real consecutive-frame match
                // for Solid, or an observed change for animation, within a bounded wait.
                for _ in 0..<4 {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.45))
                    second = try imageData()
                    matchedExpectation = animated ? first != second : first == second
                    if matchedExpectation { break }
                    first = second
                }
                if animated && !matchedExpectation {
                    throw AulaError.message("Effect \(effect.id) did not animate in the live UI")
                }
                if !animated && !matchedExpectation { throw AulaError.message("Static render did not settle") }
                if let outputDirectory, [1, 3, 8, 15, 18].contains(effect.id) {
                    try first.write(to: outputDirectory.appendingPathComponent("effect-\(effect.id)-a.png"))
                    try second.write(to: outputDirectory.appendingPathComponent("effect-\(effect.id)-b.png"))
                }
                print(
                    "PASS: live preview \(effect.name) \(LightingPreview.animates(effect.id) ? "animates" : "is stable")"
                )
            }
            for effect in [1, 2, 3, 5, 21, 0] {
                guard applyLighting, let snapshot = original else { break }
                model.settings = snapshot.settings
                model.settings.effect = effect
                model.settings.brightness = 4
                model.settings.speed = 2
                model.settings.color = RGB(0, 0, 255)
                model.settings.colorful = effect == 3
                if effect == 21 {
                    model.settings.keys = Dictionary(
                        uniqueKeysWithValues: (0..<126).map { ($0, RGB(UInt8($0), UInt8(255 - $0), 128)) })
                }
                attemptedWrite = true
                model.apply()
                try waitForOperation()
                print("PASS: UI Apply effect \(effect) · \(model.status)")
            }
        } catch { failure = error }
        if let original, attemptedWrite {
            do {
                let connection = try HIDConnection()
                let restored = try KeyboardLighting.restore(original, connection: connection)
                guard restored.config == original.config,
                    restored.palette == Array(try DeviceConfiguration.paletteForWriting(original.palette).prefix(490)),
                    restored.perKey == original.perKey, restored.matrix == original.matrix
                else {
                    throw AulaError.message("UI verification could not confirm the original settings were restored")
                }
                print("PASS: UI verification restored original settings with OEM palette reserved bytes")
            } catch { failure = error }
        }
        window.orderOut(nil)
        if let failure {
            fputs("\(failure.localizedDescription)\n", stderr)
            exit(1)
        }
        exit(0)
    }
    @MainActor
    static func checkUIConnection() -> Never {
        setbuf(stdout, nil)
        let model = AppModel(loadPresets: false)
        model.connect()
        let deadline = Date().addingTimeInterval(25)
        while model.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        guard model.connected, let snapshot = model.snapshot else {
            fputs("\(model.error ?? "UI connection timed out")\n", stderr)
            exit(1)
        }
        let unmapped = KeyCap.all.filter { snapshot.ledIndicesByUsage[$0.usage] == nil }
        guard KeyCap.all.count == 108, unmapped.isEmpty else {
            fputs("Unmapped display keys: \(unmapped.map(\.label))\n", stderr)
            exit(1)
        }
        print("PASS: all 108 displayed keys map to device LEDs")
        print(
            "PASS: UI worker connected; \(snapshot.ledIndicesByUsage.count) key mappings; battery \(snapshot.battery.map(String.init) ?? "unavailable")%; \(model.status)"
        )
        exit(0)
    }
    static func restoreBackup() -> Never {
        setbuf(stdout, nil)
        do {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: "--restore-backup"), index + 1 < args.count else { exit(2) }
            let original = try JSONDecoder().decode(
                KeyboardSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: args[index + 1])))
            let connection = try HIDConnection()
            print("Restoring lighting…")
            let restored = try KeyboardLighting.restore(original, connection: connection)
            guard restored.config == original.config,
                restored.palette == Array(try DeviceConfiguration.paletteForWriting(original.palette).prefix(490)),
                original.perKey.isEmpty || restored.perKey == original.perKey
            else {
                print(
                    "Config differences:",
                    zip(original.config.bytes, restored.config.bytes).enumerated().filter {
                        $0.element.0 != $0.element.1
                    }.map { "\($0.offset): \($0.element.0) → \($0.element.1)" })
                print(
                    "Palette differences:",
                    zip(original.palette, restored.palette).enumerated().filter { $0.element.0 != $0.element.1 }.map {
                        "\($0.offset): \($0.element.0) → \($0.element.1)"
                    })
                throw AulaError.message("Read-back differs from backup.")
            }
            print("PASS: original configuration and main palette colors restored with OEM reserved bytes")
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    @MainActor
    static func renderPreview() -> Never {
        let arguments = CommandLine.arguments
        guard let position = arguments.firstIndex(of: "--render-preview"), position + 1 < arguments.count else {
            exit(2)
        }
        let output = arguments[position + 1]
        _ = NSApplication.shared
        let model = AppModel(loadPresets: false)
        do {
            if let snapshotPath = try option("--snapshot") {
                guard !arguments.contains("--demo") else {
                    throw AulaError.message("Choose --snapshot or --demo, not both.")
                }
                let data = try Data(contentsOf: URL(fileURLWithPath: snapshotPath))
                let snapshot = try JSONDecoder().decode(KeyboardSnapshot.self, from: data)
                model.snapshot = snapshot
                model.settings = snapshot.settings
                model.applied = snapshot.settings
                model.auxiliary = Dictionary(
                    uniqueKeysWithValues: AuxiliaryLightingZone.allCases.map {
                        ($0, snapshot.config.auxiliaryLighting($0))
                    })
                model.appliedAuxiliary = model.auxiliary
                model.status = "Offline snapshot preview"
                model.hexText = snapshot.settings.color.hex
            } else if arguments.contains("--demo") {
                model.settings.effect = 3
                model.settings.colorful = true
                model.auxiliary = Dictionary(
                    uniqueKeysWithValues: AuxiliaryLightingZone.allCases.map {
                        ($0, AuxiliaryLightingSettings(effect: 1, brightness: 3, speed: 2))
                    })
                model.status = "Offline preview — no keyboard connected"
            }
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
        if let position = arguments.firstIndex(of: "--tab"), position + 1 < arguments.count {
            model.selectedTab = arguments[position + 1]
        }
        if let position = arguments.firstIndex(of: "--zone"), position + 1 < arguments.count {
            model.selectedLightingZone = AuxiliaryLightingZone(rawValue: arguments[position + 1])
        }
        if arguments.contains("--preview-paint") { model.settings.effect = 21 }
        let frame = NSRect(x: 0, y: 0, width: 1180, height: 900)
        let host = NSHostingView(rootView: ContentView(model: model).preferredColorScheme(.dark))
        host.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: frame) else { exit(1) }
        host.cacheDisplay(in: frame, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do {
            try png.write(to: URL(fileURLWithPath: output))
            print("Rendered \(output)")
            exit(0)
        } catch {
            fputs(error.localizedDescription, stderr)
            exit(1)
        }
    }
    static func run(verify: Bool) -> Never {
        setbuf(stdout, nil)
        do {
            let connection = try HIDConnection()
            let before = try KeyboardSnapshot(connection: connection)
            let backup = try before.backup()
            print(
                "Receiver: 3554:FA09; identity: \(before.identity.map { String(format: "%02X", $0) }.joined(separator: " "))"
            )
            print(
                "Config: \(before.config.bytes.count) bytes; palette: \(before.palette.count) bytes; key matrix: \(before.matrix.count) bytes"
            )
            print(
                "Effect: \(before.settings.effect); brightness: \(before.settings.brightness); speed: \(before.settings.speed); primary color: #\(before.settings.color.hex)"
            )
            print("Mapped keys: \(before.ledIndicesByUsage.count); backup: \(displayPath(backup))")
            if verify {
                // Restore the original color table and configuration after the test,
                // including on failure. Never write the key or Fn mapping tables.
                var test = before.settings
                test.effect = 1
                test.brightness = 2
                test.colorful = false
                test.color = RGB(90, 160, 230)
                var failure: Error?
                do {
                    print("Applying temporary solid color…")
                    _ = try KeyboardLighting.apply(test, connection: connection)
                    print("PASS: effect, brightness, speed and primary color read-back")
                    test.effect = 2
                    test.brightness = 4
                    test.speed = 1
                    test.colorful = true
                    _ = try KeyboardLighting.apply(test, connection: connection)
                    print("PASS: breathing effect, brightness 4/4, speed and multicolor read-back")
                    test.effect = 21
                    var keyColors: [Int: RGB] = [:]
                    for index in 0..<126 {
                        let red = UInt8(index)
                        let green = UInt8(255 - index)
                        let blue = UInt8((index * 2) % 256)
                        keyColors[index] = RGB(red, green, blue)
                    }
                    test.keys = keyColors
                    _ = try KeyboardLighting.apply(test, connection: connection)
                    print("PASS: all 126 per-key colors read back correctly")
                    test.effect = 0
                    _ = try KeyboardLighting.apply(test, connection: connection)
                    print("PASS: backlight off read-back")
                } catch {
                    failure = error
                    print("Verification failed: \(error.localizedDescription)")
                }
                let originalPalette = try DeviceConfiguration.paletteForWriting(before.palette)
                print("Restoring original lighting…")
                let restored = try KeyboardLighting.restore(before, connection: connection)
                guard restored.config == before.config, restored.palette == Array(originalPalette.prefix(490)),
                    restored.perKey == before.perKey
                else {
                    throw AulaError.message(
                        "Original settings did not fully match after restoration. Backup: \(displayPath(backup))")
                }
                print(
                    "PASS: original configuration and per-key colors restored; main color rows restored with OEM reserved bytes"
                )
                if let failure { throw failure }
            }
            print("Packets: \(connection.sentCount) sent, \(connection.receivedCount) received")
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
