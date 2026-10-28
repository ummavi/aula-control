import AulaCore
import Foundation

/// Portable lighting data; the optional auxiliary object keeps old presets readable.
struct Preset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var settings: LightingSettings
    var auxiliary: [String: AuxiliaryLightingSettings]? = nil
}
