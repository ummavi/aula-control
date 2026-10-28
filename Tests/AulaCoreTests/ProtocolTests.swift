import XCTest

@testable import AulaCore

final class ProtocolTests: XCTestCase {
    func testKnownReadPacketAndChecksumRejection() {
        let request = WirelessPacket.make(command: 0x44)
        XCTAssertEqual(Array(request.prefix(4)), [0x13, 0x44, 1, 0])
        XCTAssertEqual(request[19], 0x58)
        XCTAssertTrue(WirelessPacket.valid(request))
        var corrupt = request
        corrupt[8] = 1
        XCTAssertFalse(WirelessPacket.valid(corrupt))
        XCTAssertFalse(WirelessPacket.valid(Array(request.prefix(19))))
    }
    func testReassemblyRejectsMissingDuplicateAndCorruptPages() throws {
        let bytes = Array(0..<UInt8(40))
        let packets = DeviceConfiguration.packets(bytes, command: 0x49)
        XCTAssertEqual(try WirelessPacket.unpack(packets.reversed(), command: 0x49), bytes)
        XCTAssertThrowsError(try WirelessPacket.unpack(Array(packets.dropLast()), command: 0x49))
        XCTAssertThrowsError(try WirelessPacket.unpack([packets[0], packets[0], packets[2]], command: 0x49))
        var corrupt = packets
        corrupt[1][8] ^= 1
        XCTAssertThrowsError(try WirelessPacket.unpack(corrupt, command: 0x49))
    }
    func testLightingChangesPreserveEveryUnrelatedByte() throws {
        var bytes = (0..<128).map { UInt8($0) }
        bytes[126] = 0x5A
        bytes[127] = 0xA5
        let config = try DeviceConfiguration(bytes)
        for effect in [1, 2, 3, 6, 7, 13, 14, 18, 21, 0] {
            var settings = LightingSettings()
            settings.effect = effect
            settings.brightness = 4
            settings.speed = 2
            settings.colorful = true
            let changed = try config.changingLighting(settings)
            var permitted: Set<Int> = [9, 10]
            if let offset = DeviceConfiguration.parameterOffset(effect) {
                permitted.insert(offset)
                permitted.insert(offset + 1)
                XCTAssertEqual(changed.bytes[offset], 4)
                XCTAssertEqual(changed.bytes[offset + 1], 0x27)
            }
            XCTAssertEqual(changed.bytes[9], effect == 21 ? 1 : 0)
            for index in bytes.indices where !permitted.contains(index) {
                XCTAssertEqual(
                    changed.bytes[index], bytes[index], "Unexpected change at offset \(index) for effect \(effect)")
            }
        }
        XCTAssertEqual(DeviceConfiguration.parameterOffset(1), 58)
        XCTAssertEqual(DeviceConfiguration.parameterOffset(7), 70)
        XCTAssertEqual(DeviceConfiguration.parameterOffset(14), 84)
        XCTAssertEqual(DeviceConfiguration.parameterOffset(18), 92)
    }
    func testBadConfigAndOutOfRangeSettingsAreRejected() throws {
        XCTAssertThrowsError(try DeviceConfiguration([0, 1, 2]))
        XCTAssertThrowsError(try DeviceConfiguration([UInt8](repeating: 0, count: 128)))
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[126] = 0x5A
        bytes[127] = 0xA5
        let config = try DeviceConfiguration(bytes)
        var settings = LightingSettings()
        settings.effect = 255
        XCTAssertThrowsError(try config.changingLighting(settings))
        settings.effect = 1
        settings.brightness = -1
        XCTAssertThrowsError(try config.changingLighting(settings))
        settings.brightness = 5
        XCTAssertThrowsError(try config.changingLighting(settings))
        settings.brightness = 4
        settings.speed = 5
        XCTAssertThrowsError(try config.changingLighting(settings))
    }
    func testPaletteUsesOEMReservedRegionsAndPerEffectRGBSlots() throws {
        let read = (0..<490).map { UInt8($0 % 256) }
        let write = try DeviceConfiguration.palette(read, color: RGB(8, 15, 32), effect: 2)
        XCTAssertEqual(write.count, 512)
        XCTAssertEqual(Array(write.prefix(21)), [UInt8](repeating: 0, count: 21))
        // F108 breathing is mode 2: row 2 starts at byte 42.
        XCTAssertEqual(Array(write[42..<45]), [8, 15, 32])
        for index in 21..<420 where !(42..<45).contains(index) {
            XCTAssertEqual(write[index], read[index], "Changed another effect's color at \(index)")
        }
        XCTAssertEqual(Array(write[420..<506]), [UInt8](repeating: 0, count: 86))
        XCTAssertEqual(Array(write[506..<512]), [0x5A, 0xA5, 0, 0, 0, 0])
        XCTAssertEqual(DeviceConfiguration.paletteOffset(effect: 1), 21)
        XCTAssertEqual(DeviceConfiguration.paletteOffset(effect: 18, colorIndex: 6), 396)
        XCTAssertNil(DeviceConfiguration.paletteOffset(effect: 0))
        XCTAssertNil(DeviceConfiguration.paletteOffset(effect: 21))
        let packets = DeviceConfiguration.packets(write, command: 9)
        XCTAssertEqual(packets.count, 37)
        XCTAssertTrue(packets.allSatisfy(WirelessPacket.valid))
        XCTAssertEqual(Array(packets[36][4...12]), [8, 0, 0, 0x5A, 0xA5, 0, 0, 0, 0])
    }
    func testPerKeyPlanesMatchOEMLengthAndChannelOrder() throws {
        let packets = DeviceConfiguration.perKeyPackets([0: RGB(10, 20, 30), 125: RGB(100, 110, 120)])
        XCTAssertEqual(packets.count, 27)
        let data = try WirelessPacket.unpack(packets, command: 2)
        XCTAssertEqual(data.count, 378)
        XCTAssertEqual([data[0], data[126], data[252]], [10, 20, 30])
        XCTAssertEqual([data[125], data[251], data[377]], [100, 110, 120])
        XCTAssertEqual(packets.last?[4], 14)
    }
    func testHexColorValidationAndPresetRoundTrip() throws {
        XCTAssertEqual(RGB(hex: " #75d3ff "), RGB(117, 211, 255))
        XCTAssertNil(RGB(hex: "ffff"))
        XCTAssertNil(RGB(hex: "ZZZZZZ"))
        var settings = LightingSettings()
        settings.keys = [0: RGB(1, 2, 3), 125: RGB(253, 254, 255)]
        XCTAssertEqual(try JSONDecoder().decode(LightingSettings.self, from: JSONEncoder().encode(settings)), settings)
    }
}
