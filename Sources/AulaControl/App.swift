import AppKit
import AulaCore
import SwiftUI

@main
struct AulaControlApp: App {
    @StateObject private var model = AppModel()

    init() {
        AppTheme.registerFonts()
        Diagnostics.handleCommandLine()
    }
    var body: some Scene {
        WindowGroup("AULA Control") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
                        NSApp.applicationIconImage = NSImage(contentsOf: icon)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first(where: { $0.title == "AULA Control" }) {
                            WindowChrome.configure(window)
                        }
                    }
                    model.connect()
                }
        }
        .defaultSize(width: 1180, height: 830)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Keyboard") {
                Button("Apply Lighting") { model.apply() }.keyboardShortcut(.return, modifiers: .command).disabled(
                    !model.canApply)
                Button("Read from Keyboard") { model.connect() }.keyboardShortcut("r").disabled(model.busy)
                Divider()
                Button("Save Preset…") { model.showSavePreset = true }
                Button("Import Preset…") { model.importPreset() }
                Button("Export Preset…") { model.exportPreset() }
            }
        }
        MenuBarExtra("AULA Control", systemImage: "keyboard") {
            Text(model.connected ? "AULA F108 · 2.4 GHz" : "Keyboard disconnected")
            Button("Open AULA Control") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Main Lights Off") {
                model.settings.effect = 0
                model.apply(includeAuxiliary: false)
            }.disabled(!model.canApply)
            ForEach(model.presets) { preset in
                Button(preset.name) {
                    model.usePreset(preset)
                    model.apply()
                }.disabled(!model.canApply)
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
