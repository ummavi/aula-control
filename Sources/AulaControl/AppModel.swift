import AppKit
import AulaCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
/// Owns editable drafts on the main actor and serializes device work off the UI thread.
final class AppModel: ObservableObject {
    @Published var settings = LightingSettings()
    @Published var selectedLightingZone: AuxiliaryLightingZone?
    @Published var auxiliary: [AuxiliaryLightingZone: AuxiliaryLightingSettings] = [:]
    @Published var appliedAuxiliary: [AuxiliaryLightingZone: AuxiliaryLightingSettings] = [:]
    @Published var connected = false
    @Published var busy = false
    @Published var status = "Connect your keyboard to get started."
    @Published var error: String?
    @Published var selectedTab = "Lighting"
    @Published var presets: [Preset] = []
    @Published var showSavePreset = false
    @Published var presetName = ""
    @Published var snapshot: KeyboardSnapshot?
    @Published var applied: LightingSettings?
    @Published var selectedKeys: Set<Int> = []
    @Published var hexText = "0000FF"
    @Published var lastVerified: Date?
    private let worker = DispatchQueue(label: "app.aula-control.hid", qos: .userInitiated)
    private let presetURL: URL
    var canApply: Bool { connected && !busy }
    var dirty: Bool { applied != settings || auxiliary != appliedAuxiliary }
    var activeAuxiliary: AuxiliaryLightingSettings {
        get { selectedLightingZone.flatMap { auxiliary[$0] } ?? AuxiliaryLightingSettings() }
        set { if let zone = selectedLightingZone { auxiliary[zone] = newValue } }
    }
    var activeAuxiliaryEffect: AuxiliaryLightingEffect? {
        selectedLightingZone.flatMap { AuxiliaryLightingEffect.find(activeAuxiliary.effect, zone: $0) }
    }
    var animatesAuxiliary: Bool {
        auxiliary.values.contains {
            $0.brightness > 0
                && ($0.effect == 1 || $0.effect == 2 || $0.effect == 4 || ($0.effect == 3 && $0.colorIndex == 7))
        }
    }
    var effect: LightingEffect? { LightingEffect.find(settings.effect) }
    var color: Color {
        get {
            Color(
                red: Double(settings.color.r) / 255, green: Double(settings.color.g) / 255,
                blue: Double(settings.color.b) / 255)
        }
        set {
            guard let rgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            func byte(_ component: CGFloat) -> UInt8 { UInt8((min(1, max(0, component)) * 255).rounded()) }
            setColor(RGB(byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent)))
        }
    }
    init(loadPresets: Bool = true) {
        presetURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AULA Control/presets.json")
        guard loadPresets else { return }
        do {
            if FileManager.default.fileExists(atPath: presetURL.path) {
                presets = try JSONDecoder().decode([Preset].self, from: Data(contentsOf: presetURL))
                for index in presets.indices {
                    presets[index].settings.brightness = min(4, max(0, presets[index].settings.brightness))
                }
            }
        } catch { self.error = "Could not load saved presets: \(error.localizedDescription)" }
    }
    func connect() {
        guard !busy else { return }
        busy = true
        error = nil
        status = "Reading your keyboard…"
        worker.async {
            let result = Result { try KeyboardSnapshot(connection: HIDConnection()) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.connected = true
                    self.settings = snapshot.settings
                    self.applied = self.settings
                    self.hexText = self.settings.color.hex
                    self.auxiliary = Dictionary(
                        uniqueKeysWithValues: AuxiliaryLightingZone.allCases.map {
                            ($0, snapshot.config.auxiliaryLighting($0))
                        })
                    self.appliedAuxiliary = self.auxiliary
                    self.status = "Settings read from keyboard"
                    self.lastVerified = Date()
                case .failure(let error):
                    self.connected = false
                    self.error = error.localizedDescription
                    self.status = "Keyboard unavailable"
                }
            }
        }
    }
    func apply(includeAuxiliary: Bool = true) {
        guard canApply else { return }
        let desired = settings
        // Main Apply also reloads settings that already match receiver storage:
        // an older transfer may have stored them without updating the LEDs.
        let mainChanged = applied != desired || selectedLightingZone == nil || !includeAuxiliary
        let desiredAuxiliary = auxiliary
        let changes: [(AuxiliaryLightingZone, AuxiliaryLightingChange)] =
            includeAuxiliary
            ? AuxiliaryLightingZone.allCases.compactMap { zone in
                guard let desired = auxiliary[zone], let previous = appliedAuxiliary[zone] else { return nil }
                let change = AuxiliaryLightingChange(desired: desired, previous: previous)
                return change.isEmpty ? nil : (zone, change)
            } : []
        busy = true
        error = nil
        status = "Applying lighting…"
        worker.async {
            let result = Result {
                let connection = try HIDConnection()
                var latest: KeyboardSnapshot?
                var completed: [String] = []
                do {
                    if mainChanged {
                        latest = try KeyboardLighting.apply(desired, connection: connection)
                        completed.append("Main keys")
                    }
                    for (zone, change) in changes {
                        latest = try KeyboardLighting.applyAuxiliary(change, zone: zone, connection: connection)
                        completed.append(zone.name)
                    }
                    return try latest ?? KeyboardSnapshot(connection: connection)
                } catch {
                    guard !completed.isEmpty else { throw error }
                    throw LightingApplyError.partial(
                        "Applied \(completed.joined(separator: ", ")). The remaining changes could not be completed: \(error.localizedDescription)"
                    )
                }
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    if self.settings == desired {
                        self.settings = snapshot.settings
                        self.hexText = self.settings.color.hex
                    }
                    self.applied = snapshot.settings
                    for zone in AuxiliaryLightingZone.allCases {
                        if !includeAuxiliary && self.auxiliary[zone] != self.appliedAuxiliary[zone] { continue }
                        let actual = snapshot.config.auxiliaryLighting(zone)
                        if self.auxiliary[zone] == desiredAuxiliary[zone] { self.auxiliary[zone] = actual }
                        self.appliedAuxiliary[zone] = actual
                    }
                    self.lastVerified = Date()
                    self.status =
                        mainChanged || !changes.isEmpty
                        ? "Settings sent; receiver read-back matched" : "Settings read from keyboard"
                case .failure(let error):
                    self.error = error.localizedDescription
                    self.status = (error as? LightingApplyError)?.status ?? "Change could not be verified"
                }
            }
        }
    }
    func selectEffect(_ id: Int) {
        settings.effect = id
        settings.colorful = LightingEffect.find(id)?.supportsColor == false && id != 21 && id != 0
        selectedKeys = []
    }
    func setColor(_ rgb: RGB) {
        settings.color = rgb
        hexText = rgb.hex
        for key in selectedKeys { settings.keys[key] = rgb }
    }
    func setHex() {
        guard let rgb = RGB(hex: hexText) else {
            hexText = settings.color.hex
            return
        }
        setColor(rgb)
    }
    func paintKey(_ index: Int) {
        if NSEvent.modifierFlags.contains(.shift) {
            if selectedKeys.contains(index) { selectedKeys.remove(index) } else { selectedKeys.insert(index) }
        } else {
            selectedKeys = [index]
        }
        for key in selectedKeys { settings.keys[key] = settings.color }
    }
    func fillKeys() { for index in 0..<126 { settings.keys[index] = settings.color } }
    func usePreset(_ preset: Preset) {
        settings = preset.settings
        settings.brightness = min(4, max(0, settings.brightness))
        hexText = settings.color.hex
        selectedKeys = []
        selectedTab = "Lighting"
        selectedLightingZone = nil
        for zone in AuxiliaryLightingZone.allCases {
            if let saved = preset.auxiliary?[zone.rawValue] { auxiliary[zone] = saved }
        }
    }
    func quickPreset(name: String, color: RGB, effect: Int = 1, colorful: Bool = false) {
        selectedKeys = []
        settings.effect = effect
        settings.colorful = colorful
        settings.brightness = 4
        settings.speed = 3
        setColor(color)
    }
    func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        presets.append(currentPreset(name: name))
        presetName = ""
        showSavePreset = false
        persistPresets()
    }
    private func currentPreset(name: String) -> Preset {
        Preset(
            name: name, settings: settings,
            auxiliary: Dictionary(uniqueKeysWithValues: auxiliary.map { ($0.key.rawValue, $0.value) }))
    }
    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }
    private func persistPresets() {
        do {
            try FileManager.default.createDirectory(
                at: presetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(presets).write(to: presetURL, options: .atomic)
        } catch { self.error = "Could not save presets: \(error.localizedDescription)" }
    }
    func exportPreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AULA Lighting.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(currentPreset(name: url.deletingPathExtension().lastPathComponent)).write(
                to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 1_000_000 else {
                throw AulaError.message("The preset file is too large.")
            }
            var preset = try JSONDecoder().decode(Preset.self, from: Data(contentsOf: url))
            guard LightingEffect.find(preset.settings.effect) != nil, (0...9).contains(preset.settings.brightness),
                (0...4).contains(preset.settings.speed),
                preset.settings.keys.keys.allSatisfy({ (0..<126).contains($0) })
            else {
                throw AulaError.message("This preset contains unsupported lighting settings.")
            }
            preset.settings.brightness = min(4, preset.settings.brightness)
            for (name, settings) in preset.auxiliary ?? [:] {
                guard let zone = AuxiliaryLightingZone(rawValue: name), zone.effectRange.contains(settings.effect),
                    (0...7).contains(settings.colorIndex), (0...4).contains(settings.brightness),
                    (0...4).contains(settings.speed)
                else {
                    throw AulaError.message("This preset contains unsupported auxiliary lighting settings.")
                }
            }
            preset.id = UUID()
            presets.append(preset)
            persistPresets()
            usePreset(preset)
        } catch { self.error = "Could not import preset: \(error.localizedDescription)" }
    }
}
