import Foundation

/// Complete datasets read sequentially from the receiver, including the key map.
/// This is a recovery snapshot, not a measurement of the physical LED output.
public struct KeyboardSnapshot: Codable, Sendable {
    public let date: Date
    public let config: DeviceConfiguration
    public let palette: [UInt8]
    public let matrix: [UInt8]
    public let identity: [UInt8]
    public let perKey: [UInt8]
    public let battery: Int?
    private enum CodingKeys: String, CodingKey { case date, config, palette, matrix, identity, perKey, battery }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decode(Date.self, forKey: .date)
        config = try values.decode(DeviceConfiguration.self, forKey: .config)
        palette = try values.decode([UInt8].self, forKey: .palette)
        matrix = try values.decode([UInt8].self, forKey: .matrix)
        identity = try values.decode([UInt8].self, forKey: .identity)
        perKey = try values.decodeIfPresent([UInt8].self, forKey: .perKey) ?? []
        battery = try values.decodeIfPresent(Int.self, forKey: .battery)
        guard palette.count == 490, matrix.count == 504, perKey.isEmpty || perKey.count == 378 else {
            throw AulaError.message("This keyboard backup has an unsupported data format.")
        }
    }
    public init(connection: HIDConnection) throws {
        date = Date()
        config = try DeviceConfiguration(connection.read(command: 0x44))
        palette = try connection.read(command: 0x49)
        matrix = try connection.read(command: 0x41)
        identity = try connection.read(command: 0x05)
        perKey = try connection.read(command: 0x42)
        battery = connection.reportedBattery
        guard palette.count == 490, matrix.count == 504,
            perKey.count == 378, Array(identity.prefix(6)) == [3, 0, 0, 0, 1, 0xBA]
        else {
            throw AulaError.message(
                "The receiver replied, but its palette or key matrix format differs from the supported keyboard. No settings were written."
            )
        }
    }
    /// Map USB keyboard/consumer usages to device LED indices, with a Fn sentinel.
    public var ledIndicesByUsage: [Int: Int] {
        var result: [Int: Int] = [:]
        for index in 0..<(matrix.count / 4) {
            let start = index * 4
            if matrix[start] == 0 && matrix[start + 1] == 0 && matrix[start + 2] == 0 && matrix[start + 3] != 0 {
                result[Int(matrix[start + 3])] = index
            } else if matrix[start] == 0 && matrix[start + 1] != 0 {
                let modifiers = matrix[start + 1]
                for bit in 0..<8 where modifiers == (1 << bit) { result[224 + bit] = index }
            } else if matrix[start] == 0x0D {
                result[0xFFFF] = index
            } else if matrix[start] == 2 {
                result[0x10000 + Int(matrix[start + 2]) * 256 + Int(matrix[start + 3])] = index
            }
        }
        return result
    }
    public var settings: LightingSettings {
        var result = config.settings
        let selector = DeviceConfiguration.parameterOffset(result.effect).map { Int(config.bytes[$0 + 1] & 15) } ?? 0
        if let offset = DeviceConfiguration.paletteOffset(
            effect: result.effect, colorIndex: selector == 7 ? 0 : selector)
        {
            result.color = RGB(palette[offset], palette[offset + 1], palette[offset + 2])
        }
        if perKey.count == 378 {
            for index in 0..<126 { result.keys[index] = RGB(perKey[index], perKey[126 + index], perKey[252 + index]) }
        }
        return result
    }
    /// Persist locally before writes. Backups are distinct from portable presets.
    public func backup() throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AULA Control/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("keyboard-\(Int(Date().timeIntervalSince1970 * 1000)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        return url
    }
}
