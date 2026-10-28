import AulaCore
import SwiftUI

struct KeyCap: Identifiable {
    var id: Int { usage }
    let label: String
    let usage: Int
    let x: Double
    let y: Double
    var w = 1.0
    var h = 1.0
    static let all: [KeyCap] = {
        var keys: [KeyCap] = []
        func row(_ labels: [String], _ usages: [Int], x: Double, y: Double, widths: [Int: Double] = [:]) {
            var position = x
            for index in labels.indices {
                let width = widths[index] ?? 1
                keys.append(KeyCap(label: labels[index], usage: usages[index], x: position, y: y, w: width))
                position += width
            }
        }
        row(["esc"], [41], x: 0, y: 0)
        for group in 0..<3 {
            row(
                (1...4).map { "F\(group * 4 + $0)" }, (58 + group * 4..<62 + group * 4).map { $0 },
                x: 2 + Double(group) * 4.5, y: 0)
        }
        row(["prt", "scr", "pause"], [70, 71, 72], x: 15.5, y: 0)
        row(["calc", "mute", "vol−", "vol+"], [0x10192, 0x100E2, 0x100EA, 0x100E9], x: 19, y: 0)
        row(
            ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "−", "=", "delete"],
            [53, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 45, 46, 42], x: 0, y: 1.4, widths: [13: 2])
        row(
            ["tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],
            [43, 20, 26, 8, 21, 23, 28, 24, 12, 18, 19, 47, 48, 49], x: 0, y: 2.4, widths: [0: 1.5, 13: 1.5])
        row(
            ["caps", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "return"],
            [57, 4, 22, 7, 9, 10, 11, 13, 14, 15, 51, 52, 40], x: 0, y: 3.4, widths: [0: 1.75, 12: 2.25])
        row(
            ["shift", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "shift"],
            [225, 29, 27, 6, 25, 5, 17, 16, 54, 55, 56, 229], x: 0, y: 4.4, widths: [0: 2.25, 11: 2.75])
        row(
            ["ctrl", "⌘", "opt", "", "opt", "fn", "menu", "ctrl"], [224, 227, 226, 44, 230, 0xFFFF, 101, 228], x: 0,
            y: 5.4, widths: [0: 1.25, 1: 1.25, 2: 1.25, 3: 6.25, 4: 1.25, 5: 1.25, 6: 1.25, 7: 1.25])
        row(["ins", "home", "pg↑"], [73, 74, 75], x: 15.5, y: 1.4)
        row(["del", "end", "pg↓"], [76, 77, 78], x: 15.5, y: 2.4)
        row(["↑"], [82], x: 16.5, y: 4.4)
        row(["←", "↓", "→"], [80, 81, 79], x: 15.5, y: 5.4)
        row(["num", "/", "×", "−"], [83, 84, 85, 86], x: 19, y: 1.4)
        row(["7", "8", "9"], [95, 96, 97], x: 19, y: 2.4)
        row(["4", "5", "6"], [92, 93, 94], x: 19, y: 3.4)
        row(["1", "2", "3"], [89, 90, 91], x: 19, y: 4.4)
        row(["0", "."], [98, 99], x: 19, y: 5.4, widths: [0: 2])
        keys.append(KeyCap(label: "+", usage: 87, x: 22, y: 2.4, h: 2))
        keys.append(KeyCap(label: "enter", usage: 88, x: 22, y: 4.4, h: 2))
        return keys
    }()
}

struct KeyboardPreview: View {
    @ObservedObject var model: AppModel
    @State private var started = Date()
    @State private var lastClick: (date: Date, x: Double, y: Double)?
    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: !LightingPreview.animates(model.settings.effect) && !model.animatesAuxiliary)
        ) { timeline in
            Canvas { context, size in
                let layout = layout(size)
                let board = Path(layout.board)
                context.fill(board, with: .color(AppTheme.page))
                let elapsed = timeline.date.timeIntervalSince(started)
                let auxiliary = auxiliarySegments(layout: layout, elapsed: elapsed)
                let pulse = lastClick.map {
                    LightingPreview.Pulse(x: $0.x, y: $0.y, age: timeline.date.timeIntervalSince($0.date))
                }
                let keys: [(rect: CGRect, index: Int?, color: RGB)] = KeyCap.all.enumerated().map { position, key in
                    let index = ledIndex(key.usage)
                    let sample =
                        model.settings.effect == 21 && index == nil
                        ? RGB.black
                        : LightingPreview.color(
                            settings: model.settings,
                            x: (key.x + key.w / 2) / 23, y: (key.y + key.h / 2) / 6.4,
                            index: index ?? position, elapsed: elapsed, pulse: pulse)
                    return (keyRect(key, layout: layout), index, sample)
                }
                // Soft LED pools sit below the dark, translucent key faces.
                // Keep this layer isolated from all crisp borders and legends.
                context.drawLayer { light in
                    light.clip(to: board)
                    for key in keys where key.color != .black {
                        let center = CGPoint(x: key.rect.midX, y: key.rect.midY)
                        let radius = layout.unit * 1.15
                        let pool = Path(
                            ellipseIn: CGRect(
                                x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2))
                        let rgb = Color(LightingColorSwatch.face(for: key.color))
                        light.fill(
                            pool,
                            with: .radialGradient(
                                Gradient(stops: [
                                    .init(color: rgb.opacity(0.55), location: 0),
                                    .init(color: rgb.opacity(0.28), location: 0.45),
                                    .init(color: rgb.opacity(0.08), location: 0.75),
                                    .init(color: .clear, location: 1),
                                ]), center: center, startRadius: 0, endRadius: radius))
                    }
                    for segment in auxiliary where segment.color != .black {
                        let center = CGPoint(x: segment.rect.midX, y: segment.rect.midY)
                        let radius = layout.unit * 0.55
                        light.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                            with: .radialGradient(
                                Gradient(colors: [
                                    Color(LightingColorSwatch.face(for: segment.color)).opacity(0.24), .clear,
                                ]), center: center, startRadius: 0, endRadius: radius))
                    }
                }
                for key in keys {
                    context.fill(Path(key.rect), with: .color(AppTheme.page.opacity(0.82)))
                }
                for segment in auxiliary {
                    context.fill(
                        Path(segment.rect),
                        with: .color(Color(LightingColorSwatch.face(for: segment.color)).opacity(0.85)))
                }
                for zone in AuxiliaryLightingZone.allCases {
                    for rect in auxiliaryFrames(zone, layout: layout) {
                        context.stroke(Path(rect), with: .color(AppTheme.secondary), lineWidth: 0.7)
                        if model.selectedLightingZone == zone {
                            context.stroke(
                                Path(rect.insetBy(dx: -2, dy: -2)), with: .color(AppTheme.accent), lineWidth: 0.8)
                        }
                    }
                }
                for key in keys {
                    let path = Path(key.rect)
                    let outline = LightingPreview.outlineTint(for: key.color)
                    context.stroke(path, with: .color(AppTheme.secondary), lineWidth: 1.2)
                    if outline.opacity > 0 {
                        context.stroke(
                            path,
                            with: .color(Color(LightingColorSwatch.face(for: outline.color)).opacity(outline.opacity)),
                            lineWidth: 0.65)
                    }
                    if model.selectedKeys.contains(key.index ?? -1) {
                        context.stroke(path, with: .color(.white), lineWidth: 1.8)
                    }
                }
                context.stroke(board, with: .color(AppTheme.controlBorder), lineWidth: 1)
            }
        }
        // Keep legends in a static layer independent of animated Canvas drawing.
        .overlay {
            GeometryReader { geometry in
                let layout = layout(geometry.size)
                ZStack(alignment: .topLeading) {
                    ForEach(KeyCap.all) { key in
                        let rect = keyRect(key, layout: layout)
                        Text(key.label)
                            .font(AppTheme.font(12, weight: .medium))
                            .foregroundStyle(AppTheme.text)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: max(1, rect.width - 4), height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }.allowsHitTesting(false)
                Color.clear.contentShape(Rectangle()).onTapGesture { point in
                    guard !model.busy else { return }
                    if let zone = AuxiliaryLightingZone.allCases.first(where: { zone in
                        auxiliaryFrames(zone, layout: layout).contains { $0.insetBy(dx: -5, dy: -5).contains(point) }
                    }) {
                        model.selectedLightingZone = zone
                        model.selectedKeys = []
                        return
                    }
                    guard let key = KeyCap.all.first(where: { keyRect($0, layout: layout).contains(point) }) else {
                        return
                    }
                    if model.selectedLightingZone != nil {
                        model.selectedLightingZone = nil
                        return
                    }
                    if model.settings.effect == 21, let index = ledIndex(key.usage) {
                        model.paintKey(index)
                    } else {
                        lastClick = (Date(), (key.x + key.w / 2) / 23, (key.y + key.h / 2) / 6.4)
                    }
                }
            }
        }
        .onChange(of: model.settings.effect) { _, _ in
            started = Date()
            lastClick = nil
        }
        .accessibilityLabel("Keyboard lighting preview")
        .accessibilityChildren {
            ForEach(KeyCap.all) { key in
                Button(key.label.isEmpty ? "Space" : key.label) {
                    if model.settings.effect == 21, let index = ledIndex(key.usage) { model.paintKey(index) }
                }.disabled(
                    model.selectedLightingZone != nil || model.settings.effect != 21 || ledIndex(key.usage) == nil)
            }
        }
    }
    private func ledIndex(_ usage: Int) -> Int? { model.snapshot?.ledIndicesByUsage[usage] }
    private func auxiliaryFrames(_ zone: AuxiliaryLightingZone, layout: (board: CGRect, unit: Double)) -> [CGRect] {
        let board = layout.board
        if zone == .sideStrips {
            return [
                CGRect(x: board.minX + 2, y: board.minY + 14, width: 2.5, height: board.height - 28),
                CGRect(x: board.maxX - 4.5, y: board.minY + 14, width: 2.5, height: board.height - 28),
            ]
        }
        return [
            CGRect(
                x: board.minX + 8 + 15.5 * layout.unit, y: board.minY + 8 + 3.65 * layout.unit,
                width: 2.85 * layout.unit, height: 0.16 * layout.unit)
        ]
    }
    private func auxiliarySegments(layout: (board: CGRect, unit: Double), elapsed: Double) -> [(
        rect: CGRect, color: RGB
    )] {
        var segments: [(rect: CGRect, color: RGB)] = []
        for zone in AuxiliaryLightingZone.allCases {
            let settings = model.auxiliary[zone] ?? AuxiliaryLightingSettings(effect: 0)
            for frame in auxiliaryFrames(zone, layout: layout) {
                for index in 0..<16 {
                    let position = Double(index) / 16
                    let rect =
                        zone == .sideStrips
                        ? CGRect(
                            x: frame.minX, y: frame.minY + frame.height * position, width: frame.width,
                            height: frame.height / 16)
                        : CGRect(
                            x: frame.minX + frame.width * position, y: frame.minY, width: frame.width / 16,
                            height: frame.height)
                    segments.append(
                        (rect, AuxiliaryLightingPreview.color(settings: settings, position: position, elapsed: elapsed))
                    )
                }
            }
        }
        return segments
    }
    private func layout(_ size: CGSize) -> (board: CGRect, unit: Double) {
        let unit = max(1, min((size.width - 24) / 23, (size.height - 24) / 6.4))
        let board = CGRect(
            x: (size.width - unit * 23 - 16) / 2, y: (size.height - unit * 6.4 - 16) / 2,
            width: unit * 23 + 16, height: unit * 6.4 + 16)
        return (board, unit)
    }
    private func keyRect(_ key: KeyCap, layout: (board: CGRect, unit: Double)) -> CGRect {
        CGRect(
            x: layout.board.minX + 8 + key.x * layout.unit, y: layout.board.minY + 8 + key.y * layout.unit,
            width: key.w * layout.unit - 4, height: key.h * layout.unit - 4)
    }
}
