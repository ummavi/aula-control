import AppKit
import SwiftUI

/// A square, black window frame with standard close/minimize/zoom actions.
@MainActor
enum WindowChrome {
    private static var configured: Set<ObjectIdentifier> = []
    static var window: NSWindow? { NSApp.windows.first { $0.title == "AULA Control" } }
    private static var restoreFrames: [ObjectIdentifier: NSRect] = [:]
    @MainActor static func configure(_ window: NSWindow) {
        guard configured.insert(ObjectIdentifier(window)).inserted else { return }
        let frame = window.frame
        window.styleMask = [.borderless, .closable, .miniaturizable, .resizable]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.title = "AULA Control"
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
    }
    @MainActor static func zoom() {
        guard let window = window, let screen = window.screen else { return }
        let id = ObjectIdentifier(window)
        if window.frame.equalTo(screen.visibleFrame), let previous = restoreFrames.removeValue(forKey: id) {
            window.setFrame(previous, display: true, animate: true)
        } else {
            restoreFrames[id] = window.frame
            window.setFrame(screen.visibleFrame, display: true, animate: true)
        }
    }
}

struct WindowBar: View {
    var body: some View {
        HStack(spacing: 0) {
            WindowDragArea().frame(maxWidth: .infinity)
            windowButton("minus", label: "Minimize window") { WindowChrome.window?.miniaturize(nil) }
            windowButton("square", label: "Zoom window") { WindowChrome.zoom() }
            windowButton("xmark", label: "Close window") { WindowChrome.window?.performClose(nil) }
        }
        .frame(height: 30).background(AppTheme.page)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }
    private func windowButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(AppTheme.secondary)
                .frame(width: 36, height: 30).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

private struct WindowDragArea: View {
    @State private var dragging = false
    var body: some View {
        Rectangle().fill(AppTheme.page).contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { _ in
                    guard !dragging, let event = NSApp.currentEvent,
                        event.type == .leftMouseDown || event.type == .leftMouseDragged
                    else { return }
                    dragging = true
                    WindowChrome.window?.performDrag(with: event)
                    dragging = false
                })
    }
}
