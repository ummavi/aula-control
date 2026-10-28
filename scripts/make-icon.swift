import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(srgbRed: 16 / 255, green: 15 / 255, blue: 15 / 255, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 36, y: 36, width: 952, height: 952)).fill()
        NSColor(srgbRed: 18 / 255, green: 37 / 255, blue: 59 / 255, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 160, y: 260, width: 704, height: 504)).fill()
        let accentBlue = NSColor(srgbRed: 102 / 255, green: 160 / 255, blue: 200 / 255, alpha: 1)
        accentBlue.setStroke()
        let outline = NSBezierPath(rect: NSRect(x: 180, y: 280, width: 664, height: 464))
        outline.lineWidth = 14
        outline.stroke()
        for row in 0..<3 {
            for col in 0..<6 {
                accentBlue.setFill()
                NSBezierPath(rect: NSRect(x: 228 + col * 97, y: 475 + row * 78, width: 72, height: 52)).fill()
            }
        }
        NSColor(srgbRed: 236 / 255, green: 139 / 255, blue: 73 / 255, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 330, y: 358, width: 364, height: 58)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
