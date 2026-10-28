import Foundation

/// Independent case lighting on the plain F108. These fields are separate
/// from the main key backlight and must never change its profile or palette.
public enum AuxiliaryLightingZone: String, Codable, CaseIterable, Sendable {
    case sideStrips
    case lightBar

    public var name: String { self == .sideStrips ? "Side strips" : "Light bar" }
    public var configurationOffset: Int { self == .sideStrips ? 18 : 28 }
    public var effectRange: ClosedRange<Int> { 0...(self == .sideStrips ? 3 : 4) }
}

public struct AuxiliaryLightingSettings: Codable, Equatable, Sendable {
    public var effect: Int
    public var colorIndex: Int
    public var brightness: Int
    public var speed: Int

    public init(effect: Int = 3, colorIndex: Int = 0, brightness: Int = 4, speed: Int = 2) {
        self.effect = effect
        self.colorIndex = colorIndex
        self.brightness = brightness
        self.speed = speed
    }

    /// Built-in RGB selectors. Arbitrary RGB has not been established for
    /// these lights; do not route the main backlight's custom palette here.
    public static let colors: [RGB] = [
        RGB(255, 0, 0), RGB(0, 255, 0), RGB(0, 0, 255), RGB(255, 255, 0),
        RGB(255, 0, 255), RGB(0, 255, 255), RGB(255, 255, 255),
    ]
    public static let colorNames = ["Red", "Green", "Blue", "Yellow", "Pink", "Cyan", "White", "Multicolor"]
    public var color: RGB { Self.colors[min(6, max(0, colorIndex))] }
}

public struct AuxiliaryLightingEffect: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let symbol: String
    public var supportsColor: Bool { id == 3 || id == 4 }
    public var supportsSpeed: Bool { id == 1 || id == 2 || id == 4 }
    /// Appearance checked on the tested plain F108, including mode 0 off.
    public static let all: [Self] = [
        .init(id: 3, name: "Solid", symbol: "sun.max"),
        .init(id: 1, name: "Rainbow", symbol: "rainbow"),
        .init(id: 2, name: "Color cycle", symbol: "arrow.triangle.2.circlepath"),
        .init(id: 0, name: "Lights off", symbol: "moon"),
    ]
    public static func all(for zone: AuxiliaryLightingZone) -> [Self] {
        zone == .sideStrips ? all : Array(all.prefix(3)) + [.init(id: 4, name: "Breathing", symbol: "wind"), all[3]]
    }
    public static func find(_ id: Int, zone: AuxiliaryLightingZone = .sideStrips) -> Self? {
        all(for: zone).first { $0.id == id }
    }
}

public enum AuxiliaryLightingPreview {
    public static func color(settings: AuxiliaryLightingSettings, position: Double, elapsed: Double) -> RGB {
        guard settings.effect != 0 else { return .black }
        var intensity = Double(min(4, max(0, settings.brightness))) / 4
        if settings.effect == 4 {
            intensity *= 0.5 - 0.5 * cos(elapsed * (0.8 + Double(min(4, max(0, settings.speed))) * 0.7))
        }
        let rgb: RGB
        if (settings.effect == 3 || settings.effect == 4) && settings.colorIndex != 7 {
            rgb = settings.color
        } else {
            let speed = 0.04 + Double(min(4, max(0, settings.speed))) * 0.045
            let hue = elapsed * speed + (settings.effect == 1 ? position : 0)
            let h = (hue - floor(hue)) * 6
            let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
            let values: (Double, Double, Double)
            switch Int(h) {
            case 0: values = (1, x, 0)
            case 1: values = (x, 1, 0)
            case 2: values = (0, 1, x)
            case 3: values = (0, x, 1)
            case 4: values = (x, 0, 1)
            default: values = (1, 0, x)
            }
            rgb = RGB(
                UInt8((values.0 * 255).rounded()), UInt8((values.1 * 255).rounded()), UInt8((values.2 * 255).rounded()))
        }
        return RGB(
            UInt8((Double(rgb.r) * intensity).rounded()), UInt8((Double(rgb.g) * intensity).rounded()),
            UInt8((Double(rgb.b) * intensity).rounded()))
    }
}

/// Only changed controls are applied to a fresh configuration, retaining
/// physical Fn changes in controls the user has not edited in the app.
public struct AuxiliaryLightingChange: Equatable, Sendable {
    public let effect: Int?
    public let colorIndex: Int?
    public let brightness: Int?
    public let speed: Int?

    public init(desired: AuxiliaryLightingSettings, previous: AuxiliaryLightingSettings) {
        effect = desired.effect == previous.effect ? nil : desired.effect
        colorIndex = desired.colorIndex == previous.colorIndex ? nil : desired.colorIndex
        brightness = desired.brightness == previous.brightness ? nil : desired.brightness
        speed = desired.speed == previous.speed ? nil : desired.speed
    }
    public var isEmpty: Bool { effect == nil && colorIndex == nil && brightness == nil && speed == nil }
}

extension DeviceConfiguration {
    public func auxiliaryLighting(_ zone: AuxiliaryLightingZone) -> AuxiliaryLightingSettings {
        let start = zone.configurationOffset
        return .init(
            effect: Int(bytes[start]), colorIndex: Int(bytes[start + 1]),
            brightness: Int(bytes[start + 2]), speed: Int(bytes[start + 3]))
    }

    public func changingAuxiliaryLighting(_ change: AuxiliaryLightingChange, zone: AuxiliaryLightingZone) throws -> Self
    {
        let fields: [(Int, Int?, ClosedRange<Int>)] = [
            (0, change.effect, zone.effectRange), (1, change.colorIndex, 0...7),
            (2, change.brightness, 0...4), (3, change.speed, 0...4),
        ]
        var result = self
        for (offset, value, range) in fields {
            guard let value else { continue }
            guard range.contains(value) else {
                throw AulaError.message("The \(zone.name.lowercased()) settings are outside the supported range.")
            }
            result.bytes[zone.configurationOffset + offset] = UInt8(value)
        }
        return result
    }
}

extension KeyboardLighting {
    public static func applyAuxiliary(
        _ change: AuxiliaryLightingChange, zone: AuxiliaryLightingZone,
        connection: HIDConnection
    ) throws -> KeyboardSnapshot {
        let before: KeyboardSnapshot
        let config: DeviceConfiguration
        do {
            before = try KeyboardSnapshot(connection: connection)
            config = try before.config.changingAuxiliaryLighting(change, zone: zone)
            guard !change.isEmpty else { return before }
            _ = try before.backup()
        } catch { throw LightingApplyError.preparation(error.localizedDescription) }
        do { try connection.write(config.packets()) } catch {
            throw LightingApplyError.transfer(error.localizedDescription)
        }
        do {
            let after = try KeyboardSnapshot(connection: connection)
            guard after.config == config, after.palette == before.palette,
                after.matrix == before.matrix, after.perKey == before.perKey
            else {
                throw AulaError.message(
                    "The \(zone.name.lowercased()) read-back did not match, or another setting changed. A backup is saved on this Mac."
                )
            }
            return after
        } catch { throw LightingApplyError.verification(error.localizedDescription) }
    }
}
