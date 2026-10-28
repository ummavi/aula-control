import Foundation

/// Raw 8-bit device channels. UI display-color mapping must not alter this data.
public struct RGB: Codable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
    public static let black = RGB(0, 0, 0)
    public var hex: String { String(format: "%02X%02X%02X", r, g, b) }
    public init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let n = UInt32(value, radix: 16) else { return nil }
        self.init(UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255))
    }
}

/// Main lighting draft and preset data; effect IDs and levels are device values.
public struct LightingSettings: Codable, Equatable, Sendable {
    public var effect = 1
    public var brightness = 4
    public var speed = 3
    public var colorful = false
    public var color = RGB(0, 0, 255)
    /// Physical LED indices, obtained from the device's own key matrix.
    public var keys: [Int: RGB] = [:]
    public init() {}
}

public struct LightingEffect: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let symbol: String
    public let detail: String
    public var supportsColor: Bool { ![0, 3, 15, 16, 17, 21].contains(id) }
    public var supportsSpeed: Bool { (2...18).contains(id) }
    /// Wire IDs and order from the plain F108's OEM KB.ini (2024-10-08).
    public static let all: [Self] = [
        .init(id: 1, name: "Solid", symbol: "sun.max", detail: "One color across your keyboard"),
        .init(id: 2, name: "Breathing", symbol: "wind", detail: "A gentle fade in and out"),
        .init(id: 3, name: "Rainbow", symbol: "rainbow", detail: "A moving spectrum of color"),
        .init(id: 4, name: "Flash away", symbol: "sparkles", detail: "Flashes travel across the keys"),
        .init(id: 5, name: "Raindrops", symbol: "cloud.rain", detail: "Scattered points of light"),
        .init(id: 6, name: "Color wheel", symbol: "circle.dotted", detail: "A rotating color pattern"),
        .init(id: 7, name: "Ripples", symbol: "water.waves", detail: "Rings of light spread across the board"),
        .init(id: 8, name: "Starlight", symbol: "star", detail: "Twinkling lights"),
        .init(id: 9, name: "Fading trail", symbol: "circle.dashed", detail: "Keypresses leave a fading trail"),
        .init(
            id: 10, name: "Snake", symbol: "point.topleft.down.to.point.bottomright.curvepath",
            detail: "A trail travels across the board"),
        .init(id: 11, name: "Neon stream", symbol: "arrow.right", detail: "A flowing trail of color"),
        .init(id: 12, name: "Reactive", symbol: "hand.tap", detail: "Light responds to your typing"),
        .init(id: 13, name: "Sine wave", symbol: "waveform.path", detail: "An undulating wave"),
        .init(id: 14, name: "Scanning", symbol: "line.3.horizontal", detail: "A sweep across the board"),
        .init(id: 15, name: "Windmill", symbol: "fan", detail: "Rotating spokes of color"),
        .init(id: 16, name: "Waterfall", symbol: "arrow.down", detail: "Colors flow down the board"),
        .init(id: 17, name: "Blossom", symbol: "camera.macro", detail: "Expanding bursts of color"),
        .init(id: 18, name: "Storm", symbol: "hurricane", detail: "A rotating storm of light"),
        .init(id: 21, name: "Paint keys", symbol: "paintbrush.pointed", detail: "Choose a color for individual keys"),
        .init(id: 0, name: "Lights off", symbol: "moon", detail: "Turn the main backlight off"),
    ]
    public static func find(_ id: Int) -> Self? { all.first { $0.id == id } }
}

public enum AulaError: LocalizedError {
    case message(String)
    case incompleteResponse(command: UInt8, received: Int, expected: Int)
    case noResponse(command: UInt8)
    case missingAcknowledgment(command: UInt8, sequence: Int, count: Int)
    public var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .incompleteResponse(_, let received, let expected):
            return
                "The receiver returned an incomplete settings response (\(received) of \(expected) packets). Retry the operation."
        case .noResponse:
            return
                "The receiver did not reply to a settings request. Check the USB receiver and 2.4G connection mode, then retry."
        case .missingAcknowledgment(_, let sequence, let count):
            return "The receiver did not acknowledge lighting packet \(sequence + 1) of \(count) after three attempts."
        }
    }
}

public enum LightingApplyError: LocalizedError {
    case preparation(String)
    case transfer(String)
    case verification(String)
    case partial(String)
    public var errorDescription: String? {
        switch self {
        case .preparation(let reason): return "No settings were sent. \(reason)"
        case .transfer(let reason):
            return "The lighting transfer was interrupted. \(reason) Retry Apply to send the complete lighting setup."
        case .verification(let reason):
            return "Lighting was sent, but its final settings could not be confirmed. \(reason)"
        case .partial(let reason): return reason
        }
    }
    public var status: String {
        switch self {
        case .preparation: return "Settings were not sent"
        case .transfer: return "Lighting transfer interrupted"
        case .verification: return "Lighting sent; verification incomplete"
        case .partial: return "Some lighting changes were sent"
        }
    }
}

/// The supported 128-byte configuration, retaining fields outside the edited zone.
public struct DeviceConfiguration: Codable, Equatable, Sendable {
    public var bytes: [UInt8]
    private enum CodingKeys: String, CodingKey { case bytes }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(values.decode([UInt8].self, forKey: .bytes))
    }
    public init(_ bytes: [UInt8]) throws {
        guard bytes.count == 128, Array(bytes.suffix(2)) == [0x5A, 0xA5] else {
            throw AulaError.message("This keyboard's configuration format is not supported. No settings were written.")
        }
        self.bytes = bytes
    }
    public var settings: LightingSettings {
        var settings = LightingSettings()
        settings.effect = Int(bytes[10])
        if let offset = Self.parameterOffset(settings.effect) {
            settings.brightness = min(4, Int(bytes[offset]))
            settings.speed = min(4, Int(bytes[offset + 1] >> 4))
            settings.colorful = (bytes[offset + 1] & 15) == 7
        }
        return settings
    }
    public static func parameterOffset(_ effect: Int) -> Int? {
        guard (1...18).contains(effect) else { return nil }
        return 58 + (effect - 1) * 2
    }
    public func changingLighting(_ settings: LightingSettings) throws -> Self {
        guard LightingEffect.find(settings.effect) != nil,
            (0...4).contains(settings.brightness), (0...4).contains(settings.speed)
        else {
            throw AulaError.message("The lighting settings are outside the supported range.")
        }
        var result = self
        // OEM profile selector: self-defined lighting uses profile 1.
        // Preserve debounce and all other non-lighting fields.
        result.bytes[9] = settings.effect == 21 ? 1 : 0
        result.bytes[10] = UInt8(settings.effect)
        if let offset = Self.parameterOffset(settings.effect) {
            result.bytes[offset] = UInt8(settings.brightness)
            let spectrum = settings.colorful || LightingEffect.find(settings.effect)?.supportsColor == false
            result.bytes[offset + 1] = UInt8(settings.speed << 4) | (spectrum ? 7 : 0)
        }
        return result
    }
    public func packets() -> [[UInt8]] { Self.packets(bytes, command: 4) }
    public static func packets(_ data: [UInt8], command: UInt8) -> [[UInt8]] {
        let count = (data.count + 13) / 14
        precondition(count > 0 && count <= 64)
        return (0..<count).map { index in
            let slice = Array(data[(index * 14)..<min(data.count, (index + 1) * 14)])
            return WirelessPacket.make(
                command: command, total: UInt8(count), sequence: UInt8(index), payload: [UInt8(slice.count)] + slice)
        }
    }
    public static func paletteOffset(effect: Int, colorIndex: Int = 0) -> Int? {
        guard (1...18).contains(effect), (0...6).contains(colorIndex) else { return nil }
        return effect * 21 + colorIndex * 3
    }
    /// OEM writes a 21-byte reserved header, 19 rows of seven RGB triples,
    /// reserved zero padding, and the 5A A5 marker at offsets 506–507.
    /// A nonzero reserved region can echo back while LEDs keep stale colors.
    public static func paletteForWriting(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count == 490 else {
            throw AulaError.message("The keyboard's color palette format is not supported. No settings were written.")
        }
        var result = [UInt8](repeating: 0, count: 512)
        result.replaceSubrange(21..<420, with: bytes[21..<420])
        result[506] = 0x5A
        result[507] = 0xA5
        return result
    }
    public static func palette(_ bytes: [UInt8], color: RGB, effect: Int = 1) throws -> [UInt8] {
        guard let offset = paletteOffset(effect: effect) else {
            throw AulaError.message("This effect does not have a custom RGB slot.")
        }
        var result = try paletteForWriting(bytes)
        result.replaceSubrange(offset..<(offset + 3), with: [color.r, color.g, color.b])
        return result
    }
    public static func perKeyPackets(_ colors: [Int: RGB]) -> [[UInt8]] {
        var data: [UInt8] = []
        for channel in 0..<3 {
            for index in 0..<126 {
                let color = colors[index] ?? .black
                data.append(channel == 0 ? color.r : (channel == 1 ? color.g : color.b))
            }
        }
        // OEM sends exactly 126 RGB planes (378 bytes), with bank 0.
        return packets(data, command: 2)
    }
}

/// The F108 refreshes built-in lighting parameters when the RGB table follows
/// configuration. Reversing those transfers can read back correctly while
/// the active LEDs retain the previous color and brightness.
enum LightingWritePlan {
    static func applying(_ settings: LightingSettings, config: DeviceConfiguration, palette: [UInt8]) -> [[[UInt8]]] {
        if settings.effect == 21 { return [DeviceConfiguration.perKeyPackets(settings.keys), config.packets()] }
        if settings.effect == 0 { return [config.packets()] }
        return [config.packets(), DeviceConfiguration.packets(palette, command: 9)]
    }

    static func restoring(config: DeviceConfiguration, palette: [UInt8], perKey: [UInt8]) -> [[[UInt8]]] {
        let colors = DeviceConfiguration.packets(palette, command: 9)
        let keys = perKey.isEmpty ? [] : [DeviceConfiguration.packets(perKey, command: 2)]
        if (1...18).contains(Int(config.bytes[10])) { return keys + [config.packets(), colors] }
        // Paint mode still needs its RGB planes before configuration. End an
        // Off restoration with configuration so the main backlight stays off.
        return [colors] + keys + [config.packets()]
    }
}
