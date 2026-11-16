import Cocoa

/// Draws a bright red frame just inside the edges of a screen. Click-through, non-activating.
private final class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 6
        let lineWidth: CGFloat = 10
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        NSColor.systemRed.setStroke()
        path.stroke()
    }
}

enum OverlayManager {
    private static var windows: [NSWindow] = []

    static func showBorder() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = BorderView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    static func hideBorder() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
