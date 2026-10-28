import XCTest

@testable import AulaCore

final class RecoveryAndPreviewTests: XCTestCase {
    func testIncompleteBurstsRecoverMissingPagesFromConsistentRetries() throws {
        let data = (0..<UInt16(490)).map { UInt8($0 % 256) }
        let packets = DeviceConfiguration.packets(data, command: 0x49)
        var assembly = WirelessReadAssembly(command: 0x49)
        // A real failure returned 33 of 35 pages and then lost different pages
        // on the next request. Both bursts together contain the complete data.
        XCTAssertNil(try assembly.merge(packets.enumerated().filter { ![17, 25].contains($0.offset) }.map(\.element)))
        XCTAssertEqual(
            try assembly.merge(packets.enumerated().filter { ![4, 10].contains($0.offset) }.map(\.element)), data)
    }
    func testChangedOverlapDiscardsOldPagesInsteadOfMixingSettings() throws {
        let data = Array(0..<UInt8(40))
        let original = DeviceConfiguration.packets(data, command: 0x44)
        var changedData = data
        changedData[2] = 200
        let changed = DeviceConfiguration.packets(changedData, command: 0x44)
        var assembly = WirelessReadAssembly(command: 0x44)
        XCTAssertNil(try assembly.merge([original[0], original[1]]))
        XCTAssertNil(try assembly.merge([changed[0], changed[2]]))
        XCTAssertEqual(assembly.pages.count, 2)
        XCTAssertEqual(try assembly.merge([changed[1], changed[2]]), changedData)
    }
    func testReadRecoveryRejectsCorruptionAndDoesNotCountDuplicatesAsMissingPages() throws {
        let packets = DeviceConfiguration.packets(Array(0..<UInt8(40)), command: 0x44)
        var assembly = WirelessReadAssembly(command: 0x44)
        XCTAssertNil(try assembly.merge([packets[0], packets[0]]))
        XCTAssertEqual(assembly.pages.count, 1)
        var corrupt = packets[1]
        corrupt[8] ^= 1
        XCTAssertThrowsError(try assembly.merge([corrupt]))
        XCTAssertThrowsError(try assembly.merge([[0x13]]))
        XCTAssertNil(try assembly.merge([]))
        XCTAssertEqual(try assembly.merge([packets[1], packets[2]]), Array(0..<UInt8(40)))
    }
    func testReadRecoveryIgnoresUnusedPaddingInShortFinalPages() throws {
        let data = Array(0..<UInt8(30))
        let packets = DeviceConfiguration.packets(data, command: 0x44)
        var padded = packets[2]
        padded[12] = 255
        WirelessPacket.seal(&padded)
        var assembly = WirelessReadAssembly(command: 0x44)
        XCTAssertNil(try assembly.merge([packets[0], packets[2]]))
        XCTAssertEqual(try assembly.merge([packets[1], padded]), data)
    }
    func testLostAcknowledgmentsRetryTheSamePageAndCompleteTheTransfer() throws {
        let pages = DeviceConfiguration.packets(Array(0..<UInt8(40)), command: 9)
        var sends: [Int] = []
        var attempts: [Int: Int] = [:]
        try WirelessWriter.write(
            pages,
            send: { page in
                let index = Int(page[3])
                sends.append(index)
                attempts[index, default: 0] += 1
            },
            receiveEcho: { page in
                // Drop the first two echoes of page 1, as a receiver can do under load.
                page[3] != 1 || attempts[1] == 3
            }, pause: {})
        XCTAssertEqual(sends, [0, 1, 1, 1, 2])
    }
    func testPersistentLossStopsBeforeSendingLaterPages() {
        let pages = DeviceConfiguration.packets(Array(0..<UInt8(40)), command: 4)
        var sends: [Int] = []
        XCTAssertThrowsError(
            try WirelessWriter.write(pages, send: { sends.append(Int($0[3])) }, receiveEcho: { _ in false }, pause: {})
        ) { error in
            guard case AulaError.missingAcknowledgment(let command, let sequence, let count) = error else {
                return XCTFail("Incorrect error: \(error)")
            }
            XCTAssertEqual(command, 4)
            XCTAssertEqual(sequence, 0)
            XCTAssertEqual(count, 3)
            XCTAssertFalse(error.localizedDescription.lowercased().contains("wake"))
        }
        XCTAssertEqual(sends, [0, 0, 0])
    }
    func testEveryAnimatedEffectChangesItsRenderedColorsOverTime() {
        var settings = LightingSettings()
        settings.brightness = 4
        for effect in LightingEffect.all where LightingPreview.animates(effect.id) {
            settings.effect = effect.id
            var frames = Set<[RGB]>()
            for time in [0.0, 0.4, 0.9, 1.4, 2.1] {
                let samples = (0..<60).map { index in
                    LightingPreview.color(
                        settings: settings, x: Double(index % 10) / 9, y: Double(index / 10) / 5, index: index,
                        elapsed: time)
                }
                frames.insert(samples)
            }
            XCTAssertGreaterThan(frames.count, 1, "Effect \(effect.id) has a static preview")
            XCTAssertTrue(frames.contains { $0.contains { $0 != .black } }, "Effect \(effect.id) is invisible")
        }
    }
    func testPreviewHonorsBrightnessSpeedAndPerKeyColors() {
        var settings = LightingSettings()
        settings.effect = 2
        settings.brightness = 0
        XCTAssertEqual(LightingPreview.color(settings: settings, x: 0.4, y: 0.5, index: 3, elapsed: 1), .black)
        settings.brightness = 4
        settings.speed = 0
        let slow = LightingPreview.color(settings: settings, x: 0.4, y: 0.5, index: 3, elapsed: 1)
        settings.speed = 4
        XCTAssertNotEqual(slow, LightingPreview.color(settings: settings, x: 0.4, y: 0.5, index: 3, elapsed: 1))
        settings.effect = 21
        settings.keys[3] = RGB(12, 34, 56)
        XCTAssertEqual(LightingPreview.color(settings: settings, x: 0.4, y: 0.5, index: 3, elapsed: 1), RGB(12, 34, 56))
        XCTAssertEqual(LightingPreview.color(settings: settings, x: 0.4, y: 0.5, index: 4, elapsed: 1), .black)
        settings.effect = 0
        XCTAssertEqual(LightingPreview.color(settings: settings, x: 0.4, y: 0.5, index: 3, elapsed: 1), .black)
    }
    func testReactivePreviewRespondsToClickLocationAndFades() {
        var settings = LightingSettings()
        settings.effect = 12
        settings.brightness = 4
        settings.color = RGB(0, 255, 0)
        let fresh = LightingPreview.Pulse(x: 0.2, y: 0.5, age: 0)
        let faded = LightingPreview.Pulse(x: 0.2, y: 0.5, age: 1)
        let here = LightingPreview.color(settings: settings, x: 0.2, y: 0.5, index: 3, elapsed: 1, pulse: fresh)
        let elsewhere = LightingPreview.color(settings: settings, x: 0.8, y: 0.5, index: 3, elapsed: 1, pulse: fresh)
        let later = LightingPreview.color(settings: settings, x: 0.2, y: 0.5, index: 3, elapsed: 1, pulse: faded)
        XCTAssertNotEqual(here, elsewhere)
        XCTAssertGreaterThan(here.g, later.g)
    }
    func testFadingOutlinesBlendBackIntoTheNeutralBorder() {
        let off = LightingPreview.outlineTint(for: .black)
        XCTAssertEqual(off.opacity, 0)
        // Half-lit red blends with gray instead of painting a dark red/black edge.
        let half = LightingPreview.outlineTint(for: RGB(128, 0, 0))
        XCTAssertEqual(half.color, RGB(255, 0, 0))
        XCTAssertEqual(half.opacity, 128.0 / 255)
        func composite(_ value: UInt8, opacity: Double) -> Int {
            Int((Double(value) * opacity + 159 * (1 - opacity)).rounded())
        }
        XCTAssertEqual(composite(half.color.r, opacity: half.opacity), 207)
        XCTAssertEqual(composite(half.color.g, opacity: half.opacity), 79)
        // The last fading frame must be within one channel value of gray.
        let last = LightingPreview.outlineTint(for: RGB(1, 0, 1))
        for channel in [last.color.r, last.color.g, last.color.b] {
            XCTAssertLessThanOrEqual(abs(composite(channel, opacity: last.opacity) - 159), 1)
        }
    }

}
