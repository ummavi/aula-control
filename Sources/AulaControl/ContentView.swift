import AulaCore
import SwiftUI

let accent = AppTheme.accent
let panelColor = AppTheme.surface
let quiet = AppTheme.secondary

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            WindowBar()
            content
        }
        .background(AppTheme.page)
        .overlay(Rectangle().stroke(AppTheme.border, lineWidth: 1))
    }
    private var content: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        if let error = model.error { errorBanner(error) }
                        if model.selectedTab == "Lighting" {
                            lightingZonePicker
                            keyboardPanel
                            if let zone = model.selectedLightingZone {
                                auxiliaryControls(zone)
                            } else {
                                lightingControls
                            }
                        } else if model.selectedTab == "Presets" {
                            presetsPanel
                        } else {
                            devicePanel
                        }
                    }
                    .padding(32)
                }
                footer
            }
            .background(AppTheme.page)
        }
        .frame(minWidth: 1060, minHeight: 760)
        .tint(accent)
        .foregroundStyle(AppTheme.text)
        .font(AppTheme.font(13))
        .buttonStyle(SquareButtonStyle())
        .background(AppTheme.page)
        .sheet(isPresented: $model.showSavePreset) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Save lighting preset").font(.title2.weight(.semibold))
                Text("Save the key lighting, side strips and light bar on your Mac.").foregroundStyle(
                    AppTheme.secondary)
                TextField("Preset name", text: $model.presetName).textFieldStyle(.plain).padding(8).overlay(
                    Rectangle().stroke(AppTheme.controlBorder)
                ).onSubmit { model.savePreset() }
                HStack {
                    Button("Cancel") { model.showSavePreset = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save Preset") { model.savePreset() }.buttonStyle(SquareButtonStyle(primary: true))
                        .disabled(model.presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(28).frame(width: 390).background(AppTheme.page)
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AULA Control").font(AppTheme.font(17, weight: .semibold)).padding(.bottom, 28)
            Text("F108").font(AppTheme.font(13, weight: .medium))
            HStack(spacing: 7) {
                Rectangle().fill(model.connected ? accent : AppTheme.write).frame(width: 4, height: 4)
                Text(model.connected ? "2.4 GHz connected" : "Not connected").font(AppTheme.font(12)).foregroundStyle(
                    quiet)
            }.padding(.top, 8).padding(.bottom, 28)
            ForEach(
                [("Lighting", "sun.max"), ("Presets", "square.stack"), ("Device & shortcuts", "slider.horizontal.3")],
                id: \.0
            ) { title, icon in
                Button {
                    model.selectedTab = title
                } label: {
                    HStack(spacing: 10) {
                        Rectangle().fill(model.selectedTab == title ? accent : AppTheme.page).frame(
                            width: 2, height: 18)
                        Text(title).font(AppTheme.font(13, weight: model.selectedTab == title ? .semibold : .regular))
                        Spacer()
                    }
                    .foregroundStyle(model.selectedTab == title ? accent : quiet)
                    .padding(.vertical, 12)
                }.buttonStyle(.plain)
            }
            Spacer()
            Text(AppInfo.version == "Development" ? AppInfo.version : "v\(AppInfo.version)")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(quiet)
        }
        .padding(24).frame(width: 205).background(AppTheme.page)
        .overlay(alignment: .trailing) { Rectangle().fill(AppTheme.border).frame(width: 1) }
    }
    private var header: some View {
        HStack {
            Text(model.selectedTab == "Lighting" ? "Lighting" : model.selectedTab).font(
                AppTheme.font(23, weight: .semibold))
            Spacer()
            Button(model.busy ? "Working…" : "Read from keyboard") { model.connect() }
                .disabled(model.busy)
        }
    }
    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(AppTheme.error)
            Text(error).font(AppTheme.font(12, weight: .regular)).foregroundStyle(AppTheme.text).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                model.error = nil
            } label: {
                Image(systemName: "xmark")
            }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }.padding(15).background(AppTheme.errorSurface, in: Rectangle())
    }
    private var keyboardPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("Preview")
                Spacer()
                Text(
                    model.selectedLightingZone == nil && model.settings.effect == 21
                        ? "Click to paint · Shift-click to select more"
                        : "Lighting preview · appearance may vary on the keyboard"
                )
                .font(AppTheme.font(12, weight: .regular)).foregroundStyle(quiet)
            }
            KeyboardPreview(model: model).frame(height: 280)
            HStack {
                HStack(spacing: 6) {
                    Rectangle().fill(
                        model.selectedLightingZone == nil
                            ? (model.settings.effect == 0
                                ? quiet : Color(LightingColorSwatch.face(for: model.settings.color)))
                            : Color(LightingColorSwatch.face(for: model.activeAuxiliary.color))
                    ).frame(width: 6, height: 6)
                    Text(
                        model.selectedLightingZone == nil
                            ? (model.effect?.name ?? "Effect \(model.settings.effect)")
                            : (model.activeAuxiliaryEffect?.name ?? "Effect \(model.activeAuxiliary.effect)")
                    ).font(AppTheme.font(12, weight: .medium))
                    Text("/ \(model.selectedLightingZone?.name ?? "Main keys")").font(
                        AppTheme.font(12, weight: .regular)
                    ).foregroundStyle(quiet)
                }
                Spacer()
                if model.selectedLightingZone == nil && model.settings.effect == 21 {
                    Button("Fill all") { model.fillKeys() }.buttonStyle(.plain)
                    Button("Clear") {
                        model.settings.keys = [:]
                        model.selectedKeys = []
                    }.buttonStyle(.plain)
                } else {
                    Text("108 KEYS").font(.system(size: 12, design: .monospaced)).tracking(1).foregroundStyle(quiet)
                }
            }
            if model.selectedLightingZone == nil && model.settings.effect == 21 {
                Text(
                    "Painting replaces the main backlight map. Brightness is set by each key’s color; dim the color to lower its intensity."
                )
                .font(AppTheme.font(12, weight: .regular)).foregroundStyle(quiet).fixedSize(
                    horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }
    private var lightingZonePicker: some View {
        HStack(spacing: 10) {
            zoneButton("Main keys", zone: nil)
            ForEach(AuxiliaryLightingZone.allCases, id: \.self) { zone in
                zoneButton(zone.name, zone: zone)
            }
        }.disabled(model.busy)
    }
    private func zoneButton(_ title: String, zone: AuxiliaryLightingZone?) -> some View {
        let selected = model.selectedLightingZone == zone
        return Button {
            model.selectedLightingZone = zone
            model.selectedKeys = []
        } label: {
            Text(title).font(AppTheme.font(13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? accent : quiet)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(AppTheme.page)
                .overlay(Rectangle().stroke(selected ? accent : AppTheme.controlBorder, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel("Edit \(title.lowercased())")
    }
    private func auxiliaryControls(_ zone: AuxiliaryLightingZone) -> some View {
        let settings = Binding(get: { model.activeAuxiliary }, set: { model.activeAuxiliary = $0 })
        return HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 15) {
                sectionLabel("Effect")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(AuxiliaryLightingEffect.all(for: zone)) { effect in
                        Button {
                            model.activeAuxiliary.effect = effect.id
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: effect.symbol).font(.system(size: 13)).frame(width: 16)
                                Text(effect.name).font(AppTheme.font(12, weight: .medium)).lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(model.activeAuxiliary.effect == effect.id ? accent : AppTheme.text)
                            .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 38)
                            .background(AppTheme.page)
                            .overlay(
                                Rectangle().stroke(
                                    model.activeAuxiliary.effect == effect.id ? accent : AppTheme.controlBorder,
                                    lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
                Text(
                    zone == .sideStrips
                        ? "The two case strips share these settings." : "The light bar sits above the arrow keys."
                )
                .font(AppTheme.font(12)).foregroundStyle(quiet)
                Text("Apply sends the controls you changed across all three zones.")
                    .font(AppTheme.font(12)).foregroundStyle(quiet)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 22) {
                sectionLabel("Controls")
                controlSlider(
                    "Brightness", symbol: "sun.max", value: settings.brightness, max: 4,
                    suffix: "\(model.activeAuxiliary.brightness * 25)%")
                controlSlider(
                    "Animation speed", symbol: "speedometer", value: settings.speed, max: 4,
                    suffix: ["Slowest", "Slow", "Medium", "Fast", "Fastest"][
                        min(4, max(0, model.activeAuxiliary.speed))]
                )
                .disabled(!(model.activeAuxiliaryEffect?.supportsSpeed ?? false))
                Divider().overlay(AppTheme.border)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        sectionLabel("Color")
                        Spacer()
                        Text(AuxiliaryLightingSettings.colorNames[min(7, max(0, model.activeAuxiliary.colorIndex))])
                            .font(AppTheme.font(12)).foregroundStyle(quiet)
                    }
                    HStack(spacing: 10) {
                        ForEach(0..<AuxiliaryLightingSettings.colors.count, id: \.self) { index in
                            Button {
                                model.activeAuxiliary.colorIndex = index
                            } label: {
                                Rectangle().fill(
                                    Color(LightingColorSwatch.face(for: AuxiliaryLightingSettings.colors[index]))
                                ).frame(width: 22, height: 22)
                                    .overlay(
                                        Rectangle().stroke(
                                            .white.opacity(model.activeAuxiliary.colorIndex == index ? 0.9 : 0),
                                            lineWidth: 2
                                        ).padding(-3))
                            }.buttonStyle(.plain).accessibilityLabel(
                                "\(zone.name) color \(AuxiliaryLightingSettings.colorNames[index])")
                        }
                    }
                    Text(
                        model.activeAuxiliaryEffect?.supportsColor == true
                            ? "Choose from this light’s built-in colors." : "This effect uses its own color spectrum."
                    )
                    .font(AppTheme.font(12)).foregroundStyle(quiet).fixedSize(horizontal: false, vertical: true)
                }.disabled(!(model.activeAuxiliaryEffect?.supportsColor ?? false))
            }.frame(width: 235).disabled(model.activeAuxiliary.effect == 0)
        }.disabled(model.busy || !model.connected)
    }
    private var lightingControls: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    sectionLabel("Effect")
                    Spacer()
                    Text("\(LightingEffect.all.count) modes").font(AppTheme.font(12, weight: .regular)).foregroundStyle(
                        quiet)
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(0..<(LightingEffect.all.count / 4), id: \.self) { row in
                        GridRow {
                            ForEach(0..<4, id: \.self) { column in
                                effectButton(LightingEffect.all[row * 4 + column])
                            }
                        }
                    }
                }
            }.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 22) {
                sectionLabel("Controls")
                if model.settings.effect != 21 {
                    controlSlider(
                        "Brightness", symbol: "sun.max", value: $model.settings.brightness, max: 4,
                        suffix: "\(Int((Double(model.settings.brightness) / 4 * 100).rounded()))%"
                    )
                    .disabled(model.settings.effect == 0)
                    controlSlider(
                        "Animation speed", symbol: "speedometer", value: $model.settings.speed, max: 4,
                        suffix: ["Slowest", "Slow", "Medium", "Fast", "Fastest"][min(4, max(0, model.settings.speed))]
                    )
                    .disabled(!(model.effect?.supportsSpeed ?? false))
                }
                Divider().overlay(AppTheme.border)
                colorControls
            }.frame(width: 235)
        }.disabled(model.busy)
    }
    private func effectButton(_ effect: LightingEffect) -> some View {
        Button {
            model.selectEffect(effect.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: effect.symbol).font(.system(size: 13)).frame(width: 16)
                Text(effect.name).font(AppTheme.font(12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(model.settings.effect == effect.id ? accent : AppTheme.text)
            .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 38)
            .background(AppTheme.page)
            .overlay(
                Rectangle().stroke(model.settings.effect == effect.id ? accent : AppTheme.controlBorder, lineWidth: 1)
                    .shadow(
                        color: model.settings.effect == effect.id ? accent.opacity(0.25) : .clear, radius: 2, x: 0, y: 0
                    )
            )
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help(effect.detail)
    }
    private var colorControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(model.settings.effect == 21 ? "Paint color" : "Color").font(AppTheme.font(12, weight: .medium))
                Spacer()
                if model.effect?.supportsColor == true {
                    Toggle("Multicolor", isOn: $model.settings.colorful).toggleStyle(SquareToggleStyle()).font(
                        AppTheme.font(12, weight: .regular))
                }
            }
            HStack(spacing: 9) {
                SquareColorWell(
                    color: Binding(get: { model.color }, set: { model.color = $0 }),
                    displayColor: Color(LightingColorSwatch.face(for: model.settings.color)))
                Text("#").foregroundStyle(quiet)
                TextField("RRGGBB", text: $model.hexText).font(.system(size: 12, design: .monospaced)).textFieldStyle(
                    .plain
                )
                .onSubmit { model.setHex() }.onChange(of: model.hexText) { _, value in
                    if RGB(hex: value) != nil { model.setHex() }
                }
            }.padding(10).background(panelColor, in: Rectangle())
            HStack(spacing: 10) {
                ForEach(LightingColorSwatch.all) { swatch in
                    Button {
                        model.setColor(swatch.value)
                    } label: {
                        Rectangle().fill(Color(swatch.face)).frame(width: 22, height: 22)
                            .overlay(
                                Rectangle().stroke(
                                    .white.opacity(model.settings.color == swatch.value ? 0.9 : 0), lineWidth: 2
                                ).padding(-3))
                    }.buttonStyle(.plain).accessibilityLabel("\(swatch.name) #\(swatch.value.hex)").help(
                        "\(swatch.name) · #\(swatch.value.hex)")
                }
            }
            Text(
                model.settings.effect == 21
                    ? "Choose a color, then click keys in the preview."
                    : model.settings.colorful || model.settings.effect == 3
                        ? "This effect uses the keyboard’s color spectrum."
                        : "Choose a swatch or enter a custom hex color."
            )
            .font(AppTheme.font(12, weight: .regular)).foregroundStyle(quiet).fixedSize(
                horizontal: false, vertical: true)
        }.disabled(
            model.settings.effect == 0
                || (model.settings.effect != 21 && (model.settings.colorful || model.settings.effect == 3)))
    }
    private func controlSlider(_ title: String, symbol: String, value: Binding<Int>, max: Int, suffix: String)
        -> some View
    {
        VStack(spacing: 10) {
            HStack {
                Label(title, systemImage: symbol).font(AppTheme.font(12, weight: .medium))
                Spacer()
                Text(suffix).font(.system(size: 12, design: .monospaced)).foregroundStyle(quiet)
            }
            SquareSlider(value: value, maximum: max).accessibilityLabel(title)
        }
    }
    private var presetsPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionLabel("Built-in presets")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                starter("Moonlight", color: RGB(0, 0, 255), detail: "Blue · solid")
                starter("Warm desk", color: RGB(255, 255, 0), detail: "Yellow · solid")
                starter("Aurora", color: RGB(0, 255, 0), detail: "Green · breathing", effect: 2)
                starter("Magenta", color: RGB(255, 0, 255), detail: "Magenta · solid")
                starter("Red glow", color: RGB(255, 0, 0), detail: "Red · breathing", effect: 2)
                starter("Full spectrum", color: RGB(0, 255, 0), detail: "Rainbow · animated", effect: 3, colorful: true)
            }
            HStack {
                sectionLabel("Saved presets")
                Spacer()
                Button("Import…") { model.importPreset() }
                Button("Save Current…") { model.showSavePreset = true }
            }
            if model.presets.isEmpty {
                Text("No saved presets.").font(AppTheme.font(13)).foregroundStyle(quiet).padding(.vertical, 16)
            }
            ForEach(model.presets) { preset in
                HStack(spacing: 14) {
                    Rectangle().fill(Color(LightingColorSwatch.face(for: preset.settings.color))).frame(
                        width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(preset.name).font(AppTheme.font(13, weight: .medium))
                        Text(LightingEffect.find(preset.settings.effect)?.name ?? "Lighting").font(
                            AppTheme.font(12, weight: .regular)
                        ).foregroundStyle(quiet)
                    }
                    Spacer()
                    Button("Load") { model.usePreset(preset) }
                    Button {
                        model.deletePreset(preset)
                    } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.plain).foregroundStyle(quiet).accessibilityLabel("Delete \(preset.name)")
                }.padding(16).background(panelColor, in: Rectangle())
            }
            Text("Loading a preset updates the preview. Select Apply to Keyboard to send it.").font(
                AppTheme.font(12, weight: .regular)
            ).foregroundStyle(quiet)
        }
    }
    private func starter(_ name: String, color: RGB, detail: String, effect: Int = 1, colorful: Bool = false)
        -> some View
    {
        Button {
            model.quickPreset(name: name, color: color, effect: effect, colorful: colorful)
            model.selectedTab = "Lighting"
        } label: {
            HStack(spacing: 12) {
                Rectangle().fill(Color(LightingColorSwatch.face(for: color))).frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 6) {
                    Text(name).font(AppTheme.font(13, weight: .medium)).foregroundStyle(AppTheme.text)
                    Text(detail).font(AppTheme.font(12)).foregroundStyle(quiet)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.border).frame(height: 1) }
        }.buttonStyle(.plain)
    }
    private var devicePanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionLabel("Connection")
            VStack(spacing: 14) {
                infoRow("Keyboard", "AULA F108")
                infoRow("Connection", model.connected ? "2.4 GHz USB receiver" : "Unavailable")
                infoRow("Receiver", "3554:FA09 · Compx")
                if let snapshot = model.snapshot {
                    infoRow("Battery", snapshot.battery.map { "\($0)%" } ?? "Not reported")
                    infoRow(
                        "Device identity",
                        snapshot.identity.prefix(6).map { String(format: "%02X", $0) }.joined(separator: " "))
                    infoRow("Mapped keys", "\(snapshot.ledIndicesByUsage.count) keys read from device")
                }
                infoRow(
                    "Last read-back",
                    model.lastVerified?.formatted(date: .omitted, time: .standard) ?? "Not yet connected")
            }.padding(20).background(panelColor, in: Rectangle())
            sectionLabel("Other lights")
            Text(
                "Select Side strips or Light bar in Lighting to control them independently. The keyboard’s Fn shortcuts also remain available."
            )
            .font(AppTheme.font(12, weight: .regular)).foregroundStyle(AppTheme.secondary).fixedSize(
                horizontal: false, vertical: true)
            VStack(spacing: 14) {
                infoRow("Light bar effect", "Fn + Right Shift")
                infoRow("Light bar speed", "Fn + Right Control")
                infoRow("Light bar brightness", "Fn + Right Option / Alt")
                infoRow("Light bar color", "Fn + / ?")
                Divider()
                infoRow("Side strip effect", "Fn + Left Shift")
                infoRow("Side strip speed", "Fn + Left Control")
                infoRow("Side strip brightness", "Fn + Left Option / Alt")
                infoRow("Side strip color", "Fn + Z")
            }.padding(20).background(panelColor, in: Rectangle())
            Text("These shortcuts are from the F108 manual. Press Fn combinations on the keyboard itself.")
                .font(AppTheme.font(12, weight: .regular)).foregroundStyle(quiet).fixedSize(
                    horizontal: false, vertical: true)
            sectionLabel("Data")
            Text(
                "Presets and a configuration backup before each write stay on this Mac. The app has no network service and does not record keystrokes."
            ).font(AppTheme.font(12, weight: .regular)).foregroundStyle(AppTheme.secondary)
            HStack {
                Button("Show Backups") {
                    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("AULA Control")
                    NSWorkspace.shared.open(root)
                }
                Button("Export Current Preset…") { model.exportPreset() }
            }
        }
    }
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(quiet)
            Spacer()
            Text(value).textSelection(.enabled)
        }.font(AppTheme.font(12, weight: .regular))
    }
    private var footer: some View {
        HStack(spacing: 12) {
            if model.busy {
                ProgressView().controlSize(.small).scaleEffect(0.75)
            } else {
                Image(systemName: model.error != nil ? "exclamationmark" : model.dirty ? "asterisk" : "checkmark")
                    .foregroundStyle(model.error != nil ? AppTheme.error : accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.dirty && !model.busy && model.error == nil ? "Preview has unapplied changes" : model.status)
                    .font(AppTheme.font(12, weight: .medium))
                Text("Main keys · side strips · light bar").font(AppTheme.font(12, weight: .regular)).foregroundStyle(
                    quiet)
            }
            Spacer()
            Button("Save Preset…") { model.showSavePreset = true }.buttonStyle(.plain).font(
                AppTheme.font(12, weight: .regular))
            Button {
                model.apply()
            } label: {
                Text(model.busy ? "Working…" : "Apply to Keyboard")
                    .font(AppTheme.font(12, weight: .semibold)).foregroundStyle(
                        model.canApply ? AppTheme.write : AppTheme.disabled
                    ).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(AppTheme.page)
                    .overlay(
                        Rectangle().stroke(model.canApply ? AppTheme.write : AppTheme.disabled, lineWidth: 1)
                            .shadow(
                                color: model.canApply ? AppTheme.write.opacity(0.25) : .clear, radius: 2, x: 0, y: 0))
            }.buttonStyle(.plain).disabled(!model.canApply).keyboardShortcut(.return, modifiers: .command)
        }.padding(.horizontal, 32).padding(.vertical, 18).background(panelColor)
            .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(AppTheme.font(13, weight: .medium)).foregroundStyle(quiet)
    }
}

extension Color {
    init(_ rgb: RGB) { self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255) }
}
