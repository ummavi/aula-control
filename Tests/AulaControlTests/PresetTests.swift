import AulaCore
import XCTest

@testable import AulaControl

final class PresetTests: XCTestCase {
    func testDocumentedExampleDecodesAsAnImportablePreset() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("examples/green-reactive.json"))
        let preset = try JSONDecoder().decode(Preset.self, from: data)
        XCTAssertEqual(preset.settings.effect, 12)
        XCTAssertEqual(preset.settings.color, RGB(0, 255, 0))
        XCTAssertEqual(preset.auxiliary?["sideStrips"]?.colorIndex, 1)
        XCTAssertEqual(preset.auxiliary?["lightBar"]?.colorIndex, 2)
    }

    func testLegacyPresetOmitsAuxiliaryLightingAndStillDecodes() throws {
        let original = Preset(name: "Legacy example", settings: LightingSettings())
        let data = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["auxiliary"])
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        XCTAssertEqual(decoded.settings, original.settings)
        XCTAssertNil(decoded.auxiliary)
    }

    func testPresetRetainsAllZonesAndExactDeviceRGBValues() throws {
        var settings = LightingSettings()
        settings.color = RGB(0, 255, 0)
        settings.keys = [0: RGB(255, 0, 0), 125: RGB(0, 0, 255)]
        let zones = [
            "sideStrips": AuxiliaryLightingSettings(effect: 3, colorIndex: 1),
            "lightBar": AuxiliaryLightingSettings(effect: 4, colorIndex: 2),
        ]
        let original = Preset(name: "Three zones", settings: settings, auxiliary: zones)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.settings, original.settings)
        XCTAssertEqual(decoded.auxiliary, zones)
        XCTAssertEqual(decoded.settings.color, RGB(0, 255, 0))
        XCTAssertNotEqual(decoded.settings.color, LightingColorSwatch.face(for: decoded.settings.color))
    }
}
