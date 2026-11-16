import Cocoa

// Renders a simple app icon: a red rounded-square backdrop with a white shield
// glyph, at the sizes macOS expects inside an .iconset folder.

let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.225
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.95, green: 0.20, blue: 0.20, alpha: 1),
                               ending: NSColor(calibratedRed: 0.75, green: 0.05, blue: 0.08, alpha: 1))
    gradient?.draw(in: bgPath, angle: -90)

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.56, weight: .bold)
    if let symbol = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let symbolRect = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: symbolRect)
        symbolRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let drawSize = tinted.size
        let origin = NSPoint(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

for entry in sizes {
    let image = render(size: entry.px)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let path = "\(outDir)/\(entry.name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
