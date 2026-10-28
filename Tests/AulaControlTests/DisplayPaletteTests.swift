import AulaCore
import XCTest

@testable import AulaControl

final class DisplayPaletteTests: XCTestCase {
    func testSwatchesSelectVerifiedDeviceColorsAndSharePreviewColors() {
        let deviceColors = [
            RGB(255, 0, 0), RGB(0, 255, 0), RGB(0, 0, 255),
            RGB(255, 255, 0), RGB(255, 0, 255), RGB(0, 255, 255), RGB(255, 255, 255),
        ]
        XCTAssertEqual(LightingColorSwatch.all.map(\.value), deviceColors)
        for swatch in LightingColorSwatch.all {
            XCTAssertEqual(LightingColorSwatch.face(for: swatch.value), swatch.face, swatch.name)
        }
    }

    func testDisplayColorsFadeToBlackWithoutBrightnessReversals() {
        XCTAssertEqual(LightingColorSwatch.face(for: .black), .black)
        for swatch in LightingColorSwatch.all {
            var previous = 0
            for level in 0...255 {
                let value = RGB(
                    UInt8(Int(swatch.value.r) * level / 255),
                    UInt8(Int(swatch.value.g) * level / 255),
                    UInt8(Int(swatch.value.b) * level / 255))
                let face = LightingColorSwatch.face(for: value)
                let energy = Int(face.r) + Int(face.g) + Int(face.b)
                XCTAssertGreaterThanOrEqual(energy, previous, "Brightness reversal in \(swatch.name)")
                previous = energy
            }
        }
    }

    func testAnimatedSpectrumHasNoJumpsAtDisplayPaletteBoundaries() {
        let vertices = [
            RGB(255, 0, 0), RGB(255, 255, 0), RGB(0, 255, 0),
            RGB(0, 255, 255), RGB(0, 0, 255), RGB(255, 0, 255), RGB(255, 0, 0),
        ]
        var previous: RGB?
        for segment in 0..<6 {
            for step in 0...255 {
                let a = vertices[segment]
                let z = vertices[segment + 1]
                func interpolate(_ x: UInt8, _ y: UInt8) -> UInt8 {
                    UInt8((Int(x) * (255 - step) + Int(y) * step) / 255)
                }
                let color = RGB(interpolate(a.r, z.r), interpolate(a.g, z.g), interpolate(a.b, z.b))
                let face = LightingColorSwatch.face(for: color)
                if let previous {
                    XCTAssertLessThanOrEqual(abs(Int(previous.r) - Int(face.r)), 2)
                    XCTAssertLessThanOrEqual(abs(Int(previous.g) - Int(face.g)), 2)
                    XCTAssertLessThanOrEqual(abs(Int(previous.b) - Int(face.b)), 2)
                }
                previous = face
            }
        }
    }
}
