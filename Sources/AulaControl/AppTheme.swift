import AppKit
import AulaCore
import CoreText
import SwiftUI

/// One display palette for controls and preview lights. Device RGB is separate.
struct LightingColorSwatch: Identifiable {
    let name: String
    let value: RGB
    let face: RGB
    var id: String { value.hex }
    // HSV saturation increased by 30% from the previous display palette.
    static let all: [Self] = [
        .init(name: "Red", value: RGB(255, 0, 0), face: RGB(255, 53, 41)),
        .init(name: "Green", value: RGB(0, 255, 0), face: RGB(70, 222, 127)),
        .init(name: "Blue", value: RGB(0, 0, 255), face: RGB(61, 163, 242)),
        .init(name: "Yellow", value: RGB(255, 255, 0), face: RGB(246, 171, 30)),
        .init(name: "Magenta", value: RGB(255, 0, 255), face: RGB(231, 93, 167)),
        .init(name: "Cyan", value: RGB(0, 255, 255), face: RGB(70, 206, 192)),
        .init(name: "White", value: RGB(255, 255, 255), face: RGB(245, 245, 232)),
    ]
    private static let wheel = [all[0].face, all[3].face, all[1].face, all[5].face, all[2].face, all[4].face]
    /// Interpolate animated and custom hues through the same display colors.
    /// Preserve intensity so breathing, dimming, and fading still reach black.
    static func face(for value: RGB) -> RGB {
        let r = Double(value.r)
        let g = Double(value.g)
        let b = Double(value.b)
        let peak = max(r, max(g, b))
        let low = min(r, min(g, b))
        guard peak > 0 else { return .black }
        let delta = peak - low
        let hue: Double
        if delta == 0 {
            hue = 0
        } else if peak == r {
            hue = ((g - b) / delta + 6).truncatingRemainder(dividingBy: 6)
        } else if peak == g {
            hue = (b - r) / delta + 2
        } else {
            hue = (r - g) / delta + 4
        }
        let index = Int(hue)
        let fraction = hue - floor(hue)
        let a = wheel[index]
        let z = wheel[(index + 1) % 6]
        let white = all[6].face
        let saturation = delta / peak
        let intensity = peak / 255
        func channel(_ x: UInt8, _ y: UInt8, _ w: UInt8) -> UInt8 {
            let tint = Double(x) + (Double(y) - Double(x)) * fraction
            return UInt8(((Double(w) + (tint - Double(w)) * saturation) * intensity).rounded())
        }
        return RGB(channel(a.r, z.r, white.r), channel(a.g, z.g, white.g), channel(a.b, z.b, white.b))
    }
}

/// Figure-kit Classic on black. Presentation colors do not change device RGB.
enum AppTheme {
    static let page = color("000000")
    static let surface = color("000000")
    static let raised = color("000000")
    static let border = color("403E3C")
    static let controlBorder = color("6F6E69")
    static let text = color("CECDC3")
    static let secondary = color("9F9D96")
    static let accent = color("66A0C8")
    static let selection = color("000000")
    static let write = color("EC8B49")
    static let error = color("E8705F")
    static let errorSurface = color("000000")
    static let disabled = color("6F6E69")

    static func color(_ hex: String) -> Color {
        let value = UInt32(hex, radix: 16)!
        return Color(
            red: Double(value >> 16 & 255) / 255,
            green: Double(value >> 8 & 255) / 255,
            blue: Double(value & 255) / 255)
    }
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let face =
            weight == .bold ? "Bold" : weight == .semibold ? "SemiBold" : weight == .medium ? "Medium" : "Regular"
        return .custom("Inter-\(face)", size: size)
    }
    static func registerFonts() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts")
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
            "Resources/Fonts")
        for root in [bundled, development].compactMap({ $0 }) {
            for face in ["Regular", "Medium", "SemiBold", "Bold"] {
                let url = root.appendingPathComponent("Inter-\(face).otf")
                if FileManager.default.fileExists(atPath: url.path) {
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                }
            }
        }
    }
}

struct SquareButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let outline =
            !enabled
            ? AppTheme.controlBorder
            : primary ? AppTheme.write : configuration.isPressed ? AppTheme.accent : AppTheme.controlBorder
        configuration.label
            .font(AppTheme.font(12, weight: .medium))
            .foregroundStyle(enabled && primary ? AppTheme.write : enabled ? AppTheme.text : AppTheme.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(AppTheme.page)
            .overlay(
                Rectangle().stroke(outline, lineWidth: 1)
                    .shadow(
                        color: enabled && (primary || configuration.isPressed) ? outline.opacity(0.25) : .clear,
                        radius: 2, x: 0, y: 0))
    }
}

struct SquareToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Rectangle().fill(AppTheme.page).frame(width: 14, height: 14)
                    .overlay(
                        Rectangle().stroke(configuration.isOn ? AppTheme.accent : AppTheme.controlBorder, lineWidth: 1)
                    )
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(
                                AppTheme.accent)
                        }
                    }
                configuration.label
            }
        }.buttonStyle(.plain)
    }
}

struct SquareSlider: View {
    @Binding var value: Int
    let maximum: Int
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 8)
            ZStack(alignment: .leading) {
                Rectangle().fill(AppTheme.controlBorder).frame(height: 1)
                HStack(spacing: 0) {
                    ForEach(0...maximum, id: \.self) { index in
                        Rectangle().fill(AppTheme.secondary).frame(width: 1, height: 7)
                        if index < maximum { Spacer(minLength: 0) }
                    }
                }.padding(.horizontal, 4)
                Rectangle().fill(enabled ? AppTheme.text : AppTheme.controlBorder).frame(width: 8, height: 16)
                    .offset(x: Double(min(maximum, max(0, value))) / Double(maximum) * width)
            }
            .frame(maxHeight: .infinity).contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { event in
                    guard enabled else { return }
                    value = min(maximum, max(0, Int(((event.location.x - 4) / width * Double(maximum)).rounded())))
                })
        }
        .frame(height: 20)
        .focusable(enabled)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            guard enabled else { return .ignored }
            value = max(0, value - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard enabled else { return .ignored }
            value = min(maximum, value + 1)
            return .handled
        }
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: 0...Double(maximum), step: 1)
        }
    }
}

private final class ColorPanelBridge: NSObject, ObservableObject {
    var changed: ((Color) -> Void)?
    func show(_ color: Color, changed: @escaping (Color) -> Void) {
        self.changed = changed
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(color)
        panel.setTarget(self)
        panel.setAction(#selector(changeColor(_:)))
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func changeColor(_ sender: NSColorPanel) { changed?(Color(nsColor: sender.color)) }
}

struct SquareColorWell: View {
    @Binding var color: Color
    var displayColor: Color? = nil
    @StateObject private var panel = ColorPanelBridge()
    var body: some View {
        Button {
            let binding = $color
            panel.show(color) { binding.wrappedValue = $0 }
        } label: {
            Rectangle().fill(displayColor ?? color).frame(width: 24, height: 24)
                .overlay(Rectangle().stroke(AppTheme.secondary, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel("Choose color")
    }
}
