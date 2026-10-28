import Foundation

public enum KeyboardLighting {
    /// Read-modify-write: retain every setting outside the lighting fields.
    /// A complete read and a local backup must succeed before the first write.
    public static func apply(_ settings: LightingSettings, connection: HIDConnection) throws -> KeyboardSnapshot {
        let before: KeyboardSnapshot
        let config: DeviceConfiguration
        let palette: [UInt8]
        do {
            before = try KeyboardSnapshot(connection: connection)
            _ = try before.backup()
            config = try before.config.changingLighting(settings)
            if LightingEffect.find(settings.effect)?.supportsColor == true && !settings.colorful {
                palette = try DeviceConfiguration.palette(
                    before.palette, color: settings.color, effect: settings.effect)
            } else {
                palette = try DeviceConfiguration.paletteForWriting(before.palette)
            }
        } catch { throw LightingApplyError.preparation(error.localizedDescription) }
        do {
            for batch in LightingWritePlan.applying(settings, config: config, palette: palette) {
                try connection.write(batch)
            }
        } catch { throw LightingApplyError.transfer(error.localizedDescription) }
        let after: KeyboardSnapshot
        do {
            after = try KeyboardSnapshot(connection: connection)
        } catch {
            throw LightingApplyError.verification(error.localizedDescription)
        }
        do {
            guard after.config.bytes[10] == UInt8(settings.effect) else {
                throw AulaError.message(
                    "The keyboard acknowledged the change, but its effect read-back did not match. Reconnect and try again."
                )
            }
            if let offset = DeviceConfiguration.parameterOffset(settings.effect) {
                guard after.config.bytes[offset] == UInt8(settings.brightness),
                    after.config.bytes[offset + 1] == config.bytes[offset + 1]
                else {
                    throw AulaError.message(
                        "The keyboard's brightness or speed read-back did not match the requested settings.")
                }
            }
            if LightingEffect.find(settings.effect)?.supportsColor == true && !settings.colorful,
                let offset = DeviceConfiguration.paletteOffset(effect: settings.effect)
            {
                guard
                    Array(after.palette[offset..<(offset + 3)]) == [
                        settings.color.r, settings.color.g, settings.color.b,
                    ]
                else {
                    throw AulaError.message("The keyboard's color read-back did not match the requested color.")
                }
            }
            if settings.effect == 21 {
                let expected = try WirelessPacket.unpack(DeviceConfiguration.perKeyPackets(settings.keys), command: 2)
                guard after.perKey == Array(expected.prefix(378)) else {
                    throw AulaError.message(
                        "The per-key colors read back from the keyboard did not match the painting.")
                }
            }
            let permitted: Set<Int> = [
                9, 10,
                DeviceConfiguration.parameterOffset(settings.effect) ?? -2,
                (DeviceConfiguration.parameterOffset(settings.effect) ?? -2) + 1,
            ]
            guard
                before.config.bytes.indices.allSatisfy({
                    permitted.contains($0) || before.config.bytes[$0] == after.config.bytes[$0]
                }),
                before.matrix == after.matrix
            else {
                throw AulaError.message(
                    "Read-back shows an unexpected change outside the lighting fields. A backup of the previous configuration is saved on this Mac."
                )
            }
        } catch { throw LightingApplyError.verification(error.localizedDescription) }
        return after
    }

    /// Restore the saved configuration and color data, while leaving key mappings alone.
    /// Reserved palette regions are rebuilt rather than copied from the backup.
    public static func restore(_ original: KeyboardSnapshot, connection: HIDConnection) throws -> KeyboardSnapshot {
        let before = try KeyboardSnapshot(connection: connection)
        guard original.identity == before.identity else {
            throw AulaError.message("This backup belongs to another keyboard.")
        }
        let palette = try DeviceConfiguration.paletteForWriting(original.palette)
        _ = try before.backup()
        for batch in LightingWritePlan.restoring(config: original.config, palette: palette, perKey: original.perKey) {
            try connection.write(batch)
        }
        let after = try KeyboardSnapshot(connection: connection)
        guard after.config == original.config, after.palette == Array(palette.prefix(490)),
            after.matrix == before.matrix, original.perKey.isEmpty || after.perKey == original.perKey
        else {
            throw AulaError.message(
                "The restored lighting did not match read-back. A backup of the previous settings is saved on this Mac."
            )
        }
        return after
    }
}
