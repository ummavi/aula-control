import XCTest

@testable import AulaCore

final class AuxiliaryLightingTests: XCTestCase {
    private func configuration() throws -> DeviceConfiguration {
        var bytes = (0..<128).map { UInt8($0) }
        bytes[10] = 12
        bytes.replaceSubrange(18..<22, with: [3, 1, 4, 0])
        bytes.replaceSubrange(28..<32, with: [4, 2, 1, 3])
        bytes[126] = 0x5A
        bytes[127] = 0xA5
        return try DeviceConfiguration(bytes)
    }
    func testFieldsMatchTheF108NativeComparisons() throws {
        let config = try configuration()
        XCTAssertEqual(config.auxiliaryLighting(.sideStrips), .init(effect: 3, colorIndex: 1, brightness: 4, speed: 0))
        XCTAssertEqual(config.auxiliaryLighting(.lightBar), .init(effect: 4, colorIndex: 2, brightness: 1, speed: 3))
    }
    func testEachZonePreservesMainLightingAndEveryOtherField() throws {
        let before = try configuration()
        for zone in AuxiliaryLightingZone.allCases {
            let desired = AuxiliaryLightingSettings(effect: 1, colorIndex: 6, brightness: 2, speed: 4)
            let change = AuxiliaryLightingChange(desired: desired, previous: before.auxiliaryLighting(zone))
            let after = try before.changingAuxiliaryLighting(change, zone: zone)
            XCTAssertEqual(after.auxiliaryLighting(zone), desired)
            for index in before.bytes.indices
            where !(zone.configurationOffset..<zone.configurationOffset + 4).contains(index) {
                XCTAssertEqual(after.bytes[index], before.bytes[index], "Changed unrelated field \(index) for \(zone)")
            }
        }
    }
    func testColorEditRetainsLaterPhysicalEffectBrightnessAndSpeedChanges() throws {
        for zone in AuxiliaryLightingZone.allCases {
            let previous = AuxiliaryLightingSettings(effect: 3, colorIndex: 0, brightness: 4, speed: 0)
            var desired = previous
            desired.colorIndex = 2
            let change = AuxiliaryLightingChange(desired: desired, previous: previous)
            var fresh = try configuration()
            fresh.bytes.replaceSubrange(zone.configurationOffset..<zone.configurationOffset + 4, with: [1, 0, 2, 4])
            let changed = try fresh.changingAuxiliaryLighting(change, zone: zone)
            XCTAssertEqual(changed.auxiliaryLighting(zone), .init(effect: 1, colorIndex: 2, brightness: 2, speed: 4))
        }
    }
    func testInvalidValuesAreRejectedWithoutChangingConfiguration() throws {
        let before = try configuration()
        for zone in AuxiliaryLightingZone.allCases {
            let previous = before.auxiliaryLighting(zone)
            var invalid = previous
            invalid.effect = zone.effectRange.upperBound + 1
            XCTAssertThrowsError(
                try before.changingAuxiliaryLighting(.init(desired: invalid, previous: previous), zone: zone))
            invalid = previous
            invalid.brightness = -1
            XCTAssertThrowsError(
                try before.changingAuxiliaryLighting(.init(desired: invalid, previous: previous), zone: zone))
            invalid = previous
            invalid.speed = 5
            XCTAssertThrowsError(
                try before.changingAuxiliaryLighting(.init(desired: invalid, previous: previous), zone: zone))
            invalid = previous
            invalid.colorIndex = 8
            XCTAssertThrowsError(
                try before.changingAuxiliaryLighting(.init(desired: invalid, previous: previous), zone: zone))
            let empty = AuxiliaryLightingChange(desired: previous, previous: previous)
            XCTAssertTrue(empty.isEmpty)
            XCTAssertEqual(try before.changingAuxiliaryLighting(empty, zone: zone), before)
        }
    }
    func testAuxiliaryPreviewsDistinguishSolidWaveCycleBreathingAndOff() throws {
        var settings = AuxiliaryLightingSettings(effect: 3, colorIndex: 2, brightness: 4, speed: 2)
        func color(_ position: Double, _ elapsed: Double) -> RGB {
            AuxiliaryLightingPreview.color(settings: settings, position: position, elapsed: elapsed)
        }
        XCTAssertEqual(color(0, 0), RGB(0, 0, 255))
        XCTAssertEqual(color(0, 0), color(0.8, 10))
        settings.effect = 1
        XCTAssertNotEqual(color(0, 1), color(0.4, 1))
        XCTAssertNotEqual(color(0, 1), color(0, 2))
        settings.effect = 2
        XCTAssertEqual(color(0, 1), color(0.4, 1))
        XCTAssertNotEqual(color(0, 1), color(0, 2))
        settings.effect = 4
        XCTAssertNotEqual(color(0, 0), color(0, 1))
        settings.effect = 0
        XCTAssertEqual(color(0, 2), .black)
        settings.effect = 3
        settings.brightness = 0
        XCTAssertEqual(color(0, 2), .black)
        let encoded = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AuxiliaryLightingSettings.self, from: encoded), settings)
    }
}
