import XCTest

@testable import AulaCore

final class MainLightingTransferTests: XCTestCase {
    private func configuration(effect: Int) throws -> DeviceConfiguration {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[10] = UInt8(effect)
        bytes[3] = 2
        bytes.replaceSubrange(18..<22, with: [3, 1, 4, 2])
        bytes.replaceSubrange(28..<32, with: [4, 2, 2, 1])
        bytes[58] = 4
        bytes[59] = 0x20
        bytes[126] = 0x5A
        bytes[127] = 0xA5
        return try DeviceConfiguration(bytes)
    }
    func testSameEffectColorAndBrightnessWriteConfigurationBeforePalette() throws {
        let before = try configuration(effect: 1)
        var desired = LightingSettings()
        desired.effect = 1
        desired.brightness = 1
        desired.speed = 2
        desired.color = RGB(0, 255, 0)
        let config = try before.changingLighting(desired)
        let palette = try DeviceConfiguration.palette([UInt8](repeating: 0, count: 490), color: desired.color)
        let batches = LightingWritePlan.applying(desired, config: config, palette: palette)
        // Hardware visibly retained stale values with 09→04 despite exact
        // echoes/read-back. 04→09 updated color and brightness without a mode switch.
        XCTAssertEqual(batches.map { $0[0][1] }, [4, 9])
        let sentConfig = try WirelessPacket.unpack(batches[0], command: 4)
        let sentPalette = try WirelessPacket.unpack(batches[1], command: 9)
        XCTAssertEqual(sentConfig[10], before.bytes[10])
        XCTAssertEqual(sentConfig[58], 1)
        XCTAssertEqual(Array(sentPalette[21..<24]), [0, 255, 0])
        XCTAssertEqual(Array(sentConfig[18..<22]), Array(before.bytes[18..<22]))
        XCTAssertEqual(Array(sentConfig[28..<32]), Array(before.bytes[28..<32]))
    }
    func testPaintOffAndBackupRestorationUseTheirRequiredTransferOrders() throws {
        let palette = try DeviceConfiguration.paletteForWriting([UInt8](repeating: 0, count: 490))
        var settings = LightingSettings()
        settings.effect = 21
        settings.keys = [0: RGB(1, 2, 3)]
        let paint = try configuration(effect: 21)
        let paintBatches = LightingWritePlan.applying(settings, config: paint, palette: palette)
        XCTAssertEqual(paintBatches.map { $0[0][1] }, [2, 4])
        let keyData = try WirelessPacket.unpack(paintBatches[0], command: 2)
        XCTAssertEqual([keyData[0], keyData[126], keyData[252]], [1, 2, 3])
        settings.effect = 0
        let off = try configuration(effect: 0)
        XCTAssertEqual(LightingWritePlan.applying(settings, config: off, palette: palette).map { $0[0][1] }, [4])
        let builtin = try configuration(effect: 2)
        XCTAssertEqual(
            LightingWritePlan.restoring(config: builtin, palette: palette, perKey: keyData).map { $0[0][1] }, [2, 4, 9])
        XCTAssertEqual(
            LightingWritePlan.restoring(config: builtin, palette: palette, perKey: []).map { $0[0][1] }, [4, 9])
        XCTAssertEqual(
            LightingWritePlan.restoring(config: paint, palette: palette, perKey: keyData).map { $0[0][1] }, [9, 2, 4])
        XCTAssertEqual(
            LightingWritePlan.restoring(config: off, palette: palette, perKey: keyData).map { $0[0][1] }, [9, 2, 4])
    }
}
