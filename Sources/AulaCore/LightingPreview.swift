import Foundation

/// An illustration of each effect, not an emulation of a particular firmware.
/// Positions are normalized to the keyboard's width and height.
public enum LightingPreview {
    public struct Pulse: Sendable {
        public var x: Double
        public var y: Double
        public var age: Double
        public init(x: Double, y: Double, age: Double) {
            self.x = x
            self.y = y
            self.age = age
        }
    }
    public static func animates(_ effect: Int) -> Bool { (2...18).contains(effect) }

    public static func color(
        settings: LightingSettings, x: Double, y: Double, index: Int, elapsed: Double, pulse: Pulse? = nil
    ) -> RGB {
        if settings.effect == 0 { return .black }
        if settings.effect == 21 { return settings.keys[index] ?? .black }
        let t = elapsed * (0.35 + Double(settings.speed) * 0.27)
        let brightness = min(1, max(0, Double(settings.brightness) / 4))
        let seed = fraction(sin(Double(index + 1) * 127.1) * 43758.5453)
        var hue = fraction(x * 0.8 + y * 0.2 + t * 0.08)
        var spectrum = settings.colorful
        var light = 1.0
        let tau = Double.pi * 2
        switch settings.effect {
        case 1: break
        case 2:
            light = 0.03 + 0.97 * pow((sin(t * tau * 0.45) + 1) / 2, 1.6)
        case 3:
            spectrum = true
            hue = fraction(x - t * 0.16)
        case 4:
            light = fraction((x + y * 0.23) * 5 - t * 0.8) < 0.3 ? 1 : 0.025
        case 5:
            light = pow(max(0, sin((t * 0.45 + seed) * tau)), 18)
            hue = fraction(seed + t * 0.02)
        case 6:
            let angle = atan2((y - 0.5) * 0.65, x - 0.5)
            hue = fraction(angle / tau + t * 0.18)
            light = settings.colorful ? 1 : 0.03 + 0.97 * pow((cos(angle * 3 - t * 4) + 1) / 2, 3)
        case 7, 9, 12:
            let automatic = Pulse(
                x: 0.12 + 0.7 * fraction(floor(elapsed / 1.8) * 0.381), y: 0.5,
                age: elapsed.truncatingRemainder(dividingBy: 1.8))
            let event = pulse.flatMap { $0.age < 2.5 ? $0 : nil } ?? automatic
            let age = max(0, event.age)
            let distance = hypot((x - event.x) * 1.6, (y - event.y) * 0.7)
            if settings.effect == 7 {
                light = exp(-pow((distance - age * 0.5) / 0.11, 2)) * exp(-age * 1.4)
            } else {
                light =
                    exp(-pow(distance / (settings.effect == 9 ? 0.22 : 0.15), 2))
                    * exp(-age * (settings.effect == 9 ? 1.5 : 3))
            }
        case 8:
            light = 0.025 + 0.975 * pow((sin(t * (1.2 + seed * 2) + seed * tau) + 1) / 2, 9)
            hue = seed
        case 10:
            let row = min(5, Int(y * 6))
            let position = (Double(row) + (row.isMultiple(of: 2) ? x : 1 - x)) / 6
            light = max(0, 1 - fraction(t * 0.16 - position) / 0.18)
        case 11:
            light = max(0, 1 - fraction(t * 0.35 - x - y * 0.18) / 0.24)
        case 13:
            let center = 0.5 + 0.3 * sin(x * tau * 1.3 - t * 2)
            light = exp(-pow((y - center) / 0.16, 2))
        case 14:
            let center = (sin(t * 2) + 1) / 2
            light = exp(-pow((x - center) / 0.09, 2))
        case 15:
            spectrum = true
            let angle = atan2((y - 0.5) * 0.65, x - 0.5)
            hue = fraction(angle / tau - t * 0.15)
            light = 0.08 + 0.92 * pow((cos(angle * 3 - t * 4) + 1) / 2, 3)
        case 16:
            spectrum = true
            hue = fraction(y - t * 0.3 + x * 0.1)
            light = 0.15 + 0.85 * pow((sin((y - t * 0.3) * tau * 2) + 1) / 2, 2)
        case 17:
            spectrum = true
            let angle = atan2(y - 0.5, x - 0.5)
            let distance = hypot((x - 0.5) * 1.4, y - 0.5)
            light = pow(max(0, cos(distance * 12 - t * 4 + sin(angle * 5) * 0.7)), 4)
        case 18:
            let angle = atan2((y - 0.5) * 0.65, x - 0.5)
            let distance = hypot((x - 0.5) * 1.4, y - 0.5)
            hue = fraction(angle / tau + distance - t * 0.15)
            light = 0.04 + 0.96 * pow((cos(angle * 3 - distance * 10 - t * 4) + 1) / 2, 3)
        default: break
        }
        let base = spectrum ? hsv(hue) : settings.color
        return dim(base, by: brightness * min(1, max(0, light)))
    }
    /// Fade a fully colored outline to transparency over the neutral key edge.
    /// Drawing a dim RGB value opaquely would replace that edge with black.
    public static func outlineTint(for sample: RGB) -> (color: RGB, opacity: Double) {
        let peak = max(sample.r, max(sample.g, sample.b))
        guard peak > 0 else { return (.black, 0) }
        func channel(_ value: UInt8) -> UInt8 {
            UInt8(min(255, (Double(value) * 255 / Double(peak)).rounded()))
        }
        return (RGB(channel(sample.r), channel(sample.g), channel(sample.b)), Double(peak) / 255)
    }
    private static func fraction(_ value: Double) -> Double { value - floor(value) }
    private static func dim(_ color: RGB, by level: Double) -> RGB {
        func channel(_ byte: UInt8) -> UInt8 { UInt8(min(255, max(0, (Double(byte) * level).rounded()))) }
        return RGB(channel(color.r), channel(color.g), channel(color.b))
    }
    private static func hsv(_ hue: Double) -> RGB {
        let h = fraction(hue) * 6
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let components: (Double, Double, Double)
        switch Int(h) {
        case 0: components = (1, x, 0)
        case 1: components = (x, 1, 0)
        case 2: components = (0, 1, x)
        case 3: components = (0, x, 1)
        case 4: components = (x, 0, 1)
        default: components = (1, 0, x)
        }
        return RGB(
            UInt8((components.0 * 255).rounded()), UInt8((components.1 * 255).rounded()),
            UInt8((components.2 * 255).rounded()))
    }
}
